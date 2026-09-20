import fs from 'node:fs';

const data = JSON.parse(fs.readFileSync('scratch/deep_audit_result.json', 'utf8'));
const tests = data.tests_by_source_breakdown.filter(t => t.code.startsWith('PRO-') || t.name.toLowerCase().includes('profile') || t.name.toLowerCase().includes('panel'));

console.log('=== ALL PRO- OR PROFILE TESTS ===');
for (const p of tests) {
  console.log(`${p.code}: ${p.name} (Kind: ${p.test_kind}, Params: ${p.param_count}, Calc: ${p.calc_count}, Analyzers: ${JSON.stringify(p.analyzer_mappings)})`);
}
