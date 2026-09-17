import { createClient } from '@supabase/supabase-js'
import { writeFile } from 'node:fs/promises'
import { assertSyntheticStagingTarget } from './staging-target-guard.js'

const {
  STAGING_SUPABASE_URL: url,
  STAGING_ANON_KEY: anonKey,
  STAGING_SERVICE_KEY: serviceKey,
  STAGING_TEST_PASSWORD: password,
} = process.env

if (!url || !anonKey || !serviceKey || !password) {
  throw new Error('Staging environment variables are required')
}

// This prints and proves environment/project/head before the first mutation.
// The guard rejects the production project ref and never trusts CLI link state.
const target = assertSyntheticStagingTarget({
  expectedHead: process.env.STAGING_EXPECTED_MIGRATION_HEAD,
})

const service = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})
const stamp = Date.now().toString(36)
const roleCode = `ROLE_RACE_${stamp}`.toUpperCase().slice(0, 50)
const email = `role-race-${stamp}@example.invalid`
const rounds = 12
const setA = [
  'can_view_dashboard',
  'can_edit_patient',
  'can_collect_sample',
  'can_receive_sample',
  'can_enter_results',
  'can_verify_results',
  'can_print_reports',
  'can_manage_catalogue',
  'can_view_hmis_reports',
  'can_edit_hmis_reports',
]
const setB = [
  'can_create_bill',
  'can_reject_sample',
  'can_acknowledge_critical',
  'can_sign_reports',
  'can_amend_reports',
  'can_manage_referring_doctors',
  'can_manage_personnel',
  'can_view_financials',
  'can_manage_users',
  'can_view_audit_logs',
  'can_manage_outsource_tracking',
  'can_finalize_hmis_reports',
]
const initialSet = ['can_view_dashboard']
const signature = (values) => [...values].sort().join('|')
const allowedCommittedSignatures = new Set([
  signature(initialSet),
  signature(setA),
  signature(setB),
])

const evidence = {
  target,
  started_at: new Date().toISOString(),
  rounds,
  results: [],
  observations: [],
  cleanup: [],
}
const record = (name, pass, details = {}) => evidence.results.push({ name, pass, ...details })
let roleId = null
let userId = null
let clientA = null
let clientB = null
let polling = false
let poller = null

async function currentPermissions() {
  const response = await service
    .from('role_permissions')
    .select('permission_key')
    .eq('role_id', roleId)
    .order('permission_key')
  if (response.error) throw response.error
  return response.data.map((row) => row.permission_key)
}

try {
  const role = await service
    .from('roles')
    .insert({ code: roleCode, name: `Synthetic role concurrency ${stamp}`, is_system: false })
    .select('id')
    .single()
  if (role.error) throw role.error
  roleId = role.data.id

  const made = await service.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: `Synthetic Role Manager ${stamp}` },
  })
  if (made.error) throw made.error
  userId = made.data.user.id

  await service.from('user_profiles').update({ is_active: true }).eq('id', userId).throwOnError()
  await service.from('user_direct_permissions').insert({
    user_id: userId,
    permission_key: 'can_manage_roles',
    is_granted: true,
  }).throwOnError()
  await service.from('role_permissions').insert(
    initialSet.map((permission_key) => ({ role_id: roleId, permission_key })),
  ).throwOnError()

  clientA = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })
  clientB = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const [loginA, loginB] = await Promise.all([
    clientA.auth.signInWithPassword({ email, password }),
    clientB.auth.signInWithPassword({ email, password }),
  ])
  if (loginA.error) throw loginA.error
  if (loginB.error) throw loginB.error

  polling = true
  poller = (async () => {
    while (polling) {
      const values = await currentPermissions()
      evidence.observations.push({ signature: signature(values), count: values.length })
      await new Promise((resolve) => setTimeout(resolve, 5))
    }
  })()

  const calls = []
  for (let round = 1; round <= rounds; round += 1) {
    const payloadA = [{ role_id: roleId, permissions: setA }]
    const payloadB = [{ role_id: roleId, permissions: setB }]
    const pair = await Promise.all([
      clientA.rpc('replace_role_permission_matrix', { p_matrix: payloadA }),
      clientB.rpc('replace_role_permission_matrix', { p_matrix: payloadB }),
    ])
    calls.push(...pair)
    const committed = await currentPermissions()
    record(
      `round ${round}: both replacements commit and final matrix is whole`,
      pair.every((response) => !response.error && response.data === 1)
        && [signature(setA), signature(setB)].includes(signature(committed)),
      {
        response_codes: pair.map((response) => response.error?.code || null),
        returned_role_counts: pair.map((response) => response.data ?? null),
        final_permission_count: committed.length,
        final_matrix: signature(committed) === signature(setA) ? 'A' : 'B',
      },
    )
  }
  polling = false
  await poller

  const partialObservations = evidence.observations.filter(
    (observation) => !allowedCommittedSignatures.has(observation.signature),
  )
  record(
    'concurrent readers observe only complete committed matrices',
    evidence.observations.length > 0 && partialObservations.length === 0,
    {
      observation_count: evidence.observations.length,
      partial_observation_count: partialObservations.length,
      observed_counts: [...new Set(evidence.observations.map((item) => item.count))].sort((a, b) => a - b),
    },
  )

  const audit = await service
    .from('audit_logs')
    .select('action,user_id,entity_id')
    .eq('action', 'ROLE_PERMISSIONS_REPLACED')
    .eq('entity_id', roleId)
  if (audit.error) throw audit.error
  record(
    'every committed replacement has one server-derived audit event',
    audit.data.length === calls.length
      && audit.data.every((row) => row.user_id === userId && row.entity_id === roleId),
    { committed_calls: calls.length, audit_rows: audit.data.length },
  )
} catch (error) {
  record('runtime completed without an unexpected exception', false, {
    error: error instanceof Error ? error.message : String(error),
  })
} finally {
  polling = false
  if (poller) {
    try {
      await poller
    } catch (error) {
      evidence.cleanup.push({
        object: 'concurrent committed-state observer',
        pass: false,
        error: error instanceof Error ? error.message : String(error),
      })
    }
  }
  if (clientA) await clientA.auth.signOut()
  if (clientB) await clientB.auth.signOut()

  if (userId) {
    const deletedUser = await service.auth.admin.deleteUser(userId)
    evidence.cleanup.push({ object: 'synthetic auth identity', pass: !deletedUser.error, error: deletedUser.error?.message || null })
    if (deletedUser.error) {
      // Fail closed even if Auth cleanup is temporarily unavailable: remove
      // application authority and deactivate the synthetic identity.
      const [directCleanup, roleCleanup, deactivate] = await Promise.all([
        service.from('user_direct_permissions').delete().eq('user_id', userId),
        service.from('user_roles').delete().eq('user_id', userId),
        service.from('user_profiles').update({ is_active: false, is_super_admin: false }).eq('id', userId),
      ])
      evidence.cleanup.push({
        object: 'synthetic identity fail-closed fallback',
        pass: !directCleanup.error && !roleCleanup.error && !deactivate.error,
        error: directCleanup.error?.message || roleCleanup.error?.message || deactivate.error?.message || null,
      })
    }
  }
  if (roleId) {
    const deletedRole = await service.from('roles').delete().eq('id', roleId)
    evidence.cleanup.push({ object: 'synthetic role and permission rows', pass: !deletedRole.error, error: deletedRole.error?.message || null })

    const [roleCheck, permissionCheck] = await Promise.all([
      service.from('roles').select('id', { count: 'exact', head: true }).eq('id', roleId),
      service.from('role_permissions').select('id', { count: 'exact', head: true }).eq('role_id', roleId),
    ])
    evidence.cleanup.push({
      object: 'synthetic database fixture absence',
      pass: !roleCheck.error && !permissionCheck.error && roleCheck.count === 0 && permissionCheck.count === 0,
      role_count: roleCheck.count,
      permission_count: permissionCheck.count,
      error: roleCheck.error?.message || permissionCheck.error?.message || null,
    })
  }

  evidence.finished_at = new Date().toISOString()
  evidence.summary = {
    pass: evidence.results.filter((item) => item.pass).length,
    fail: evidence.results.filter((item) => !item.pass).length,
    cleanup_pass: evidence.cleanup.filter((item) => item.pass).length,
    cleanup_fail: evidence.cleanup.filter((item) => !item.pass).length,
    safe: evidence.results.every((item) => item.pass) && evidence.cleanup.every((item) => item.pass),
    production_touched: false,
  }
  await writeFile(
    process.env.STAGING_RESULT_PATH || 'artifacts/staging-role-permission-concurrency.json',
    JSON.stringify(evidence, null, 2),
  )
  console.log(JSON.stringify(evidence.summary))
  if (!evidence.summary.safe) process.exitCode = 1
}
