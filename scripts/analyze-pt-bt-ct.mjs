import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync('scripts/inspect_pt_bt_ct_results.json', 'utf8'));

console.log('=== MATCHING TESTS IN DATABASE ===');
for (const t of data) {
  console.log(`\n--- [ID: ${t.id}] Code: "${t.code}", Name: "${t.name}", Short: "${t.short_name}" ---`);
  console.log(`  Dept: ${t.department}, Specimen: ${t.specimen_type}, Method: ${t.method}, Reporting: ${t.reporting_type}`);
  console.log(`  Active: ${t.is_active}, Billable: ${t.is_billable}, Rate paisa: ${JSON.stringify(t.rates)}`);
  console.log(`  Aliases: ${(t.aliases || []).map(a => a.alias_name).join(', ')}`);
  console.log(`  Parameters (${(t.parameters || []).length}):`);
  for (const p of t.parameters || []) {
    console.log(`    - [${p.id}] "${p.name}" (Code: ${p.code}, Type: ${p.value_type}, Unit: ${p.unit}, Formula: ${p.formula})`);
  }
  console.log(`  Ranges (${(t.ranges || []).length}):`);
  for (const r of t.ranges || []) {
    console.log(`    - Param [${r.parameter_id}] Gender: ${r.gender}, Min: ${r.normal_min}, Max: ${r.normal_max}, Text: "${r.textual_range}"`);
  }
}
