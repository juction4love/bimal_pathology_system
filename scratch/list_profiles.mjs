import fs from 'node:fs';

const data = JSON.parse(fs.readFileSync('scratch/deep_audit_result.json', 'utf8'));
const tests = data.tests_by_source_breakdown.filter(t => t.test_kind === 'Profile');

console.log('=== PROFILES IN CATALOGUE ===');
for (const p of tests) {
  console.log(`${p.code}: ${p.name} (Reporting: ${p.reporting_type}, Params: ${p.param_count}, Calc: ${p.calc_count}, Analyzer: ${JSON.stringify(p.analyzer_mappings)})`);
}
