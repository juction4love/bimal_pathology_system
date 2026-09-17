import { createClient } from '@supabase/supabase-js'
import { writeFile } from 'node:fs/promises'
import { assertSyntheticStagingTarget } from './staging-target-guard.js'

const {
  STAGING_SUPABASE_URL: url,
  STAGING_ANON_KEY: anonKey,
  STAGING_SERVICE_KEY: serviceKey,
  STAGING_TEST_PASSWORD: password,
} = process.env
if (!url || !anonKey || !serviceKey || !password) throw new Error('Staging environment variables are required')

const targetProof = assertSyntheticStagingTarget({ expectedHead: process.env.STAGING_EXPECTED_MIGRATION_HEAD })
const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
const anon = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })
const stamp = Date.now().toString(36)
const results = []
const record = (name, pass, details = {}) => results.push({ name, pass, ...details })

const PERMISSIONS = [
  'can_view_dashboard', 'can_create_bill', 'can_edit_patient', 'can_collect_sample',
  'can_receive_sample', 'can_reject_sample', 'can_enter_results', 'can_verify_results',
  'can_acknowledge_critical', 'can_sign_reports', 'can_amend_reports', 'can_print_reports',
  'can_manage_catalogue', 'can_manage_referring_doctors', 'can_manage_personnel',
  'can_view_financials', 'can_manage_users', 'can_manage_roles', 'can_view_audit_logs',
  'can_manage_outsource_tracking', 'can_view_hmis_reports', 'can_edit_hmis_reports',
  'can_finalize_hmis_reports',
]

async function identity(label, { active = true, roleId = null, direct = [], superAdmin = false, removeProfile = false } = {}) {
  const email = `final-00051-${label}-${stamp}@example.invalid`
  const made = await service.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: `Final 00051 ${label}` },
  })
  if (made.error) throw made.error
  const userId = made.data.user.id
  await service.from('user_profiles').update({ is_active: active, is_super_admin: superAdmin }).eq('id', userId).throwOnError()
  if (roleId) {
    await service.from('user_roles').delete().eq('user_id', userId).throwOnError()
    await service.from('user_roles').insert({ user_id: userId, role_id: roleId }).throwOnError()
  }
  if (direct.length) {
    await service.from('user_direct_permissions').upsert(
      direct.map(({ key, granted = true }) => ({ user_id: userId, permission_key: key, is_granted: granted })),
    ).throwOnError()
  }
  if (removeProfile) await service.from('user_profiles').delete().eq('id', userId).throwOnError()
  const client = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const login = await client.auth.signInWithPassword({ email, password })
  if (login.error) throw login.error
  return { client, userId, email }
}

const ADMIN_ROLE = '00000000-0000-0000-0000-000000000001'
const TECH_ROLE = '00000000-0000-0000-0000-000000000004'
const admin = await identity('admin', { active: true, roleId: ADMIN_ROLE })
const technician = await identity('technician', { active: true, roleId: TECH_ROLE })
const billing = await identity('billing', { active: true, direct: [{ key: 'can_create_bill' }] })
const inactiveRole = await identity('inactive-role', { active: false, roleId: ADMIN_ROLE })
const inactiveDirect = await identity('inactive-direct', { active: false, direct: PERMISSIONS.map(key => ({ key })) })
const inactiveSuper = await identity('inactive-super', { active: false, roleId: ADMIN_ROLE, superAdmin: true })
const missingProfile = await identity('missing-profile', { active: false, direct: [{ key: 'can_create_bill' }], removeProfile: true })

for (const [label, subject] of [
  ['inactive role', inactiveRole],
  ['inactive direct grants', inactiveDirect],
  ['inactive super admin', inactiveSuper],
  ['missing profile', missingProfile],
]) {
  const checks = await Promise.all(PERMISSIONS.map(key => subject.client.rpc('has_permission', { p_permission_key: key })))
  const leaked = checks.flatMap((response, index) => response.error || response.data !== false
    ? [{ permission: PERMISSIONS[index], value: response.data, error: response.error?.message }]
    : [])
  record(`${label}: all ${PERMISSIONS.length} application permissions denied`, leaked.length === 0, { leaked })
}

const activeAdminChecks = await Promise.all(PERMISSIONS.map(key => admin.client.rpc('has_permission', { p_permission_key: key })))
const missingAdminPermissions = activeAdminChecks.flatMap((response, index) =>
  response.error || response.data !== true
    ? [{ permission: PERMISSIONS[index], value: response.data, error: response.error?.message }]
    : [],
)
record('active Admin retains all configured permissions', missingAdminPermissions.length === 0, { missing: missingAdminPermissions })

const customRole = await service.from('roles').insert({
  code: `FINAL_DENY_${stamp}`.slice(0, 50), name: `Final direct deny ${stamp}`, is_system: false,
}).select('id').single()
if (customRole.error) throw customRole.error
await service.from('role_permissions').insert({ role_id: customRole.data.id, permission_key: 'can_create_bill' }).throwOnError()
const explicitDeny = await identity('explicit-deny', {
  active: true, roleId: customRole.data.id, direct: [{ key: 'can_create_bill', granted: false }],
})
const explicitDenyCheck = await explicitDeny.client.rpc('has_permission', { p_permission_key: 'can_create_bill' })
record('active direct denial overrides role grant', !explicitDenyCheck.error && explicitDenyCheck.data === false)

async function expectRpcDenied(name, client, fn, args) {
  const response = await client.rpc(fn, args)
  record(name, Boolean(response.error), { code: response.error?.code, message: response.error?.message })
}

const emptyBilling = {
  p_patient_data: {}, p_bill_data: {}, p_items_data: [], p_payment_data: null,
  p_idempotency_key: `denied-${stamp}`,
}
for (const [label, client] of [['anonymous', anon], ['inactive', inactiveDirect.client], ['active billing user', billing.client], ['Admin', admin.client]]) {
  await expectRpcDenied(`${label}: obsolete five-argument billing denied`, client, 'create_patient_bill_and_order', emptyBilling)
}
for (const [label, client] of [['anonymous', anon], ['active billing user', billing.client], ['Admin', admin.client]]) {
  const fourArgument = { ...emptyBilling }
  delete fourArgument.p_idempotency_key
  await expectRpcDenied(`${label}: obsolete four-argument billing denied`, client, 'create_patient_bill_and_order', fourArgument)
}

await expectRpcDenied('authenticated direct queue_bill_sms denied', admin.client, 'queue_bill_sms', { p_bill_id: crypto.randomUUID() })
await expectRpcDenied('authenticated direct sign_and_freeze denied', admin.client, 'sign_and_freeze_diagnostic_report', {
  p_order_id: crypto.randomUUID(), p_reported_by_id: crypto.randomUUID(), p_authorized_by_id: null,
  p_reported_by_signature_hash: 'denied', p_amended_from_report_id: null,
})
await expectRpcDenied('authenticated obsolete acknowledge_critical_result denied', admin.client, 'acknowledge_critical_result', {
  p_result_id: crypto.randomUUID(), p_notified_person: 'Synthetic',
  p_notification_method: 'Direct Phone Call', p_notification_comment: 'must be denied',
})

for (const [name, promise] of [
  ['tests direct mutation denied', admin.client.from('tests').update({ name: '__must_not_write__' }).eq('id', crypto.randomUUID())],
  ['parameters direct mutation denied', admin.client.from('parameters').update({ name: '__must_not_write__' }).eq('id', crypto.randomUUID())],
  ['reference ranges direct mutation denied', admin.client.from('reference_ranges').update({ validation_source: '__must_not_write__' }).eq('id', crypto.randomUUID())],
  ['categories direct mutation denied', admin.client.from('test_categories').update({ name: '__must_not_write__' }).eq('id', crypto.randomUUID())],
  ['packages direct mutation denied', admin.client.from('health_packages').update({ name: '__must_not_write__' }).eq('id', crypto.randomUUID())],
  ['package components direct mutation denied', admin.client.from('health_package_components').delete().eq('package_id', crypto.randomUUID())],
  ['role permissions direct mutation denied', admin.client.from('role_permissions').delete().eq('role_id', customRole.data.id)],
  ['roles direct mutation denied', admin.client.from('roles').update({ name: '__must_not_write__' }).eq('id', customRole.data.id)],
  ['user profiles direct mutation denied', admin.client.from('user_profiles').update({ full_name: '__must_not_write__' }).eq('id', admin.userId)],
  ['user roles direct mutation denied', admin.client.from('user_roles').delete().eq('user_id', admin.userId)],
  ['direct permission mutation denied', admin.client.from('user_direct_permissions').delete().eq('user_id', admin.userId)],
  ['reporting personnel direct mutation denied', admin.client.from('reporting_personnel').update({ full_name: '__must_not_write__' }).eq('id', crypto.randomUUID())],
  ['referring doctor direct mutation denied', admin.client.from('referring_doctors').update({ full_name: '__must_not_write__' }).eq('id', crypto.randomUUID())],
  ['audit-log forgery denied', admin.client.from('audit_logs').insert({ action: 'FORGED', entity_type: 'SecurityTest', entity_id: stamp, user_id: admin.userId, user_name: 'forged' })],
]) {
  const response = await promise
  record(name, Boolean(response.error), { code: response.error?.code, message: response.error?.message })
}

const updateAccess = await admin.client.rpc('update_user_access', {
  p_user_id: technician.userId, p_is_active: true, p_is_super_admin: false, p_role_ids: [TECH_ROLE],
})
record('guarded atomic update_user_access remains operational', !updateAccess.error, { error: updateAccess.error?.message })

const inactiveSearch = await inactiveDirect.client.rpc('search_billable_catalogue', { p_query: 'cbc', p_limit: 5 })
record('inactive guarded catalogue search denied', Boolean(inactiveSearch.error), { code: inactiveSearch.error?.code, message: inactiveSearch.error?.message })
const activeSearch = await billing.client.rpc('search_billable_catalogue', { p_query: 'cbc', p_limit: 5 })
record('active billing catalogue search allowed', !activeSearch.error && activeSearch.data?.some(row => row.code === 'CBC'), { error: activeSearch.error?.message })

const inactiveTestRead = await inactiveDirect.client.from('tests').select('id').limit(1)
record('inactive generic catalogue read returns no rows', !inactiveTestRead.error && inactiveTestRead.data.length === 0, { error: inactiveTestRead.error?.message, row_count: inactiveTestRead.data?.length })

const summary = {
  pass: results.filter(x => x.pass).length,
  fail: results.filter(x => !x.pass).length,
  safe: results.every(x => x.pass),
  permissions_exercised: PERMISSIONS.length,
  sms_provider_send_attempted: false,
}
const evidence = { target: targetProof, summary, test_count: results.length, results }
await writeFile('artifacts/staging-00051-runtime.json', JSON.stringify(evidence, null, 2))
console.log(JSON.stringify(summary))
if (!summary.safe) process.exitCode = 1
