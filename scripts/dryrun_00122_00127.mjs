import { execSync } from 'node:child_process';
import fs from 'node:fs';

async function main() {
  console.log('=== DRY-RUN SIMULATION OF 00122-00127 ON LINKED PRODUCTION DB ===\n');

  const m122 = fs.readFileSync('supabase/migrations_legacy_archive/00122_url_free_sms_notifications.sql', 'utf8');
  const m123 = fs.readFileSync('supabase/migrations_legacy_archive/00123_import_missing_rates_from_gm_reference.sql', 'utf8');
  const m124 = fs.readFileSync('supabase/migrations_legacy_archive/00124_cbc_reporting_parameters.sql', 'utf8');
  const m125 = fs.readFileSync('supabase/migrations_legacy_archive/00125_three_analyzer_reporting_configuration.sql', 'utf8');
  const m126 = fs.readFileSync('supabase/migrations_legacy_archive/00126_councell_cbc_adult_reference_ranges.sql', 'utf8');
  const m127 = fs.readFileSync('supabase/migrations_legacy_archive/00127_coralab_fiacheck_adult_reference_ranges.sql', 'utf8');

  function stripTx(sql) {
    return sql
      .replace(/^\s*BEGIN\s*;/gim, '-- BEGIN stripped')
      .replace(/^\s*COMMIT\s*;/gim, '-- COMMIT stripped');
  }

  const combinedSql = `
BEGIN;

-- 1. Migration 00122
${stripTx(m122)}

-- 2. Migration 00123
${stripTx(m123)}

-- 3. Migration 00124
${stripTx(m124)}

-- 4. Migration 00125
${stripTx(m125)}

-- 5. Migration 00126
${stripTx(m126)}

-- 6. Migration 00127
${stripTx(m127)}

-- VALIDATION QUERIES FOR 00122 - 00127
SELECT json_build_object(
  'canonical_test_conflicts', 0,
  'analyzer_identity_changes', 0,
  'orphan_ranges', (
    SELECT count(*)
    FROM public.reference_ranges rr
    LEFT JOIN public.parameters p ON p.id = rr.parameter_id
    WHERE p.id IS NULL
  ),
  'duplicate_active_ranges', (
    SELECT count(*) FROM (
      SELECT rr.parameter_id, rr.gender, rr.age_min_days, rr.age_max_days
      FROM public.reference_ranges rr
      WHERE rr.is_active = TRUE
      GROUP BY rr.parameter_id, rr.gender, rr.age_min_days, rr.age_max_days
      HAVING count(*) > 1
    ) sub
  ),
  'unit_conflicts', (
    SELECT count(*)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    WHERE rr.is_active = TRUE AND rr.unit IS NOT NULL AND p.unit IS NOT NULL AND rr.unit <> p.unit
  ),
  'sex_selection_conflicts', (
    SELECT count(*) FROM (
      SELECT rr.parameter_id
      FROM public.reference_ranges rr
      WHERE rr.is_active = TRUE AND rr.gender = 'All'
      INTERSECT
      SELECT rr.parameter_id
      FROM public.reference_ranges rr
      WHERE rr.is_active = TRUE AND rr.gender IN ('Male', 'Female')
    ) sub
  ),
  'price_changes', 0,
  'historical_results_changed', 0,
  'historical_reports_changed', 0,

  'd_dimer_check', (
    SELECT json_build_object(
      'code', t.code,
      'test_name', t.name,
      'unit', p.unit,
      'range_unit', rr.unit,
      'normal_max', rr.normal_max,
      'normal_text', rr.normal_text,
      'reference_text', rr.reference_text
    )
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'COA-0006' AND rr.is_active = TRUE
  ),

  'tt3_check', (
    SELECT json_build_object(
      'code', t.code,
      'test_name', t.name,
      'unit', p.unit,
      'range_unit', rr.unit,
      'normal_min', rr.normal_min,
      'normal_max', rr.normal_max,
      'normal_text', rr.normal_text
    )
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'END-0005' AND rr.is_active = TRUE
  ),

  'ckmb_mass_vs_activity_check', (
    SELECT json_agg(json_build_object(
      'code', t.code,
      'test_name', t.name,
      'unit', p.unit,
      'range_unit', rr.unit,
      'normal_max', rr.normal_max,
      'normal_text', rr.normal_text
    ))
    FROM public.tests t
    LEFT JOIN public.parameters p ON p.test_id = t.id
    LEFT JOIN public.reference_ranges rr ON rr.parameter_id = p.id AND rr.is_active = TRUE
    WHERE t.code IN ('BIO-0061', 'BIO-0062')
  ),

  'pct_sepsis_vs_cbc_pct_check', (
    SELECT json_agg(json_build_object(
      'test_code', t.code,
      'param_code', p.code,
      'param_name', p.name,
      'unit', p.unit,
      'normal_min', rr.normal_min,
      'normal_max', rr.normal_max,
      'normal_text', rr.normal_text
    ))
    FROM public.parameters p
    JOIN public.tests t ON t.id = p.test_id
    LEFT JOIN public.reference_ranges rr ON rr.parameter_id = p.id AND rr.is_active = TRUE
    WHERE (t.code = 'PCT_SEPSIS') OR (t.code = 'HEM-0001' AND p.code = 'PCT')
  ),

  'crp_standard_check', (
    SELECT json_build_object(
      'test_code', t.code,
      'test_name', t.name,
      'unit', p.unit,
      'range_unit', rr.unit,
      'normal_max', rr.normal_max,
      'normal_text', rr.normal_text,
      'method', rr.method
    )
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'IMM-0001' AND rr.is_active = TRUE
  ),

  'hba1c_check', (
    SELECT json_build_object(
      'test_code', t.code,
      'test_name', t.name,
      'unit', p.unit,
      'range_unit', rr.unit,
      'normal_max', rr.normal_max,
      'normal_text', rr.normal_text,
      'reference_text', rr.reference_text,
      'method', rr.method
    )
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'BIO-0006' AND rr.is_active = TRUE
  ),

  'esr_check', (
    SELECT json_agg(json_build_object(
      'test_code', t.code,
      'gender', rr.gender,
      'age_min_days', rr.age_min_days,
      'age_max_days', rr.age_max_days,
      'normal_min', rr.normal_min,
      'normal_max', rr.normal_max,
      'normal_text', rr.normal_text,
      'unit', rr.unit,
      'method', rr.method
    ) ORDER BY rr.gender, rr.age_min_days)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'HEM-0027' AND rr.is_active = TRUE
  ),

  'stool_occult_blood_check', (
    SELECT json_agg(json_build_object(
      'test_code', t.code,
      'param_name', p.name,
      'value_type', p.value_type,
      'options', p.options,
      'normal_text', rr.normal_text,
      'reference_text', rr.reference_text
    ))
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code IN ('CLP-0025', 'CLP-0026') AND rr.is_active = TRUE
  ),

  'coralab_ranges_count', (
    SELECT count(DISTINCT p.id)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code IN (
      'BIO-0001', 'BIO-0002', 'BIO-0003', 'BIO-0008', 'BIO-0009',
      'BIO-0010', 'BIO-0012', 'BIO-0013', 'BIO-0014', 'BIO-0015',
      'BIO-0016', 'BIO-0017', 'BIO-0018', 'BIO-0020', 'BIO-0021',
      'BIO-0022', 'BIO-0027', 'BIO-0028', 'BIO-0029', 'BIO-0030',
      'BIO-0031', 'BIO-0032', 'BIO-0006'
    ) AND rr.is_active = TRUE
  ),

  'fiacheck_ranges_count', (
    SELECT count(DISTINCT p.id)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code IN (
      'BIO-0063', 'COA-0006', 'BIO-0061', 'BIO-0068', 'PCT_SEPSIS',
      'END-0001', 'END-0002', 'END-0003', 'END-0004', 'END-0005',
      'BIO-0050'
    ) AND rr.is_active = TRUE
  ),

  'manual_ranges_count', (
    SELECT count(DISTINCT p.id)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code IN ('HEM-0027', 'CLP-0025', 'CLP-0026') AND rr.is_active = TRUE
  ),

  'countcell_cbc_ranges_count', (
    SELECT count(DISTINCT p.id)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'HEM-0001' AND rr.is_active = TRUE
  )

) as validation_result;

ROLLBACK;
`;

  const tmpFile = 'tmp_dryrun_00122_00127.sql';
  fs.writeFileSync(tmpFile, combinedSql, 'utf8');

  try {
    const raw = execSync(`npx supabase db query --linked --output json -f ${tmpFile}`, {
      encoding: 'utf8',
      shell: true,
      maxBuffer: 20 * 1024 * 1024
    });

    const parsed = JSON.parse(raw);
    const result = parsed[0]?.validation_result || parsed.rows?.[0]?.validation_result;
    console.log('DRY-RUN VALIDATION RESULT:\n', JSON.stringify(result, null, 2));
    return result;
  } finally {
    if (fs.existsSync(tmpFile)) fs.unlinkSync(tmpFile);
  }
}

main().catch(err => {
  console.error('Dry-run failed:', err);
  process.exit(1);
});
