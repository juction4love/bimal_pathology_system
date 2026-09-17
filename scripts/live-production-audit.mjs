import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const querySql = `
WITH counts AS (
    SELECT
        (SELECT count(*)::int FROM public.tests) AS total_tests,
        (SELECT count(*)::int FROM public.tests WHERE test_type = 'Single') AS total_singles,
        (SELECT count(*)::int FROM public.tests WHERE test_type = 'Panel') AS total_panels,
        (SELECT count(*)::int FROM public.catalogue_panel_components) AS total_panel_components,
        (SELECT count(*)::int FROM public.test_aliases) AS total_aliases,
        (SELECT count(*)::int FROM public.parameters) AS total_parameters,
        (SELECT count(*)::int FROM public.reference_ranges) AS total_reference_ranges,
        (SELECT count(*)::int FROM public.analyzers) AS total_analyzers,
        (SELECT count(*)::int FROM public.analyzer_parameter_mappings) AS total_analyzer_mappings,
        (SELECT count(*)::int FROM public.assay_specimen_governance_rules) AS total_specimen_rules,
        (SELECT count(*)::int FROM public.user_profiles) AS total_users,
        (SELECT count(*)::int FROM public.user_roles) AS total_user_roles,
        (SELECT count(*)::int FROM public.role_permissions) AS total_permissions,
        (SELECT count(*)::int FROM public.catalogue_rate_versions) AS total_rate_versions,
        (SELECT count(*)::int FROM public.patients) AS total_patients,
        (SELECT count(*)::int FROM public.bills) AS total_bills,
        (SELECT count(*)::int FROM public.bill_items) AS total_bill_items,
        (SELECT count(*)::int FROM public.clinical_orders) AS total_orders,
        (SELECT count(*)::int FROM public.clinical_order_items) AS total_order_items,
        (SELECT count(*)::int FROM public.samples) AS total_samples,
        (SELECT count(*)::int FROM public.test_results) AS total_results
),
duplicates AS (
    SELECT
        (SELECT count(*)::int FROM (SELECT code FROM public.tests GROUP BY code HAVING count(*) > 1) d) AS duplicate_test_codes,
        (SELECT count(*)::int FROM (SELECT name FROM public.tests GROUP BY name HAVING count(*) > 1) d) AS duplicate_test_names
),
orphans AS (
    SELECT
        (SELECT count(*)::int FROM public.catalogue_panel_components cpc WHERE cpc.panel_id NOT IN (SELECT id FROM public.tests)) AS orphan_panel_ids,
        (SELECT count(*)::int FROM public.catalogue_panel_components cpc WHERE cpc.component_test_id NOT IN (SELECT id FROM public.tests)) AS orphan_component_test_ids,
        (SELECT count(*)::int FROM public.parameters p WHERE p.test_id NOT IN (SELECT id FROM public.tests)) AS orphan_parameters,
        (SELECT count(*)::int FROM public.test_aliases a WHERE a.test_id NOT IN (SELECT id FROM public.tests)) AS orphan_aliases,
        (SELECT count(*)::int FROM public.bill_items bi WHERE bi.bill_id NOT IN (SELECT id FROM public.bills)) AS orphan_bill_items,
        (SELECT count(*)::int FROM public.clinical_order_items coi WHERE coi.order_id NOT IN (SELECT id FROM public.clinical_orders)) AS orphan_order_items
),
recent_tests AS (
    SELECT json_agg(json_build_object(
        'code', t.code,
        'name', t.name,
        'short_name', t.short_name,
        'department', t.department,
        'test_type', t.test_type,
        'specimen_type', t.specimen_type,
        'sample_type', t.sample_type,
        'container', t.container,
        'method', t.method,
        'unit', t.unit,
        'price_paisa', t.price_paisa,
        'price_npr', t.price_paisa / 100,
        'validation_status', t.validation_status,
        'clinical_reporting_enabled', t.clinical_reporting_enabled,
        'is_active', t.is_active,
        'billing_enabled', t.billing_enabled,
        'parameters', (
            SELECT json_agg(json_build_object(
                'code', p.code,
                'name', p.name,
                'value_type', p.value_type,
                'unit', p.unit,
                'options', p.options,
                'interpretation_config', p.interpretation_config
            ))
            FROM public.parameters p WHERE p.test_id = t.id
        ),
        'aliases', (
            SELECT json_agg(json_build_object(
                'alias_name', a.alias_name,
                'alias_type', a.alias_type
            ))
            FROM public.test_aliases a WHERE a.test_id = t.id
        )
    ) ORDER BY t.code) AS tests
    FROM public.tests t
    WHERE t.code IN (
        'SER-0001', 'SER-0004', 'SER-0010', 'SER-0086', 'SER-0087', 'SER-0088', 'SER-0089',
        'BIO-0063', 'BIO-0064', 'BIO-0061', 'BIO-0062', 'BIO-0065', 'BIO-0067', 'COA-0006',
        'BIO-0068', 'IMM-0001', 'PCT_SEPSIS', 'IMM-0093', 'BIO-0050',
        'BIO-0006', 'BIO-0085', 'BIO-0141',
        'END-0001', 'END-0002', 'END-0003', 'END-0004', 'END-0005', 'END-0039', 'END-0031', 'END-0028', 'END-0027', 'END-0025', 'END-0037', 'BIO-0053',
        'SER-0015', 'SER-0016', 'SER-0017', 'SER-0020', 'SER-0043',
        'IMM-0004', 'IMM-0003', 'IMM-0002', 'IMM-0031', 'TUM-0007', 'TUM-0001', 'TUM-0002',
        'PRO-0026', 'PRO-0027', 'PRO-0028', 'PRO-0029', 'PRO-0004', 'PRO-0007'
    )
),
panels_audit AS (
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
    WHERE p.code IN ('PRO-0026', 'PRO-0027', 'PRO-0028', 'PRO-0029', 'PRO-0004', 'PRO-0007')
)
SELECT json_build_object(
    'counts', (SELECT row_to_json(counts.*) FROM counts),
    'duplicates', (SELECT row_to_json(duplicates.*) FROM duplicates),
    'orphans', (SELECT row_to_json(orphans.*) FROM orphans),
    'recent_tests', (SELECT tests FROM recent_tests),
    'panels_audit', (SELECT panels FROM panels_audit)
) AS live_audit_payload;
`;

async function run() {
  const tmpFile = path.resolve('tmp_live_audit.sql');
  writeFileSync(tmpFile, querySql, 'utf8');

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
    const data = Array.isArray(parsed) ? parsed[0]?.live_audit_payload : parsed.rows?.[0]?.live_audit_payload;
    writeFileSync('scripts/live_audit_results.json', JSON.stringify(data, null, 2), 'utf8');
    console.log('Live audit query executed successfully!');
  } catch (err) {
    console.error('Error executing live audit:', err.message, err.stderr);
  } finally {
    try { unlinkSync(tmpFile); } catch {}
  }
}

run();
