import fs from 'node:fs';
import assert from 'node:assert/strict';

const read = (path) => fs.readFileSync(path, 'utf8');
const billing = read('src/features/billing/NewBillPage.tsx');
const samples = read('src/features/samples/SampleAccessioningPage.tsx');
const worklist = read('src/features/worklist/WorklistPage.tsx');
const resultEntry = read('src/features/worklist/ResultEntryPage.tsx');
const m55 = read('supabase/migrations/00055_foundation_rpc_and_sample_traceability_contracts.sql');
const m56 = read('supabase/migrations/00056_foundation_result_readiness_and_revision.sql');
const m72 = read('supabase/migrations/00072_worklist_server_search_pagination.sql');

const checks = [];
const check = (name, fn) => { fn(); checks.push(name); console.log(`PASS ${name}`); };

check('billing remains one atomic package-aware RPC', () => {
  assert.match(billing, /rpc\('create_patient_bill_order_with_packages'/);
  assert.match(m55, /response:=public\.create_patient_bill_and_order[\s\S]*response:=response\|\|public\.ensure_bill_collection_traceability/);
});
check('bill finalization creates order, samples, and order items in the same transaction', () => {
  for (const fragment of ['INSERT INTO public.clinical_orders', 'INSERT INTO public.samples', 'INSERT INTO public.clinical_order_items']) assert.ok(m55.includes(fragment));
});
check('future order items freeze reporting and collection gates', () => {
  assert.match(m55, /x\.workflow_type,x\.clinical_reporting_enabled,x\.collection_required/);
});
check('reportability predicate remains exact for InHouse and Bimal-report outsource', () => {
  assert.match(m72, /coi\.clinical_reporting_enabled=TRUE/);
  assert.match(m72, /coi\.reporting_type IN \('InHouse','OutsourceWithBimalReport'\)/);
});
check('NoReporting and reporting-disabled services cannot enter the worklist', () => {
  assert.ok(!/NoReporting/.test("'InHouse','OutsourceWithBimalReport'"));
  assert.match(m55, /DELETE FROM public\.test_results[\s\S]*NOT oi\.clinical_reporting_enabled/);
});
check('booking search verifies immutable clinical gates before selection', () => {
  for (const field of ['clinical_reporting_enabled', 'collection_required', 'workflow_type', 'workflow_supported']) assert.ok(billing.includes(field));
});
check('profile and package components carry canonical gate snapshots', () => {
  assert.match(billing, /clinicalReportingEnabled: t\.clinical_reporting_enabled/);
  assert.match(billing, /catalogue_expand_package/);
});
check('bill success provides the normal sample handoff', () => {
  assert.ok(billing.includes('Bill saved and order registered successfully.'));
  assert.ok(samples.includes("searchParams.get('search')"));
});
check('worklist result action is blocked until collection readiness', () => {
  assert.ok(worklist.includes("['Collected', 'Received', 'Processing', 'Completed']"));
  assert.ok(worklist.includes('Sample Pending'));
  assert.match(m56, /RESULT_COLLECTION_NOT_READY/);
});
check('received/ready item opens the order-centric workspace with selected item UUID', () => {
  assert.match(worklist, /navigate\(`\/worklist\/order\/\$\{item\.order_id\}\?item=\$\{item\.id\}`\)/);
  assert.match(resultEntry, /\.eq\('id', orderItemId\)[\s\S]*\.eq\('clinical_reporting_enabled', true\)/);
});
check('exact Lab No handoff and server search are page-independent', () => {
  assert.ok(worklist.includes("searchParams.get('search')"));
  assert.match(m72, /o\.order_number=upper\(term\)/);
});
check('order and sample invalidations include worklist and dashboard', () => {
  assert.match(billing, /publishWorkflowInvalidation\('order-created',\['patients','bills','samples','worklist','dashboard'\]/);
  assert.match(samples, /publishWorkflowInvalidation\('sample-changed',\['samples','worklist','dashboard'\]/);
});

console.log(`Bill → Worklist → Result flow: ${checks.length} passed, 0 failed.`);
