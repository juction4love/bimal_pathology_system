import { writeFile } from 'node:fs/promises'
import { assertSyntheticStagingTarget } from './staging-target-guard.js'
import { bootstrapAdminClient } from './hosted-synthetic-actors.js'
const { STAGING_SUPABASE_URL: url, STAGING_ANON_KEY: anonKey, STAGING_SERVICE_KEY: serviceKey, STAGING_TEST_PASSWORD: password } = process.env
if (!url || !anonKey || !serviceKey || !password) throw new Error('Staging environment variables are required')
assertSyntheticStagingTarget({ expectedHead: process.env.STAGING_EXPECTED_MIGRATION_HEAD })
const service = await bootstrapAdminClient(url, anonKey)
const client = service
const stamp = Date.now().toString(36)
const active = await service.from('tests').select('*').like('code', 'P2SAFE_%').eq('lifecycle_status', 'Active').order('created_at', { ascending: false }).limit(1).single()
if (active.error) throw active.error
const test = active.data
const results = []
const record = (name, pass, details = {}) => results.push({ name, pass, ...details })
const updateTest = async patch => {
  const current = await service.from('tests').select('*').eq('id', test.id).single()
  if (current.error) throw current.error
  const saved = await client.rpc('catalogue_save_test', { p_test: { ...current.data, ...patch }, p_expected_version: current.data.row_version })
  if (saved.error) throw saved.error
}
let mobileCounter = 0
const payload = (key, rate, ack = false, packages = []) => ({
  p_patient_data: { mobile: `98${String(70000000 + mobileCounter++).padStart(8, '0')}`, title: 'Mr.', full_name: `Phase Two Billing ${stamp}`, gender: 'Male', dob: null, age_years: 30, age_months: 0, age_days: 0, address: 'Synthetic Staging', email: null, identification_no: null },
  p_bill_data: { referring_doctor_id: null, referring_doctor_name_snapshot: 'Self', gross_amount_paisa: rate, discount_amount_paisa: 0, discount_reason: null, paid_amount_paisa: 0, order_date_bs: null, remarks: 'Synthetic staging acceptance' },
  p_items_data: [{ test_id: test.id, test_code: test.code, test_name: test.name, reporting_type: test.reporting_type, outsource_lab_name: null, unit_price_paisa: rate, manual_price_paisa: rate, discount_paisa: 0, net_price_paisa: rate, specimen_type: test.sample_type, container_type: test.container, department: test.department, item_description: null, zero_price_acknowledged: ack }],
  p_payment_data: null, p_idempotency_key: key, p_packages: packages,
})
const fixedArgs = payload(`p2-fixed-${stamp}`, test.price_paisa)
const simultaneous = await Promise.all([client.rpc('create_patient_bill_order_with_packages', fixedArgs), client.rpc('create_patient_bill_order_with_packages', fixedArgs)])
record('rapid finalize/idempotent replay', simultaneous.every(x => !x.error) && simultaneous[0].data.bill_id === simultaneous[1].data.bill_id && simultaneous.some(x => x.data.idempotency_replay), { errors: simultaneous.map(x => x.error?.message || null), bill_ids: simultaneous.map(x => x.data?.bill_id) })
const billId = simultaneous[0].data?.bill_id
const [bills, items, orders] = await Promise.all([
  service.from('bills').select('id').eq('id', billId), service.from('bill_items').select('id,unit_price_paisa,test_id').eq('bill_id', billId),
  service.from('clinical_orders').select('id,order_number').eq('bill_id', billId),
])
const samples = orders.data?.[0]?.id ? await service.from('samples').select('id,order_id').eq('order_id', orders.data[0].id) : { data: [] }
record('one bill/order and correct sample', bills.data?.length === 1 && items.data?.length === 1 && orders.data?.length === 1 && samples.data?.length === 1, { bills: bills.data?.length, items: items.data?.length, orders: orders.data?.length, samples: samples.data?.length, sample_error: samples.error?.message })
record('immutable integer-paisa snapshot', items.data?.[0]?.unit_price_paisa === test.price_paisa)

const fixedOverride = await client.rpc('create_patient_bill_order_with_packages', payload(`p2-fixed-override-${stamp}`, test.price_paisa + 1))
record('fixed price override denied', Boolean(fixedOverride.error), { error: fixedOverride.error?.message })
const duplicateArgs = payload(`p2-duplicate-${stamp}`, test.price_paisa)
duplicateArgs.p_items_data.push({ ...duplicateArgs.p_items_data[0] })
const duplicate = await client.rpc('create_patient_bill_order_with_packages', duplicateArgs)
record('duplicate selected test denied', Boolean(duplicate.error), { error: duplicate.error?.message })

for (const policy of ['Negotiable', 'Manual', 'PricePending']) {
  await updateTest({ pricing_policy: policy, price_configured: policy !== 'PricePending', allow_manual_price: true, allow_zero_price_billing: false })
  const manual = await client.rpc('create_patient_bill_order_with_packages', payload(`p2-${policy}-${stamp}`, 17777))
  record(`${policy} positive agreed rate`, !manual.error, { error: manual.error?.message })
  const zero = await client.rpc('create_patient_bill_order_with_packages', payload(`p2-${policy}-zero-${stamp}`, 0, true))
  record(`${policy} unauthorized zero denied`, Boolean(zero.error), { error: zero.error?.message })
}
await updateTest({ pricing_policy: 'Manual', price_paisa: 0, price_configured: true, allow_manual_price: true, allow_zero_price_billing: true })
const noAck = await client.rpc('create_patient_bill_order_with_packages', payload(`p2-zero-noack-${stamp}`, 0, false))
const ack = await client.rpc('create_patient_bill_order_with_packages', payload(`p2-zero-ack-${stamp}`, 0, true))
record('authorized zero requires acknowledgement', Boolean(noAck.error) && !ack.error, { no_ack: noAck.error?.message, acknowledged_error: ack.error?.message })

// Restore the fixture to fixed price and verify a true multi-component package.
await updateTest({ pricing_policy: 'Fixed', price_paisa: 12345, price_configured: true, allow_manual_price: false, allow_zero_price_billing: false })
const companionQuery = await service.from('tests').select('*')
  .eq('lifecycle_status', 'Active').eq('is_active', true).eq('workflow_supported', true)
  .in('clinical_configuration_status', ['Configured', 'Ready for Activation'])
  .neq('id', test.id).limit(1).single()
if (companionQuery.error) throw companionQuery.error
const companion = companionQuery.data
const packagePrice = 23456
const packageSave = await client.rpc('catalogue_save_package', { p_package: { code: `P2PKG_${stamp}`.toUpperCase(), name: `Phase 2 Package ${stamp}`, description: 'Synthetic staging package', price_paisa: packagePrice, pricing_policy: 'Fixed', search_aliases: [`p2pkg${stamp}`] }, p_components: [test.id, companion.id], p_expected_version: null })
if (packageSave.error) throw packageSave.error
let packageRow = await service.from('health_packages').select('row_version').eq('id', packageSave.data).single()
const packageActive = await client.rpc('catalogue_set_package_lifecycle', { p_package_id: packageSave.data, p_status: 'Active', p_expected_version: packageRow.data.row_version })
record('package activate', !packageActive.error, { error: packageActive.error?.message })
packageRow = await service.from('health_packages').select('*').eq('id', packageSave.data).single()
const concurrentPackageReplacements = await Promise.all([
  client.rpc('catalogue_save_package', {
    p_package: { ...packageRow.data, description: 'Concurrent package replacement A' },
    p_components: [test.id, companion.id],
    p_expected_version: packageRow.data.row_version,
  }),
  client.rpc('catalogue_save_package', {
    p_package: { ...packageRow.data, description: 'Concurrent package replacement B' },
    p_components: [test.id, companion.id],
    p_expected_version: packageRow.data.row_version,
  }),
])
record(
  'concurrent package replacement is atomic and stale-safe',
  concurrentPackageReplacements.filter((response) => !response.error).length === 1
    && concurrentPackageReplacements.filter((response) => response.error?.code === 'PT409').length === 1,
  { errors: concurrentPackageReplacements.map((response) => response.error?.code || null) },
)
const expanded = await client.rpc('catalogue_expand_package', { p_package_id: packageSave.data })
record('package expands two unique ordered components', !expanded.error && expanded.data.length === 2 && new Set(expanded.data.map(row => row.test_id)).size === 2)
const packageArgs = payload(`p2-package-${stamp}`, packagePrice, false, [{ package_id: packageSave.data, component_ids: [test.id, companion.id], agreed_price_paisa: packagePrice }])
packageArgs.p_items_data.push({
  test_id: companion.id, test_code: companion.code, test_name: companion.name,
  reporting_type: companion.reporting_type, outsource_lab_name: companion.outsource_lab_name,
  unit_price_paisa: 0, manual_price_paisa: 0, discount_paisa: 0, net_price_paisa: 0,
  specimen_type: companion.sample_type, container_type: companion.container,
  department: companion.department, item_description: `Package: P2PKG_${stamp}`,
  zero_price_acknowledged: false,
})
const packageBill = await client.rpc('create_patient_bill_order_with_packages', packageArgs)
const selections = packageBill.error ? { data: [] } : await service.from('bill_package_selections').select('id,package_price_paisa').eq('bill_id', packageBill.data.bill_id)
const packageComponents = selections.data?.[0] ? await service.from('bill_package_components').select('test_id').eq('bill_package_selection_id', selections.data[0].id) : { data: [] }
const packageItems = packageBill.error ? { data: [] } : await service.from('bill_items').select('test_id,unit_price_paisa').eq('bill_id', packageBill.data.bill_id)
record('package billing identity and immutable agreed-price snapshot retained', !packageBill.error && selections.data.length === 1 && selections.data[0].package_price_paisa === packagePrice && packageComponents.data.length === 2 && packageItems.data.length === 2 && packageItems.data.reduce((sum, row) => sum + row.unit_price_paisa, 0) === packagePrice, { error: packageBill.error?.message, selections: selections.data?.length, package_components: packageComponents.data?.length, bill_items: packageItems.data?.length })

const duplicatePackageArgs = structuredClone(packageArgs)
duplicatePackageArgs.p_idempotency_key = `p2-package-duplicate-${stamp}`
duplicatePackageArgs.p_items_data.push({ ...duplicatePackageArgs.p_items_data[1] })
const duplicatePackageComponent = await client.rpc('create_patient_bill_order_with_packages', duplicatePackageArgs)
record('package plus duplicate component selection is rejected', Boolean(duplicatePackageComponent.error), { error: duplicatePackageComponent.error?.message })

// PricePending package is searchable/activatable, but cannot finalize without
// an explicit positive agreed rate.
const manualSave = await client.rpc('catalogue_save_package', { p_package: { code: `P2MAN_${stamp}`.toUpperCase(), name: `Phase 2 Manual Package ${stamp}`, description: 'Synthetic manual-rate package', price_paisa: 0, pricing_policy: 'PricePending', search_aliases: [`manualpkg${stamp}`] }, p_components: [test.id, companion.id], p_expected_version: null })
if (manualSave.error) throw manualSave.error
let manualRow = await service.from('health_packages').select('row_version').eq('id', manualSave.data).single()
const manualActive = await client.rpc('catalogue_set_package_lifecycle', { p_package_id: manualSave.data, p_status: 'Active', p_expected_version: manualRow.data.row_version })
record('PricePending package activates with configured active components', !manualActive.error, { error: manualActive.error?.message })
const manualPrice = 20000
const manualArgs = payload(`p2-package-manual-${stamp}`, manualPrice, false, [{ package_id: manualSave.data, component_ids: [test.id, companion.id], agreed_price_paisa: manualPrice }])
manualArgs.p_items_data.push({
  test_id: companion.id, test_code: companion.code, test_name: companion.name,
  reporting_type: companion.reporting_type, outsource_lab_name: companion.outsource_lab_name,
  unit_price_paisa: 0, manual_price_paisa: 0, discount_paisa: 0, net_price_paisa: 0,
  specimen_type: companion.sample_type, container_type: companion.container,
  department: companion.department, item_description: `Package: P2MAN_${stamp}`,
  zero_price_acknowledged: false,
})
const manualPackageBill = await client.rpc('create_patient_bill_order_with_packages', manualArgs)
record('PricePending package accepts explicit positive agreed rate', !manualPackageBill.error, { error: manualPackageBill.error?.message })
const zeroManualArgs = structuredClone(manualArgs)
zeroManualArgs.p_idempotency_key = `p2-package-manual-zero-${stamp}`
zeroManualArgs.p_bill_data.gross_amount_paisa = 0
zeroManualArgs.p_items_data[0].unit_price_paisa = 0
zeroManualArgs.p_items_data[0].manual_price_paisa = 0
zeroManualArgs.p_items_data[0].net_price_paisa = 0
zeroManualArgs.p_packages[0].agreed_price_paisa = 0
const zeroManualPackage = await client.rpc('create_patient_bill_order_with_packages', zeroManualArgs)
record('package NPR 0 is denied without an explicit package zero-price policy', Boolean(zeroManualPackage.error), { error: zeroManualPackage.error?.message })

const summary = { pass: results.filter(x => x.pass).length, fail: results.filter(x => !x.pass).length }
await writeFile('artifacts/phase2-billing-runtime.json', JSON.stringify({ summary, results }, null, 2))
console.log(JSON.stringify(summary))
if (summary.fail) process.exitCode = 1
