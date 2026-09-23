import fs from 'node:fs';

const live = JSON.parse(fs.readFileSync('scripts/output/live_audit_dump.json', 'utf8'));

console.log('=== REFERENCE RANGE AUDIT (195 rows in Live) ===');
console.log(`Total Live Reference Ranges: ${live.reference_ranges.length}`);
console.log(`Active Live Reference Ranges: ${live.reference_ranges.filter(r => r.is_active).length}`);
console.log(`Inactive Live Reference Ranges: ${live.reference_ranges.filter(r => !r.is_active).length}`);

// Group by test_code and parameter_code
const liveRRs = live.reference_ranges;
const activeRRs = liveRRs.filter(r => r.is_active);
const inactiveRRs = liveRRs.filter(r => !r.is_active);

console.log('\n--- Inactive Reference Ranges in Live (9 rows) ---');
inactiveRRs.forEach((r, idx) => {
  console.log(`${idx + 1}. Test: ${r.test_code} (${r.test_name}) | Param: ${r.parameter_code} (${r.parameter_name})`);
  console.log(`   Gender: ${r.gender}, Age: ${r.age_min_days}-${r.age_max_days} days`);
  console.log(`   Range: normal_min=${r.normal_min}, normal_max=${r.normal_max}, normal_text="${r.normal_text}", unit="${r.unit}"`);
  console.log(`   Active: ${r.is_active}, Approved: ${r.is_approved}`);
});

console.log('\n--- Active Reference Ranges by Test Code ---');
const byTest = {};
activeRRs.forEach(r => {
  if (!byTest[r.test_code]) byTest[r.test_code] = [];
  byTest[r.test_code].push(r);
});

for (const [code, list] of Object.entries(byTest)) {
  console.log(`Test ${code}: ${list.length} active reference ranges`);
}
