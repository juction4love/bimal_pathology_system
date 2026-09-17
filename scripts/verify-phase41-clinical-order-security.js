import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/00047_clinical_order_direct_write_hardening.sql', 'utf8');
const billing = fs.readFileSync('supabase/migrations/00018_outsource_sample_tracking.sql', 'utf8');
const samples = fs.readFileSync('supabase/migrations/00021_final_flow_integrity_and_concurrency.sql', 'utf8');
const results = fs.readFileSync('supabase/migrations/00046_report_audit_result_security_hardening.sql', 'utf8');
const signoff = fs.readFileSync('supabase/migrations/00030_fix_optional_authorizer_runtime.sql', 'utf8');
const source = fs.readFileSync('src/features/worklist/ResultEntryPage.tsx', 'utf8');

let passed = 0;
let failed = 0;
const check = (condition, name) => condition ? (passed++, console.log(`PASS ${name}`)) : (failed++, console.error(`FAIL ${name}`));

for (const policy of ['clinical_orders_insert', 'clinical_orders_update', 'clinical_order_items_insert', 'clinical_order_items_update']) {
  check(migration.includes(`DROP POLICY IF EXISTS "${policy}"`), `${policy} removed`);
}
check(/REVOKE INSERT, UPDATE, DELETE ON public\.clinical_orders FROM authenticated, anon/.test(migration), 'direct clinical order writes revoked');
check(/REVOKE INSERT, UPDATE, DELETE ON public\.clinical_order_items FROM authenticated, anon/.test(migration), 'direct clinical order item writes revoked');
check(migration.includes('DROP POLICY IF EXISTS "diagnostic_reports_update_draft"') && migration.includes('REVOKE UPDATE, DELETE ON public.diagnostic_reports'), 'remaining direct diagnostic report mutations revoked');
check(/REVOKE ALL ON FUNCTION public\.acknowledge_critical_result[\s\S]*DROP FUNCTION public\.acknowledge_critical_result/.test(migration), 'legacy signed-result acknowledgement bypass retired');
check(/REVOKE ALL ON FUNCTION public\.recompute_order_item_calculated_results\(UUID\)[\s\S]*FROM PUBLIC, anon, authenticated/.test(migration), 'calculation helper is internal-only');
check(/REVOKE ALL ON FUNCTION public\.attach_report_artifact[\s\S]*DROP FUNCTION public\.attach_report_artifact/.test(migration), 'legacy signed-report hash rewrite RPC retired');
check(/INSERT INTO public\.clinical_orders/.test(billing) && /INSERT INTO public\.clinical_order_items/.test(billing), 'transactional billing RPC retains order creation');
check(/UPDATE public\.clinical_order_items/.test(samples) && /transition_sample_lifecycle/.test(samples), 'sample lifecycle RPC retains guarded state transitions');
check(/UPDATE public\.clinical_order_items SET status = v_item_status/.test(results) && /save_test_results/.test(results), 'result RPC retains guarded item status transitions');
check(/UPDATE public\.clinical_orders[\s\S]*SET status = 'SignedOff'/.test(signoff), 'sign-off RPC retains guarded final state transition');
check(!/\.from\('clinical_orders'\)[\s\S]{0,120}\.(?:insert|update|delete)\(/.test(source) && !/\.from\('clinical_order_items'\)[\s\S]{0,120}\.(?:insert|update|delete)\(/.test(source), 'Result Entry has no direct clinical order mutation');

console.log(`\nPhase 41 clinical order security: ${passed} passed, ${failed} failed`);
if (failed) process.exit(1);
