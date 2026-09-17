import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync('scripts/audit_output.json', 'utf8'));
const tests = data.matched_tests;

function findTests(kw) {
  const lower = kw.toLowerCase();
  return tests.filter(t => 
    t.code.toLowerCase().includes(lower) || 
    t.name.toLowerCase().includes(lower) || 
    (t.short_name && t.short_name.toLowerCase().includes(lower))
  );
}

const queries = [
  // A. Cardiac
  'Troponin', 'cTnI', 'cTnT', 'CK-MB', 'Myoglobin', 'proBNP', 'BNP', 'Dimer',
  // B. Inflammation
  'CRP', 'Procalcitonin', 'PCT', 'Interleukin', 'IL-6', 'Ferritin',
  // C. Diabetes & Renal
  'HbA1c', 'Glycated', 'Microalbumin', 'mAlb', 'Cystatin',
  // D. Thyroid & Hormones
  'TSH', 'Free T3', 'Free T4', 'Total T3', 'Total T4', 'Triiodo', 'Thyroxine', 'HCG', 'Testosterone', 'LH', 'FSH', 'Prolactin', 'AMH', 'Mullerian', 'Vitamin D',
  // E. Infectious & Fever
  'Scrub', 'Dengue', 'HCV', 'HBsAg', 'Pylori',
  // F. Rheumatism & Tumor Markers
  'CCP', 'ASO', 'RF', 'Rheumatoid', 'IgE', 'PSA', 'AFP', 'CEA'
];

console.log('=== SEARCH RESULTS ===');
for (const q of queries) {
  const res = findTests(q);
  console.log(`\n--- Query: "${q}" (Count: ${res.length}) ---`);
  for (const t of res) {
    console.log(`[${t.code}] ${t.name} (${t.short_name}) | Dept: ${t.department} | Spec: ${t.sample_type || t.specimen_type} | Method: ${t.method} | Unit: ${t.unit} | Price: NPR ${t.price_paisa / 100} | Active: ${t.is_active} | Billable: ${t.billing_enabled} | Valid: ${t.validation_status} | Data: ${t.report_data_type}`);
  }
}
