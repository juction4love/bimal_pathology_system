import { createClient } from '@supabase/supabase-js'
import { writeFile } from 'node:fs/promises'
import { assertSyntheticStagingTarget } from './staging-target-guard.js'

const url = process.env.STAGING_SUPABASE_URL
const anonKey = process.env.STAGING_ANON_KEY
const serviceKey = process.env.STAGING_SERVICE_KEY
const password = process.env.STAGING_TEST_PASSWORD
if (!url || !anonKey || !serviceKey || !password) throw new Error('Staging environment variables are required')
assertSyntheticStagingTarget({ expectedHead: process.env.STAGING_EXPECTED_MIGRATION_HEAD })

const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
const stamp = Date.now().toString(36)
const results = { project: new URL(url).hostname.split('.')[0], started_at: new Date().toISOString(), identities: {}, acl: [], runtime: [] }

async function createIdentity(label, permissions = [], roleId = null, inactive = false) {
  const email = `phase2-${label}-${stamp}@example.invalid`
  const { data, error } = await service.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name: `Phase 2 ${label}` } })
  if (error) throw error
  const id = data.user.id
  if (inactive) {
    await service.from('user_profiles').update({ is_active: false }).eq('id', id).throwOnError()
  } else if (roleId) {
    await service.from('user_profiles').update({ is_active: true }).eq('id', id).throwOnError()
    await service.from('user_roles').delete().eq('user_id', id).throwOnError()
    await service.from('user_roles').insert({ user_id: id, role_id: roleId }).throwOnError()
  } else if (permissions.length) {
    const code = `phase2_${label}_${stamp}`.slice(0, 50)
    const { data: role, error: roleError } = await service.from('roles').insert({ code, name: `Phase 2 ${label}`, is_system: false }).select('id').single()
    if (roleError) throw roleError
    await service.from('role_permissions').insert(permissions.map(permission_key => ({ role_id: role.id, permission_key }))).throwOnError()
    await service.from('user_profiles').update({ is_active: true }).eq('id', id).throwOnError()
    await service.from('user_roles').delete().eq('user_id', id).throwOnError()
    await service.from('user_roles').insert({ user_id: id, role_id: role.id }).throwOnError()
  }
  const client = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const signed = await client.auth.signInWithPassword({ email, password })
  if (signed.error) throw signed.error
  results.identities[label] = { id, inactive, permissions }
  return client
}

function denied(error) {
  return Boolean(error && /permission|access denied|inactive|not active|authentication/i.test(`${error.message} ${error.details || ''}`))
}

async function call(label, client, fn, args, expectation) {
  const { data, error } = await client.rpc(fn, args)
  const isDenied = denied(error)
  const pass = expectation === 'deny' ? isDenied : !isDenied
  results.acl.push({ label, function: fn, expectation, pass, error_code: error?.code || null, error: error?.message || null, reachable: !isDenied })
  return { data, error, pass }
}

const admin = await createIdentity('admin', [], '00000000-0000-0000-0000-000000000001')
const inactive = await createIdentity('inactive', [], null, true)
const technician = await createIdentity('technician', [], '00000000-0000-0000-0000-000000000004')
const billing = await createIdentity('billing', ['can_create_bill', 'can_edit_patient'])
const catalogue = await createIdentity('catalogue', ['can_manage_catalogue'])
const roleManager = await createIdentity('role_manager', ['can_manage_roles'])

const anon = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })
const allCalls = [
  ['search_billable_catalogue', { p_query: 'cb', p_limit: 5 }],
  ['catalogue_expand_package', { p_package_id: '00000000-0000-0000-0000-000000000000' }],
  ['catalogue_test_missing_configuration', { p_test_id: '10000000-0000-0000-0000-000000000001' }],
  ['catalogue_save_category', { p_category: { code: '', name: '' }, p_expected_version: null }],
  ['catalogue_save_test', { p_test: { code: '', name: '' }, p_expected_version: null }],
  ['catalogue_save_parameter', { p_parameter: {}, p_expected_version: null }],
  ['catalogue_save_range', { p_range: {}, p_expected_version: null }],
  ['catalogue_save_package', { p_package: {}, p_components: [], p_expected_version: null }],
  ['catalogue_delete_package', { p_package_id: '00000000-0000-0000-0000-000000000000', p_expected_version: 1 }],
  ['create_patient_bill_order_with_packages', { p_patient_data: {}, p_bill_data: {}, p_items_data: [], p_payment_data: {}, p_idempotency_key: `acl-${stamp}`, p_packages: [] }],
  ['replace_role_permission_matrix', { p_matrix: [] }],
  ['save_reporting_personnel', { p_personnel: {} }],
  ['save_referring_doctor', { p_doctor: {} }],
]

await Promise.all(allCalls.flatMap(([fn, args]) => [
  call('anonymous', anon, fn, args, 'deny'),
  call('inactive', inactive, fn, args, 'deny'),
  call('technician', technician, fn, args, 'deny'),
  call('billing', billing, fn, args, ['search_billable_catalogue', 'catalogue_expand_package', 'create_patient_bill_order_with_packages'].includes(fn) ? 'allow' : 'deny'),
  call('catalogue', catalogue, fn, args, fn.startsWith('catalogue_') && fn !== 'catalogue_expand_package' ? 'allow' : 'deny'),
  call('role_manager', roleManager, fn, args, fn === 'replace_role_permission_matrix' ? 'allow' : 'deny'),
  call('admin', admin, fn, args, 'allow'),
]))

// A valid server-authorized category lifecycle round trip and stale-write attack.
const categoryPayload = { code: `P2_${stamp}`.toUpperCase(), name: `Phase 2 Runtime ${stamp}`, description: 'Synthetic staging-only fixture', display_order: 999 }
const created = await catalogue.rpc('catalogue_save_category', { p_category: categoryPayload, p_expected_version: null })
if (created.error) throw created.error
const categoryId = created.data
const row = await service.from('test_categories').select('id,row_version,lifecycle_status').eq('id', categoryId).single()
if (row.error) throw row.error
const edited = await catalogue.rpc('catalogue_save_category', { p_category: { ...categoryPayload, id: categoryId, description: 'Edited staging fixture' }, p_expected_version: row.data.row_version })
const stale = await catalogue.rpc('catalogue_save_category', { p_category: { ...categoryPayload, id: categoryId, description: 'Stale overwrite' }, p_expected_version: row.data.row_version })
const latest = await service.from('test_categories').select('row_version').eq('id', categoryId).single()
const archived = await catalogue.rpc('catalogue_set_category_lifecycle', { p_category_id: categoryId, p_status: 'Archived', p_expected_version: latest.data.row_version })
const latest2 = await service.from('test_categories').select('row_version').eq('id', categoryId).single()
const restored = await catalogue.rpc('catalogue_set_category_lifecycle', { p_category_id: categoryId, p_status: 'Active', p_expected_version: latest2.data.row_version })
results.runtime.push({ test: 'category CRUD/lifecycle', pass: !edited.error && Boolean(stale.error) && !archived.error && !restored.error, stale_error: stale.error?.message || null })

const audit = await service.from('audit_logs').select('action,user_id,user_name').eq('entity_id', categoryId).order('timestamp')
results.runtime.push({ test: 'server-derived catalogue audit actor', pass: !audit.error && audit.data.length >= 4 && audit.data.every(x => x.user_id === results.identities.catalogue.id), error: audit.error?.message || null, rows: audit.data })

results.finished_at = new Date().toISOString()
results.summary = {
  acl_pass: results.acl.filter(x => x.pass).length,
  acl_fail: results.acl.filter(x => !x.pass).length,
  runtime_pass: results.runtime.filter(x => x.pass).length,
  runtime_fail: results.runtime.filter(x => !x.pass).length,
}
await writeFile(process.env.STAGING_RESULT_PATH || 'artifacts/phase2-runtime-acceptance.json', JSON.stringify(results, null, 2))
console.log(JSON.stringify(results.summary))
if (results.summary.acl_fail || results.summary.runtime_fail) process.exitCode = 1
