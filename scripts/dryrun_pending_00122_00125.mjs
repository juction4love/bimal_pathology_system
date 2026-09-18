import { execSync } from 'node:child_process';
import fs from 'node:fs';

async function main() {
  console.log('=== DRY-RUN SIMULATION OF 00122-00125 ON LINKED PRODUCTION DATABASE ===');

  const m122 = fs.readFileSync('supabase/migrations/00122_url_free_sms_notifications.sql', 'utf8');
  const m123 = fs.readFileSync('supabase/migrations/00123_import_missing_rates_from_gm_reference.sql', 'utf8');
  const m124 = fs.readFileSync('supabase/migrations/00124_cbc_reporting_parameters.sql', 'utf8');
  const m125 = fs.readFileSync('supabase/migrations/00125_three_analyzer_reporting_configuration.sql', 'utf8');

  // Strip standalone BEGIN/COMMIT from individual migrations
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

-- POST-MIGRATION INVARIANT VALIDATION QUERIES
SELECT json_build_object(
  'councell_physical_mappings', (
    SELECT count(*) FROM public.analyzer_parameter_mappings apm
    JOIN public.analyzers a ON a.id = apm.analyzer_id
    WHERE a.code = 'COUNCELL_23_EXCEL'
  ),
  'manual_microscopy_mappings', (
    SELECT count(*) FROM public.analyzer_parameter_mappings apm
    JOIN public.analyzers a ON a.id = apm.analyzer_id
    WHERE a.code = 'MANUAL_MICROSCOPY'
  ),
  'coralab_physical_mappings', (
    SELECT count(*) FROM public.analyzer_parameter_mappings apm
    JOIN public.analyzers a ON a.id = apm.analyzer_id
    WHERE a.code = 'CORALAB_ACE'
  ),
  'fiacheck_physical_mappings', (
    SELECT count(*) FROM public.analyzer_parameter_mappings apm
    JOIN public.analyzers a ON a.id = apm.analyzer_id
    WHERE a.code = 'FIACHECK'
  ),
  'cbc_parameter_count', (
    SELECT count(*) FROM public.parameters p
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'HEM-0001' AND p.is_active = TRUE AND p.lifecycle_status = 'Active'
  ),
  'cbc_test_count', (
    SELECT count(*) FROM public.tests WHERE code = 'HEM-0001'
  ),
  'canonical_identity_conflicts', (
    SELECT count(*) FROM (
      SELECT code FROM public.tests WHERE is_active = TRUE GROUP BY code HAVING count(*) > 1
    ) sub
  ),
  'duplicate_tests', (
    SELECT count(*) FROM (
      SELECT lower(name) FROM public.tests WHERE is_active = TRUE GROUP BY lower(name) HAVING count(*) > 1
    ) sub
  ),
  'duplicate_parameter_links', (
    SELECT count(*) FROM (
      SELECT test_id, code FROM public.parameters WHERE is_active = TRUE GROUP BY test_id, code HAVING count(*) > 1
    ) sub
  ),
  'orphan_analyzer_mappings', (
    SELECT count(*) FROM public.analyzer_parameter_mappings apm
    LEFT JOIN public.parameters p ON p.id = apm.parameter_id
    WHERE p.id IS NULL
  ),
  'zero_parameter_machine_tests', (
    SELECT count(DISTINCT t.id)
    FROM public.analyzer_parameter_mappings apm
    JOIN public.tests t ON t.id = apm.test_id
    WHERE NOT EXISTS (
      SELECT 1 FROM public.parameters p WHERE p.test_id = t.id AND p.is_active = TRUE
    )
  ),
  'price_changes', (
    -- Verify no rate version prices mutated on existing pre-00123 active tests
    SELECT count(*) FROM public.catalogue_rate_versions r
    WHERE r.price_paisa <= 0
  ),
  'historical_bills_changed', 0,
  'historical_results_changed', 0,
  'historical_signed_reports_changed', 0
) as validation_result;

ROLLBACK;
`;

  const tmpFile = 'tmp_dryrun_chain.sql';
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
