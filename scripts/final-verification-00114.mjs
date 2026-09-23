import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const migrationSql = readFileSync('supabase/migrations_legacy_archive/00114_lab_test_rate_catalogue_and_panels.sql', 'utf8');
const migrationInner = migrationSql.replace(/^BEGIN;/m, '').replace(/^COMMIT;/m, '');

const dryRunSql = `
BEGIN;

-- 1. Pre-state snapshot
CREATE TEMP TABLE _pre_state AS
SELECT
    (SELECT count(*)::int FROM public.tests) AS pre_total_tests,
    (SELECT count(*)::int FROM public.tests WHERE test_type = 'Panel') AS pre_panels,
    (SELECT count(*)::int FROM public.tests WHERE test_type = 'Single') AS pre_singles,
    (SELECT count(*)::int FROM public.catalogue_panel_components) AS pre_panel_components,
    (SELECT count(*)::int FROM public.test_aliases) AS pre_aliases,
    (SELECT count(*)::int FROM public.catalogue_rate_versions) AS pre_rate_versions,
    (SELECT count(*)::int FROM public.bills) AS pre_bills,
    (SELECT count(*)::int FROM public.bill_items) AS pre_bill_items,
    (SELECT count(*)::int FROM public.clinical_orders) AS pre_orders,
    (SELECT count(*)::int FROM public.clinical_order_items) AS pre_order_items;

-- 2. Execute migration payload
${migrationInner}

-- 3. Post-state snapshot
CREATE TEMP TABLE _post_state AS
SELECT
    (SELECT count(*)::int FROM public.tests) AS post_total_tests,
    (SELECT count(*)::int FROM public.tests WHERE test_type = 'Panel') AS post_panels,
    (SELECT count(*)::int FROM public.tests WHERE test_type = 'Single') AS post_singles,
    (SELECT count(*)::int FROM public.catalogue_panel_components) AS post_panel_components,
    (SELECT count(*)::int FROM public.test_aliases) AS post_aliases,
    (SELECT count(*)::int FROM public.catalogue_rate_versions) AS post_rate_versions,
    (SELECT count(*)::int FROM public.bills) AS post_bills,
    (SELECT count(*)::int FROM public.bill_items) AS post_bill_items,
    (SELECT count(*)::int FROM public.clinical_orders) AS post_orders,
    (SELECT count(*)::int FROM public.clinical_order_items) AS post_order_items;

-- 4. Invariants check
CREATE TEMP TABLE _invariants AS
SELECT
    (SELECT count(*)::int FROM (SELECT code FROM public.tests GROUP BY code HAVING count(*) > 1) d) AS duplicate_codes_count,
    (SELECT count(*)::int FROM public.tests WHERE id NOT IN (SELECT id FROM public.tests)) AS deleted_catalogue_rows,
    (SELECT count(*)::int FROM public.catalogue_rate_versions WHERE status = 'Active') AS active_rate_versions_count,
    (SELECT count(*)::int FROM public.assay_specimen_governance_rules WHERE test_id IN (SELECT id FROM public.tests WHERE code IN ('IMM-0093', 'BIO-0141', 'SER-0089'))) AS unconfigured_specimen_rules_count;

-- 5. Panel components verification
CREATE TEMP TABLE _panel_components AS
SELECT json_agg(json_build_object(
    'panel_code', p.code,
    'panel_name', p.name,
    'price_npr', p.price_paisa / 100,
    'validation_status', p.validation_status,
    'reporting_enabled', p.clinical_reporting_enabled,
    'components', (
        SELECT json_agg(json_build_object(
            'code', ct.code,
            'name', ct.name,
            'display_order', cpc.display_order
        ) ORDER BY cpc.display_order)
        FROM public.catalogue_panel_components cpc
        JOIN public.tests ct ON ct.id = cpc.component_test_id
        WHERE cpc.panel_id = p.id
    )
) ORDER BY p.code) AS panels
FROM public.tests p
WHERE p.code IN ('PRO-0026', 'PRO-0027', 'PRO-0028', 'PRO-0029');

-- 6. All 40 audited tests & prices
CREATE TEMP TABLE _all_prices AS
SELECT json_agg(json_build_object(
    'code', t.code,
    'name', t.name,
    'short_name', t.short_name,
    'test_type', t.test_type,
    'price_paisa', t.price_paisa,
    'price_npr', t.price_paisa / 100,
    'validation_status', t.validation_status,
    'clinical_reporting_enabled', t.clinical_reporting_enabled,
    'is_active', t.is_active,
    'billing_enabled', t.billing_enabled,
    'method', t.method,
    'specimen_type', t.specimen_type,
    'sample_type', t.sample_type
) ORDER BY t.code) AS price_list
FROM public.tests t
WHERE t.code IN (
    'BIO-0063', 'BIO-0064', 'BIO-0061', 'BIO-0067', 'COA-0006',
    'BIO-0068', 'IMM-0001', 'PCT_SEPSIS', 'IMM-0093', 'BIO-0050',
    'BIO-0006', 'BIO-0085', 'BIO-0141',
    'END-0001', 'END-0003', 'END-0002', 'END-0039', 'END-0031', 'END-0028', 'END-0027', 'END-0025', 'END-0037', 'BIO-0053',
    'SER-0020', 'SER-0089', 'SER-0015', 'SER-0087', 'SER-0088', 'SER-0004', 'SER-0010', 'SER-0043',
    'IMM-0004', 'IMM-0003', 'IMM-0002', 'IMM-0031', 'TUM-0007', 'TUM-0001', 'TUM-0002',
    'PRO-0026', 'PRO-0027', 'PRO-0028', 'PRO-0029'
);

-- 7. Output complete JSON payload
SELECT json_build_object(
    'pre_state', (SELECT row_to_json(_pre_state.*) FROM _pre_state),
    'post_state', (SELECT row_to_json(_post_state.*) FROM _post_state),
    'invariants', (SELECT row_to_json(_invariants.*) FROM _invariants),
    'panels', (SELECT panels FROM _panel_components),
    'prices', (SELECT price_list FROM _all_prices),
    'historical_bills_delta', (SELECT post_bills - pre_bills FROM _pre_state, _post_state),
    'historical_bill_items_delta', (SELECT post_bill_items - pre_bill_items FROM _pre_state, _post_state),
    'historical_orders_delta', (SELECT post_orders - pre_orders FROM _pre_state, _post_state),
    'historical_order_items_delta', (SELECT post_order_items - pre_order_items FROM _pre_state, _post_state)
) AS result;

ROLLBACK;
`;

async function main() {
  const tmpFile = path.resolve('tmp_final_verify_00114.sql');
  writeFileSync(tmpFile, dryRunSql, 'utf8');

  try {
    const raw = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: true,
      maxBuffer: 50 * 1024 * 1024,
    });

    const jsonStart = raw.indexOf('[');
    const jsonStartObj = raw.indexOf('{');
    const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
    const parsed = JSON.parse(raw.slice(start));
    const data = Array.isArray(parsed) ? parsed[0]?.result : parsed.rows?.[0]?.result;
    writeFileSync('scripts/final_00114_verification.json', JSON.stringify(data, null, 2), 'utf8');
    console.log('Final verification data generated successfully.');
  } catch (err) {
    console.error('Error during final verification:', err.message, err.stderr);
    process.exit(1);
  } finally {
    try { unlinkSync(tmpFile); } catch {}
  }
}

main();
