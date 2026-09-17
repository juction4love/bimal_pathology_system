// scripts/semantic-clinical-audit.mjs
import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

function runSql(sql) {
  const tmp = path.resolve('tmp_semantic_audit.sql');
  writeFileSync(tmp, sql, 'utf8');
  try {
    const out = execSync(`npx supabase db query --linked -f "${tmp}"`, {
      encoding: 'utf8',
      shell: true,
      maxBuffer: 20 * 1024 * 1024
    });
    const jsonStart = out.indexOf('{');
    if (jsonStart === -1) return null;
    return JSON.parse(out.slice(jsonStart));
  } finally {
    try { unlinkSync(tmp); } catch {}
  }
}

console.log('=== SEMANTIC CLINICAL GOVERNANCE AUDIT ===\n');

// 1. Audit Result Types and Reference Range Prerequisites
const res1 = runSql(`
  SELECT json_build_object(
    'test_count', (SELECT count(*) FROM public.tests),
    'parameter_count', (SELECT count(*) FROM public.parameters),
    'report_data_types', (SELECT json_agg(t) FROM (SELECT report_data_type, count(*) as cnt FROM public.tests GROUP BY report_data_type ORDER BY cnt DESC) t),
    'test_types', (SELECT json_agg(t) FROM (SELECT test_type, count(*) as cnt FROM public.tests GROUP BY test_type ORDER BY cnt DESC) t),
    'param_value_types', (SELECT json_agg(t) FROM (SELECT value_type, count(*) as cnt FROM public.parameters GROUP BY value_type ORDER BY cnt DESC) t),
    'qualitative_params_requiring_range', (
      SELECT count(*)
      FROM public.parameters p
      JOIN public.tests t ON p.test_id = t.id
      WHERE (p.value_type NOT IN ('Numeric', 'Calculated') OR t.report_data_type NOT IN ('Numeric', 'Calculated'))
        AND p.range_validation_required = TRUE
    ),
    'numeric_calculated_params', (
      SELECT count(*)
      FROM public.parameters p
      JOIN public.tests t ON p.test_id = t.id
      WHERE p.value_type IN ('Numeric', 'Calculated') AND t.report_data_type IN ('Numeric', 'Calculated')
    ),
    'narrative_tests_sample', (
      SELECT json_agg(json_build_object('code', code, 'name', name, 'report_data_type', report_data_type, 'department', department))
      FROM public.tests
      WHERE report_data_type IN ('PathologyNarrative', 'Microbiology', 'Multiline', 'CultureAST')
      LIMIT 10
    )
  ) as summary;
`);

const s1 = res1?.rows?.[0]?.summary || res1?.[0]?.summary;
console.log('1. Result-Type Distribution:');
console.log('   Report Data Types   :', JSON.stringify(s1.report_data_types, null, 2));
console.log('   Test Types (Single/Panel):', JSON.stringify(s1.test_types, null, 2));
console.log('   Param Value Types   :', JSON.stringify(s1.param_value_types, null, 2));
console.log('   Qualitative parameters wrongly requiring range validation:', s1.qualitative_params_requiring_range);
console.log('   Numeric/Calculated parameters:', s1.numeric_calculated_params);

// 2. Audit Field Integrity on all 1122 tests
const res2 = runSql(`
  SELECT json_build_object(
    'invalid_department', (SELECT count(*) FROM public.tests WHERE department IS NULL OR btrim(department) = ''),
    'invalid_report_data_type', (SELECT count(*) FROM public.tests WHERE report_data_type IS NULL OR btrim(report_data_type) = ''),
    'invalid_specimen', (SELECT count(*) FROM public.tests WHERE reporting_type <> 'NoReporting' AND (sample_type IS NULL OR btrim(sample_type) = '')),
    'invalid_container', (SELECT count(*) FROM public.tests WHERE collection_required AND (container IS NULL OR btrim(container) = '')),
    'invalid_unit_on_numeric', (
      SELECT count(*)
      FROM public.tests t
      JOIN public.parameters p ON p.test_id = t.id
      WHERE t.report_data_type = 'Numeric'
        AND p.value_type IN ('Numeric', 'Calculated')
        AND (t.unit IS NULL OR btrim(t.unit) = '' OR p.unit IS NULL OR btrim(p.unit) = '')
    ),
    'missing_params_on_reportable', (
      SELECT count(*)
      FROM public.tests t
      WHERE t.reporting_type <> 'NoReporting'
        AND NOT EXISTS (SELECT 1 FROM public.parameters p WHERE p.test_id = t.id)
    ),
    'panel_components_count', (SELECT count(*) FROM public.catalogue_panel_components),
    'orphaned_panel_components', (
      SELECT count(*)
      FROM public.catalogue_panel_components c
      WHERE NOT EXISTS (SELECT 1 FROM public.tests t WHERE t.id = c.panel_id)
         OR NOT EXISTS (SELECT 1 FROM public.tests t WHERE t.id = c.component_test_id)
    ),
    'aliases_count', (SELECT count(*) FROM public.test_aliases),
    'orphaned_aliases', (
      SELECT count(*)
      FROM public.test_aliases a
      WHERE NOT EXISTS (SELECT 1 FROM public.tests t WHERE t.id = a.test_id)
    )
  ) as integrity;
`);

const s2 = res2?.rows?.[0]?.integrity || res2?.[0]?.integrity;
console.log('\n2. Field & Relationship Integrity across 1,122 tests:');
console.log('   - Invalid / missing department      :', s2.invalid_department);
console.log('   - Invalid / missing report data type:', s2.invalid_report_data_type);
console.log('   - Invalid specimen where applicable :', s2.invalid_specimen);
console.log('   - Invalid container where applicable:', s2.invalid_container);
console.log('   - Missing unit on Numeric/Calculated:', s2.invalid_unit_on_numeric);
console.log('   - Missing parameters on reportable  :', s2.missing_params_on_reportable);
console.log('   - Panel components count            :', s2.panel_components_count);
console.log('   - Orphaned panel components         :', s2.orphaned_panel_components);
console.log('   - Total test aliases count          :', s2.aliases_count);
console.log('   - Orphaned test aliases             :', s2.orphaned_aliases);

// 3. Normalization breakdown
const res3 = runSql(`
  SELECT json_build_object(
    'distinct_specimens_in_tests', (SELECT count(DISTINCT sample_type) FROM public.tests WHERE sample_type IS NOT NULL AND btrim(sample_type) <> ''),
    'distinct_containers_in_tests', (SELECT count(DISTINCT container) FROM public.tests WHERE container IS NOT NULL AND btrim(container) <> ''),
    'distinct_units_in_tests', (SELECT count(DISTINCT unit) FROM public.tests WHERE unit IS NOT NULL AND btrim(unit) <> ''),
    'distinct_methods_in_tests', (SELECT count(DISTINCT method) FROM public.tests WHERE method IS NOT NULL AND btrim(method) <> ''),
    'aliases', (SELECT count(*) FROM public.test_aliases),
    'panels_in_tests', (SELECT count(*) FROM public.tests WHERE test_type = 'Panel'),
    'panels_with_components', (SELECT count(DISTINCT panel_id) FROM public.catalogue_panel_components),
    'total_tests', (SELECT count(*) FROM public.tests)
  ) as counts;
`);
const s3 = res3?.rows?.[0]?.counts || res3?.[0]?.counts;
console.log('\n3. Normalized Entities Count in Catalogue:');
console.log('   Distinct Specimen Types :', s3.distinct_specimens_in_tests);
console.log('   Distinct Containers     :', s3.distinct_containers_in_tests);
console.log('   Distinct Units          :', s3.distinct_units_in_tests);
console.log('   Distinct Methods        :', s3.distinct_methods_in_tests);
console.log('   Total Aliases           :', s3.aliases);
console.log('   Panels in Tests Table   :', s3.panels_in_tests);
console.log('   Panels with Components  :', s3.panels_with_components);
console.log('   Total Canonical Tests   :', s3.total_tests);

// 4. Missing Configuration Rule Check on diverse test types
console.log('\n4. Checking missing configuration prerequisites across different clinical test types:');
const res4 = runSql(`
  DO $$
  DECLARE
    v_admin_id UUID;
  BEGIN
    SELECT id INTO v_admin_id FROM public.user_profiles WHERE is_active = TRUE LIMIT 1;
    IF v_admin_id IS NOT NULL THEN
      PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
      PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);
    END IF;
  END $$;

  SELECT json_agg(json_build_object(
    'code', t.code,
    'name', t.name,
    'department', t.department,
    'report_data_type', t.report_data_type,
    'param_type', p.value_type,
    'missing', public.catalogue_test_missing_configuration(t.id)
  )) as missing_audit
  FROM public.tests t
  LEFT JOIN public.parameters p ON p.test_id = t.id
  WHERE t.code IN ('BIO-0001', 'HIS-0001', 'CYT-0001', 'MIC-0001', 'SER-0001', 'PAT-0001');
`);
console.log(JSON.stringify(res4, null, 2));
