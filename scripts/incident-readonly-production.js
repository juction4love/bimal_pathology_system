import { createClient } from '@supabase/supabase-js'

const { INCIDENT_SUPABASE_URL: url, INCIDENT_SERVICE_KEY: key } = process.env
if (!url || !key) throw new Error('Production read-only environment variables are required')
const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })

async function exact(table, configure = q => q) {
  const q = configure(db.from(table).select('*', { count: 'exact', head: true }))
  const { count, error } = await q
  if (error) throw new Error(`${table}: ${error.message}`)
  return count
}

const priorityCodes = ['AFP','BT_CT','PT_INR','LDH','CHOL_TOTAL','HDL_CHOL','LDL_CHOL','TRIGLYCERIDES','BILIRUBIN_TD','AST','ALT','ALP','GGT','LIPASE','AMYLASE','CK_TOTAL','CK_MB','BICARBONATE','GLOBULIN','EGFR','RETIC_COUNT','AEC','ANC']
const priorityParameterCodes = ['AFP','BLEEDING_TIME','CLOTTING_TIME','PATIENT_PT','CONTROL_PT','ISI','INR','LDH']

const result = {
  generated_at: new Date().toISOString(),
  production_project_ref: 'rncjxstujioagcezvfkb',
  counts: {},
  catalogue: {},
  legacy_ranges: {},
}
for (const table of ['patients','bills','bill_items','payment_transactions','clinical_orders','clinical_order_items','test_results','diagnostic_reports','sms_queue_items','tests','parameters','reference_ranges','test_categories','health_packages','health_package_components','bill_package_selections','bill_package_components','role_permissions']) {
  result.counts[table] = await exact(table)
}
result.catalogue.seed_identities = await exact('tests', q => q.in('code', priorityCodes))
result.catalogue.seed_draft = await exact('tests', q => q.in('code', priorityCodes).eq('lifecycle_status','Draft').eq('is_active',false))
result.catalogue.seed_active = await exact('tests', q => q.in('code', priorityCodes).eq('lifecycle_status','Active'))
result.catalogue.priority_parameters = await exact('parameters', q => q.in('code', priorityParameterCodes).eq('lifecycle_status','Draft').eq('is_active',false))
result.catalogue.all_draft_tests = await exact('tests', q => q.eq('lifecycle_status','Draft'))
result.catalogue.active_tests = await exact('tests', q => q.eq('lifecycle_status','Active').eq('is_active',true))
result.catalogue.price_pending = await exact('tests', q => q.eq('price_configured',false))
result.catalogue.zero_price = await exact('tests', q => q.eq('price_paisa',0))
result.catalogue.collision_exempt = await exact('tests', q => q.eq('normalized_name_collision_exempt',true))
result.catalogue.category_linked = await exact('tests', q => q.not('category_id','is',null))
result.catalogue.workflow_unsupported = await exact('tests', q => q.eq('workflow_supported',false))
const priorityRows = await db.from('tests').select('code,lifecycle_status,is_active,price_paisa,price_configured,pricing_policy,clinical_configuration_status,workflow_supported').in('code', priorityCodes).order('code')
if (priorityRows.error) throw priorityRows.error
result.catalogue.priority_states = priorityRows.data
result.legacy_ranges.tagged = await exact('reference_ranges', q => q.eq('validation_state','LegacyDefaultRequiresValidation'))
result.legacy_ranges.source_method_rows = await exact('reference_ranges', q => q.eq('method','Default reference interval - verify with analyzer/reagent'))
result.legacy_ranges.clinically_validated = await exact('reference_ranges', q => q.eq('validation_state','ClinicallyValidated'))

console.log(JSON.stringify(result, null, 2))
