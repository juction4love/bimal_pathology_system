/**
 * Synthetic final-core runtime acceptance.
 *
 * Despite the historical filename, this harness is staging-only. It aborts
 * before Auth/PostgREST access unless the shared guard proves the exact
 * isolated project and migration head 00052.
 */
import { createClient } from '@supabase/supabase-js'
import { writeFile } from 'node:fs/promises'
import { getAdminCredential } from './lib/testCredentials.js'
import { assertSyntheticStagingTarget } from './staging-target-guard.js'

const EXPECTED_MIGRATION_HEAD = '00052'
if (process.env.STAGING_EXPECTED_MIGRATION_HEAD !== EXPECTED_MIGRATION_HEAD) {
  throw new Error(`STAGING_EXPECTED_MIGRATION_HEAD must equal ${EXPECTED_MIGRATION_HEAD}`)
}

const target = assertSyntheticStagingTarget({ expectedHead: EXPECTED_MIGRATION_HEAD })
const url = process.env.STAGING_SUPABASE_URL
const anonKey = process.env.STAGING_ANON_KEY
if (!url || !anonKey) throw new Error('STAGING_SUPABASE_URL and STAGING_ANON_KEY are required')

const admin = createClient(url, anonKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})
const login = await admin.auth.signInWithPassword(getAdminCredential())
if (login.error) throw login.error

let passed = 0
const results = []
const check = (condition, name, details = {}) => {
  if (!condition) throw new Error(`FAIL: ${name}${details.error ? ` — ${details.error}` : ''}`)
  passed += 1
  results.push({ name, pass: true, ...details })
  console.log(`PASS: ${name}`)
}

const query = process.env.STAGING_CORE_TEST_QUERY?.trim() || 'cbc'
const catalogue = await admin.rpc('search_billable_catalogue', { p_query: query, p_limit: 20 })
if (catalogue.error) throw catalogue.error
const selectedTest = catalogue.data?.find((row) => (
  row.entity_type === 'Test'
  && row.reporting_type !== 'NoReporting'
  && row.price_paisa > 0
))
if (!selectedTest) throw new Error(`No positive-price active staging test matched ${query}`)

const suffix = `${Date.now()}`.slice(-8)
const pricePaisa = Number(selectedTest.price_paisa)
const patient = {
  mobile: `98${suffix}`,
  title: 'Mr.',
  full_name: `Synthetic Final Core ${suffix}`,
  gender: 'Male',
  age_years: 30,
  age_months: 0,
  age_days: 0,
  address: 'Synthetic Isolated Staging',
  email: null,
  identification_no: null,
}
const bill = {
  referring_doctor_id: null,
  referring_doctor_name_snapshot: 'Self / Walk-in',
  gross_amount_paisa: pricePaisa,
  discount_amount_paisa: 0,
  discount_reason: null,
  paid_amount_paisa: 0,
  order_date_bs: null,
  remarks: 'Synthetic isolated-staging final-core acceptance',
}
const items = [{
  test_id: selectedTest.entity_id,
  test_code: selectedTest.code,
  test_name: selectedTest.name,
  reporting_type: selectedTest.reporting_type,
  outsource_lab_name: null,
  unit_price_paisa: pricePaisa,
  manual_price_paisa: pricePaisa,
  discount_paisa: 0,
  net_price_paisa: pricePaisa,
  specimen_type: selectedTest.specimen,
  container_type: selectedTest.container,
  department: selectedTest.category,
  item_description: null,
  zero_price_acknowledged: false,
}]
const idempotencyKey = crypto.randomUUID()
const args = {
  p_patient_data: patient,
  p_bill_data: bill,
  p_items_data: items,
  p_payment_data: null,
  p_idempotency_key: idempotencyKey,
  p_packages: [],
}

const [first, replay] = await Promise.all([
  admin.rpc('create_patient_bill_order_with_packages', args),
  admin.rpc('create_patient_bill_order_with_packages', args),
])
check(!first.error && !replay.error, 'concurrent package-aware billing requests complete', {
  error: first.error?.message || replay.error?.message,
})
check(
  first.data.bill_id === replay.data.bill_id && first.data.order_id === replay.data.order_id,
  'same caller and idempotency key produce one logical bill/order',
)
check(
  Boolean(first.data.idempotency_replay) !== Boolean(replay.data.idempotency_replay),
  'exactly one concurrent response is an idempotent replay',
)

const changed = await admin.rpc('create_patient_bill_order_with_packages', {
  ...args,
  p_bill_data: { ...bill, remarks: 'Different synthetic payload' },
})
check(Boolean(changed.error), 'same idempotency key with different payload is rejected')

const [billCount, orderCount, sampleRows] = await Promise.all([
  admin.from('bills').select('*', { count: 'exact', head: true }).eq('id', first.data.bill_id),
  admin.from('clinical_orders').select('*', { count: 'exact', head: true }).eq('id', first.data.order_id),
  admin.from('samples').select('id,status').eq('order_id', first.data.order_id),
])
check(billCount.count === 1 && orderCount.count === 1, 'concurrent finalize leaves one bill and one clinical order')
check(sampleRows.data?.length === 1 && sampleRows.data[0].status === 'Pending', 'billing creates one pending sample')

const sampleId = sampleRows.data[0].id
const collected = await admin.rpc('transition_sample_lifecycle', {
  p_sample_id: sampleId,
  p_to_status: 'Collected',
  p_reason: 'Synthetic isolated-staging collection',
})
check(!collected.error && collected.data?.status === 'Collected', 'guarded sample collection succeeds', { error: collected.error?.message })
const repeated = await admin.rpc('transition_sample_lifecycle', {
  p_sample_id: sampleId,
  p_to_status: 'Collected',
  p_reason: 'Synthetic invalid replay',
})
check(Boolean(repeated.error), 'invalid repeated sample transition is rejected')
const received = await admin.rpc('transition_sample_lifecycle', {
  p_sample_id: sampleId,
  p_to_status: 'Received',
  p_reason: 'Synthetic isolated-staging accession',
})
check(!received.error && received.data?.status === 'Received', 'guarded sample accession succeeds', { error: received.error?.message })

const direct = await admin.from('samples').update({ status: 'Pending' }).eq('id', sampleId).select('id')
check(Boolean(direct.error) || direct.data?.length === 0, 'direct sample-table mutation remains denied')

await writeFile('artifacts/final-core-runtime.json', JSON.stringify({
  target,
  summary: { pass: passed, fail: 0, real_patient_data_used: false },
  results,
}, null, 2))
console.log(`SYNTHETIC STAGING FINAL CORE: ${passed} PASSED, 0 FAILED`)
