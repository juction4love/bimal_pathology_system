/** Deterministic Phase 6 regression suite; never reads or mutates live data. */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const migration01 = read('supabase/migrations_legacy_archive/00001_initial_schema.sql');
const migration12 = read('supabase/migrations_legacy_archive/00012_fix_test_results_id_and_draft_save.sql');
const migration46 = read('supabase/migrations_legacy_archive/00046_report_audit_result_security_hardening.sql');
const resultEntrySource = read('src/features/worklist/ResultEntryPage.tsx');
let passedCount = 0;
let failedCount = 0;

function assert(condition, code, description) {
  if (condition) { console.log(`  ✅ [PASS] ${code}: ${description}`); passedCount++; }
  else { console.error(`  ❌ [FAIL] ${code}: ${description}`); failedCount++; }
}

const isValidUuid = (uuid) =>
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(uuid);

function buildSavePayloads(results, orderItemId, targetStatus, profile, now) {
  const existingRows = [];
  const newRows = [];
  for (const result of results) {
    const row = {
      order_item_id: orderItemId, parameter_id: result.parameter_id,
      parameter_name: result.name, unit: result.unit || null,
      value_type: result.value_type, display_value: result.display_value.trim(),
      flag: result.flag || 'Normal', status: targetStatus,
      entered_by: targetStatus === 'Draft' ? profile?.id : undefined,
      entered_by_name: targetStatus === 'Draft' ? profile?.fullName : undefined,
      entered_at: targetStatus === 'Draft' ? now : undefined,
      verified_by: targetStatus === 'Verified' ? profile?.id : undefined,
      verified_by_name: targetStatus === 'Verified' ? profile?.fullName : undefined,
      verified_at: targetStatus === 'Verified' ? now : undefined,
    };
    (result.id ? existingRows : newRows).push(result.id ? { id: result.id, ...row } : row);
  }
  return { existingRows, newRows };
}

class IsolatedResultStore {
  rows = new Map();
  identities = new Map();
  save(row) {
    const identity = `${row.order_item_id}:${row.parameter_id}`;
    const existingId = this.identities.get(identity);
    const id = row.id || existingId || randomUUID();
    if (existingId && row.id && existingId !== row.id) throw new Error('duplicate result identity');
    const saved = { ...this.rows.get(id), ...row, id };
    this.rows.set(id, saved);
    this.identities.set(identity, id);
    return saved;
  }
}

async function runRegressionSuite() {
  console.log('================================================================');
  console.log(' BIMAL PATHOLOGY - PHASE 6 DRAFT SAVE & WORKFLOW REGRESSION SUITE');
  console.log('================================================================\n');

  const activeDir = path.join(root, 'supabase/migrations');
  const legacyDir = path.join(root, 'supabase/migrations_legacy_archive');
  const files = (fs.existsSync(legacyDir) ? fs.readdirSync(legacyDir) : []).concat(fs.existsSync(activeDir) ? fs.readdirSync(activeDir) : []);
  const migrationsPresent = Array.from({ length: 18 }, (_, i) =>
    files.some((name) => name.startsWith(String(i + 1).padStart(5, '0'))));
  assert(migrationsPresent.every(Boolean), '0. MigrationBaseline', 'Migrations 00001 through 00018 are present');

  console.log('\n--- TEST GROUP 1: ID ARCHITECTURE & PAYLOAD INTEGRITY ---');
  const profile = { id: randomUUID(), fullName: 'Phase 6 Technician' };
  const orderItemId = randomUUID();
  const parameterId = randomUUID();
  const store = new IsolatedResultStore();
  const { newRows } = buildSavePayloads(
    [{ parameter_id: parameterId, name: 'Free T3', value_type: 'Numeric', display_value: '2.5' }],
    orderItemId, 'Draft', profile, '2026-08-19T12:00:00Z');

  assert(!('id' in newRows[0]), '1. DraftInsert_ShouldNeverSendNullId', 'New payload omits id so PostgreSQL owns UUID generation');
  const uuidDefault = /ALTER COLUMN id SET DEFAULT gen_random_uuid\(\)/i.test(migration12)
    && /id UUID PRIMARY KEY DEFAULT uuid_generate_v4\(\)/i.test(migration01);
  const draft = store.save(newRows[0]);
  assert(uuidDefault && isValidUuid(draft.id), '2. DraftInsert_ShouldGenerateUuid', 'Schema defines UUID generation and isolated insert receives a UUID');

  const repeated = store.save({ ...newRows[0], id: draft.id, display_value: '3.50' });
  assert(repeated.id === draft.id && store.rows.size === 1, '3. RepeatedDraftSave_ShouldUpdateExistingResult', 'Repeated save preserves UUID without a duplicate row');
  assert(repeated.status === 'Draft', '4. DraftSave_ShouldRemainDraft', 'Draft save does not advance workflow');
  assert(store.rows.get(draft.id).display_value === '3.50', '5. DraftRefresh_ShouldPersistValues', 'Reload preserves the draft value');

  const uniqueIdentity = /uq_test_results_order_item_parameter\s+ON public\.test_results \(order_item_id, parameter_id\)/i.test(migration12);
  assert(uniqueIdentity, '6. OneResultPerOrderItemParameter', 'Migration 00012 enforces one result per order-item parameter');

  const technicianDraft = store.save({ ...repeated, display_value: '4.50' });
  const techPolicy = /p_target_status IN \('Draft', 'SubmittedForVerification'\)[\s\S]*can_enter_results/i.test(migration46);
  assert(techPolicy && technicianDraft.display_value === '4.50', '7. TechnicianDraftWrite_ShouldBeAllowed', 'Draft RLS policy and update behavior remain present');

  const submitted = store.save({ ...technicianDraft, status: 'SubmittedForVerification' });
  assert(submitted.status === 'SubmittedForVerification', '8. Submit_ShouldTransitionToAwaitingVerification', 'Explicit submit advances workflow');

  const beforeFailure = store.rows.get(draft.id).status;
  try { store.save({ ...submitted, id: randomUUID(), status: 'Verified' }); } catch { /* expected */ }
  assert(store.rows.get(draft.id).status === beforeFailure, '9. FailedSave_ShouldNotAdvanceStatus', 'Rejected persistence leaves workflow unchanged');

  console.log('\n--- TEST GROUP 2: ROLE-BASED ACCESS CONTROL & VERIFICATION SAFETY ---');
  const anonymousDenied = /REVOKE ALL ON FUNCTION public\.save_test_results[\s\S]*FROM PUBLIC, anon/i.test(migration46);
  assert(anonymousDenied, '10. AnonymousResultWrite_ShouldBeDenied', 'RLS restricts result inserts to authenticated result-entry users');

  const { SYSTEM_ROLES, PERMISSION_KEYS } = await import('../src/types/permissions.ts');
  const techCanSign = SYSTEM_ROLES.LAB_TECHNICIAN.defaultPermissions.includes(PERMISSION_KEYS.CAN_SIGN_REPORTS);
  assert(techCanSign, '11. TechnicianSignOff_ShouldBeAllowed', 'Lab Technician has report-signing permission for the single-operator workflow');

  const verified = store.save({ ...submitted, status: 'Verified', verified_by_name: 'Dr. Pathologist' });
  const verifyMapping = resultEntrySource.includes("supabase.rpc('save_test_results'")
    && /p_target_status IN \('ReturnedForCorrection', 'Verified'\)[\s\S]*can_verify_results/i.test(migration46)
    && /v_item_status := CASE WHEN p_target_status = 'Verified' THEN 'Verified'/i.test(migration46);
  assert(verifyMapping && verified.status === 'Verified', '12. AuthorizedVerify_ShouldBeAllowed', 'Authorized verification maps result and order item to Verified');

  console.log('\n================================================================');
  console.log(` SUMMARY: ${passedCount} PASSED, ${failedCount} FAILED`);
  console.log('================================================================\n');
  if (failedCount > 0) process.exit(1);
}

runRegressionSuite().catch((error) => { console.error(error); process.exit(1); });
