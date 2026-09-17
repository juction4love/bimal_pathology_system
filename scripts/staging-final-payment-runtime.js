import { createClient } from '@supabase/supabase-js'
import { writeFile } from 'node:fs/promises'
import { assertSyntheticStagingTarget } from './staging-target-guard.js'

const { STAGING_SUPABASE_URL: url, STAGING_ANON_KEY: anonKey, STAGING_SERVICE_KEY: serviceKey, STAGING_TEST_PASSWORD: password } = process.env
if (!url || !anonKey || !serviceKey || !password) throw new Error('Staging environment variables are required')
const target = assertSyntheticStagingTarget({ expectedHead: process.env.STAGING_EXPECTED_MIGRATION_HEAD })
const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
const billing = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })
const stamp = Date.now().toString(36)
const results = []
const record = (name, pass, details = {}) => results.push({ name, pass, ...details })

const email = `final-payment-${stamp}@example.invalid`
const made = await service.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name: 'Final Payment Operator' } })
if (made.error) throw made.error
await service.from('user_profiles').update({ is_active: true }).eq('id', made.data.user.id).throwOnError()
await service.from('user_roles').delete().eq('user_id', made.data.user.id).throwOnError()
await service.from('user_roles').insert({ user_id: made.data.user.id, role_id: '00000000-0000-0000-0000-000000000001' }).throwOnError()
const login = await billing.auth.signInWithPassword({ email, password })
if (login.error) throw login.error

const search = await billing.rpc('search_billable_catalogue', { p_query: 'cbc', p_limit: 5 })
if (search.error) throw search.error
const test = search.data.find(row => row.code === 'CBC')
if (!test) throw new Error('CBC is not available as a controlled Active billing fixture')
let mobileCounter = 0
const nextMobile = () => `98${String(91000000 + ((Date.now() + mobileCounter++) % 8000000)).slice(-8)}`

function billArgs(label, paidPaisa) {
  const mobile = nextMobile()
  return {
    mobile,
    args: {
      p_patient_data: { mobile, title: 'Ms.', full_name: `Final Payment ${label} ${stamp}`, gender: 'Female', dob: null, age_years: 32, age_months: 0, age_days: 0, address: 'Synthetic Staging', email: null, identification_no: null },
      p_bill_data: { referring_doctor_id: null, referring_doctor_name_snapshot: 'Self / Walk-in', gross_amount_paisa: test.price_paisa, discount_amount_paisa: 0, discount_reason: null, paid_amount_paisa: paidPaisa, order_date_bs: null, remarks: `Synthetic ${label}` },
      p_items_data: [{ test_id: test.entity_id, test_code: test.code, test_name: test.name, reporting_type: test.reporting_type, outsource_lab_name: null, unit_price_paisa: test.price_paisa, manual_price_paisa: test.price_paisa, discount_paisa: 0, net_price_paisa: test.price_paisa, specimen_type: test.specimen, container_type: test.container, department: test.category, item_description: null, zero_price_acknowledged: false }],
      p_payment_data: paidPaisa > 0 ? { payment_mode: 'Cash', transaction_reference: null, remarks: `Synthetic ${label}`, received_by_name: 'Final Payment Operator' } : null,
      p_idempotency_key: `final-payment-${label}-${stamp}`,
      p_packages: [],
    },
  }
}

async function createBill(label, paid) {
  const request = billArgs(label, paid)
  const response = await billing.rpc('create_patient_bill_order_with_packages', request.args)
  if (response.error) throw response.error
  const bill = await service.from('bills').select('id,net_amount_paisa,paid_amount_paisa,due_amount_paisa,payment_status,patient_id').eq('id', response.data.bill_id).single()
  if (bill.error) throw bill.error
  return { request, response: response.data, bill: bill.data }
}

const unpaid = await createBill('unpaid', 0)
record('unpaid bill retains full due and no payment row', unpaid.bill.paid_amount_paisa === 0 && unpaid.bill.due_amount_paisa === unpaid.bill.net_amount_paisa && unpaid.bill.payment_status === 'Due', { bill: unpaid.bill })

const full = await createBill('full', test.price_paisa)
const fullPayments = await service.from('payment_transactions').select('id,amount_paisa').eq('bill_id', full.bill.id)
record('full payment closes due with immutable payment snapshot', full.bill.due_amount_paisa === 0 && full.bill.payment_status === 'Paid' && fullPayments.data?.length === 1 && fullPayments.data[0].amount_paisa === test.price_paisa, { bill: full.bill, payments: fullPayments.data })

const initialPartial = Math.max(1, Math.floor(test.price_paisa / 3))
const partial = await createBill('partial', initialPartial)
record('partial payment leaves exact due', partial.bill.payment_status === 'Partial' && partial.bill.due_amount_paisa === test.price_paisa - initialPartial, { bill: partial.bill })

const partialPatient = await service.from('patients').select('*').eq('id', partial.bill.patient_id).single()
if (partialPatient.error) throw partialPatient.error
const correctedMobile = nextMobile()
const mobileCorrection = await billing.rpc('update_patient_demographics', {
  p_patient_id: partial.bill.patient_id,
  p_patient_data: {
    title: partialPatient.data.title, full_name: partialPatient.data.full_name,
    gender: partialPatient.data.gender, dob: partialPatient.data.dob,
    age_years: partialPatient.data.age_years, age_months: partialPatient.data.age_months,
    age_days: partialPatient.data.age_days, mobile: correctedMobile,
    address: partialPatient.data.address, email: partialPatient.data.email,
    identification_no: partialPatient.data.identification_no,
  },
})
if (mobileCorrection.error) throw mobileCorrection.error

const additionalAmount = Math.max(1, Math.floor(partial.bill.due_amount_paisa / 2))
const additionalArgs = {
  p_bill_id: partial.bill.id, p_amount_paisa: additionalAmount, p_payment_mode: 'Cash',
  p_transaction_reference: null, p_remarks: 'Synthetic additional payment',
  p_idempotency_key: `final-additional-${stamp}`,
}
const concurrentReplay = await Promise.all([
  billing.rpc('receive_bill_payment', additionalArgs),
  billing.rpc('receive_bill_payment', additionalArgs),
])
record('concurrent same-key additional payment commits exactly once', concurrentReplay.every(x => !x.error) && concurrentReplay[0].data.payment_id === concurrentReplay[1].data.payment_id && concurrentReplay.some(x => x.data.idempotency_replay), { errors: concurrentReplay.map(x => x.error?.message), payment_ids: concurrentReplay.map(x => x.data?.payment_id), replay: concurrentReplay.map(x => x.data?.idempotency_replay) })
const afterReplay = await service.from('bills').select('paid_amount_paisa,due_amount_paisa,payment_status').eq('id', partial.bill.id).single()
const partialPayments = await service.from('payment_transactions').select('id,amount_paisa').eq('bill_id', partial.bill.id)
record('additional-payment totals and immutable history are exact', !afterReplay.error && partialPayments.data?.length === 2 && partialPayments.data.reduce((sum, row) => sum + row.amount_paisa, 0) === afterReplay.data.paid_amount_paisa && afterReplay.data.due_amount_paisa === test.price_paisa - initialPartial - additionalAmount, { bill: afterReplay.data, payments: partialPayments.data })

const competing = await createBill('competing', 0)
const competingAmount = Math.max(1, Math.floor((test.price_paisa * 7) / 10))
const competingCalls = await Promise.all([
  billing.rpc('receive_bill_payment', { p_bill_id: competing.bill.id, p_amount_paisa: competingAmount, p_payment_mode: 'Cash', p_transaction_reference: null, p_remarks: 'Competing A', p_idempotency_key: `competing-a-${stamp}` }),
  billing.rpc('receive_bill_payment', { p_bill_id: competing.bill.id, p_amount_paisa: competingAmount, p_payment_mode: 'Cash', p_transaction_reference: null, p_remarks: 'Competing B', p_idempotency_key: `competing-b-${stamp}` }),
])
const afterCompeting = await service.from('bills').select('net_amount_paisa,paid_amount_paisa,due_amount_paisa').eq('id', competing.bill.id).single()
record('competing payments serialize and overpayment is rejected', competingCalls.filter(x => !x.error).length === 1 && competingCalls.filter(x => x.error).length === 1 && afterCompeting.data.paid_amount_paisa <= afterCompeting.data.net_amount_paisa && afterCompeting.data.due_amount_paisa >= 0, { errors: competingCalls.map(x => x.error?.message), bill: afterCompeting.data })

const digitalMissingRef = await billing.rpc('receive_bill_payment', { p_bill_id: unpaid.bill.id, p_amount_paisa: 1, p_payment_mode: 'eSewa', p_transaction_reference: null, p_remarks: 'Invalid digital payment', p_idempotency_key: `digital-missing-${stamp}` })
record('digital payment without reference is rejected', Boolean(digitalMissingRef.error), { error: digitalMissingRef.error?.message })

const paymentIds = partialPayments.data.map(row => row.id)
const directUpdate = await billing.from('payment_transactions').update({ amount_paisa: 1 }).in('id', paymentIds)
const directDelete = await billing.from('payment_transactions').delete().in('id', paymentIds)
record('payment history cannot be updated or deleted by browser', Boolean(directUpdate.error) && Boolean(directDelete.error), { update_error: directUpdate.error?.message, delete_error: directDelete.error?.message })

const paymentQueue = await service.from('sms_queue_items').select('id,status,idempotency_key,recipient_phone,message_body,bill_id').eq('bill_id', partial.bill.id).like('idempotency_key', 'PAYMENT_CONFIRMATION:%')
const order = await service.from('clinical_orders').select('order_number').eq('bill_id', partial.bill.id).single()
const additionalPaymentId = concurrentReplay.find(response => response.data?.payment_id)?.data?.payment_id
const additionalQueue = paymentQueue.data?.find(row => row.idempotency_key === `PAYMENT_CONFIRMATION:${additionalPaymentId}`)
record('Payment Confirmation queue uses corrected current mobile, Lab No and remains pending', !paymentQueue.error && paymentQueue.data.length === 2 && paymentQueue.data.every(row => row.status === 'Pending' && row.message_body.includes(order.data.order_number)) && additionalQueue?.recipient_phone === correctedMobile, { queue_count: paymentQueue.data?.length, statuses: paymentQueue.data?.map(row => row.status), corrected_recipient_match: additionalQueue?.recipient_phone === correctedMobile, lab_no: order.data?.order_number })

const summary = { pass: results.filter(x => x.pass).length, fail: results.filter(x => !x.pass).length, sms_provider_send_attempted: false }
await writeFile('artifacts/final-payment-runtime.json', JSON.stringify({ target, summary, results }, null, 2))
console.log(JSON.stringify(summary))
if (summary.fail) process.exitCode = 1
