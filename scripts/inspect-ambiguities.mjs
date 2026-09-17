import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync('scripts/full_catalogue_dump.json', 'utf8'));
const tests = data.tests;
const testMap = new Map(tests.map(t => [t.code, t]));

console.log('=== POINT 1: CRP & PCT INVESTIGATION ===');
const crpTests = tests.filter(t => t.name.toLowerCase().includes('crp') || t.code.includes('CRP') || (t.short_name && t.short_name.toLowerCase().includes('crp')));
for (const t of crpTests) {
  console.log(`[${t.code}] "${t.name}" | Dept: ${t.department} | Method: ${t.method} | Specimen: ${t.sample_type || t.specimen_type} | Unit: ${t.unit} | Price: NPR ${t.price_paisa / 100} | Valid: ${t.validation_status} | Active: ${t.is_active} | Billable: ${t.billing_enabled}`);
}

const pctTests = tests.filter(t => t.name.toLowerCase().includes('procalcitonin') || t.code.includes('PCT'));
for (const t of pctTests) {
  console.log(`[${t.code}] "${t.name}" | Dept: ${t.department} | Method: ${t.method} | Specimen: ${t.sample_type || t.specimen_type} | Unit: ${t.unit} | Price: NPR ${t.price_paisa / 100} | Valid: ${t.validation_status} | Active: ${t.is_active} | Billable: ${t.billing_enabled}`);
}

console.log('\n=== POINT 2: SCRUB TYPHUS INVESTIGATION ===');
const scrubTests = tests.filter(t => t.name.toLowerCase().includes('scrub') || t.code.toLowerCase().includes('scrub') || (t.notes && t.notes.toLowerCase().includes('scrub')));
for (const t of scrubTests) {
  console.log(`[${t.code}] "${t.name}" | Dept: ${t.department} | Method: ${t.method} | Specimen: ${t.sample_type || t.specimen_type} | Unit: ${t.unit} | Price: NPR ${t.price_paisa / 100} | Valid: ${t.validation_status} | Active: ${t.is_active} | Billable: ${t.billing_enabled} | Notes: ${t.notes}`);
}

console.log('\n=== POINT 3: TROPONIN T INVESTIGATION ===');
const tropTests = tests.filter(t => t.name.toLowerCase().includes('troponin') || t.code.toLowerCase().includes('trop') || (t.short_name && t.short_name.toLowerCase().includes('ctn')));
for (const t of tropTests) {
  console.log(`[${t.code}] "${t.name}" | Dept: ${t.department} | Method: ${t.method} | Specimen: ${t.sample_type || t.specimen_type} | Unit: ${t.unit} | Price: NPR ${t.price_paisa / 100} | Valid: ${t.validation_status} | Active: ${t.is_active} | Billable: ${t.billing_enabled}`);
}

console.log('\n=== POINT 4: CK-MB INVESTIGATION ===');
const ckmbTests = tests.filter(t => t.name.toLowerCase().includes('ck-mb') || t.code.toLowerCase().includes('ck-mb') || t.name.toLowerCase().includes('creatine kinase'));
for (const t of ckmbTests) {
  console.log(`[${t.code}] "${t.name}" | Dept: ${t.department} | Method: ${t.method} | Specimen: ${t.sample_type || t.specimen_type} | Unit: ${t.unit} | Price: NPR ${t.price_paisa / 100} | Valid: ${t.validation_status} | Active: ${t.is_active} | Billable: ${t.billing_enabled}`);
}

console.log('\n=== POINT 5: THYROID PROFILE INVESTIGATION ===');
const thyroidCodes = ['END-0001', 'END-0002', 'END-0003', 'END-0004', 'END-0005', 'PRO-0004'];
for (const c of thyroidCodes) {
  const t = testMap.get(c);
  if (t) {
    console.log(`[${t.code}] "${t.name}" | Dept: ${t.department} | Method: ${t.method} | Specimen: ${t.sample_type || t.specimen_type} | Unit: ${t.unit} | Price: NPR ${t.price_paisa / 100} | Valid: ${t.validation_status} | Active: ${t.is_active} | Billable: ${t.billing_enabled}`);
  }
}

console.log('\n=== POINT 6: DENGUE INVESTIGATION ===');
const dengueTests = tests.filter(t => t.name.toLowerCase().includes('dengue') || t.code.toLowerCase().includes('dengue'));
for (const t of dengueTests) {
  console.log(`[${t.code}] "${t.name}" | Dept: ${t.department} | Method: ${t.method} | Specimen: ${t.sample_type || t.specimen_type} | Unit: ${t.unit} | Price: NPR ${t.price_paisa / 100} | Valid: ${t.validation_status} | Active: ${t.is_active} | Billable: ${t.billing_enabled}`);
}

console.log('\n=== POINT 7: SEROLOGY HBsAg & HCV INVESTIGATION ===');
const serologyTargetCodes = ['SER-0004', 'SER-0087', 'SER-0010', 'SER-0088'];
for (const c of serologyTargetCodes) {
  const t = testMap.get(c);
  if (t) {
    console.log(`[${t.code}] "${t.name}" | Dept: ${t.department} | Method: ${t.method} | Specimen: ${t.sample_type || t.specimen_type} | Unit: ${t.unit} | Price: NPR ${t.price_paisa / 100} | Valid: ${t.validation_status} | Active: ${t.is_active} | Billable: ${t.billing_enabled}`);
  }
}
