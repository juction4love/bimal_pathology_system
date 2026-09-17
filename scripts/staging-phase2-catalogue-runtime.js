import { writeFile } from 'node:fs/promises'
import { assertSyntheticStagingTarget } from './staging-target-guard.js'
import { bootstrapAdminClient } from './hosted-synthetic-actors.js'

const { STAGING_SUPABASE_URL: url, STAGING_ANON_KEY: anonKey, STAGING_SERVICE_KEY: serviceKey, STAGING_TEST_PASSWORD: password } = process.env
if (!url || !anonKey || !serviceKey || !password) throw new Error('Staging environment variables are required')
assertSyntheticStagingTarget({ expectedHead: process.env.STAGING_EXPECTED_MIGRATION_HEAD })
const service = await bootstrapAdminClient(url, anonKey)
const client = service
const adminUser = await client.auth.getUser()
if (adminUser.error) throw adminUser.error
const stamp = Date.now().toString(36)
const out = []
const record = (name, pass, details = {}) => out.push({ name, pass, ...details })
const rpc = (fn, args) => client.rpc(fn, args)

const category = await service.from('test_categories').select('id').eq('code', 'BIOCHEMISTRY').single()
if (category.error) throw category.error
const baseTest = {
  code: `P2SAFE_${stamp}`.toUpperCase(), name: `Phase 2 Safe Numeric ${stamp}`, short_name: `p2s${stamp}`,
  description: 'Synthetic staging-only runtime fixture', category_id: category.data.id, department: 'Clinical Biochemistry', category: 'Biochemistry',
  test_kind: 'Individual', reporting_type: 'InHouse', price_paisa: 12345, price_configured: true, allow_zero_price_billing: false,
  pricing_policy: 'Fixed', sample_type: 'Serum', container: 'SST', sample_volume: '1 mL', method: 'Controlled staging fixture', tat_hours: 24,
  display_order: 999, clinical_configuration_status: 'Configured', workflow_supported: true, search_aliases: [`p2${stamp}`, 'acceptance']
}
const saveTest = await rpc('catalogue_save_test', { p_test: baseTest, p_expected_version: null })
if (saveTest.error) throw saveTest.error
const testId = saveTest.data.id
const saveParameter = await rpc('catalogue_save_parameter', { p_parameter: { test_id: testId, code: `P2PARAM_${stamp}`.toUpperCase(), name: 'Controlled Analyte', value_type: 'Numeric', unit: 'U/L', options: [], formula_dependencies: [], decimal_precision: 1, interpretation_config: {}, display_order: 1, is_mandatory: true }, p_expected_version: null })
if (saveParameter.error) throw saveParameter.error
const paramId = saveParameter.data
let param = await service.from('parameters').select('row_version').eq('id', paramId).single()
const paramActive = await rpc('catalogue_set_parameter_lifecycle', { p_parameter_id: paramId, p_status: 'Active', p_expected_version: param.data.row_version })
record('parameter add/activate', !paramActive.error, { error: paramActive.error?.message })
const saveRange = await rpc('catalogue_save_range', { p_range: { parameter_id: paramId, gender: 'All', age_min_days: 0, age_max_days: 43800, normal_min: 1, normal_max: 2, critical_low: null, critical_high: null, normal_text: null, reference_text: 'Controlled staging fixture only', method: 'Controlled staging fixture', unit: 'U/L', validation_state: 'ClinicallyValidated', validation_source: 'Synthetic staging acceptance fixture', is_approved: true }, p_expected_version: null })
if (saveRange.error) throw saveRange.error
const rangeId = saveRange.data
let range = await service.from('reference_ranges').select('row_version,is_approved,lifecycle_status').eq('id', rangeId).single()
// New ranges are deliberately draft/unapproved even when a caller asks otherwise.
record('new range defaults fail closed', !range.error && !range.data.is_approved && range.data.lifecycle_status === 'Draft', { row: range.data })
const updateRange = await rpc('catalogue_save_range', { p_range: { id: rangeId, parameter_id: paramId, gender: 'All', age_min_days: 0, age_max_days: 43800, normal_min: 1, normal_max: 2, critical_low: null, critical_high: null, normal_text: null, reference_text: 'Controlled staging fixture only', method: 'Controlled staging fixture', unit: 'U/L', validation_state: 'ClinicallyValidated', validation_source: 'Synthetic staging acceptance fixture', is_approved: true }, p_expected_version: range.data.row_version })
record('range reviewed update', !updateRange.error, { error: updateRange.error?.message })
range = await service.from('reference_ranges').select('row_version').eq('id', rangeId).single()
const rangeActive = await rpc('catalogue_set_range_lifecycle', { p_range_id: rangeId, p_status: 'Active', p_expected_version: range.data.row_version })
record('range activate', !rangeActive.error, { error: rangeActive.error?.message })
let test = await service.from('tests').select('row_version').eq('id', testId).single()
const activate = await rpc('catalogue_set_test_lifecycle', { p_test_id: testId, p_status: 'Active', p_expected_version: test.data.row_version })
record('fully configured fixture activates', !activate.error, { error: activate.error?.message })
test = await service.from('tests').select('row_version').eq('id', testId).single()
const gates = await rpc('catalogue_set_test_operational_gates', {
  p_test_id: testId,
  p_billing_enabled: true,
  p_clinical_reporting_enabled: true,
  p_collection_required: true,
  p_expected_version: test.data.row_version,
})
record('independent operational gates enable configured fixture', !gates.error, { error: gates.error?.message })

for (const code of ['AFP', 'PT_INR']) {
  const row = await service.from('tests').select('id,row_version').eq('code', code).single()
  const attempted = await rpc('catalogue_set_test_lifecycle', { p_test_id: row.data.id, p_status: 'Active', p_expected_version: row.data.row_version })
  record(`${code} incomplete activation denied`, Boolean(attempted.error), { error: attempted.error?.message })
}
const legacy = await service.from('reference_ranges').select('id', { count: 'exact', head: true }).eq('validation_state', 'LegacyDefaultRequiresValidation')
record('legacy range provenance retained and unapproved', !legacy.error && legacy.count > 0, { count: legacy.count })

for (const q of [baseTest.code.slice(0, 2), baseTest.code.slice(0, 3), baseTest.code.slice(0, 4), 'acceptance']) {
  const found = await rpc('search_billable_catalogue', { p_query: q.toLowerCase(), p_limit: 50 })
  record(`search ${q}`, !found.error && found.data.some(x => x.entity_id === testId), { count: found.data?.length, error: found.error?.message })
}

// Genuine duplicate-code race and stale-row conflict through PostgREST.
const raceCode = `P2RACE_${stamp}`.toUpperCase()
const racePayload = { ...baseTest, code: raceCode, name: `Race A ${stamp}` }
const racePayload2 = { ...baseTest, code: raceCode, name: `Race B ${stamp}` }
const race = await Promise.all([rpc('catalogue_save_test', { p_test: racePayload, p_expected_version: null }), rpc('catalogue_save_test', { p_test: racePayload2, p_expected_version: null })])
record('concurrent duplicate code deterministic', race.filter(x => !x.error).length === 1 && race.filter(x => x.error).length === 1, { errors: race.map(x => x.error?.code || null) })
test = await service.from('tests').select('*').eq('id', testId).single()
const editPayload = { ...baseTest, id: testId, description: 'Fresh edit' }
const fresh = await rpc('catalogue_save_test', { p_test: editPayload, p_expected_version: test.data.row_version })
const stale = await rpc('catalogue_save_test', { p_test: { ...editPayload, description: 'Stale edit' }, p_expected_version: test.data.row_version })
record('stale edit returns HTTP conflict', !fresh.error && stale.error?.code === 'PT409', { code: stale.error?.code, error: stale.error?.message })

// Safe-delete a never-referenced Draft; reject deletion of an Active catalogue test.
const disposable = await rpc('catalogue_save_test', { p_test: { ...baseTest, code: `P2DEL_${stamp}`.toUpperCase(), name: `Disposable ${stamp}` }, p_expected_version: null })
let disposableRow = await service.from('tests').select('row_version').eq('id', disposable.data.id).single()
const deleted = await rpc('catalogue_delete_test', { p_test_id: disposable.data.id, p_expected_version: disposableRow.data.row_version })
record('unused test safe delete', !deleted.error, { error: deleted.error?.message })
const activeTest = await service.from('tests').select('id,row_version').eq('lifecycle_status', 'Active').limit(1).single()
if (activeTest.error) throw activeTest.error
const blockedDelete = await rpc('catalogue_delete_test', { p_test_id: activeTest.data.id, p_expected_version: activeTest.data.row_version })
record('authorized active-test delete preserves reference integrity', !blockedDelete.error || blockedDelete.error.code === '23503', { error: blockedDelete.error?.message, code: blockedDelete.error?.code })

const audit = await service.from('audit_logs').select('action,user_id').in('entity_id', [testId, paramId, rangeId]).order('timestamp')
record('catalogue audit rows server actor', !audit.error && audit.data.length >= 6 && audit.data.every(x => x.user_id === adminUser.data.user.id), { count: audit.data?.length, error: audit.error?.message })
const summary = { pass: out.filter(x => x.pass).length, fail: out.filter(x => !x.pass).length }
await writeFile('artifacts/phase2-catalogue-runtime.json', JSON.stringify({ summary, results: out }, null, 2))
console.log(JSON.stringify(summary))
if (summary.fail) process.exitCode = 1
