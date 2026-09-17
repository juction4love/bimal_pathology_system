import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync('scripts/full_catalogue_dump.json', 'utf8'));
const tests = data.tests;

function find(pattern) {
  const reg = new RegExp(pattern, 'i');
  return tests.filter(t => reg.test(t.name) || reg.test(t.code) || reg.test(t.short_name || ''));
}

function printSection(title, list) {
  console.log(`\n================================================================`);
  console.log(`>>> SECTION: ${title}`);
  console.log(`================================================================`);
  for (const item of list) {
    const res = find(item.pat);
    console.log(`\n-- Target: "${item.name}" (Req Price: NPR ${item.price}) -- Candidates: ${res.length}`);
    for (const m of res) {
      console.log(`   [${m.code}] "${m.name}" | Short: "${m.short_name}" | Dept: ${m.department} | Type: ${m.test_type} | Spec: ${m.sample_type || m.specimen_type} | Method: ${m.method} | Unit: ${m.unit} | Price: NPR ${m.price_paisa / 100} | Valid: ${m.validation_status} | Active: ${m.is_active} | Billable: ${m.billing_enabled}`);
    }
  }
}

// Section A
printSection('A. CARDIAC MARKERS', [
  { name: 'Troponin I (cTnI)', pat: 'Troponin.*I|cTnI|BIO-0063', price: 1200 },
  { name: 'Troponin T', pat: 'Troponin.*T|cTnT', price: 1800 },
  { name: 'CK-MB (Quantitative)', pat: 'CK-MB|BIO-0061|Creatine Kinase-MB', price: 700 },
  { name: 'Myoglobin', pat: 'Myoglobin|BIO-0065', price: 'for combo' },
  { name: 'NT-proBNP', pat: 'proBNP|NT-proBNP|BIO-0067|BNP', price: 3000 },
  { name: 'D-Dimer', pat: 'D-Dimer|BIO-0059|COA-0006', price: 1500 }
]);

// Section B
printSection('B. INFLAMMATION & INFECTION', [
  { name: 'hs-CRP / CRP (Quantitative)', pat: 'hs-CRP|C-Reactive|BIO-0060|BIO-0033|SER-0031', price: 700 },
  { name: 'Procalcitonin (PCT)', pat: 'Procalcitonin|PCT_SEPSIS|BIO-0068', price: 2500 },
  { name: 'Interleukin-6 (IL-6)', pat: 'Interleukin|IL-6|IL6', price: 3000 },
  { name: 'Ferritin', pat: 'Ferritin|BIO-0050|IMM-0001', price: 1000 }
]);

// Section C
printSection('C. DIABETES & RENAL MARKERS', [
  { name: 'HbA1c (Glycated Hemoglobin)', pat: 'HbA1c|BIO-0006|BIO-0058|Glycated', price: 800 },
  { name: 'Microalbumin (mAlb - Urine)', pat: 'Microalbumin|mAlb|BIO-0035|CLP-0004', price: 800 },
  { name: 'Cystatin C (CysC)', pat: 'Cystatin', price: 1200 }
]);
