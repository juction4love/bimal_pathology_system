// scripts/verify-00134-dryrun.mjs
// Dry-run verification of migration 00134 with rollback

import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const migrationSql = readFileSync(path.resolve('supabase/migrations/00134_p0_lab_approved_configuration.sql'), 'utf8');

// Strip outer BEGIN/COMMIT from migration to control transaction
const cleanMigrationSql = migrationSql
    .replace(/^BEGIN;/m, '')
    .replace(/^COMMIT;/m, '');

const testWrapperSql = `
BEGIN;

-- 1. Snapshot BEFORE state
CREATE TEMP TABLE before_state AS
SELECT 
    (SELECT COUNT(*) FROM public.tests WHERE is_active = TRUE) AS active_tests_count,
    (SELECT COUNT(*) FROM public.catalogue_rate_versions WHERE status = 'Active') AS active_rates_count,
    (SELECT COUNT(*) FROM public.analyzer_parameter_mappings) AS analyzer_mappings_count,
    (SELECT COUNT(*) FROM public.tests t WHERE t.is_active = TRUE AND (SELECT COUNT(*) FROM public.parameters p WHERE p.test_id = t.id AND p.is_active = TRUE) = 0) AS total_zero_param_tests,
    (SELECT COUNT(*) FROM public.tests t WHERE t.code IN ('BIO-0141', 'IMM-0093', 'SER-0089', 'END-0056', 'END-0057', 'END-0058', 'END-0059', 'END-0060', 'END-0061', 'END-0062', 'END-0063', 'END-0064', 'END-0065', 'POC-0002', 'SPC-0007') AND (SELECT COUNT(*) FROM public.parameters p WHERE p.test_id = t.id AND p.is_active = TRUE) = 0) AS p0_zero_param_tests;

-- 2. Execute Migration SQL
${cleanMigrationSql}

-- 3. Snapshot AFTER state
CREATE TEMP TABLE after_state AS
SELECT 
    (SELECT COUNT(*) FROM public.tests WHERE is_active = TRUE) AS active_tests_count,
    (SELECT COUNT(*) FROM public.catalogue_rate_versions WHERE status = 'Active') AS active_rates_count,
    (SELECT COUNT(*) FROM public.analyzer_parameter_mappings) AS analyzer_mappings_count,
    (SELECT COUNT(*) FROM public.tests t WHERE t.code IN ('BIO-0141', 'IMM-0093', 'SER-0089', 'END-0056', 'END-0057', 'END-0058', 'END-0059', 'END-0060', 'END-0061', 'END-0062', 'END-0063', 'END-0064', 'END-0065', 'POC-0002', 'SPC-0007') AND (SELECT COUNT(*) FROM public.parameters p WHERE p.test_id = t.id AND p.is_active = TRUE) = 0) AS p0_zero_param_tests,
    (SELECT COUNT(*) FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'HEM-0001' AND p.is_active = TRUE) AS cbc_active_params,
    (SELECT COUNT(*) FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'SER-0024' AND p.is_active = TRUE) AS widal_active_params,
    (SELECT COUNT(*) FROM public.parameters WHERE is_active = TRUE AND (unit ILIKE 'Panel' OR value_type::text ILIKE 'Panel' OR value_type::text ILIKE 'Profile')) AS structural_panel_params;

-- 4. Gather 15 configured P0 tests details
CREATE TEMP TABLE p0_after_details AS
SELECT 
    t.code,
    t.name,
    t.sample_type AS specimen,
    t.method,
    COUNT(p.id) AS param_count,
    json_agg(json_build_object('param_code', p.code, 'param_name', p.name, 'value_type', p.value_type, 'unit', p.unit)) AS parameters
FROM public.tests t
LEFT JOIN public.parameters p ON p.test_id = t.id AND p.is_active = TRUE
WHERE t.code IN ('BIO-0141', 'IMM-0093', 'SER-0089', 'END-0056', 'END-0057', 'END-0058', 'END-0059', 'END-0060', 'END-0061', 'END-0062', 'END-0063', 'END-0064', 'END-0065', 'POC-0002', 'SPC-0007')
GROUP BY t.id, t.code, t.name, t.sample_type, t.method
ORDER BY t.code;

SELECT json_build_object(
    'before', (SELECT row_to_json(b) FROM before_state b),
    'after', (SELECT row_to_json(a) FROM after_state a),
    'p0_tests', (SELECT json_agg(d) FROM p0_after_details d)
) AS dry_run_result;

ROLLBACK;
`;

const tmp = path.resolve('tmp_00134_dryrun.sql');
writeFileSync(tmp, testWrapperSql, 'utf8');

try {
    const raw = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8' });
    const jsonStart = raw.indexOf('{');
    const jsonEnd = raw.lastIndexOf('}');
    const parsed = JSON.parse(raw.slice(jsonStart, jsonEnd + 1));
    console.log(JSON.stringify(parsed.rows[0].dry_run_result, null, 2));
} finally {
    try { unlinkSync(tmp); } catch {}
}
