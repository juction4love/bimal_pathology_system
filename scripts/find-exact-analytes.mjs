import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync('scripts/full_catalogue_dump.json', 'utf8'));
const tests = data.tests;

function findByName(pattern) {
  const reg = new RegExp(pattern, 'i');
  return tests.filter(t => reg.test(t.name) || reg.test(t.code) || reg.test(t.short_name || ''));
}

const targets = [
  // A. Cardiac
  { name: 'Troponin I', pat: 'Troponin|cTnI' },
  { name: 'Troponin T', pat: 'Troponin.*T|cTnT' },
  { name: 'CK-MB', pat: 'CK-MB|Creatine Kinase-MB' },
  { name: 'Myoglobin', pat: 'Myoglobin' },
  { name: 'NT-proBNP', pat: 'BNP|proBNP' },
  { name: 'D-Dimer', pat: 'D-Dimer|Dimer' },

  // B. Inflammation & Infection
  { name: 'CRP / hs-CRP', pat: 'CRP|C-Reactive' },
  { name: 'Procalcitonin', pat: 'Procalcitonin|PCT' },
  { name: 'Interleukin-6', pat: 'Interleukin|IL-6|IL6' },
  { name: 'Ferritin', pat: 'Ferritin' },

  // C. Diabetes & Renal
  { name: 'HbA1c', pat: 'HbA1c|Glycated|A1c' },
  { name: 'Microalbumin', pat: 'Microalbumin|mAlb' },
  { name: 'Cystatin C', pat: 'Cystatin' },

  // D. Thyroid & Hormones
  { name: 'TSH', pat: '\\bTSH\\b|Thyrotropin' },
  { name: 'Free T3', pat: 'Free T3|FT3' },
  { name: 'Free T4', pat: 'Free T4|FT4' },
  { name: 'Total T3', pat: 'Total T3|Triiodothyronine' },
  { name: 'Total T4', pat: 'Total T4|Thyroxine' },
  { name: 'Beta-HCG', pat: 'HCG|Chorionic' },
  { name: 'Testosterone', pat: 'Testosterone' },
  { name: 'LH', pat: '\\bLH\\b|Luteinizing' },
  { name: 'FSH', pat: '\\bFSH\\b|Follicle' },
  { name: 'Prolactin', pat: 'Prolactin' },
  { name: 'AMH', pat: 'AMH|Mullerian' },
  { name: 'Vitamin D', pat: 'Vitamin D|25-OH' },

  // E. Infectious & Fever
  { name: 'Scrub Typhus', pat: 'Scrub|Tsutsugamushi' },
  { name: 'Dengue', pat: 'Dengue' },
  { name: 'Anti-HCV', pat: 'HCV|Hepatitis C' },
  { name: 'HBsAg', pat: 'HBsAg|Hepatitis B Surface' },
  { name: 'H. pylori', pat: 'Pylori' },

  // F. Rheumatism & Tumor Markers
  { name: 'Anti-CCP', pat: 'CCP|Citrullinated' },
  { name: 'ASO', pat: '\\bASO\\b|Antistreptolysin' },
  { name: 'RF', pat: '\\bRF\\b|Rheumatoid' },
  { name: 'Total IgE', pat: 'IgE|Immunoglobulin E' },
  { name: 'PSA', pat: 'PSA|Prostate' },
  { name: 'AFP', pat: 'AFP|Alpha-Fetoprotein' },
  { name: 'CEA', pat: 'CEA|Carcinoembryonic' }
];

for (const tgt of targets) {
  const matches = findByName(tgt.pat);
  console.log(`\n======================================================`);
  console.log(`Target: ${tgt.name} (Pattern: ${tgt.pat}) -> Matches: ${matches.length}`);
  for (const m of matches) {
    console.log(`  [${m.code}] "${m.name}" | Short: "${m.short_name}" | Dept: ${m.department} | Type: ${m.test_type} | Spec: ${m.sample_type || m.specimen_type} | Method: ${m.method} | Unit: ${m.unit} | Price: NPR ${m.price_paisa / 100} | Valid: ${m.validation_status} | Active: ${m.is_active} | Billable: ${m.billing_enabled} | Data: ${m.report_data_type}`);
  }
}
