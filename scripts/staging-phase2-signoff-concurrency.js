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
async function actor(label, role) {
  if (label === 'admin') return service
  return (await provisionSyntheticActor({ url, anonKey, management, label:`sign-${label}`, password, roleId:role })).client
}
const admin = await actor('admin', '00000000-0000-0000-0000-000000000001')
const tech = await actor('tech', '00000000-0000-0000-0000-000000000004')
const verifier = await actor('verifier', '00000000-0000-0000-0000-000000000007')
const signerA = await actor('signer-a', '00000000-0000-0000-0000-000000000008')
const signerB = await actor('signer-b', '00000000-0000-0000-0000-000000000008')
const must = (x, m, d) => { if (!x) throw new Error(`${m}: ${JSON.stringify(d)}`) }
const ok = async (promise, label) => { const r = await promise; if (r.error) throw new Error(`${label}: ${r.error.message}`); return r.data }
const tokenArgs = () => { const raw = randomBytes(32).toString('base64url'); return { hash: createHash('sha256').update(raw).digest('hex'), url: `https://lis.bimalpathology.com.np/r/${raw}` } }

const search = await ok(admin.rpc('search_billable_catalogue', { p_query: 'p2safe', p_limit: 50 }), 'search')
const enabled = await service.from('tests').select('id').eq('clinical_reporting_enabled', true).in('id', search.filter(x => x.entity_type === 'Test').map(x => x.entity_id)); if (enabled.error) throw enabled.error
const enabledIds = new Set(enabled.data.map(x => x.id))
const cbc = search.find(x => x.code.startsWith('P2SAFE_') && enabledIds.has(x.entity_id)); must(cbc, 'Clinically enabled synthetic test unavailable', search)
const mobile = `98${String(82000000 + (Date.now() % 10000000)).padStart(8, '0').slice(-8)}`
const patient = await ok(admin.rpc('create_patient', { p_patient_data: { mobile, title: 'Mr.', full_name: `Sign Concurrency ${stamp}`, gender: 'Male', dob: null, age_years: 40, age_months: 0, age_days: 0, address: 'Synthetic Staging', email: null, identification_no: null } }), 'patient')
const billed = await ok(admin.rpc('create_patient_bill_order_with_packages', {
  p_patient_data: { patient_id: patient.id, mobile, title: 'Mr.', full_name: patient.full_name, gender: 'Male', dob: null, age_years: 40, age_months: 0, age_days: 0, address: 'Synthetic Staging', email: null, identification_no: null },
  p_bill_data: { referring_doctor_id: null, referring_doctor_name_snapshot: 'Self / Walk-in', gross_amount_paisa: cbc.price_paisa, discount_amount_paisa: 0, discount_reason: null, paid_amount_paisa: 0, order_date_bs: null, remarks: 'Sign concurrency fixture' },
  p_items_data: [{ test_id: cbc.entity_id, test_code: cbc.code, test_name: cbc.name, reporting_type: cbc.reporting_type, outsource_lab_name: null, unit_price_paisa: cbc.price_paisa, manual_price_paisa: cbc.price_paisa, discount_paisa: 0, net_price_paisa: cbc.price_paisa, specimen_type: cbc.specimen, container_type: cbc.container, department: 'Hematology', item_description: null, zero_price_acknowledged: false }],
  p_payment_data: null, p_idempotency_key: `phase2-sign-${stamp}`, p_packages: [],
}), 'billing')
const order = await service.from('clinical_orders').select('id').eq('bill_id', billed.bill_id).single(); if (order.error) throw order.error
const sample = await service.from('samples').select('id').eq('order_id', order.data.id).single(); if (sample.error) throw sample.error
const item = await service.from('clinical_order_items').select('id,test_id,result_revision').eq('order_id', order.data.id).single(); if (item.error) throw item.error
await ok(tech.rpc('transition_sample_lifecycle', { p_sample_id: sample.data.id, p_to_status: 'Collected', p_reason: null }), 'collect')
await ok(tech.rpc('transition_sample_lifecycle', { p_sample_id: sample.data.id, p_to_status: 'Received', p_reason: null }), 'receive')
const parameters = await service.from('parameters').select('id,value_type').eq('test_id', item.data.test_id).eq('is_active', true).order('display_order'); if (parameters.error) throw parameters.error
const values = suffix => parameters.data.map((p, i) => ({ parameter_id: p.id, numeric_value: ['Numeric','Calculated'].includes(p.value_type) ? String(10 + i) : null, text_value: ['Numeric','Calculated'].includes(p.value_type) ? null : `Synthetic ${suffix}`, display_value: ['Numeric','Calculated'].includes(p.value_type) ? String(10 + i) : `Synthetic ${suffix}`, flag: 'Normal', is_critical: false, critical_acknowledged: false, normal_range_text: 'Synthetic staging snapshot', normal_min: '1', normal_max: '100', critical_low: null, critical_high: null }))
await ok(tech.rpc('save_test_results', { p_order_item_id: item.data.id, p_results: values('initial'), p_target_status: 'SubmittedForVerification', p_amended_from_report_id: null, p_amendment_reason: null, p_expected_revision: 0 }), 'submit')
await ok(verifier.rpc('save_test_results', { p_order_item_id: item.data.id, p_results: values('initial'), p_target_status: 'Verified', p_amended_from_report_id: null, p_amendment_reason: null, p_expected_revision: 1 }), 'verify')
const performer = await ok(admin.rpc('save_reporting_personnel', { p_personnel: { full_name: `Concurrency Performer ${stamp}`, professional_type: 'Lab Technologist', qualification: 'Synthetic MLT', registration_council: 'Synthetic Council', registration_number: `CP-${stamp}`, specialization: null, phone: null, email: null, can_enter_results: true, can_verify_results: false, can_acknowledge_critical: false, can_sign_reports: false, is_active: true, display_order: 999 } }), 'performer')
const signatory = await ok(admin.rpc('save_reporting_personnel', { p_personnel: { full_name: `Concurrency Signatory ${stamp}`, professional_type: 'Pathologist', qualification: 'Synthetic MD', registration_council: 'Synthetic Council', registration_number: `CS-${stamp}`, specialization: 'Synthetic', phone: null, email: null, can_enter_results: false, can_verify_results: true, can_acknowledge_critical: true, can_sign_reports: true, is_active: true, display_order: 1000 } }), 'signatory')
const sign = (client, amendment = null, reason = null) => { const t = tokenArgs(); return client.rpc('sign_and_queue_diagnostic_report', { p_order_id: order.data.id, p_performed_by_id: performer, p_signed_by_id: signatory, p_amendment_reason: reason, p_amended_from_report_id: amendment, p_token_hash: t.hash, p_public_report_url: t.url }) }

const initialConcurrent = await Promise.all([sign(signerA), sign(signerB)])
must(initialConcurrent.every(x => !x.error), 'concurrent initial sign failed', initialConcurrent.map(x => x.error?.message))
const initialIds = initialConcurrent.map(x => x.data.report_id)
must(new Set(initialIds).size === 1, 'concurrent initial created multiple reports', initialIds)
const initialId = initialIds[0]
const double = await sign(signerA); const retry = await sign(signerB)
must(!double.error && !retry.error && double.data.report_id === initialId && retry.data.report_id === initialId, 'double/retry mismatch', { double, retry })

async function versionState(version) {
  const reports = await service.from('diagnostic_reports').select('id,version,status,integrity_hash,clinical_snapshot_json').eq('order_id', order.data.id).eq('version', version)
  if (reports.error) throw reports.error
  return { reports: reports.data }
}
const v1 = await versionState(1)
const initialResponses = [...initialConcurrent.map(x => x.data), double.data, retry.data]
const v1TokenIds = initialResponses.map(x => x.notification?.token_id).filter(Boolean)
must(v1.reports.length === 1 && v1TokenIds.length >= 1 && new Set(v1TokenIds).size === 1 && initialResponses.every(x => x.report_id === initialId), 'version 1 uniqueness failed', { v1, v1TokenIds, initialResponses })

const amendmentReason = 'Synthetic concurrency amendment validation'
const amendmentSubmit = await admin.rpc('save_test_results', { p_order_item_id: item.data.id, p_results: values('amended'), p_target_status: 'SubmittedForVerification', p_amended_from_report_id: initialId, p_amendment_reason: amendmentReason, p_expected_revision: 2 })
if (amendmentSubmit.error) {
  const failed = {
    summary: { passed: false, initial_replay_passed: true, amendment_replay_passed: false, provider_send_attempted: false },
    failure: { stage: 'amendment_submit', message: amendmentSubmit.error.message, code: amendmentSubmit.error.code },
    order_id: order.data.id,
    initial: { report_id: initialId, call_report_ids: initialIds, replay_flags: initialConcurrent.map(x => x.data.idempotency_replay), double_replay: double.data.idempotency_replay, retry_replay: retry.data.idempotency_replay, state: v1 },
  }
  await writeFile('artifacts/phase2-signoff-concurrency.json', JSON.stringify(failed, null, 2))
  console.log(JSON.stringify(failed.summary))
  process.exitCode = 2
} else {
await ok(admin.rpc('save_test_results', { p_order_item_id: item.data.id, p_results: values('amended'), p_target_status: 'Verified', p_amended_from_report_id: initialId, p_amendment_reason: amendmentReason, p_expected_revision: 3 }), 'amend verify')
const amendedConcurrent = await Promise.all([sign(signerA, initialId, amendmentReason), sign(signerB, initialId, amendmentReason)])
must(amendedConcurrent.every(x => !x.error), 'concurrent amendment failed', amendedConcurrent.map(x => x.error?.message))
const amendedIds = amendedConcurrent.map(x => x.data.report_id)
must(new Set(amendedIds).size === 1, 'amendment replay created multiple versions', amendedIds)
const amendedId = amendedIds[0]
const amendmentReplay = await sign(signerA, initialId, amendmentReason)
must(!amendmentReplay.error && amendmentReplay.data.report_id === amendedId, 'amendment retry mismatch', amendmentReplay)
const v2 = await versionState(2)
const amendmentResponses = [...amendedConcurrent.map(x => x.data), amendmentReplay.data]
const v2TokenIds = amendmentResponses.map(x => x.notification?.token_id).filter(Boolean)
must(v2.reports.length === 1 && v2TokenIds.length >= 1 && new Set(v2TokenIds).size === 1 && amendmentResponses.every(x => x.report_id === amendedId), 'version 2 uniqueness failed', { v2, v2TokenIds, amendmentResponses })
const allReports = await service.from('diagnostic_reports').select('id,version,status,integrity_hash,amended_from_report_id').eq('order_id', order.data.id).order('version')
must(allReports.data.length === 2 && new Set(allReports.data.map(x => x.integrity_hash)).size === 2, 'duplicated/missing frozen snapshot versions', allReports.data)
const result = {
  summary: { passed: true, initial_concurrent_calls: 2, double_sign_calls: 1, retry_calls: 1, amendment_concurrent_calls: 2, amendment_retry_calls: 1, logical_reports: 2, versions: [1,2], provider_send_attempted: false },
  order_id: order.data.id,
  initial: { report_id: initialId, call_report_ids: initialIds, replay_flags: initialConcurrent.map(x => x.data.idempotency_replay), double_replay: double.data.idempotency_replay, retry_replay: retry.data.idempotency_replay, state: v1 },
  amendment: { report_id: amendedId, call_report_ids: amendedIds, replay_flags: amendedConcurrent.map(x => x.data.idempotency_replay), retry_replay: amendmentReplay.data.idempotency_replay, state: v2 },
  reports: allReports.data,
}
await writeFile('artifacts/phase2-signoff-concurrency.json', JSON.stringify(result, null, 2))
console.log(JSON.stringify(result.summary))
}
