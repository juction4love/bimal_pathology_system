import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const billingSql = read('supabase/migrations_legacy_archive/00018_outsource_sample_tracking.sql');
const idempotencySql = read('supabase/migrations_legacy_archive/00043_payment_receivables_integrity.sql');
const traceabilitySql = read('supabase/migrations_legacy_archive/00055_foundation_rpc_and_sample_traceability_contracts.sql');
const resultSql = read('supabase/migrations_legacy_archive/00056_foundation_result_readiness_and_revision.sql');
const lineageSql = read('supabase/migrations_legacy_archive/00021_final_flow_integrity_and_concurrency.sql');
const labNoSql = read('supabase/migrations_legacy_archive/00054_shared_catalogue_collection_and_bpdc_foundation.sql');
const newBill = read('src/features/billing/NewBillPage.tsx');
const patients = read('src/features/patients/PatientsPage.tsx');
const invalidation = read('src/lib/workflowInvalidation.ts');

function makeVisit(patientId, visitNo) {
  const billId = `bill-${visitNo}`;
  const orderId = `order-${visitNo}`;
  const itemId = `item-${visitNo}`;
  const sampleId = `sample-${visitNo}`;
  return {
    patientId, billId, orderId, labNo: `BPDC-0000000${visitNo}`,
    itemId, sampleId, resultRevision: 0,
    resultIds: [`result-${visitNo}`], reportIds: [`report-${visitNo}-v1`],
  };
}

test('a repeat patient gets a wholly new visit graph', () => {
  const historical = makeVisit('patient-1', 1);
  const repeat = makeVisit('patient-1', 2);
  assert.equal(repeat.patientId, historical.patientId);
  for (const key of ['billId', 'orderId', 'labNo', 'itemId', 'sampleId']) assert.notEqual(repeat[key], historical[key]);
  assert.equal(repeat.resultRevision, 0);
  assert.notDeepEqual(repeat.resultIds, historical.resultIds);
  assert.notDeepEqual(repeat.reportIds, historical.reportIds);
  assert.deepEqual(historical, makeVisit('patient-1', 1), 'historical graph remains immutable');
});

test('patient deduplication is locked and protected by normalized mobile uniqueness', () => {
  assert.match(billingSql, /WHERE mobile = v_clean_mobile\s+FOR UPDATE/);
  assert.match(billingSql, /ON CONFLICT \(mobile\) DO UPDATE/);
  assert.match(read('supabase/migrations_legacy_archive/00013_enforce_patient_mobile_uniqueness.sql'), /UNIQUE INDEX IF NOT EXISTS uq_patients_mobile/);
  assert.match(patients, /billing\/new\?mobile=\$\{pat\.mobile\}/);
  assert.match(newBill, /patient_id: existingPatientId/);
});

test('new request key creates a new bill while retry replays only the same request', () => {
  assert.match(idempotencySql, /WHERE caller_id=v_caller AND idempotency_key=v_key FOR UPDATE/);
  assert.match(idempotencySql, /response_json IS NOT NULL THEN RETURN v_existing\.response_json\|\|jsonb_build_object\('idempotency_replay',TRUE\)/);
  assert.match(newBill, /billingRequestKeyRef\.current = crypto\.randomUUID\(\)/);
});

test('order and sample discovery are scoped to the new bill/order', () => {
  assert.match(traceabilitySql, /WHERE bill_id=b\.id ORDER BY created_at LIMIT 1 FOR UPDATE/);
  assert.match(traceabilitySql, /INSERT INTO public\.clinical_orders\(order_number,bill_id,patient_id/);
  assert.match(traceabilitySql, /INSERT INTO public\.samples\(barcode,order_id,patient_id/);
  assert.match(traceabilitySql, /INSERT INTO public\.clinical_order_items\(order_id,bill_item_id,test_id/);
});

test('Lab No allocation is unique and permanently bound to one new order', () => {
  assert.match(labNoSql, /INSERT INTO public\.lab_number_registry/);
  assert.match(labNoSql, /reserved_count=1/);
  assert.match(labNoSql, /SET order_id=NEW\.id,assigned_at=NOW\(\)/);
});

test('result revision and rows are isolated by new order item', () => {
  assert.match(resultSql, /result_revision BIGINT NOT NULL DEFAULT 0/);
  assert.match(resultSql, /WHERE id=p_order_item_id FOR UPDATE/);
  assert.match(resultSql, /save_test_results_unversioned_internal\(\s*p_order_item_id/);
  assert.match(resultSql, /SET result_revision=result_revision\+1/);
});

test('verification, sign-off, and version lineage remain order-local', () => {
  assert.match(lineageSql, /UNIQUE \(order_id, version\)/);
  assert.match(lineageSql, /pg_advisory_xact_lock\(hashtextextended\(NEW\.order_id::TEXT/);
  assert.match(read('supabase/migrations_legacy_archive/00005_reporting_signoff_and_pdf.sql'), /WHERE coi\.order_id = p_order_id/);
});

test('new reportable visit follows sample readiness into Worklist and Result Entry', () => {
  assert.match(traceabilitySql, /x\.clinical_reporting_enabled,x\.collection_required/);
  assert.match(resultSql, /sample\.status NOT IN \('Collected','Received','Processing','Completed'\)/);
  assert.match(read('supabase/migrations_legacy_archive/00072_worklist_server_search_pagination.sql'), /coi\.clinical_reporting_enabled=TRUE[\s\S]*coi\.reporting_type IN \('InHouse','OutsourceWithBimalReport'\)/);
  assert.match(read('src/features/worklist/WorklistPage.tsx'), /worklist\/order\/\$\{item\.order_id\}/);
});

test('new bill and sample transitions invalidate immediate operational consumers', () => {
  assert.match(newBill, /\['patients','bills','samples','worklist','dashboard'\]/);
  assert.match(read('src/features/samples/SampleAccessioningPage.tsx'), /\['samples','worklist','dashboard'\]/);
  assert.match(invalidation, /BroadcastChannel/);
  assert.match(invalidation, /setTimeout\(listener,120\)/);
});
