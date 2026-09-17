import { createClient } from '@supabase/supabase-js'
import { writeFile } from 'node:fs/promises'
import { assertSyntheticStagingTarget } from './staging-target-guard.js'

const { STAGING_SUPABASE_URL: url, STAGING_ANON_KEY: anonKey, STAGING_SERVICE_KEY: serviceKey, STAGING_TEST_PASSWORD: password } = process.env
if (!url || !anonKey || !serviceKey || !password) throw new Error('Staging environment variables are required')
const target = assertSyntheticStagingTarget({ expectedHead: process.env.STAGING_EXPECTED_MIGRATION_HEAD })
const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
const admin = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })
const stamp = Date.now().toString(36)
const results = []
const record = (name, pass, details = {}) => results.push({ name, pass, ...details })

const email = `final-patient-${stamp}@example.invalid`
const made = await service.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name: 'Final Patient Admin' } })
if (made.error) throw made.error
await service.from('user_profiles').update({ is_active: true }).eq('id', made.data.user.id).throwOnError()
await service.from('user_roles').delete().eq('user_id', made.data.user.id).throwOnError()
await service.from('user_roles').insert({ user_id: made.data.user.id, role_id: '00000000-0000-0000-0000-000000000001' }).throwOnError()
const login = await admin.auth.signInWithPassword({ email, password })
if (login.error) throw login.error

const mobileA = `98${String(93000000 + (Date.now() % 6000000)).slice(-8)}`
const mobileB = `97${String(93000000 + ((Date.now() + 17) % 6000000)).slice(-8)}`
const created = await admin.rpc('create_patient', { p_patient_data: { mobile: mobileA, title: 'Ms.', full_name: `Synthetic Patient ${stamp}`, gender: 'Female', dob: null, age_years: 28, age_months: 4, age_days: 2, address: 'Synthetic Staging', email: null, identification_no: null } })
if (created.error) throw created.error
const patientId = created.data.id || created.data.patient_id
const first = await service.from('patients').select('*').eq('id', patientId).single()
record('Add patient creates immutable 10-digit UHID', !first.error && /^\d{10}$/.test(first.data.uhid), { patient_id: patientId, uhid_shape: /^\d{10}$/.test(first.data?.uhid) })
const uhid = first.data.uhid

const duplicate = await admin.rpc('create_patient', { p_patient_data: { mobile: mobileA, title: 'Mr.', full_name: 'Duplicate Synthetic', gender: 'Male', dob: null, age_years: 20, age_months: 0, age_days: 0, address: 'Synthetic', email: null, identification_no: null } })
record('duplicate normalized mobile is rejected', Boolean(duplicate.error), { error: duplicate.error?.message })

const unicodeName = `श्रीमती परीक्षण ${stamp}`
const edited = await admin.rpc('update_patient_demographics', { p_patient_id: patientId, p_patient_data: { title: 'Mrs.', full_name: unicodeName, gender: 'Female', dob: null, age_years: 29, age_months: 1, age_days: 0, mobile: mobileA, address: 'भरतपुर-७, चितवन', email: null, identification_no: `SYN-${stamp}` } })
if (edited.error) throw edited.error
const afterEdit = await service.from('patients').select('*').eq('id', patientId).single()
record('name/address/age/gender and Unicode edit persists without changing UHID', afterEdit.data.full_name === unicodeName && afterEdit.data.address.includes('चितवन') && afterEdit.data.age_years === 29 && afterEdit.data.uhid === uhid, { uhid_unchanged: afterEdit.data.uhid === uhid, unicode_name_match: afterEdit.data.full_name === unicodeName })

const search = await admin.rpc('search_billable_catalogue', { p_query: 'cbc', p_limit: 5 })
if (search.error) throw search.error
const test = search.data.find(row => row.code === 'CBC')
if (!test) throw new Error('CBC fixture unavailable')
function billRequest(key) {
  return {
    p_patient_data: { patient_id: patientId, mobile: mobileA, title: afterEdit.data.title, full_name: afterEdit.data.full_name, gender: afterEdit.data.gender, dob: afterEdit.data.dob, age_years: afterEdit.data.age_years, age_months: afterEdit.data.age_months, age_days: afterEdit.data.age_days, address: afterEdit.data.address, email: afterEdit.data.email, identification_no: afterEdit.data.identification_no },
    p_bill_data: { referring_doctor_id: null, referring_doctor_name_snapshot: 'Self / Walk-in', gross_amount_paisa: test.price_paisa, discount_amount_paisa: 0, discount_reason: null, paid_amount_paisa: 0, order_date_bs: null, remarks: 'Synthetic patient history' },
    p_items_data: [{ test_id: test.entity_id, test_code: test.code, test_name: test.name, reporting_type: test.reporting_type, outsource_lab_name: null, unit_price_paisa: test.price_paisa, manual_price_paisa: test.price_paisa, discount_paisa: 0, net_price_paisa: test.price_paisa, specimen_type: test.specimen, container_type: test.container, department: test.category, item_description: null, zero_price_acknowledged: false }],
    p_payment_data: null, p_idempotency_key: key, p_packages: [],
  }
}
const billed = await admin.rpc('create_patient_bill_order_with_packages', billRequest(`patient-history-${stamp}`))
if (billed.error) throw billed.error
const billSnapshot = await service.from('bills').select('id,patient_id,patient_name_snapshot,patient_mobile_snapshot').eq('id', billed.data.bill_id).single()
const orderHistory = await service.from('clinical_orders').select('id,patient_id,bill_id').eq('patient_id', patientId)
record('History links one canonical patient to bill and clinical order', billSnapshot.data.patient_id === patientId && orderHistory.data.some(row => row.bill_id === billed.data.bill_id), { bills: 1, orders: orderHistory.data?.length })

const corrected = await admin.rpc('update_patient_demographics', { p_patient_id: patientId, p_patient_data: { title: afterEdit.data.title, full_name: `${unicodeName} सुधार`, gender: afterEdit.data.gender, dob: afterEdit.data.dob, age_years: afterEdit.data.age_years, age_months: afterEdit.data.age_months, age_days: afterEdit.data.age_days, mobile: mobileB, address: afterEdit.data.address, email: afterEdit.data.email, identification_no: afterEdit.data.identification_no } })
if (corrected.error) throw corrected.error
const afterCorrection = await service.from('patients').select('uhid,mobile,full_name').eq('id', patientId).single()
const billAfterCorrection = await service.from('bills').select('patient_name_snapshot,patient_mobile_snapshot').eq('id', billed.data.bill_id).single()
record('mobile/name correction keeps UHID and historical bill snapshots immutable', afterCorrection.data.uhid === uhid && afterCorrection.data.mobile === mobileB && billAfterCorrection.data.patient_mobile_snapshot === mobileA && billAfterCorrection.data.patient_name_snapshot === unicodeName, { uhid_unchanged: afterCorrection.data.uhid === uhid, current_mobile_corrected: afterCorrection.data.mobile === mobileB, historical_mobile_unchanged: billAfterCorrection.data.patient_mobile_snapshot === mobileA })

const archived = await admin.rpc('set_patient_archived', { p_patient_id: patientId, p_archived: true })
if (archived.error) throw archived.error
const archivedBillAttempt = await admin.rpc('create_patient_bill_order_with_packages', { ...billRequest(`archived-denied-${stamp}`), p_patient_data: { ...billRequest('unused').p_patient_data, mobile: mobileB, full_name: afterCorrection.data.full_name } })
record('archived patient is unavailable for new billing', Boolean(archivedBillAttempt.error), { error: archivedBillAttempt.error?.message })
const restored = await admin.rpc('set_patient_archived', { p_patient_id: patientId, p_archived: false })
if (restored.error) throw restored.error
const restoredRow = await service.from('patients').select('is_active,uhid').eq('id', patientId).single()
record('Archive/Restore retains UHID continuity', restoredRow.data.is_active === true && restoredRow.data.uhid === uhid)

const referencedDelete = await admin.rpc('delete_unused_patient', { p_patient_id: patientId })
record('referenced patient cannot be hard deleted', Boolean(referencedDelete.error), { error: referencedDelete.error?.message })

const unusedMobile = `98${String(94000000 + ((Date.now() + 31) % 5000000)).slice(-8)}`
const unused = await admin.rpc('create_patient', { p_patient_data: { mobile: unusedMobile, title: 'Mr.', full_name: `Unused Synthetic ${stamp}`, gender: 'Male', dob: null, age_years: 40, age_months: 0, age_days: 0, address: 'Synthetic', email: null, identification_no: null } })
if (unused.error) throw unused.error
const unusedId = unused.data.id || unused.data.patient_id
const unusedDelete = await admin.rpc('delete_unused_patient', { p_patient_id: unusedId })
const unusedGone = await service.from('patients').select('id').eq('id', unusedId).maybeSingle()
record('never-referenced patient can be safely deleted', !unusedDelete.error && !unusedGone.data, { error: unusedDelete.error?.message })

const patientAudit = await service.from('audit_logs').select('action,user_id').eq('entity_type', 'Patient').eq('entity_id', patientId)
const expectedAudit = ['PATIENT_CREATED', 'PATIENT_DEMOGRAPHICS_UPDATED', 'PATIENT_ARCHIVED', 'PATIENT_RESTORED']
record('patient lifecycle writes server-authored audit evidence', !patientAudit.error && expectedAudit.every(action => patientAudit.data.some(row => row.action === action && row.user_id === made.data.user.id)), { actions: patientAudit.data?.map(row => row.action) })

const summary = { pass: results.filter(x => x.pass).length, fail: results.filter(x => !x.pass).length, real_patient_data_used: false }
await writeFile('artifacts/final-patient-runtime.json', JSON.stringify({ target, summary, results }, null, 2))
console.log(JSON.stringify(summary))
if (summary.fail) process.exitCode = 1
