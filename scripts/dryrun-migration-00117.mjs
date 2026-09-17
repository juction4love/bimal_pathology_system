import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const migrationSql = readFileSync('supabase/migrations/00117_easy_test_catalogue_management.sql', 'utf8');

// Strip BEGIN; and COMMIT; from migration to wrap in dry-run transaction with verification
const migrationInner = migrationSql
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

-- 2. Execute migration payload
${migrationInner}

-- 3. Verify RPC existence and compilation
CREATE TEMP TABLE _rpc_verification AS
SELECT
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'catalogue_save_test_easy') AS has_save_test_easy,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'catalogue_delete_test_guarded') AS has_delete_test_guarded,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'catalogue_clone_test_easy') AS has_clone_test_easy,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'catalogue_save_parameter_easy') AS has_save_parameter_easy,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'catalogue_reorder_parameters_easy') AS has_reorder_parameters_easy,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'catalogue_delete_parameter_guarded') AS has_delete_parameter_guarded,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'catalogue_save_range_easy') AS has_save_range_easy,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'catalogue_delete_range_guarded') AS has_delete_range_guarded,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'catalogue_save_test_aliases_easy') AS has_save_test_aliases_easy,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'catalogue_save_analyzer_mapping_easy') AS has_save_analyzer_mapping_easy,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'catalogue_delete_analyzer_mapping_easy') AS has_delete_analyzer_mapping_easy,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'catalogue_get_test_history') AS has_get_test_history,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'replace_role_permission_matrix') AS has_replace_role_permission_matrix;

-- 4. Verify Lab Technician role has can_manage_catalogue permission
CREATE TEMP TABLE _perm_verification AS
SELECT
    EXISTS (
        SELECT 1 FROM public.role_permissions rp
        JOIN public.roles r ON r.id = rp.role_id
        WHERE r.code = 'admin' AND rp.permission_key = 'can_manage_catalogue'
    ) AS admin_can_manage_catalogue,
    EXISTS (
        SELECT 1 FROM public.role_permissions rp
        JOIN public.roles r ON r.id = rp.role_id
        WHERE r.code = 'lab_technician' AND rp.permission_key = 'can_manage_catalogue'
    ) AS lab_tech_can_manage_catalogue;

-- 5. Audit post-migration state
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

-- 6. Produce final dry-run payload
SELECT json_build_object(
    'pre_state', (SELECT row_to_json(_pre_state.*) FROM _pre_state),
    'post_state', (SELECT row_to_json(_post_state.*) FROM _post_state),
    'rpc_verification', (SELECT row_to_json(_rpc_verification.*) FROM _rpc_verification),
    'perm_verification', (SELECT row_to_json(_perm_verification.*) FROM _perm_verification),
    'historical_bills_delta', (SELECT post_bills - pre_bills FROM _pre_state, _post_state),
    'historical_bill_items_delta', (SELECT post_bill_items - pre_bill_items FROM _pre_state, _post_state),
    'historical_orders_delta', (SELECT post_orders - pre_orders FROM _pre_state, _post_state),
    'historical_order_items_delta', (SELECT post_order_items - pre_order_items FROM _pre_state, _post_state),
    'historical_results_delta', (SELECT post_test_results - pre_test_results FROM _pre_state, _post_state),
    'historical_reports_delta', (SELECT post_reports - pre_reports FROM _pre_state, _post_state)
) AS dry_run_result;

-- 7. STRICT ROLLBACK: Zero permanent changes applied during dry-run
ROLLBACK;
`;

async function run() {
  const tmpFile = path.resolve('tmp_dry_run_00117.sql');
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
    writeFileSync('scripts/dryrun_00117_output.json', JSON.stringify(result, null, 2), 'utf8');
    console.log('=== DRY-RUN 00117 RESULTS ===');
    console.log('RPC Verification:');
    console.log(JSON.stringify(result.rpc_verification, null, 2));
    console.log('\nPermission Verification:');
    console.log(JSON.stringify(result.perm_verification, null, 2));
    console.log('\nHistorical Data Deltas (All must be 0):');
    console.log('Bills delta:', result.historical_bills_delta);
    console.log('Bill items delta:', result.historical_bill_items_delta);
    console.log('Orders delta:', result.historical_orders_delta);
    console.log('Order items delta:', result.historical_order_items_delta);
    console.log('Results delta:', result.historical_results_delta);
    console.log('Report snapshots delta:', result.historical_reports_delta);
    console.log('\nDry run succeeded and ROLLED BACK cleanly.');
  } catch (err) {
    console.error('Error executing dry run:');
    if (err.stdout) console.error('stdout:', err.stdout);
    if (err.stderr) console.error('stderr:', err.stderr);
    console.error('message:', err.message);
    process.exit(1);
  } finally {
    try { unlinkSync(tmpFile); } catch {}
  }
}

run();
