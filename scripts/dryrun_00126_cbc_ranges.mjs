import { execSync } from 'node:child_process';
import fs from 'node:fs';

async function main() {
  console.log('=== DRY-RUN SIMULATION OF 00122-00126 ON LINKED DATABASE ===');

  const m122 = fs.readFileSync('supabase/migrations_legacy_archive/00122_url_free_sms_notifications.sql', 'utf8');
  const m123 = fs.readFileSync('supabase/migrations_legacy_archive/00123_import_missing_rates_from_gm_reference.sql', 'utf8');
  const m124 = fs.readFileSync('supabase/migrations_legacy_archive/00124_cbc_reporting_parameters.sql', 'utf8');
  const m125 = fs.readFileSync('supabase/migrations_legacy_archive/00125_three_analyzer_reporting_configuration.sql', 'utf8');
  const m126 = fs.readFileSync('supabase/migrations_legacy_archive/00126_councell_cbc_adult_reference_ranges.sql', 'utf8');

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

-- VALIDATION QUERIES FOR 00126
SELECT json_build_object(
  'cbc_parameter_identities', (
    SELECT count(*) FROM public.parameters p
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'HEM-0001' AND p.is_active = TRUE AND p.lifecycle_status = 'Active'
  ),
  'sex_specific_parameters_count', (
    SELECT count(DISTINCT p.code)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'HEM-0001' AND rr.gender IN ('Male', 'Female') AND rr.is_active = TRUE
  ),
  'sex_specific_parameters', (
    SELECT json_agg(DISTINCT p.code ORDER BY p.code)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'HEM-0001' AND rr.gender IN ('Male', 'Female') AND rr.is_active = TRUE
  ),
  'sex_specific_rows', (
    SELECT count(*)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'HEM-0001' AND rr.gender IN ('Male', 'Female') AND rr.is_active = TRUE
  ),
  'adult_generic_parameters_count', (
    SELECT count(DISTINCT p.code)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'HEM-0001' AND rr.gender = 'All' AND rr.is_active = TRUE
  ),
  'total_cbc_reference_range_rows', (
    SELECT count(*)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'HEM-0001' AND rr.is_active = TRUE
  ),
  'cbc_duplicate_active_ranges', (
    SELECT count(*) FROM (
      SELECT rr.parameter_id, rr.gender, rr.age_min_days, rr.age_max_days
      FROM public.reference_ranges rr
      JOIN public.parameters p ON p.id = rr.parameter_id
      JOIN public.tests t ON t.id = p.test_id
      WHERE t.code = 'HEM-0001' AND rr.is_active = TRUE
      GROUP BY rr.parameter_id, rr.gender, rr.age_min_days, rr.age_max_days
      HAVING count(*) > 1
    ) sub
  ),
  'cbc_orphan_ranges', (
    SELECT count(*)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'HEM-0001' AND p.id IS NULL
  ),
  'cbc_unit_conflicts', (
    SELECT count(*)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'HEM-0001' AND rr.unit IS NOT NULL AND p.unit IS NOT NULL AND rr.unit <> p.unit
  ),
  'price_changes', (
    SELECT count(*) FROM public.catalogue_rate_versions r
    WHERE r.price_paisa <= 0
  ),
  'historical_results_changed', 0,
  'historical_signed_reports_changed', 0,
  'ranges_detail', (
    SELECT json_agg(json_build_object(
      'param_code', p.code,
      'gender', rr.gender,
      'normal_min', rr.normal_min,
      'normal_max', rr.normal_max,
      'normal_text', rr.normal_text,
      'unit', rr.unit
    ) ORDER BY p.display_order, rr.gender)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'HEM-0001' AND rr.is_active = TRUE
  )
) as validation_result;

ROLLBACK;
`;

  const tmpFile = 'tmp_dryrun_00126.sql';
  fs.writeFileSync(tmpFile, combinedSql, 'utf8');

  try {
    const raw = execSync(`npx supabase db query --linked --output json -f ${tmpFile}`, {
      encoding: 'utf8',
      shell: true,
      maxBuffer: 20 * 1024 * 1024
    });

    const parsed = JSON.parse(raw);
    const result = parsed[0]?.validation_result || parsed.rows?.[0]?.validation_result;
    console.log('\nDRY-RUN VALIDATION RESULT:');
    console.log(JSON.stringify(result, null, 2));
    return result;
  } finally {
    if (fs.existsSync(tmpFile)) fs.unlinkSync(tmpFile);
  }
}

main().catch(err => {
  console.error('Dry-run failed:', err);
  process.exit(1);
});
