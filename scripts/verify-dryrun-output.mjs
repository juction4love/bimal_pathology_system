import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync('scripts/dryrun_00114_output.json', 'utf8'));

console.log('=== VERIFICATION OF ALL 40 REPRICED/ADDED ITEMS IN 00114 DRY-RUN ===');
for (const t of data.audited_tests) {
  console.log(`[${t.code}] "${t.name}" | Type: ${t.test_type} | Rate: NPR ${t.price_npr} (${t.price_paisa} paisa) | Active: ${t.is_active} | Billable: ${t.billing_enabled} | Valid: ${t.validation_status} | ReportEnabled: ${t.clinical_reporting_enabled}`);
}

console.log('\n=== PANELS VERIFICATION ===');
for (const p of data.audited_panels) {
  const compStr = p.components.map(c => `${c.component_code} (${c.component_name})`).join(' + ');
  console.log(`[${p.panel_code}] "${p.panel_name}" | Price: NPR ${p.price_npr} | Valid: ${p.validation_status} | Components: [${compStr}]`);
}
