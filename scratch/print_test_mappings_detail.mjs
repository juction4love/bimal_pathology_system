import fs from 'node:fs';

const data = JSON.parse(fs.readFileSync('scratch/deep_audit_result.json', 'utf8'));
const mappings = data.all_mappings;

console.log('=== ANALYZER PARAMETER MAPPINGS BY TEST ===');
const testMappings = {};
for (const m of mappings) {
  if (!testMappings[m.test_code]) {
    testMappings[m.test_code] = {
      test_code: m.test_code,
      test_name: m.test_name,
      test_kind: m.test_kind,
      analyzers: new Set(),
      params: []
    };
  }
  testMappings[m.test_code].analyzers.add(m.analyzer_name);
  testMappings[m.test_code].params.push({
    param_code: m.param_code,
    param_name: m.param_name,
    analyzer: m.analyzer_name,
    channel: m.channel_code
  });
}

for (const [code, info] of Object.entries(testMappings)) {
  console.log(`${code} [${info.test_name}] (${info.test_kind}): Analyzers -> [${Array.from(info.analyzers).join(', ')}] (${info.params.length} params mapped)`);
}
