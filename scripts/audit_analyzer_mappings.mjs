import fs from 'node:fs';

const live = JSON.parse(fs.readFileSync('scripts/output/live_audit_dump.json', 'utf8'));

console.log('=== ANALYZER MAPPINGS AUDIT ===');
console.log(`Live Analyzer Mappings Count: ${live.analyzer_mappings.length}`);

const calculatedTests = [
  { test: 'BIO-0019', param: 'BIO-0019', name: 'Indirect Bilirubin' },
  { test: 'BIO-0015', param: 'BIO-0015', name: 'Globulin' },
  { test: 'BIO-0016', param: 'BIO-0016', name: 'A/G Ratio' },
  { test: 'BIO-0031', param: 'BIO-0031', name: 'LDL Calculated' },
  { test: 'BIO-0032', param: 'BIO-0032', name: 'VLDL' },
  { test: 'BIO-0009', param: 'BIO-0009', name: 'BUN' }
];

console.log('\n--- Checking Hard Rule for Calculated Parameters ---');
for (const item of calculatedTests) {
  const matchingLive = live.analyzer_mappings.filter(m => m.test_code === item.test || m.parameter_code === item.param || m.channel_code === item.param);
  console.log(`[${item.name} (${item.test})]: Physical Mappings in Live = ${matchingLive.length} (Expected 0)`);
  if (matchingLive.length > 0) {
    matchingLive.forEach(m => console.log(`   -> Analyzer: ${m.analyzer_code}, Channel: ${m.channel_code}`));
  }
}

console.log('\n--- Complete List of Live Analyzer Mappings (24) ---');
live.analyzer_mappings.forEach((m, idx) => {
  console.log(`${idx + 1}. Analyzer: ${m.analyzer_code} | Channel: ${m.channel_code} | Test: ${m.test_code} | Param: ${m.parameter_code} | Name: "${m.channel_name || m.parameter_name}" | Type: ${m.measurement_type} | Method: ${m.analytical_method}`);
});
