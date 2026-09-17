import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync('scripts/audit_output.json', 'utf8'));
const tests = data.matched_tests;
const panels = data.panels;

console.log('=== MATCHED TESTS SUMMARY ===');
for (const t of tests) {
  console.log(`[${t.code}] ${t.name} (${t.short_name}) | Dept: ${t.department} | Specimen: ${t.sample_type || t.specimen_type} | Method: ${t.method} | Unit: ${t.unit} | Price: NPR ${t.price_paisa / 100} | Active: ${t.is_active} | Billable: ${t.billing_enabled} | Valid: ${t.validation_status}`);
}

console.log('\n=== PANELS SUMMARY ===');
for (const p of panels) {
  const compStr = (p.components || []).map(c => `${c.test_code}: ${c.test_name}`).join(', ');
  console.log(`[${p.panel_code}] ${p.panel_name} | Dept: ${p.department} | Price: NPR ${p.price_paisa / 100} | Active: ${p.is_active} | Billable: ${p.billing_enabled} | Components: [${compStr}]`);
}
