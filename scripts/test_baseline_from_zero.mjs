// scripts/test_baseline_from_zero.mjs
// Validates 00001_bimal_pathology_clean_baseline.sql from zero state in an isolated schema

import { readFileSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const baselineSql = readFileSync(path.resolve('supabase/migrations/00001_bimal_pathology_clean_baseline.sql'), 'utf8')
  .replace(/^BEGIN;/m, '')
  .replace(/^COMMIT;/m, '');

const testZeroSql = `
BEGIN;

-- Create an isolated clean schema to simulate a fresh empty database
DROP SCHEMA IF EXISTS fresh_baseline CASCADE;
CREATE SCHEMA fresh_baseline;

-- Set search path to fresh_baseline
SET search_path = fresh_baseline, extensions, pg_temp;

-- Alias public references in baseline to fresh_baseline
DO $$
BEGIN
    RAISE NOTICE 'Executing 00001_bimal_pathology_clean_baseline.sql into fresh isolated schema...';
END $$;

`;

// Let's modify baselineSql for isolated schema by replacing "public." with "fresh_baseline."
const isolatedBaselineSql = baselineSql.replace(/public\./g, 'fresh_baseline.');

const verificationSql = `
${testZeroSql}

${isolatedBaselineSql}

-- Now verify all tables, rows, constraints, and operational resolution in fresh_baseline
WITH test_direct_params AS (
  SELECT 
    p.test_id,
    COUNT(p.id) FILTER (
      WHERE p.is_active = TRUE 
        AND (p.lifecycle_status IS NULL OR p.lifecycle_status = 'Active')
        AND LOWER(COALESCE(p.unit, '')) <> 'panel'
        AND LOWER(COALESCE(p.value_type::text, '')) NOT IN ('panel', 'profile')
    ) AS direct_active_param_count,
    jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'code', p.code,
        'name', p.name,
        'unit', p.unit,
        'value_type', p.value_type::text,
        'display_order', p.display_order
      ) ORDER BY p.display_order
    ) FILTER (
      WHERE p.is_active = TRUE 
        AND (p.lifecycle_status IS NULL OR p.lifecycle_status = 'Active')
        AND LOWER(COALESCE(p.unit, '')) <> 'panel'
        AND LOWER(COALESCE(p.value_type::text, '')) NOT IN ('panel', 'profile')
    ) AS direct_params
  FROM fresh_baseline.parameters p
  GROUP BY p.test_id
),
panel_comps AS (
  SELECT 
    COALESCE(cpc.panel_test_id, cpc.panel_id) AS panel_id,
    COUNT(cpc.id) AS component_count,
    jsonb_agg(
      jsonb_build_object(
        'component_test_id', cpc.component_test_id,
        'component_parameter_id', cpc.component_parameter_id,
        'display_order', cpc.display_order
      ) ORDER BY cpc.display_order
    ) AS components
  FROM fresh_baseline.catalogue_panel_components cpc
  GROUP BY COALESCE(cpc.panel_test_id, cpc.panel_id)
),
all_tests AS (
  SELECT 
    jsonb_build_object(
      'test_id', t.id,
      'test_code', t.code,
      'test_name', t.name,
      'category', t.category,
      'department', t.department,
      'direct_param_count', COALESCE(tdp.direct_active_param_count, 0),
      'component_count', COALESCE(pc.component_count, 0),
      'direct_params', tdp.direct_params,
      'components', pc.components
    ) AS test_json
  FROM fresh_baseline.tests t
  LEFT JOIN test_direct_params tdp ON tdp.test_id = t.id
  LEFT JOIN panel_comps pc ON pc.panel_id = t.id
  WHERE t.is_active = TRUE
  ORDER BY t.code
)
SELECT jsonb_build_object(
  'tests_count', (SELECT COUNT(*) FROM fresh_baseline.tests WHERE is_active = TRUE),
  'parameters_count', (SELECT COUNT(*) FROM fresh_baseline.parameters WHERE is_active = TRUE),
  'reference_ranges_count', (SELECT COUNT(*) FROM fresh_baseline.reference_ranges),
  'panel_components_count', (SELECT COUNT(*) FROM fresh_baseline.catalogue_panel_components),
  'rate_versions_count', (SELECT COUNT(*) FROM fresh_baseline.catalogue_rate_versions WHERE status = 'Active'),
  'analyzers_count', (SELECT COUNT(*) FROM fresh_baseline.analyzers),
  'analyzer_mappings_count', (SELECT COUNT(*) FROM fresh_baseline.analyzer_parameter_mappings),
  'patients_count', (SELECT COUNT(*) FROM fresh_baseline.patients),
  'bills_count', (SELECT COUNT(*) FROM fresh_baseline.bills),
  'orders_count', (SELECT COUNT(*) FROM fresh_baseline.clinical_orders),
  'results_count', (SELECT COUNT(*) FROM fresh_baseline.test_results),
  'reports_count', (SELECT COUNT(*) FROM fresh_baseline.diagnostic_reports),
  'tests', (SELECT jsonb_agg(test_json) FROM all_tests)
) AS baseline_verification;

ROLLBACK;
`;

const tmp = path.resolve('tmp_test_zero_baseline.sql');
writeFileSync(tmp, verificationSql, 'utf8');

console.log('Running isolated replay verification of 00001_bimal_pathology_clean_baseline.sql...');
const raw = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8', maxBuffer: 100 * 1024 * 1024 });
const jsonStart = raw.indexOf('{');
const jsonEnd = raw.lastIndexOf('}');
const parsed = JSON.parse(raw.slice(jsonStart, jsonEnd + 1));
const data = (parsed.rows || [])[0]?.baseline_verification;

if (!data) {
  throw new Error('Baseline verification failed to return data.');
}

console.log('================ ISOLATED FRESH BASELINE VERIFICATION ================');
console.log(`Tests (Active): ${data.tests_count}`);
console.log(`Parameters: ${data.parameters_count}`);
console.log(`Reference Ranges: ${data.reference_ranges_count}`);
console.log(`Panel Components: ${data.panel_components_count}`);
console.log(`Active Rate Versions: ${data.rate_versions_count}`);
console.log(`Analyzers: ${data.analyzers_count}`);
console.log(`Analyzer Channel Mappings: ${data.analyzer_mappings_count}`);
console.log('\n--- Transactional Row Counts (Must be 0) ---');
console.log(`Patients: ${data.patients_count}`);
console.log(`Bills: ${data.bills_count}`);
console.log(`Orders: ${data.orders_count}`);
console.log(`Results: ${data.results_count}`);
console.log(`Diagnostic Reports: ${data.reports_count}`);

const tests = data.tests || [];
const testsById = new Map(tests.map(t => [t.test_id, t]));
const testsByCode = new Map(tests.map(t => [t.test_code, t]));

function resolveLeafCount(t) {
  if (t.direct_param_count > 0) return t.direct_param_count;
  if (t.components && t.components.length > 0) {
    let sum = 0;
    for (const c of t.components) {
      if (c.component_parameter_id) sum += 1;
      else if (c.component_test_id) {
        const child = testsById.get(c.component_test_id);
        sum += (child?.direct_param_count || 0);
      }
    }
    return sum;
  }
  return 0;
}

const hardAssertions = {
  'PRO-0001': { name: 'Liver Function Test (LFT)', expected: 11 },
  'PRO-0002': { name: 'Renal Function Test (RFT/KFT)', expected: 4 },
  'PRO-0003': { name: 'Lipid Profile', expected: 5 },
  'HEM-0001': { name: 'Complete Blood Count (CBC)', expected: 24 },
  'CLP-0001': { name: 'Urine Routine Examination', expected: 14 },
  'SER-0024': { name: 'Widal Test', expected: 4 },
  'POC-0002': { name: 'Venous Blood Gas (VBG)', expected: 7 }
};

console.log('\n================ HARD PROFILE ASSERTIONS (FROM FRESH BASELINE) ================');
let allHardPass = true;
for (const [code, spec] of Object.entries(hardAssertions)) {
  const t = testsByCode.get(code);
  const resolvedCount = t ? resolveLeafCount(t) : 0;
  const pass = resolvedCount === spec.expected;
  if (!pass) allHardPass = false;
  console.log(`  [${pass ? 'PASS' : 'FAIL'}] ${code} (${spec.name}): expected=${spec.expected}, resolved=${resolvedCount}`);
}

const unconfiguredTests = tests.filter(t => resolveLeafCount(t) === 0);
console.log(`\nUNRESOLVED_REPORTABLE_TESTS: ${unconfiguredTests.length}`);
console.log(`ALL_HARD_ASSERTIONS_PASSED: ${allHardPass}`);
