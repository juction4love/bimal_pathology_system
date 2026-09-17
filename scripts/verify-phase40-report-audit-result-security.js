import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const migration = read('supabase/migrations/00046_report_audit_result_security_hardening.sql');
const resultEntry = read('src/features/worklist/ResultEntryPage.tsx');
const safeErrors = read('src/lib/safeError.ts');
const payment = read('supabase/migrations/00043_payment_receivables_integrity.sql');
const reportSms = read('supabase/migrations/00041_standardize_report_ready_sms.sql');

let passed = 0;
let failed = 0;
const check = (condition, description) => {
  if (condition) { passed++; console.log(`PASS ${description}`); }
  else { failed++; console.error(`FAIL ${description}`); }
};

check(migration.includes('DROP POLICY IF EXISTS "diagnostic_reports_insert"') &&
  migration.includes('REVOKE INSERT ON public.diagnostic_reports FROM authenticated'),
  'ordinary and sign-capable authenticated sessions cannot directly insert diagnostic reports');
check(migration.includes('sign_and_queue_diagnostic_report') &&
  migration.includes('public.sign_and_freeze_diagnostic_report(') &&
  /GRANT EXECUTE ON FUNCTION public\.sign_and_queue_diagnostic_report[\s\S]*TO authenticated/.test(migration),
  'the legitimate guarded sign-off RPC remains callable');
check(migration.includes('DROP POLICY IF EXISTS "audit_logs_insert"') &&
  migration.includes('REVOKE INSERT, UPDATE, DELETE ON public.audit_logs FROM authenticated'),
  'authenticated clients cannot fabricate audit rows');
check(!/CREATE POLICY[\s\S]{0,100}audit_logs[\s\S]{0,100}FOR INSERT/.test(migration),
  'no replacement general-purpose audit insert policy is introduced');
check(/record_critical_value_acknowledgement[\s\S]*auth\.uid\(\)[\s\S]*'CRITICAL_VALUE_ACKNOWLEDGED'/.test(migration),
  'critical acknowledgement audit identity and action are server-derived');
check(!resultEntry.includes("from('audit_logs').insert") &&
  resultEntry.includes("rpc(\n          'record_critical_value_acknowledgement'"),
  'frontend no longer writes audit_logs directly');
check(migration.includes('DROP POLICY IF EXISTS "test_results_insert"') &&
  migration.includes('DROP POLICY IF EXISTS "test_results_update"') &&
  migration.includes('REVOKE INSERT, UPDATE, DELETE ON public.test_results FROM authenticated'),
  'direct result mutation is denied');
check(resultEntry.includes("supabase.rpc('save_test_results'") &&
  !resultEntry.includes(".from('test_results')\n          .upsert") &&
  !resultEntry.includes(".from('test_results')\n          .insert"),
  'allowed result entry uses the secured transactional RPC');
check(/p_target_status IN \('Draft', 'SubmittedForVerification'\)[\s\S]*can_enter_results/.test(migration) &&
  /p_target_status IN \('ReturnedForCorrection', 'Verified'\)[\s\S]*can_verify_results/.test(migration),
  'result entry and verification permissions are enforced server-side');
check(/v_item\.status = 'SignedOff' AND NOT v_is_amendment/.test(migration) &&
  /p_amended_from_report_id[\s\S]*can_amend_reports/.test(migration),
  'signed results require a valid reasoned amendment workflow');
check(migration.includes('pg_advisory_xact_lock') && migration.includes("'idempotency_replay',TRUE"),
  'sign-off retry serializes and returns the existing logical report');
check(/amended_from_report_id=p_amended_from_report_id[\s\S]*ORDER BY version LIMIT 1/.test(migration),
  'amendment retry does not create another report version');
check(migration.includes('uq_public_report_tokens_one_active_report') &&
  migration.includes('WHERE is_active = TRUE AND revoked_at IS NULL'),
  'database enforces one active non-revoked token per report version');
check(/expires_at <= NOW\(\)[\s\S]*SELECT \* INTO v_existing_token/.test(migration),
  'expired or revoked tokens are retired before safe replacement');
check(migration.includes("'REPORT_READY:'||p_report_id::TEXT||':'||v_report.version::TEXT") &&
  migration.includes('ON CONFLICT(idempotency_key) DO NOTHING'),
  'ReportReady idempotency remains one notification per report version');
check(payment.includes("'PAYMENT_CONFIRMATION:'||v_payment.id::TEXT") &&
  payment.includes('ON CONFLICT(idempotency_key) DO NOTHING'),
  'Payment Confirmation idempotency remains unchanged');
const finalMatrix = read('supabase/migrations/00077_two_role_permission_reconciliation.sql');
check(finalMatrix.includes("'can_enter_results','can_verify_results','can_acknowledge_critical'") &&
  finalMatrix.includes("'can_sign_reports','can_amend_reports','can_print_reports'"),
  'final Technician matrix supports verification, signing and controlled amendments');
check(/SET search_path = public, pg_temp/g.test(migration) &&
  /REVOKE ALL ON FUNCTION public\.save_test_results[\s\S]*FROM PUBLIC, anon/.test(migration),
  'new SECURITY DEFINER functions use fixed search_path and narrow grants');
check(safeErrors.includes("code === '42501'") && safeErrors.includes('This mobile number is already registered.') &&
  !safeErrors.includes('return candidate.message'),
  'frontend error mapper returns actionable messages without raw backend diagnostics');
check(reportSms.includes("'REPORT_READY:' || p_report_id::TEXT || ':' || v_report.version::TEXT"),
  'existing report notification identity contract is preserved');

console.log(`\nPhase 40 report/audit/result security: ${passed} passed, ${failed} failed`);
if (failed) process.exit(1);
