// scripts/final-semantic-audit.mjs
import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';
import assert from 'node:assert/strict';

function runSql(sql) {
  const tmp = path.resolve('tmp_final_audit.sql');
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

console.log('================================================================');
console.log('=== BIMAL PATHOLOGY LIS: FINAL SEMANTIC CLINICAL AUDIT ===');
console.log('================================================================\n');

const auditSql = `
  SELECT json_build_object(
    'total_tests', (SELECT count(*)::int FROM public.tests),
    'invalid_department_count', (SELECT count(*)::int FROM public.tests WHERE department IS NULL OR btrim(department) = ''),
    'invalid_result_type_count', (SELECT count(*)::int FROM public.tests WHERE report_data_type IS NULL OR btrim(report_data_type) = ''),
    'invalid_specimen_count', (SELECT count(*)::int FROM public.tests WHERE reporting_type <> 'NoReporting' AND (sample_type IS NULL OR btrim(sample_type) = '')),
    'invalid_container_count', (SELECT count(*)::int FROM public.tests WHERE collection_required AND (container IS NULL OR btrim(container) = '')),
    'invalid_unit_count', (SELECT count(*)::int FROM public.tests WHERE report_data_type = 'Numeric' AND (unit IS NULL OR btrim(unit) = '')),
    'orphaned_panel_components', (
      SELECT count(*)::int
      FROM public.catalogue_panel_components c
      WHERE NOT EXISTS (SELECT 1 FROM public.tests t WHERE t.id = c.panel_id)
         OR NOT EXISTS (SELECT 1 FROM public.tests t WHERE t.id = c.component_test_id)
    ),
    'orphaned_aliases', (
      SELECT count(*)::int
      FROM public.test_aliases a
      WHERE NOT EXISTS (SELECT 1 FROM public.tests t WHERE t.id = a.test_id)
    ),
    'distinct_departments', (SELECT count(DISTINCT department)::int FROM public.tests),
    'distinct_result_types', (SELECT count(DISTINCT report_data_type)::int FROM public.tests),
    'distinct_specimens', (SELECT count(DISTINCT sample_type)::int FROM public.tests WHERE sample_type IS NOT NULL AND btrim(sample_type) <> ''),
    'distinct_containers', (SELECT count(DISTINCT container)::int FROM public.tests WHERE container IS NOT NULL AND btrim(container) <> ''),
    'distinct_units', (SELECT count(DISTINCT unit)::int FROM public.tests WHERE unit IS NOT NULL AND btrim(unit) <> ''),
    'distinct_methods', (SELECT count(DISTINCT method)::int FROM public.tests WHERE method IS NOT NULL AND btrim(method) <> ''),
    'total_aliases', (SELECT count(*)::int FROM public.test_aliases),
    'total_panels', (SELECT count(*)::int FROM public.tests WHERE test_type = 'Panel'),
    'active_test_count', (SELECT count(*)::int FROM public.tests WHERE is_active = TRUE)
  ) as audit;
`;

const res = runSql(auditSql);
const a = res?.rows?.[0]?.audit || res?.[0]?.audit;

console.log('1. Tests & Field Resolutions:');
console.log(`   - Total tests in catalogue          : ${a.total_tests}`);
console.log(`   - Invalid / missing department      : ${a.invalid_department_count}`);
console.log(`   - Invalid / missing result type     : ${a.invalid_result_type_count}`);
console.log(`   - Invalid specimen where reportable : ${a.invalid_specimen_count}`);
console.log(`   - Invalid container where collection: ${a.invalid_container_count}`);
console.log(`   - Invalid unit where Numeric        : ${a.invalid_unit_count}`);
console.log(`   - Orphaned panel components         : ${a.orphaned_panel_components}`);
console.log(`   - Orphaned aliases                  : ${a.orphaned_aliases}`);
console.log(`   - ACTIVE tests (must remain 0)      : ${a.active_test_count}`);

assert.equal(a.total_tests, 1122, 'Total tests must be 1,122');
assert.equal(a.invalid_department_count, 0, 'No tests should have invalid department');
assert.equal(a.invalid_result_type_count, 0, 'No tests should have invalid result type');
assert.equal(a.invalid_specimen_count, 0, 'No reportable tests should have missing specimen');
assert.equal(a.invalid_container_count, 0, 'No collection-required tests should have missing container');
assert.equal(a.invalid_unit_count, 0, 'No numeric tests should have missing unit');
assert.equal(a.orphaned_panel_components, 0, 'No orphaned panel components');
assert.equal(a.orphaned_aliases, 0, 'No orphaned aliases');
assert.equal(a.active_test_count, 0, 'No tests must be active');

console.log('\n2. Normalized Semantic Metadata Counts:');
console.log(`   - Canonical Departments : ${a.distinct_departments}`);
console.log(`   - Result Types          : ${a.distinct_result_types}`);
console.log(`   - Canonical Specimens   : ${a.distinct_specimens}`);
console.log(`   - Canonical Containers  : ${a.distinct_containers}`);
console.log(`   - Canonical Units       : ${a.distinct_units}`);
console.log(`   - Analytical Methods    : ${a.distinct_methods}`);
console.log(`   - Indexed Aliases       : ${a.total_aliases}`);
console.log(`   - Panels / Profiles     : ${a.total_panels}`);

console.log('\n================================================================');
console.log('CATALOGUE SEMANTIC AUDIT PASS');
console.log('================================================================');
