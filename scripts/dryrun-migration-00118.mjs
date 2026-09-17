import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const migrationSql118 = readFileSync('supabase/migrations/00118_lab_technician_operational_rbac.sql', 'utf8');

// Strip BEGIN; and COMMIT; from migration to wrap in dry-run transaction
const migrationInner118 = migrationSql118
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
    (SELECT count(*)::int FROM public.bills) AS pre_bills,
    (SELECT count(*)::int FROM public.clinical_orders) AS pre_orders,
    (SELECT count(*)::int FROM public.test_results) AS pre_test_results,
    (SELECT count(*)::int FROM public.diagnostic_reports) AS pre_reports,
    (SELECT count(*)::int FROM public.role_permissions rp JOIN public.roles r ON r.id = rp.role_id WHERE r.code = 'lab_technician') AS pre_technician_perms;

-- 2. Execute 00118 payload
${migrationInner118}

-- 3. Verify technician permissions and functions
CREATE TEMP TABLE _verification AS
SELECT
    (SELECT count(*)::int FROM public.role_permissions rp JOIN public.roles r ON r.id = rp.role_id WHERE r.code = 'lab_technician') AS post_technician_perms,
    (SELECT array_agg(rp.permission_key ORDER BY rp.permission_key) FROM public.role_permissions rp JOIN public.roles r ON r.id = rp.role_id WHERE r.code = 'lab_technician') AS technician_permission_list,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'catalogue_require_manager') AS has_catalogue_require_manager,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'catalogue_require_technical') AS has_catalogue_require_technical,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'replace_role_permission_matrix') AS has_replace_role_permission_matrix;

-- 4. Produce final dry-run payload
SELECT json_build_object(
    'pre_state', (SELECT row_to_json(_pre_state.*) FROM _pre_state),
    'verification', (SELECT row_to_json(_verification.*) FROM _verification)
) AS dry_run_result;

-- 5. STRICT ROLLBACK: Zero permanent changes applied during dry-run
ROLLBACK;
`;

async function run() {
  const tmpFile = path.resolve('tmp_dry_run_00118.sql');
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
    writeFileSync('scripts/dryrun_00118_output.json', JSON.stringify(result, null, 2), 'utf8');
    console.log('=== DRY-RUN 00118 RESULTS ===');
    console.log('Verification:');
    console.log(JSON.stringify(result.verification, null, 2));
    console.log('\n00118 Dry run succeeded and ROLLED BACK cleanly.');
  } catch (err) {
    console.error('Error executing 00118 dry run:');
    if (err.stdout) console.error('stdout:', err.stdout);
    if (err.stderr) console.error('stderr:', err.stderr);
    console.error('message:', err.message);
    process.exit(1);
  } finally {
    try { unlinkSync(tmpFile); } catch {}
  }
}

run();
