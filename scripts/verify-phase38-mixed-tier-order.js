import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.join(process.cwd(), file), 'utf8');
let passed = 0;
const check = (description, fn) => { fn(); passed += 1; console.log(`PASS ${description}`); };
const billing = read('src/features/billing/NewBillPage.tsx');
const selection = read('src/features/billing/mixedTierSelection.ts');
const atomicBilling = read('supabase/migrations/00018_outsource_sample_tracking.sql');
const latestBilling = read('supabase/migrations/00040_short_payment_confirmation_sms.sql');
const catalogueBilling = read('supabase/migrations/00050_catalogue_management_architecture.sql');
const readiness = read('supabase/migrations/00005_reporting_signoff_and_pdf.sql');
const signoff = read('supabase/migrations/00030_fix_optional_authorizer_runtime.sql');
const worklist = read('src/features/worklist/WorklistPage.tsx');
const worklistSearch = read('supabase/migrations/00072_worklist_server_search_pagination.sql');
const resultEntry = read('src/features/worklist/ResultEntryPage.tsx');
const reportDocument = read('src/features/reports/ReportDocument.tsx');
const multiReport = read('supabase/migrations/00092_multi_report_group_lifecycle.sql');

check('billing exposes one unified fast search and no routing-tier selector', () => {
  assert.match(billing, /const \[selectedItems, setSelectedItems\] = useState<BillItemEntry\[]>\(\[\]\)/);
  assert.match(billing, /Search Test \/ Profile \/ Package/);
  assert.match(billing, /search_billable_catalogue/);
  assert.doesNotMatch(billing, /setReportingTypeFilter|reportingTypeFilter/);
  assert.match(selection, /reporting metadata remains internal/);
});
check('search supports short aliases and keyboard-first addition', () => {
  assert.match(catalogueBilling, /length\(q\.value\)>=2/);
  assert.match(catalogueBilling, /unnest\(t\.search_aliases\)/);
  for (const key of ['ArrowDown', 'ArrowUp', 'Enter']) assert.match(billing, new RegExp(`e\\.key === '${key}'`));
  assert.match(billing, /setTestSearchTerm\(''\)/);
});
check('selection accumulation is duplicate-safe and filter-independent', () => {
  assert.match(selection, /current\.some\(\(item\) => item\.test\.id === test\.id\)/);
  assert.match(selection, /return \[\.\.\.current/);
  assert.match(billing, /setSelectedItems\(\(current\) => \{/);
});
check('one unified payload preserves identity, price, and routing', () => {
  assert.match(billing, /const itemsPayload = selectedItems\.map/);
  for (const contract of [/test_id: item\.test\.id/, /reporting_type: item\.test\.reportingType/, /unit_price_paisa: item\.unitPricePaisa/, /calculateBillTotals\(selectedItems/]) assert.match(billing, contract);
});
check('pricing policies and agreed-rate snapshots are server enforced', () => {
  assert.match(catalogueBilling, /pricing_policy='Fixed'/);
  assert.match(catalogueBilling, /pricing_policy IN \('Negotiable','PricePending','Manual'\)/);
  assert.match(catalogueBilling, /Fixed catalogue prices cannot be overridden/);
  assert.match(catalogueBilling, /zero_price_acknowledged/);
  assert.match(billing, /parseRupeesToPaisa/);
  assert.match(billing, /item\.rateResolved/);
});
check('one idempotent RPC submits the whole visit', () => {
  assert.equal((billing.match(/\.rpc\('create_patient_bill_order_with_packages'/g) || []).length, 1);
  assert.match(billing, /p_items_data: itemsPayload/);
  assert.match(billing, /p_idempotency_key: billingRequestKeyRef\.current/);
  assert.match(latestBilling, /billing_idempotency_requests/);
  assert.match(latestBilling, /PAYMENT_CONFIRMATION:' \|\| v_payment\.id::TEXT/);
  assert.match(latestBilling, /ON CONFLICT \(idempotency_key\) DO NOTHING/);
  assert.match(catalogueBilling, /response:=public\.create_patient_bill_and_order\(p_patient_data,p_bill_data,p_items_data,p_payment_data,p_idempotency_key\)/);
});
check('atomic backend creates one bill and one reportable clinical order', () => {
  assert.equal((atomicBilling.match(/INSERT INTO public\.bills \(/g) || []).length, 1);
  assert.equal((atomicBilling.match(/INSERT INTO public\.clinical_orders \(/g) || []).length, 1);
  assert.match(atomicBilling, /FOREACH v_item IN ARRAY p_items_data LOOP[\s\S]*INSERT INTO public\.bill_items/);
  assert.match(atomicBilling, /FOREACH v_item IN ARRAY p_items_data LOOP[\s\S]*INSERT INTO public\.clinical_order_items/);
});
check('worklist completion remains scoped to individual routed order items', () => {
  assert.match(worklist, /rpc\('search_laboratory_worklist'/);
  assert.match(worklistSearch, /coi\.clinical_reporting_enabled=TRUE/);
  assert.match(worklistSearch, /coi\.reporting_type IN \('InHouse','OutsourceWithBimalReport'\)/);
  assert.match(resultEntry, /\.eq\('order_id', orderId\)/);
  assert.match(resultEntry, /\.eq\('id', orderItemId\)/);
});
check('finalization waits for every reportable item and acknowledged criticals', () => {
  assert.match(readiness, /v_reportable_count > 0 AND v_verified_count = v_reportable_count AND v_unack_critical_count = 0/);
  assert.match(signoff, /check_order_report_readiness\(p_order_id\)/);
});
check('frozen group reports aggregate only their reportable investigations', () => {
  assert.match(multiReport, /clinical_report_group_items/);
  assert.match(multiReport, /WHERE gi\.report_group_id=g\.id/);
  assert.match(multiReport, /'investigations',investigations/);
  assert.match(reportDocument, /snapshot\?\.investigations/);
});
check('existing authorized signatory snapshots are preserved', () => {
  assert.match(signoff, /'performed_by', jsonb_build_object/);
  assert.match(signoff, /'authorized_by', v_authorized_snapshot/);
  assert.match(signoff, /can_sign_reports/);
});
check('one order portal token and order-aware ReportReady generation are used', () => {
  assert.match(multiReport, /ORDER_REPORT_READY:'\|\|report\.order_id\|\|':1'/);
  assert.match(multiReport, /ON CONFLICT\(idempotency_key\) DO NOTHING/);
  assert.equal((resultEntry.match(/generateRawToken\(\)/g) || []).length, 1);
  assert.equal((resultEntry.match(/\.rpc as any\)\('sign_and_queue_report_group'/g) || []).length, 1);
});
console.log(`\nPhase 38 unified-search combined-order contracts: ${passed}/12 passed.`);
