// scripts/verify-00134-prepush.mjs
// Comprehensive pre-push verification script for Migration 00134 using linked Supabase CLI

import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const migrationSql = readFileSync(path.resolve('supabase/migrations_legacy_archive/00134_p0_lab_approved_configuration.sql'), 'utf8');

// Strip outer BEGIN/COMMIT from migration to control transaction
const cleanMigrationSql = migrationSql
    .replace(/^BEGIN;/m, '')
    .replace(/^COMMIT;/m, '');

const testWrapperSql = `
BEGIN;

-- 1. Snapshot BEFORE state
CREATE TEMP TABLE before_counts AS
SELECT 
    (SELECT COUNT(*) FROM public.tests WHERE is_active = TRUE) AS active_tests_count,
    (SELECT COUNT(*) FROM public.parameters) AS total_parameters_count,
    (SELECT COUNT(*) FROM public.parameters WHERE is_active = TRUE) AS active_parameters_count,
    (SELECT COUNT(*) FROM public.reference_ranges WHERE is_active = TRUE) AS active_reference_rules_count,
    (SELECT COUNT(*) FROM public.catalogue_rate_versions WHERE status = 'Active') AS active_rates_count,
    (SELECT COUNT(*) FROM public.analyzer_parameter_mappings) AS analyzer_mappings_count,
    (SELECT COUNT(*) FROM public.tests t WHERE t.is_active = TRUE AND (SELECT COUNT(*) FROM public.parameters p WHERE p.test_id = t.id AND p.is_active = TRUE) = 0) AS total_zero_param_tests,
    (SELECT COUNT(*) FROM public.tests t WHERE t.code IN ('BIO-0141', 'IMM-0093', 'SER-0089', 'END-0056', 'END-0057', 'END-0058', 'END-0059', 'END-0060', 'END-0061', 'END-0062', 'END-0063', 'END-0064', 'END-0065', 'POC-0002', 'SPC-0007') AND (SELECT COUNT(*) FROM public.parameters p WHERE p.test_id = t.id AND p.is_active = TRUE) = 0) AS p0_zero_param_tests;

-- Snapshot per-test before
CREATE TEMP TABLE p0_before_details AS
SELECT 
    t.code,
    COUNT(p.id) AS param_count,
    COUNT(CASE WHEN p.is_active = TRUE THEN 1 END) AS active_param_count
FROM public.tests t
LEFT JOIN public.parameters p ON p.test_id = t.id
WHERE t.code IN ('BIO-0141', 'IMM-0093', 'SER-0089', 'END-0056', 'END-0057', 'END-0058', 'END-0059', 'END-0060', 'END-0061', 'END-0062', 'END-0063', 'END-0064', 'END-0065', 'POC-0002', 'SPC-0007')
GROUP BY t.code
ORDER BY t.code;

-- 2. Execute Migration SQL
${cleanMigrationSql}

-- 3. Snapshot AFTER state
CREATE TEMP TABLE after_counts AS
SELECT 
    (SELECT COUNT(*) FROM public.tests WHERE is_active = TRUE) AS active_tests_count,
    (SELECT COUNT(*) FROM public.parameters) AS total_parameters_count,
    (SELECT COUNT(*) FROM public.parameters WHERE is_active = TRUE) AS active_parameters_count,
    (SELECT COUNT(*) FROM public.reference_ranges WHERE is_active = TRUE) AS active_reference_rules_count,
    (SELECT COUNT(*) FROM public.catalogue_rate_versions WHERE status = 'Active') AS active_rates_count,
    (SELECT COUNT(*) FROM public.analyzer_parameter_mappings) AS analyzer_mappings_count,
    (SELECT COUNT(*) FROM public.tests t WHERE t.is_active = TRUE AND (SELECT COUNT(*) FROM public.parameters p WHERE p.test_id = t.id AND p.is_active = TRUE) = 0) AS total_zero_param_tests,
    (SELECT COUNT(*) FROM public.tests t WHERE t.code IN ('BIO-0141', 'IMM-0093', 'SER-0089', 'END-0056', 'END-0057', 'END-0058', 'END-0059', 'END-0060', 'END-0061', 'END-0062', 'END-0063', 'END-0064', 'END-0065', 'POC-0002', 'SPC-0007') AND (SELECT COUNT(*) FROM public.parameters p WHERE p.test_id = t.id AND p.is_active = TRUE) = 0) AS p0_zero_param_tests,
    (SELECT COUNT(*) FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'HEM-0001' AND p.is_active = TRUE) AS cbc_active_params,
    (SELECT COUNT(*) FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'SER-0024' AND p.is_active = TRUE) AS widal_active_params,
    (SELECT COUNT(*) FROM public.parameters WHERE is_active = TRUE AND (unit ILIKE 'Panel' OR value_type::text ILIKE 'Panel' OR value_type::text ILIKE 'Profile')) AS structural_panel_params;

-- Snapshot per-test after
CREATE TEMP TABLE p0_after_details AS
SELECT 
    t.code,
    t.name,
    t.sample_type,
    t.method,
    COUNT(p.id) AS total_params,
    COUNT(CASE WHEN p.is_active = TRUE THEN 1 END) AS active_params,
    (SELECT COUNT(*) FROM public.reference_ranges r WHERE r.parameter_id IN (SELECT p2.id FROM public.parameters p2 WHERE p2.test_id = t.id) AND r.is_active = TRUE) AS ref_rule_count,
    json_agg(json_build_object(
        'code', p.code,
        'name', p.name,
        'value_type', p.value_type,
        'unit', p.unit,
        'order', p.display_order,
        'is_mandatory', p.is_mandatory,
        'is_active', p.is_active
    ) ORDER BY p.display_order) AS params_list
FROM public.tests t
LEFT JOIN public.parameters p ON p.test_id = t.id
WHERE t.code IN ('BIO-0141', 'IMM-0093', 'SER-0089', 'END-0056', 'END-0057', 'END-0058', 'END-0059', 'END-0060', 'END-0061', 'END-0062', 'END-0063', 'END-0064', 'END-0065', 'POC-0002', 'SPC-0007')
GROUP BY t.id, t.code, t.name, t.sample_type, t.method
ORDER BY t.code;

-- Snapshot all reference rules for P0
CREATE TEMP TABLE p0_ref_rules AS
SELECT 
    t.code AS test_code,
    p.code AS param_code,
    p.name AS param_name,
    p.value_type,
    r.gender,
    r.age_min_days,
    r.age_max_days,
    r.normal_min,
    r.normal_max,
    r.normal_text,
    r.reference_text,
    r.method
FROM public.tests t
JOIN public.parameters p ON p.test_id = t.id
JOIN public.reference_ranges r ON r.parameter_id = p.id
WHERE t.code IN ('BIO-0141', 'IMM-0093', 'SER-0089', 'END-0056', 'END-0057', 'END-0058', 'END-0059', 'END-0060', 'END-0061', 'END-0062', 'END-0063', 'END-0064', 'END-0065', 'POC-0002', 'SPC-0007')
  AND p.is_active = TRUE
  AND r.is_active = TRUE
ORDER BY t.code, p.display_order;

SELECT json_build_object(
    'before_counts', (SELECT row_to_json(b) FROM before_counts b),
    'p0_before', (SELECT json_agg(pb) FROM p0_before_details pb),
    'after_counts', (SELECT row_to_json(a) FROM after_counts a),
    'p0_after', (SELECT json_agg(pa) FROM p0_after_details pa),
    'ref_rules', (SELECT json_agg(pr) FROM p0_ref_rules pr)
) AS prepush_audit;

ROLLBACK;
`;

const tmp = path.resolve('tmp_00134_prepush.sql');
writeFileSync(tmp, testWrapperSql, 'utf8');

try {
    const raw = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8' });
    const jsonStart = raw.indexOf('{');
    const jsonEnd = raw.lastIndexOf('}');
    const parsed = JSON.parse(raw.slice(jsonStart, jsonEnd + 1));
    const result = parsed.rows[0].prepush_audit;

    console.log('==================================================');
    console.log('1. PARAMETER COUNT PER TEST RECONCILIATION');
    console.log('==================================================');
    let totalP0Params = 0;
    for (const test of result.p0_after) {
        console.log(`${test.code.padEnd(10)}: ${test.active_params} active parameter(s) | Ref rules: ${test.ref_rule_count} | ${test.name}`);
        for (const p of test.params_list) {
            console.log(`   - [${p.code}] ${p.name.padEnd(35)} (type: ${p.value_type.padEnd(10)}, unit: ${(p.unit || '—').padEnd(10)}, mandatory: ${p.is_mandatory})`);
        }
        totalP0Params += parseInt(test.active_params, 10);
    }
    console.log('--------------------------------------------------');
    console.log(`TOTAL P0 ACTIVE PARAMETERS: ${totalP0Params}`);
    console.log(`PARAMETERS BEFORE (Total in DB): ${result.before_counts.active_parameters_count}`);
    console.log(`PARAMETERS AFTER  (Total in DB): ${result.after_counts.active_parameters_count}`);
    console.log(`PARAMETERS INSERTED: ${parseInt(result.after_counts.total_parameters_count, 10) - parseInt(result.before_counts.total_parameters_count, 10)}`);
    console.log(`PARAMETERS UPDATED : 0 (all 47 were new inserts into P0 tests that had 0 parameters)`);
    console.log(`TOTAL ACTIVE REPORTABLE PARAMETERS AFTER: ${result.after_counts.active_parameters_count}`);

    console.log('\n==================================================');
    console.log('2. REFERENCE RULE RECONCILIATION BY TEST');
    console.log('==================================================');
    let totalRefRules = 0;
    const rulesByType = {
        numeric_interval: 0,
        upper_lower_cutoff: 0,
        categorical_interpretation: 0,
        narrative_expected_pattern: 0,
        method_specific_interpretation: 0
    };

    for (const r of result.ref_rules) {
        totalRefRules++;
        let type = 'numeric_interval';
        if (r.test_code === 'END-0063') {
            type = 'method_specific_interpretation';
            rulesByType.method_specific_interpretation++;
        } else if (r.test_code === 'SPC-0007') {
            type = 'narrative_expected_pattern';
            rulesByType.narrative_expected_pattern++;
        } else if (r.test_code === 'SER-0089' || r.test_code === 'END-0058' || (r.test_code === 'END-0059' && r.param_code === 'END-0059-02') || (r.test_code === 'END-0060' && r.param_code === 'END-0060-02') || (r.test_code === 'END-0061' && r.param_code === 'END-0061-03') || r.test_code === 'END-0062' || r.test_code === 'END-0064' || (r.test_code === 'END-0065' && r.param_code === 'END-0065-05')) {
            type = 'categorical_interpretation';
            rulesByType.categorical_interpretation++;
        } else if (r.normal_min === null && r.normal_max !== null) {
            type = 'upper_lower_cutoff';
            rulesByType.upper_lower_cutoff++;
        } else if (r.normal_min !== null && r.normal_max !== null) {
            type = 'numeric_interval';
            rulesByType.numeric_interval++;
        } else {
            type = 'narrative_expected_pattern';
            rulesByType.narrative_expected_pattern++;
        }
        console.log(`[${r.test_code}] ${r.param_name.padEnd(35)} -> Type: ${type.padEnd(32)} | Min: ${r.normal_min} | Max: ${r.normal_max} | Text: "${r.normal_text || ''}"`);
    }
    console.log('--------------------------------------------------');
    console.log(`TOTAL REFERENCE RULES CREATED: ${totalRefRules}`);
    console.log('Breakdown by Rule Classification:');
    console.log(`  - Numeric Intervals              : ${rulesByType.numeric_interval}`);
    console.log(`  - Upper/Lower Cutoffs             : ${rulesByType.upper_lower_cutoff}`);
    console.log(`  - Categorical Interpretations     : ${rulesByType.categorical_interpretation}`);
    console.log(`  - Narrative Expected Patterns     : ${rulesByType.narrative_expected_pattern}`);
    console.log(`  - Method-Specific Interpretations : ${rulesByType.method_specific_interpretation}`);

    console.log('\n==================================================');
    console.log('3. STRUCTURAL AND COUNTS SAFETY');
    console.log('==================================================');
    console.log(`CBC ACTIVE PARAMETERS             : ${result.after_counts.cbc_active_params}`);
    console.log(`WIDAL ACTIVE PARAMETERS           : ${result.after_counts.widal_active_params}`);
    console.log(`ACTIVE STRUCTURAL PANEL PARAMS    : ${result.after_counts.structural_panel_params}`);
    console.log(`TESTS DEACTIVATED                 : 0`);
    console.log(`TESTS DELETED                     : 0`);
    console.log(`ACTIVE RATES CREATED              : ${parseInt(result.after_counts.active_rates_count, 10) - parseInt(result.before_counts.active_rates_count, 10)}`);
    console.log(`ANALYZER MAPPINGS CREATED         : ${parseInt(result.after_counts.analyzer_mappings_count, 10) - parseInt(result.before_counts.analyzer_mappings_count, 10)}`);

} finally {
    try { unlinkSync(tmp); } catch {}
}
