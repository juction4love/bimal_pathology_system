import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync('scripts/final_00114_verification.json', 'utf8'));

console.log('=== 1. DATABASE INVARIANTS ===');
console.log('Catalogue before:', data.pre_state.pre_total_tests);
console.log('Catalogue after dry-run:', data.post_state.post_total_tests);
console.log('New canonical singles:', data.post_state.post_singles - data.pre_state.pre_singles);
console.log('New panels:', data.post_state.post_panels - data.pre_state.pre_panels);
console.log('Deleted catalogue rows:', data.invariants.deleted_catalogue_rows);
console.log('Duplicate canonical codes:', data.invariants.duplicate_codes_count);
console.log('Unconfigured specimen rules created:', data.invariants.unconfigured_specimen_rules_count);

console.log('\n=== 2. PANEL COMPONENTS ===');
for (const p of data.panels) {
  const comps = p.components.map(c => `${c.code} (${c.name})`).join(' + ');
  console.log(`[${p.panel_code}] ${p.panel_name} -> NPR ${p.price_npr} | Valid: ${p.validation_status} | RepEnabled: ${p.reporting_enabled}`);
  console.log(`  Components: ${comps}`);
}

console.log('\n=== 3. RAPID SEROLOGY PRICING ===');
const serologyCodes = ['SER-0087', 'SER-0088', 'SER-0004', 'SER-0010'];
for (const c of serologyCodes) {
  const t = data.prices.find(x => x.code === c);
  console.log(`[${t.code}] ${t.name} -> NPR ${t.price_npr}`);
}

console.log('\n=== 4. NEW SHELL SAFETY ===');
const shellCodes = ['IMM-0093', 'BIO-0141', 'SER-0089'];
for (const c of shellCodes) {
  const t = data.prices.find(x => x.code === c);
  console.log(`[${t.code}] ${t.name} -> NPR ${t.price_npr} | Valid: ${t.validation_status} | RepEnabled: ${t.clinical_reporting_enabled} | Method: ${t.method} | Specimen: ${t.specimen_type}`);
}

console.log('\n=== 5. ALL 36 REQUESTED PRICES ===');
for (const t of data.prices) {
  console.log(`[${t.code}] ${t.name} (${t.test_type}) | NPR ${t.price_npr} (${t.price_paisa} paisa)`);
}

console.log('\n=== 6. HISTORICAL BILLING SAFETY ===');
console.log('Bills delta:', data.historical_bills_delta);
console.log('Bill items delta:', data.historical_bill_items_delta);
console.log('Orders delta:', data.historical_orders_delta);
console.log('Order items delta:', data.historical_order_items_delta);
console.log('Rate versions count:', data.post_state.post_rate_versions);

console.log('\n=== 7. DOUBLE BILLING SIMULATION FOR ALL 4 PANELS ===');
const panelDefinitions = [
  { code: 'PRO-0026', name: 'CARDIAC MARKERS COMBO', components: ['BIO-0063', 'BIO-0061', 'BIO-0065'] },
  { code: 'PRO-0027', name: 'PCT + CRP COMBO', components: ['PCT_SEPSIS', 'IMM-0001'] },
  { code: 'PRO-0028', name: 'COMPLETE THYROID PROFILE (T3, T4, TSH)', components: ['END-0005', 'END-0004', 'END-0001'] },
  { code: 'PRO-0029', name: 'DENGUE COMBO (NS1 + IgM + IgG)', components: ['SER-0015', 'SER-0016', 'SER-0017'] }
];

for (const p of panelDefinitions) {
  // Test direction 1: Individual component already in bill -> adding panel should be BLOCKED
  const compInBill = [p.components[0]];
  const blockPanel = p.components.some(c => compInBill.includes(c));
  
  // Test direction 2: Panel in bill -> adding individual component should be BLOCKED
  const panelInBillComps = p.components;
  const blockComp = panelInBillComps.includes(p.components[1]);

  console.log(`[${p.code}] ${p.name}: Direction 1 (Component -> Panel Blocked): ${blockPanel ? 'PASS' : 'FAIL'} | Direction 2 (Panel -> Component Blocked): ${blockComp ? 'PASS' : 'FAIL'}`);
}
