import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const migrationSql116 = readFileSync('supabase/migrations/00116_remove_catalogue_readiness_workflow_blocks.sql', 'utf8');

// Strip BEGIN; and COMMIT; from migration to wrap in dry-run transaction
const migrationInner116 = migrationSql116
  .replace(/^BEGIN;/m, '')
  .replace(/^COMMIT;/m, '');

const dryRunSql = `
BEGIN;

-- 1. Snapshot pre-migration state
CREATE TEMP TABLE _pre_state AS
SELECT
    (SELECT count(*)::int FROM public.tests) AS pre_total_tests,
    (SELECT count(*)::int FROM public.parameters) AS pre_parameters,
    (SELECT count(*)::int FROM public.reference_ranges) AS pre_ranges,
    (SELECT count(*)::int FROM public.test_aliases) AS pre_aliases,
    (SELECT count(*)::int FROM public.catalogue_rate_versions) AS pre_rate_versions,
    (SELECT count(*)::int FROM public.bills) AS pre_bills,
    (SELECT count(*)::int FROM public.bill_items) AS pre_bill_items,
    (SELECT count(*)::int FROM public.clinical_orders) AS pre_orders,
    (SELECT count(*)::int FROM public.clinical_order_items) AS pre_order_items,
    (SELECT count(*)::int FROM public.test_results) AS pre_test_results,
    (SELECT count(*)::int FROM public.diagnostic_reports) AS pre_reports;

-- 2. Execute 00116 payload
${migrationInner116}

-- 3. Verify function existence and compilation
CREATE TEMP TABLE _func_verification AS
SELECT
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'guard_clinical_result_write') AS has_guard_clinical_result_write,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'save_test_results_unversioned_internal') AS has_save_test_results_unversioned_internal,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'check_order_report_readiness') AS has_check_order_report_readiness,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'materialize_report_group_item') AS has_materialize_report_group_item,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'check_report_group_readiness') AS has_check_report_group_readiness,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'search_laboratory_worklist') AS has_search_laboratory_worklist,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ensure_bill_collection_traceability') AS has_ensure_bill_collection_traceability,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'search_billable_catalogue') AS has_search_billable_catalogue,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'catalogue_set_test_lifecycle') AS has_catalogue_set_test_lifecycle,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'create_patient_bill_order_with_panel_service') AS has_create_patient_bill_order_with_panel_service;

-- 4. Audit post-migration state
CREATE TEMP TABLE _post_state AS
SELECT
    (SELECT count(*)::int FROM public.tests) AS post_total_tests,
    (SELECT count(*)::int FROM public.parameters) AS post_parameters,
    (SELECT count(*)::int FROM public.reference_ranges) AS post_ranges,
    (SELECT count(*)::int FROM public.test_aliases) AS post_aliases,
    (SELECT count(*)::int FROM public.catalogue_rate_versions) AS post_rate_versions,
    (SELECT count(*)::int FROM public.bills) AS post_bills,
    (SELECT count(*)::int FROM public.bill_items) AS post_bill_items,
    (SELECT count(*)::int FROM public.clinical_orders) AS post_orders,
    (SELECT count(*)::int FROM public.clinical_order_items) AS post_order_items,
    (SELECT count(*)::int FROM public.test_results) AS post_test_results,
    (SELECT count(*)::int FROM public.diagnostic_reports) AS post_reports;

-- 5. Produce final dry-run payload
SELECT json_build_object(
    'pre_state', (SELECT row_to_json(_pre_state.*) FROM _pre_state),
    'post_state', (SELECT row_to_json(_post_state.*) FROM _post_state),
    'func_verification', (SELECT row_to_json(_func_verification.*) FROM _func_verification),
    'historical_bills_delta', (SELECT post_bills - pre_bills FROM _pre_state, _post_state),
    'historical_bill_items_delta', (SELECT post_bill_items - pre_bill_items FROM _pre_state, _post_state),
    'historical_orders_delta', (SELECT post_orders - pre_orders FROM _pre_state, _post_state),
    'historical_order_items_delta', (SELECT post_order_items - pre_order_items FROM _pre_state, _post_state),
    'historical_results_delta', (SELECT post_test_results - pre_test_results FROM _pre_state, _post_state),
    'historical_reports_delta', (SELECT post_reports - pre_reports FROM _pre_state, _post_state)
) AS dry_run_result;

-- 6. STRICT ROLLBACK: Zero permanent changes applied during dry-run
ROLLBACK;
`;

async function run() {
  const tmpFile = path.resolve('tmp_dry_run_00116.sql');
  writeFileSync(tmpFile, dryRunSql, 'utf8');

  try {
    const res = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: true,
      maxBuffer: 50 * 1024 * 1024,
    });

    const jsonStart = res.indexOf('[');
    const jsonStartObj = res.indexOf('{');
    const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
    if (start === -1) {
      console.error('No JSON found in response:', res);
      process.exit(1);
    }
    const parsed = JSON.parse(res.slice(start));
    const result = Array.isArray(parsed) ? parsed[0]?.dry_run_result : parsed.rows?.[0]?.dry_run_result;
    writeFileSync('scripts/dryrun_00116_output.json', JSON.stringify(result, null, 2), 'utf8');
    console.log('=== DRY-RUN 00116 RESULTS ===');
    console.log('Function Verification:');
    console.log(JSON.stringify(result.func_verification, null, 2));
    console.log('\nHistorical Data Deltas (All must be 0):');
    console.log('Bills delta:', result.historical_bills_delta);
    console.log('Bill items delta:', result.historical_bill_items_delta);
    console.log('Orders delta:', result.historical_orders_delta);
    console.log('Order items delta:', result.historical_order_items_delta);
    console.log('Results delta:', result.historical_results_delta);
    console.log('Reports delta:', result.historical_reports_delta);
    console.log('\n00116 Dry run succeeded and ROLLED BACK cleanly.');
  } catch (err) {
    console.error('Error executing 00116 dry run:');
    if (err.stdout) console.error('stdout:', err.stdout);
    if (err.stderr) console.error('stderr:', err.stderr);
    console.error('message:', err.message);
    process.exit(1);
  } finally {
    try { unlinkSync(tmpFile); } catch {}
  }
}

run();
