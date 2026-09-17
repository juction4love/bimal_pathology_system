import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync('scripts/full_catalogue_dump.json', 'utf8'));
const tests = data.tests;

function search(terms) {
  return tests.filter(t => {
    const text = `${t.code} ${t.name} ${t.short_name || ''} ${t.department || ''} ${t.method || ''} ${(t.search_aliases || []).join(' ')}`.toLowerCase();
    return terms.some(term => text.includes(term.toLowerCase()));
  });
}

const auditItems = [
  // A. Cardiac
  { section: 'A. CARDIAC MARKERS', item: 'Troponin I (cTnI)', terms: ['troponin', 'ctni'], targetPrice: 1200 },
  { section: 'A. CARDIAC MARKERS', item: 'Troponin T', terms: ['troponin t', 'ctnt'], targetPrice: 1800 },
  { section: 'A. CARDIAC MARKERS', item: 'CK-MB (Quantitative)', terms: ['ck-mb', 'ckmb', 'creatine kinase-mb'], targetPrice: 700 },
  { section: 'A. CARDIAC MARKERS', item: 'Myoglobin (for combo)', terms: ['myoglobin', 'myo'], targetPrice: null },
  { section: 'A. CARDIAC MARKERS', item: 'NT-proBNP', terms: ['probnp', 'bnp', 'nt-probnp'], targetPrice: 3000 },
  { section: 'A. CARDIAC MARKERS', item: 'D-Dimer', terms: ['d-dimer', 'ddimer', 'dimer'], targetPrice: 1500 },
  
  // B. Inflammation & Infection
  { section: 'B. INFLAMMATION & INFECTION', item: 'hs-CRP / CRP (Quantitative)', terms: ['crp', 'c-reactive'], targetPrice: 700 },
  { section: 'B. INFLAMMATION & INFECTION', item: 'Procalcitonin (PCT)', terms: ['procalcitonin', 'pct'], targetPrice: 2500 },
  { section: 'B. INFLAMMATION & INFECTION', item: 'Interleukin-6 (IL-6)', terms: ['interleukin', 'il-6', 'il6'], targetPrice: 3000 },
  { section: 'B. INFLAMMATION & INFECTION', item: 'Ferritin', terms: ['ferritin'], targetPrice: 1000 },

  // C. Diabetes & Renal
  { section: 'C. DIABETES & RENAL MARKERS', item: 'HbA1c (Glycated Hemoglobin)', terms: ['hba1c', 'glycated', 'a1c'], targetPrice: 800 },
  { section: 'C. DIABETES & RENAL MARKERS', item: 'Microalbumin (mAlb - Urine)', terms: ['microalbumin', 'malb', 'albumin, urine', 'urine microalbumin'], targetPrice: 800 },
  { section: 'C. DIABETES & RENAL MARKERS', item: 'Cystatin C (CysC)', terms: ['cystatin', 'cysc'], targetPrice: 1200 },

  // D. Thyroid & Hormones
  { section: 'D. THYROID & HORMONES', item: 'TSH', terms: ['tsh', 'thyrotropin'], targetPrice: 500 },
  { section: 'D. THYROID & HORMONES', item: 'Free T3 (fT3)', terms: ['free t3', 'ft3', 'triiodothyronine, free'], targetPrice: 550 },
  { section: 'D. THYROID & HORMONES', item: 'Free T4 (fT4)', terms: ['free t4', 'ft4', 'thyroxine, free'], targetPrice: 550 },
  { section: 'D. THYROID & HORMONES', item: 'Total T3 (T3)', terms: ['total t3', 'triiodothyronine, total', 't3, total', 'END-0004'], targetPrice: null },
  { section: 'D. THYROID & HORMONES', item: 'Total T4 (T4)', terms: ['total t4', 'thyroxine, total', 't4, total', 'END-0005'], targetPrice: null },
  { section: 'D. THYROID & HORMONES', item: 'Beta-HCG (Quantitative)', terms: ['beta-hcg', 'hcg', 'human chorionic'], targetPrice: 1000 },
  { section: 'D. THYROID & HORMONES', item: 'Total Testosterone', terms: ['testosterone'], targetPrice: 1200 },
  { section: 'D. THYROID & HORMONES', item: 'LH', terms: ['luteinizing', 'lh', 'END-0006'], targetPrice: 800 },
  { section: 'D. THYROID & HORMONES', item: 'FSH', terms: ['follicle', 'fsh', 'END-0007'], targetPrice: 800 },
  { section: 'D. THYROID & HORMONES', item: 'Prolactin', terms: ['prolactin', 'prl', 'END-0008'], targetPrice: 800 },
  { section: 'D. THYROID & HORMONES', item: 'AMH (Anti-Mullerian Hormone)', terms: ['mullerian', 'amh', 'anti-mullerian'], targetPrice: 3500 },
  { section: 'D. THYROID & HORMONES', item: 'Vitamin D (25-OH-VD)', terms: ['vitamin d', '25-oh', 'cholecalciferol'], targetPrice: 2000 },

  // E. Infectious & Fever
  { section: 'E. INFECTIOUS & FEVER', item: 'Scrub Typhus (FIA IgM/IgG)', terms: ['scrub', 'tsutsugamushi', 'orientia'], targetPrice: 1000 },
  { section: 'E. INFECTIOUS & FEVER', item: 'Dengue NS1 Ag (FIA)', terms: ['dengue ns1', 'ns1'], targetPrice: 800 },
  { section: 'E. INFECTIOUS & FEVER', item: 'Dengue IgM/IgG (for combo)', terms: ['dengue igm', 'dengue igg', 'dengue serology'], targetPrice: null },
  { section: 'E. INFECTIOUS & FEVER', item: 'Anti-HCV', terms: ['hcv', 'hepatitis c'], targetPrice: 600 },
  { section: 'E. INFECTIOUS & FEVER', item: 'HBsAg', terms: ['hbsag', 'hepatitis b surface'], targetPrice: 600 },
  { section: 'E. INFECTIOUS & FEVER', item: 'H. pylori Antigen (Stool)', terms: ['pylori', 'h. pylori'], targetPrice: 1000 },

  // F. Rheumatism & Tumor Markers
  { section: 'F. RHEUMATISM & TUMOR MARKERS', item: 'Anti-CCP', terms: ['ccp', 'citrullinated'], targetPrice: 2200 },
  { section: 'F. RHEUMATISM & TUMOR MARKERS', item: 'ASO (Quantitative)', terms: ['aso', 'antistreptolysin'], targetPrice: 600 },
  { section: 'F. RHEUMATISM & TUMOR MARKERS', item: 'RF (Quantitative)', terms: ['rheumatoid factor', 'rf quantitative', 'rf'], targetPrice: 600 },
  { section: 'F. RHEUMATISM & TUMOR MARKERS', item: 'Total IgE', terms: ['total ige', 'immunoglobulin e, total', 'ige'], targetPrice: 1200 },
  { section: 'F. RHEUMATISM & TUMOR MARKERS', item: 'Total PSA', terms: ['psa', 'prostate specific', 'prostate-specific'], targetPrice: 1200 },
  { section: 'F. RHEUMATISM & TUMOR MARKERS', item: 'AFP', terms: ['afp', 'alpha-fetoprotein', 'alpha fetoprotein'], targetPrice: 1400 },
  { section: 'F. RHEUMATISM & TUMOR MARKERS', item: 'CEA', terms: ['cea', 'carcinoembryonic'], targetPrice: 1400 }
];

console.log('=== AUDIT MATCHES ===');
for (const entry of auditItems) {
  const matches = search(entry.terms);
  console.log(`\n======================================================`);
  console.log(`[${entry.section}] -> ${entry.item} (Target: NPR ${entry.targetPrice})`);
  console.log(`Found ${matches.length} candidate(s):`);
  for (const m of matches) {
    console.log(`  - [${m.code}] "${m.name}" (Short: "${m.short_name}") | Dept: ${m.department} | Type: ${m.test_type} | Spec: ${m.sample_type || m.specimen_type} | Method: ${m.method} | Price: NPR ${m.price_paisa / 100} | Valid: ${m.validation_status} | Active: ${m.is_active} | Billable: ${m.billing_enabled}`);
  }
}
