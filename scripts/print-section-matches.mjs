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

// Section D
printSection('D. THYROID & HORMONES', [
  { name: 'TSH', pat: '\\bTSH\\b|END-0001|Thyrotropin', price: 500 },
  { name: 'Free T3 (fT3)', pat: 'Free T3|FT3|END-0003', price: 550 },
  { name: 'Free T4 (fT4)', pat: 'Free T4|FT4|END-0002', price: 550 },
  { name: 'Total T3', pat: 'Total T3|Triiodothyronine.*Total|END-0004', price: 'panel comp' },
  { name: 'Total T4', pat: 'Total T4|Thyroxine.*Total|END-0005', price: 'panel comp' },
  { name: 'Beta-HCG (Quantitative)', pat: 'Beta-HCG|HCG.*Quant|END-0039|Human Chorionic', price: 1000 },
  { name: 'Total Testosterone', pat: 'Testosterone', price: 1200 },
  { name: 'LH', pat: 'Luteinizing|\\bLH\\b', price: 800 },
  { name: 'FSH', pat: 'Follicle|\\bFSH\\b', price: 800 },
  { name: 'Prolactin', pat: 'Prolactin|\\bPRL\\b', price: 800 },
  { name: 'AMH (Anti-Mullerian Hormone)', pat: 'Anti-Mullerian|\\bAMH\\b|Mullerian', price: 3500 },
  { name: 'Vitamin D (25-OH-VD)', pat: 'Vitamin D|25-OH|BIO-0053', price: 2000 }
]);

// Section E
printSection('E. INFECTIOUS & FEVER', [
  { name: 'Scrub Typhus (FIA IgM/IgG)', pat: 'Scrub|SER-0020|SER-0021|Tsutsugamushi', price: 1000 },
  { name: 'Dengue NS1 Ag (FIA)', pat: 'Dengue NS1|SER-0015', price: 800 },
  { name: 'Dengue IgM', pat: 'Dengue IgM|SER-0016', price: 'combo comp' },
  { name: 'Dengue IgG', pat: 'Dengue IgG|SER-0017', price: 'combo comp' },
  { name: 'Anti-HCV', pat: 'Anti-HCV|HCV Rapid|SER-0010|SER-0088', price: 600 },
  { name: 'HBsAg', pat: 'HBsAg|HBsAg Rapid|SER-0004|SER-0087', price: 600 },
  { name: 'H. pylori Antigen (Stool)', pat: 'Pylori.*Stool|SER-0043', price: 1000 }
]);

// Section F
printSection('F. RHEUMATISM & TUMOR MARKERS', [
  { name: 'Anti-CCP', pat: 'Anti-CCP|CCP|Citrullinated', price: 2200 },
  { name: 'ASO (Quantitative)', pat: 'ASO|Antistreptolysin', price: 600 },
  { name: 'RF (Quantitative)', pat: 'Rheumatoid Factor|\\bRF\\b', price: 600 },
  { name: 'Total IgE', pat: 'Total IgE|IMM-0031', price: 1200 },
  { name: 'Total PSA', pat: 'PSA.*Total|TUM-0007', price: 1200 },
  { name: 'AFP', pat: '\\bAFP\\b|TUM-0001|Alpha-Fetoprotein', price: 1400 },
  { name: 'CEA', pat: '\\bCEA\\b|TUM-0002|Carcinoembryonic', price: 1400 }
]);
