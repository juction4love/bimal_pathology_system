import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const querySql = `
WITH counts AS (
    SELECT
        (SELECT count(*)::int FROM public.tests) AS total_tests,
        (SELECT count(*)::int FROM public.tests WHERE is_active = TRUE) AS active_tests,
        (SELECT count(*)::int FROM public.tests WHERE test_type = 'Panel') AS panel_tests_in_tests,
        (SELECT count(*)::int FROM public.catalogue_panels) AS total_catalogue_panels,
        (SELECT count(*)::int FROM public.catalogue_panel_services) AS total_panel_services,
        (SELECT count(*)::int FROM public.health_packages) AS total_health_packages,
        (SELECT count(*)::int FROM public.catalogue_panel_components) AS total_panel_components,
        (SELECT count(*)::int FROM public.test_aliases) AS total_test_aliases,
        (SELECT count(*)::int FROM public.parameters) AS total_parameters,
        (SELECT count(*)::int FROM public.reference_ranges) AS total_reference_ranges,
        (SELECT count(*)::int FROM public.catalogue_standard_presets) AS total_standard_presets,
        (SELECT count(*)::int FROM public.assay_specimen_governance_rules) AS total_specimen_rules
),
ser_tests AS (
    SELECT json_agg(json_build_object(
        'id', t.id,
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
        'report_data_type', t.report_data_type,
        'is_active', t.is_active,
        'billing_enabled', t.billing_enabled,
        'clinical_reporting_enabled', t.clinical_reporting_enabled,
        'validation_status', t.validation_status,
        'configuration_status', t.configuration_status,
        'lifecycle_status', t.lifecycle_status,
        'notes', t.notes,
        'parameters', (
            SELECT json_agg(json_build_object(
                'id', p.id,
                'code', p.code,
                'name', p.name,
                'value_type', p.value_type,
                'unit', p.unit,
                'options', p.options,
                'option_set_id', p.option_set_id,
                'option_set_code', (SELECT code FROM public.catalogue_option_sets WHERE id = p.option_set_id),
                'interpretation_config', p.interpretation_config
            ))
            FROM public.parameters p
            WHERE p.test_id = t.id
        ),
        'aliases', (
            SELECT json_agg(json_build_object(
                'alias_name', a.alias_name,
                'alias_type', a.alias_type
            ))
            FROM public.test_aliases a
            WHERE a.test_id = t.id
        ),
        'specimen_rules', (
            SELECT json_agg(json_build_object(
                'preferred_specimen', r.preferred_specimen,
                'allowed_specimens', r.allowed_specimens,
                'primary_tube_color', r.primary_tube_color
            ))
            FROM public.assay_specimen_governance_rules r
            WHERE r.test_id = t.id
        ),
        'preset', (
            SELECT json_build_object(
                'test_code', cp.test_code,
                'test_name', cp.test_name,
                'specimen', cp.specimen,
                'method', cp.method,
                'report_data_type', cp.report_data_type
            )
            FROM public.catalogue_standard_presets cp
            WHERE cp.test_code = t.code
        )
    )) AS tests
    FROM public.tests t
    WHERE t.code IN ('SER-0001', 'SER-0002', 'SER-0003', 'SER-0004', 'SER-0010', 'POC-HIV-RAPID', 'POC-HCV-RAPID', 'POC-HBSAG-RAPID')
),
duplicate_check AS (
    SELECT json_agg(json_build_object(
        'code', code,
        'count', c
    )) AS duplicate_codes
    FROM (
        SELECT code, count(*) AS c
        FROM public.tests
        GROUP BY code
        HAVING count(*) > 1
    ) dup
),
duplicate_names AS (
    SELECT json_agg(json_build_object(
        'name', name,
        'count', c,
        'codes', codes
    )) AS duplicate_test_names
    FROM (
        SELECT name, count(*) AS c, array_agg(code) AS codes
        FROM public.tests
        GROUP BY name
        HAVING count(*) > 1
    ) dup_n
),
discrepancy_breakdown AS (
    SELECT json_build_object(
        'tests_count', (SELECT count(*) FROM public.tests),
        'packages_count', (SELECT count(*) FROM public.health_packages),
        'panel_services_count', (SELECT count(*) FROM public.catalogue_panel_services),
        'total_billable_entities', (
            (SELECT count(*) FROM public.tests) +
            (SELECT count(*) FROM public.health_packages)
        )
    ) AS entity_breakdown
)
SELECT json_build_object(
    'counts', (SELECT row_to_json(counts.*) FROM counts),
    'ser_tests', (SELECT tests FROM ser_tests),
    'duplicate_check', (SELECT duplicate_codes FROM duplicate_check),
    'duplicate_names', (SELECT duplicate_test_names FROM duplicate_names),
    'discrepancy_breakdown', (SELECT entity_breakdown FROM discrepancy_breakdown)
) AS verification_payload;
`;

async function run() {
  const tmpFile = path.resolve('tmp_live_verify.sql');
  writeFileSync(tmpFile, querySql, 'utf8');

  try {
    const raw = execSync(`npx supabase db query --linked -f "${tmpFile}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: true,
      maxBuffer: 20 * 1024 * 1024,
    });

    const jsonStart = raw.indexOf('{');
    if (jsonStart === -1) {
      console.error('No JSON returned:', raw);
      process.exit(1);
    }
    const parsed = JSON.parse(raw.slice(jsonStart));
    const payload = parsed.rows?.[0]?.verification_payload;
    console.log(JSON.stringify(payload, null, 2));
  } catch (err) {
    console.error('Error executing query:', err.message, err.stderr);
  } finally {
    try { unlinkSync(tmpFile); } catch {}
  }
}

run();
