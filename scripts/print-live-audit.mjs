import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync('scripts/live_audit_results.json', 'utf8'));

console.log('=== LIVE PRODUCTION COUNTS ===');
console.log(JSON.stringify(data.counts, null, 2));

console.log('\n=== LIVE DUPLICATES ===');
console.log(JSON.stringify(data.duplicates, null, 2));

console.log('\n=== LIVE ORPHANS ===');
console.log(JSON.stringify(data.orphans, null, 2));

console.log('\n=== RECENT TESTS AUDIT (Count: ' + data.recent_tests?.length + ') ===');
for (const t of data.recent_tests) {
  console.log(`[${t.code}] "${t.name}" (${t.test_type}) | NPR ${t.price_npr} | Valid: ${t.validation_status} | RepEnabled: ${t.clinical_reporting_enabled} | Active: ${t.is_active} | Billable: ${t.billing_enabled} | Specimen: ${t.specimen_type || t.sample_type} | Method: ${t.method}`);
}

console.log('\n=== PANELS AUDIT ===');
for (const p of data.panels_audit) {
  const comps = (p.components || []).map(c => `${c.code}: ${c.name}`).join(' + ');
  console.log(`[${p.panel_code}] "${p.panel_name}" | NPR ${p.price_npr} | Valid: ${p.validation_status} | RepEnabled: ${p.reporting_enabled} | Comps: [${comps}]`);
}
