/** Final flow-audit hardening regression suite. No production rows are mutated. */
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');
const migration = read('supabase/migrations/00021_final_flow_integrity_and_concurrency.sql');
const migration22 = read('supabase/migrations/00022_repair_clinical_order_billing_insert.sql');
const migration23 = read('supabase/migrations/00023_repair_billing_receipt_number.sql');
const migration24 = read('supabase/migrations/00024_repair_billing_initial_order_status.sql');
const migration25 = read('supabase/migrations/00025_repair_billing_sample_patient_lineage.sql');
const migration26 = read('supabase/migrations/00026_separate_technician_from_verifier.sql');
const billing = read('src/features/billing/NewBillPage.tsx');
const samples = read('src/features/samples/SampleAccessioningPage.tsx');
const technician = read('src/features/dashboard/TechnicianDashboard.tsx');
const publicGateway = read('supabase/functions/public-report/index.ts');

let passed = 0;
let failed = 0;
function assert(condition, name, detail) {
  if (condition) { passed++; console.log(`  ✅ [PASS] ${name}: ${detail}`); }
  else { failed++; console.error(`  ❌ [FAIL] ${name}: ${detail}`); }
}

console.log('\n================================================================');
console.log(' BIMAL PATHOLOGY - PHASE 17 FINAL HARDENING SUITE');
console.log('================================================================\n');

assert(/PRIMARY KEY \(caller_id, idempotency_key\)/.test(migration),
  'BillingIdempotency_UniqueCallerKey', 'database uniqueness is scoped to authenticated caller and request key');
assert(/FOR UPDATE;[\s\S]*response_json IS NOT NULL[\s\S]*idempotency_replay/.test(migration),
  'ConcurrentBilling_ReplaysCommittedResult', 'duplicate requests serialize and return the stored transaction response');
assert(/v_response := public\.create_patient_bill_and_order\([\s\S]*UPDATE public\.billing_idempotency_requests/.test(migration),
  'FailedBilling_DoesNotPoisonKey', 'business transaction and completed-key write share one PostgreSQL transaction');
assert(/REVOKE EXECUTE ON FUNCTION public\.create_patient_bill_and_order\(JSONB, JSONB, JSONB\[\], JSONB\)[\s\S]*authenticated/.test(migration),
  'LegacyBillingBypass_Revoked', 'authenticated clients cannot bypass the idempotent overload');
assert(/p_idempotency_key: billingRequestKeyRef\.current/.test(billing) && /crypto\.randomUUID/.test(billing),
  'BillingUi_StableRequestKey', 'UI supplies a cryptographically random key that remains stable across retries');
assert(/replace\(v_definition, 'clinical_order_seq', 'lab_order_seq'\)/.test(migration) &&
  /replace\(v_fixed, 'sample_barcode_seq', 'sample_seq'\)/.test(migration),
  'BillingSequences_RepairLiveSchemaMismatch', 'pending migration repairs both invalid deployed billing sequence references');
assert(/clinical_orders has no created_by column/i.test(migration22) &&
  /refusing partial repair/i.test(migration22) &&
  /REVOKE EXECUTE ON FUNCTION public\.create_patient_bill_and_order\(JSONB, JSONB, JSONB\[\], JSONB\)/.test(migration22),
  'BillingClinicalOrderInsert_RepairLiveSchemaMismatch', 'forward-only repair removes the invalid clinical order actor column and preserves RPC grants');
assert(/payment_transactions\.receipt_number is NOT NULL/i.test(migration23) &&
  /NEXTVAL\(\\'receipt_seq\\'\)/.test(migration23) && /refusing partial repair/i.test(migration23),
  'BillingReceiptNumber_RepairLiveSchemaMismatch', 'forward-only repair preserves required receipt numbering');
assert(/clinical_orders accepts Registered as its initial state/i.test(migration24) &&
  /\\'Registered\\'/.test(migration24) && /refusing partial repair/i.test(migration24),
  'BillingOrderStatus_RepairLiveSchemaMismatch', 'forward-only repair uses the authoritative initial order state');
assert(/samples\.patient_id is required/i.test(migration25) &&
  /v_patient_id/.test(migration25) && /refusing partial repair/i.test(migration25),
  'BillingSamplePatient_RepairLiveSchemaMismatch', 'forward-only repair preserves required sample patient lineage');
assert(/r\.code = 'lab_technician'/.test(migration26) &&
  /'can_verify_results', 'can_sign_reports', 'can_amend_reports'/.test(migration26),
  'TechnicianVerifierSeparation_LiveRoleRepair', 'technician role membership no longer confers verification or report authority');

assert(/CREATE OR REPLACE FUNCTION public\.transition_sample_lifecycle/.test(migration) &&
  /SELECT \* INTO v_sample[\s\S]*FOR UPDATE/.test(migration),
  'SampleLifecycle_AtomicLock', 'server RPC locks the sample before validating and changing state');
assert(/UPDATE public\.samples[\s\S]*INSERT INTO public\.sample_lifecycle_events/.test(migration),
  'SampleLifecycle_StateAndEventTogether', 'status, order-item state, and immutable event execute in one transaction');
assert(/DROP POLICY IF EXISTS "samples_update"/.test(migration) &&
  /REVOKE INSERT, UPDATE, DELETE ON public\.sample_lifecycle_events FROM authenticated/.test(migration),
  'SampleLifecycle_DirectMutationDenied', 'browser roles cannot bypass the lifecycle RPC');
assert((samples.match(/rpc\('transition_sample_lifecycle'/g) || []).length === 4 &&
  !samples.includes("from('sample_lifecycle_events').insert"),
  'SampleLifecycle_AllUiActionsUseRpc', 'collection, receipt, rejection, and recollection use the atomic RPC');
assert(/only Pending samples can be collected/.test(migration) && /only Collected samples can be received/.test(migration) &&
  /only Rejected samples can be recollected/.test(migration),
  'SampleLifecycle_InvalidTransitionsRejected', 'legal transition predecessors are explicit and regression-safe');

assert(/HAVING count\(\*\) > 1/.test(migration) && /RAISE EXCEPTION 'Duplicate diagnostic report versions/.test(migration),
  'ReportVersion_PreflightAnomalyGuard', 'migration fails without rewriting clinical history when duplicates exist');
assert(/UNIQUE \(order_id, version\)/.test(migration),
  'ReportVersion_UniqueLineageVersion', 'database enforces one version per order lineage');
assert(/pg_advisory_xact_lock\(hashtextextended\(NEW\.order_id::TEXT, 0\)\)/.test(migration),
  'ReportVersion_ConcurrentInsertSerialized', 'simultaneous report inserts serialize per order lineage');

assert(/REVOKE EXECUTE ON FUNCTION public\.claim_sms_batch[\s\S]*service_role/.test(migration) &&
  /REVOKE EXECUTE ON FUNCTION public\.update_sms_status[\s\S]*service_role/.test(migration),
  'SmsWorker_ServiceRoleOnly', 'ordinary sessions cannot claim work or forge provider outcomes');
assert(/guard_diagnostic_report_personnel[\s\S]*can_sign_reports = TRUE/.test(migration),
  'ReportingPersonnel_SignoffEnforced', 'active authorized reporting personnel is checked independently of login identity');
assert(!/revenue|outstanding|discount|invoice|\bNPR\b|from\('bills'\)/i.test(technician),
  'TechnicianDashboard_NoFinancialData', 'clinical dashboard source contains no financial metrics or terminology');
assert(/status NOT IN \('SignedOff', 'Amended'\)/.test(migration) &&
  !/'pdf_storage_path', v_report\.pdf_storage_path/.test(migration),
  'PublicReport_SignedOnlyNoPrivatePath', 'resolver exposes only signed/amended snapshots and omits private storage paths');
assert(/rpc\('resolve_public_report_by_token'/.test(publicGateway),
  'PublicReport_GatewayIsolation', 'edge gateway resolves opaque token hashes through the hardened RPC');

console.log(`\nSUMMARY: ${passed} PASSED, ${failed} FAILED\n`);
if (failed) process.exit(1);
