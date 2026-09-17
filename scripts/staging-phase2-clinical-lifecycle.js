import { createClient } from '@supabase/supabase-js'
import { createHash, randomBytes } from 'node:crypto'
import { writeFile } from 'node:fs/promises'
import { assertSyntheticStagingTarget } from './staging-target-guard.js'
import { bootstrapAdminClient, provisionSyntheticActor } from './hosted-synthetic-actors.js'

const { STAGING_SUPABASE_URL: url, STAGING_ANON_KEY: anonKey, STAGING_SERVICE_KEY: serviceKey, STAGING_TEST_PASSWORD: password } = process.env
if (!url || !anonKey || !serviceKey || !password) throw new Error('Staging environment variables are required')
assertSyntheticStagingTarget({ expectedHead: process.env.STAGING_EXPECTED_MIGRATION_HEAD })
const management = createClient(url, serviceKey, { auth: { persistSession: false } })
const service = await bootstrapAdminClient(url, anonKey)
const stamp = Date.now().toString(36)
const ledger = []
const ids = {}

async function identity(label, roleId) {
  if (label === 'admin') {
    const session = await service.auth.getUser()
    ids.admin_user_id = session.data.user.id
    ids.admin_email = session.data.user.email
    return service
  }
  const made = await provisionSyntheticActor({ url, anonKey, management, label:`lifecycle-${label}`, password, roleId })
  ids[`${label}_user_id`] = made.id
  ids[`${label}_email`] = made.email
  return made.client
}
const admin = await identity('admin', '00000000-0000-0000-0000-000000000001')
const technician = await identity('technician', '00000000-0000-0000-0000-000000000004')
const technicianB = await identity('technician_b', '00000000-0000-0000-0000-000000000004')
const verifier = await identity('verifier', '00000000-0000-0000-0000-000000000007')
const signingUser = await identity('signatory', '00000000-0000-0000-0000-000000000008')
const assert = (condition, message, details) => { if (!condition) throw new Error(`${message}: ${JSON.stringify(details)}`) }
async function step(name, mutate, prove) {
  const mutation = mutate ? await mutate() : null
  if (mutation?.error) throw new Error(`${name} mutation failed: ${mutation.error.message}`)
  const state = await prove(mutation?.data)
  ledger.push({ sequence: ledger.length + 1, step: name, actor: mutation?.actor || null, mutation: mutation?.data ?? null, state })
  return { mutation: mutation?.data, state }
}
const one = async (table, select, column, value) => {
  const q = await service.from(table).select(select).eq(column, value).single()
  if (q.error) throw new Error(`${table}.${column} single-state query failed: ${q.error.message}`)
  return q.data
}
const oneResult = async select => {
  const q = await service.from('test_results').select(select).eq('order_item_id', ids.order_item_id).eq('parameter_id', ids.parameter_id).single()
  if (q.error) throw new Error(`test_results state query failed: ${q.error.message}`)
  return q.data
}

const mobile = `98${String(80000000 + (Date.now() % 10000000)).padStart(8, '0').slice(-8)}`
await step('Patient', async () => Object.assign(await admin.rpc('create_patient', { p_patient_data: { mobile, title: 'Ms.', full_name: `Synthetic Lifecycle ${stamp}`, gender: 'Female', dob: null, age_years: 35, age_months: 0, age_days: 0, address: 'Synthetic Staging Address', email: null, identification_no: null } }), { actor: 'Admin JWT' }), async data => {
  ids.patient_id = data.id || data.patient_id
  const patient = await one('patients', 'id,uhid,full_name,mobile,is_active', 'id', ids.patient_id)
  assert(patient.mobile === mobile, 'patient persistence mismatch', patient)
  return patient
})

const cbcSearch = await step('Search', async () => {
  const response = await admin.rpc('search_billable_catalogue', { p_query: 'p2safe', p_limit: 50 })
  return Object.assign(response, { actor: 'Admin JWT' })
}, async data => {
  const enabled = await service.from('tests').select('id').eq('clinical_reporting_enabled', true).in('id', data.filter(x => x.entity_type === 'Test').map(x => x.entity_id))
  if (enabled.error) throw enabled.error
  const enabledIds = new Set(enabled.data.map(x => x.id))
  const match = data.find(x => x.code.startsWith('P2SAFE_') && enabledIds.has(x.entity_id))
  assert(match, 'Clinically enabled synthetic search match missing', data)
  ids.test_id = match.entity_id
  return { query: 'p2safe', matches: data.length, selected: { id: match.entity_id, code: match.code, name: match.name, price_paisa: match.price_paisa } }
})
const cbc = cbcSearch.state.selected
const billArgs = {
  p_patient_data: { patient_id: ids.patient_id, mobile, title: 'Ms.', full_name: `Synthetic Lifecycle ${stamp}`, gender: 'Female', dob: null, age_years: 35, age_months: 0, age_days: 0, address: 'Synthetic Staging Address', email: null, identification_no: null },
  p_bill_data: { referring_doctor_id: null, referring_doctor_name_snapshot: 'Self / Walk-in', gross_amount_paisa: cbc.price_paisa, discount_amount_paisa: 0, discount_reason: null, paid_amount_paisa: cbc.price_paisa, order_date_bs: null, remarks: 'Synthetic lifecycle acceptance' },
  p_items_data: [{ test_id: cbc.id, test_code: cbc.code, test_name: cbc.name, reporting_type: 'InHouse', outsource_lab_name: null, unit_price_paisa: cbc.price_paisa, manual_price_paisa: cbc.price_paisa, discount_paisa: 0, net_price_paisa: cbc.price_paisa, specimen_type: 'Whole Blood (EDTA)', container_type: 'Lavender Top (EDTA)', department: 'Hematology', item_description: null, zero_price_acknowledged: false }],
  p_payment_data: { payment_mode: 'Cash', transaction_reference: null, remarks: 'Synthetic staging payment', received_by_name: 'Phase 2 Admin' },
  p_idempotency_key: `phase2-lifecycle-${stamp}`, p_packages: [],
}
await step('Patient → Bill → Payment', async () => Object.assign(await admin.rpc('create_patient_bill_order_with_packages', billArgs), { actor: 'Admin JWT' }), async data => {
  Object.assign(ids, { patient_id: data.patient_id, bill_id: data.bill_id })
  const order = await one('clinical_orders', 'id,order_number,status,bill_id,patient_id', 'bill_id', data.bill_id); ids.order_id = order.id
  const [patient, bill, items, payments] = await Promise.all([
    one('patients', 'id,uhid,full_name,mobile,is_active', 'id', data.patient_id), one('bills', 'id,bill_number,gross_amount_paisa,paid_amount_paisa,due_amount_paisa,payment_status', 'id', data.bill_id),
    service.from('bill_items').select('id,test_id,unit_price_paisa').eq('bill_id', data.bill_id), service.from('payment_transactions').select('id,receipt_number,amount_paisa,payment_mode,created_at').eq('bill_id', data.bill_id),
  ])
  assert(items.data?.length === 1 && payments.data?.length === 1, 'bill/payment cardinality', { items: items.data, payments: payments.data })
  return { patient, bill, bill_items: items.data, payments: payments.data, order }
})
await step('Sample created', null, async () => {
  const samples = await service.from('samples').select('id,barcode,status,order_id,patient_id,specimen_type,container_type').eq('order_id', ids.order_id)
  assert(!samples.error && samples.data.length === 1 && samples.data[0].status === 'Pending', 'pending sample missing', samples)
  ids.sample_id = samples.data[0].id
  const item = await one('clinical_order_items', 'id,status,test_id,sample_id,reporting_type', 'order_id', ids.order_id); ids.order_item_id = item.id
  return { sample: samples.data[0], order_item: item }
})
const pendingParams = await service.from('parameters').select('id,value_type,display_order').eq('test_id', ids.test_id).eq('is_active', true).order('display_order')
if (pendingParams.error || !pendingParams.data.length) throw pendingParams.error || new Error('Synthetic parameters missing')
const pendingResult = pendingParams.data.map((p, index) => ({
  parameter_id: p.id,
  numeric_value: p.value_type === 'Numeric' || p.value_type === 'Calculated' ? String(12 + index) : null,
  text_value: p.value_type === 'Numeric' || p.value_type === 'Calculated' ? null : 'Synthetic',
  display_value: p.value_type === 'Numeric' || p.value_type === 'Calculated' ? String(12 + index) : 'Synthetic',
  flag: 'Normal', is_critical: false, critical_acknowledged: false,
  normal_range_text: 'Synthetic acceptance range snapshot', normal_min: '10', normal_max: '20', critical_low: null, critical_high: null,
}))
await step('Pending sample blocks result entry', async () => {
  const denied = await technician.rpc('save_test_results', { p_order_item_id: ids.order_item_id, p_results: pendingResult, p_target_status: 'Draft', p_amended_from_report_id: null, p_amendment_reason: null, p_expected_revision: 0 })
  assert(denied.error?.message?.includes('RESULT_COLLECTION_NOT_READY'), 'pending sample result mutation was not denied', denied.error)
  return { data: { error_code: denied.error.code, error_message: denied.error.message }, actor: 'Technician JWT' }
}, async () => {
  const orderItem = await one('clinical_order_items', 'id,status,result_revision', 'id', ids.order_item_id)
  const placeholders = await service.from('test_results').select('status,numeric_value,text_value,display_value,flag,is_critical,critical_acknowledged,entered_by,verified_by,signed_off_by').eq('order_item_id', ids.order_item_id)
  const structurallyEmpty = !placeholders.error && placeholders.data.length === pendingParams.data.length && placeholders.data.every(row => row.status === 'Draft' && row.numeric_value === null && row.text_value === null && row.display_value === '' && row.flag === 'Normal' && !row.is_critical && !row.critical_acknowledged && row.entered_by === null && row.verified_by === null && row.signed_off_by === null)
  assert(orderItem.result_revision === 0 && structurallyEmpty, 'denied pending-sample write changed placeholder clinical meaning', { orderItem, placeholders })
  return { order_item: orderItem, placeholder_count: placeholders.data.length, structurally_empty: structurallyEmpty }
})
await step('Sample collection', async () => Object.assign(await technician.rpc('transition_sample_lifecycle', { p_sample_id: ids.sample_id, p_to_status: 'Collected', p_reason: null }), { actor: 'Technician JWT' }), async () => ({
  sample: await one('samples', 'id,status,collected_at,collected_by,collected_by_name', 'id', ids.sample_id),
  order_item: await one('clinical_order_items', 'id,status', 'id', ids.order_item_id),
}))
await step('Accession / receive', async () => Object.assign(await technician.rpc('transition_sample_lifecycle', { p_sample_id: ids.sample_id, p_to_status: 'Received', p_reason: null }), { actor: 'Technician JWT' }), async () => ({
  sample: await one('samples', 'id,status,received_at,received_by,received_by_name', 'id', ids.sample_id),
  lifecycle_events: (await service.from('sample_lifecycle_events').select('from_status,to_status,performed_by,timestamp').eq('sample_id', ids.sample_id).order('timestamp')).data,
  order_item: await one('clinical_order_items', 'id,status', 'id', ids.order_item_id),
}))
await step('Worklist', null, async () => {
  const visible = await technician.from('clinical_order_items').select('id,status,test_name,order_id').eq('id', ids.order_item_id).single()
  assert(!visible.error && visible.data.status === 'SampleReceived', 'technician worklist item not ready', visible)
  return visible.data
})
const params = await service.from('parameters').select('id,code,name,unit,value_type,display_order').eq('test_id', ids.test_id).eq('is_active', true).order('display_order')
if (params.error || !params.data.length) throw params.error || new Error('CBC parameters missing')
const parameter = params.data.find(x => x.value_type === 'Numeric') || params.data[0]; ids.parameter_id = parameter.id
const result = acknowledged => params.data.map((p, index) => ({
  parameter_id: p.id,
  numeric_value: p.value_type === 'Numeric' || p.value_type === 'Calculated' ? String(index === 0 ? 1 : 15 + index) : null,
  text_value: p.value_type === 'Numeric' || p.value_type === 'Calculated' ? null : 'Synthetic',
  display_value: p.value_type === 'Numeric' || p.value_type === 'Calculated' ? String(index === 0 ? 1 : 15 + index) : 'Synthetic',
  flag: p.id === parameter.id ? 'CriticalLow' : 'Normal', is_critical: p.id === parameter.id,
  critical_acknowledged: p.id === parameter.id ? acknowledged : false,
  normal_range_text: 'Synthetic staging range snapshot', normal_min: '10', normal_max: '20', critical_low: '5', critical_high: '25',
}))
await step('Two authenticated contexts race at revision 0', async () => {
  const calls = await Promise.all([
    technician.rpc('save_test_results', { p_order_item_id: ids.order_item_id, p_results: result(false), p_target_status: 'Draft', p_amended_from_report_id: null, p_amendment_reason: null, p_expected_revision: 0 }),
    technicianB.rpc('save_test_results', { p_order_item_id: ids.order_item_id, p_results: result(false), p_target_status: 'Draft', p_amended_from_report_id: null, p_amendment_reason: null, p_expected_revision: 0 }),
  ])
  const winners = calls.filter(call => !call.error)
  const stale = calls.filter(call => call.error?.message?.includes('RESULT_REVISION_CONFLICT'))
  assert(winners.length === 1 && stale.length === 1, 'two-context revision race did not produce exactly one winner and one conflict', calls.map(call => call.error || call.data))
  assert(stale[0].error.code === 'PT409', 'stale revision did not return PT409', stale[0].error)
  return { data: { winner_count: winners.length, conflict_count: stale.length, conflict_code: stale[0].error.code, conflict_message: stale[0].error.message }, actor: 'Technician A JWT + Technician B JWT' }
}, async () => {
  const orderItem = await one('clinical_order_items', 'id,status,result_revision', 'id', ids.order_item_id)
  assert(orderItem.result_revision === 1, 'race winner did not advance revision exactly once', orderItem)
  return { result: await oneResult('id,status,display_value,flag,is_critical,critical_acknowledged,entered_by'), order_item: orderItem }
})
await step('Submit for verification', async () => Object.assign(await technician.rpc('save_test_results', { p_order_item_id: ids.order_item_id, p_results: result(false), p_target_status: 'SubmittedForVerification', p_amended_from_report_id: null, p_amendment_reason: null, p_expected_revision: 1 }), { actor: 'Technician JWT' }), async () => ({ result: await oneResult('id,status,is_critical,critical_acknowledged'), order_item: await one('clinical_order_items', 'id,status,result_revision', 'id', ids.order_item_id) }))
await step('Critical acknowledgement', async () => Object.assign(await verifier.rpc('record_critical_value_acknowledgement', { p_order_item_id: ids.order_item_id, p_notification_method: 'Direct Phone Call', p_notified_person: 'Synthetic Duty Clinician', p_comment: 'Synthetic staging acknowledgement only' }), { actor: 'Verifier JWT' }), async () => {
  const audit = await service.from('audit_logs').select('id,user_id,user_name,action,new_data,timestamp').eq('entity_id', ids.order_item_id).eq('action', 'CRITICAL_VALUE_ACKNOWLEDGED').order('timestamp', { ascending: false }).limit(1).single()
  assert(!audit.error, 'critical acknowledgement audit missing', audit)
  return audit.data
})
await step('Verification', async () => Object.assign(await verifier.rpc('save_test_results', { p_order_item_id: ids.order_item_id, p_results: result(true), p_target_status: 'Verified', p_amended_from_report_id: null, p_amendment_reason: null, p_expected_revision: 2 }), { actor: 'Verifier JWT' }), async () => ({ result: await oneResult('id,status,is_critical,critical_acknowledged,critical_acknowledged_by,verified_by,verified_at'), order_item: await one('clinical_order_items', 'id,status,result_revision', 'id', ids.order_item_id) }))
const correctedName = `Synthetic Corrected ${stamp}`
await step('Pre-signoff demographic reload', async () => Object.assign(await admin.rpc('update_patient_demographics', { p_patient_id: ids.patient_id, p_patient_data: { title: 'Ms.', full_name: correctedName, gender: 'Female', dob: null, age_years: 35, age_months: 0, age_days: 0, mobile, address: 'Corrected Synthetic Staging Address', email: null, identification_no: null } }), { actor: 'Admin JWT' }), async () => {
  const patient = await one('patients', 'id,uhid,full_name,address,mobile,updated_at', 'id', ids.patient_id)
  assert(patient.full_name === correctedName, 'demographic reload not current', patient)
  return patient
})
const performed = await admin.rpc('save_reporting_personnel', { p_personnel: { full_name: `Synthetic Performer ${stamp}`, professional_type: 'Lab Technologist', qualification: 'Synthetic MLT', registration_council: 'Synthetic Council', registration_number: `P-${stamp}`, specialization: null, phone: null, email: null, can_enter_results: true, can_verify_results: false, can_acknowledge_critical: false, can_sign_reports: false, is_active: true, display_order: 999 } })
if (performed.error) throw performed.error
const signatory = await admin.rpc('save_reporting_personnel', { p_personnel: { full_name: `Synthetic Signatory ${stamp}`, professional_type: 'Pathologist', qualification: 'Synthetic MD', registration_council: 'Synthetic Council', registration_number: `S-${stamp}`, specialization: 'Synthetic Pathology', phone: null, email: null, can_enter_results: false, can_verify_results: true, can_acknowledge_critical: true, can_sign_reports: true, is_active: true, display_order: 1000 } })
if (signatory.error) throw signatory.error
const rawToken = randomBytes(32).toString('base64url'); const tokenHash = createHash('sha256').update(rawToken).digest('hex'); const publicUrl = `https://lis.bimalpathology.com.np/r/${rawToken}`
await step('Sign-off → frozen snapshot → token → ReportReady queue', async () => Object.assign(await signingUser.rpc('sign_and_queue_diagnostic_report', { p_order_id: ids.order_id, p_performed_by_id: performed.data, p_signed_by_id: signatory.data, p_amendment_reason: null, p_amended_from_report_id: null, p_token_hash: tokenHash, p_public_report_url: publicUrl }), { actor: 'Signatory JWT' }), async data => {
  ids.report_id = data.report_id
  const [report, order, item, resultRow] = await Promise.all([
    one('diagnostic_reports', 'id,report_number,status,version,clinical_snapshot_json,integrity_hash,signed_at,patient_id,order_id', 'id', data.report_id), one('clinical_orders', 'id,status', 'id', ids.order_id),
    one('clinical_order_items', 'id,status', 'id', ids.order_item_id), service.from('test_results').select('id,parameter_id,status,signed_off_by,signed_off_at').eq('order_item_id', ids.order_item_id),
  ])
  assert(report.status === 'SignedOff' && report.integrity_hash?.length === 64, 'signed report/hash invalid', report)
  ids.report_number = report.report_number; ids.integrity_hash = report.integrity_hash
  ids.report_token_id = data.notification?.token_id; ids.report_token_hash = tokenHash
  assert(report.clinical_snapshot_json?.patient?.full_name === correctedName, 'snapshot did not reload current demographics', report.clinical_snapshot_json?.patient)
  assert(data.notification?.token_id && data.notification?.sms_queued === true, 'secure token/ReportReady response invalid', data.notification)
  return { report: { ...report, clinical_snapshot_json: { patient: report.clinical_snapshot_json.patient, order: report.clinical_snapshot_json.order, investigation_count: report.clinical_snapshot_json.investigations?.length, result_count: report.clinical_snapshot_json.investigations?.reduce((n, x) => n + (x.results?.length || 0), 0) } }, order, order_item: item, results: resultRow.data, token_id: data.notification.token_id, report_ready_queued: data.notification.sms_queued, public_url_shape: 'https://lis.bimalpathology.com.np/r/<secure-random-token>' }
})
await step('Canonical public report resolution', async () => Object.assign(await createClient(url, anonKey, { auth: { persistSession: false } }).rpc('resolve_public_report_by_token', { p_token_hash: tokenHash }), { actor: 'Anonymous PostgREST' }), async data => {
  assert(data?.valid === true && data?.report_number === ids.report_number && data?.integrity_hash === ids.integrity_hash, 'public report resolution mismatch', data)
  return { valid: data.valid, report_number: data.report_number, integrity_hash: data.integrity_hash, version: data.version, payload_keys: Object.keys(data || {}), canonical_report_document_input_available: Boolean(data.snapshot) }
})
const summary = { passed_steps: ledger.length, failed_steps: 0, report_id: ids.report_id, report_ready_queued: true, sms_provider_send_attempted: false }
await writeFile('artifacts/phase2-clinical-lifecycle.json', JSON.stringify({ summary, ids, ledger }, null, 2))
console.log(JSON.stringify(summary))
