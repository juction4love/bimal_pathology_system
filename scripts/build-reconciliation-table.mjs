import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync('scripts/full_catalogue_dump.json', 'utf8'));
const tests = data.tests;
const testMap = new Map(tests.map(t => [t.code, t]));

const mappingSpec = [
  // A. CARDIAC MARKERS
  {
    section: 'A. CARDIAC MARKERS',
    requestedName: 'Troponin I (cTnI)',
    requestedPrice: 1200,
    searchCodes: ['BIO-0063', 'BIO-0062'],
    notes: 'FIAcheck hs-cTnI / Troponin I'
  },
  {
    section: 'A. CARDIAC MARKERS',
    requestedName: 'Troponin T',
    requestedPrice: 1800,
    searchCodes: ['BIO-0064', 'END-0040', 'BIO-0070'],
    notes: 'Must NOT be mapped to Troponin I. Check if canonical Troponin T exists.'
  },
  {
    section: 'A. CARDIAC MARKERS',
    requestedName: 'CK-MB (Quantitative)',
    requestedPrice: 700,
    searchCodes: ['BIO-0061', 'BIO-0026'],
    notes: 'FIAcheck CK-MB Mass (ng/mL) vs CK-MB Activity (U/L)'
  },
  {
    section: 'A. CARDIAC MARKERS',
    requestedName: 'Troponin I + CK-MB + Myo Combo',
    requestedPrice: 2500,
    searchCodes: ['PRO-0007', 'CARDIAC-COMBO'],
    isPanel: true,
    panelComponents: ['Troponin I', 'CK-MB Mass', 'Myoglobin'],
    notes: 'Cardiac Markers Combo Panel'
  },
  {
    section: 'A. CARDIAC MARKERS',
    requestedName: 'NT-proBNP',
    requestedPrice: 3000,
    searchCodes: ['BIO-0067'],
    notes: 'FIAcheck NT-proBNP'
  },
  {
    section: 'A. CARDIAC MARKERS',
    requestedName: 'D-Dimer',
    requestedPrice: 1500,
    searchCodes: ['BIO-0059', 'COA-0006'],
    notes: 'FIAcheck D-Dimer FEU (ng/mL)'
  },

  // B. INFLAMMATION & INFECTION
  {
    section: 'B. INFLAMMATION & INFECTION',
    requestedName: 'hs-CRP / CRP (Quantitative)',
    requestedPrice: 700,
    searchCodes: ['BIO-0060', 'SER-0031', 'BIO-0033'],
    notes: 'BIO-0060 hs-CRP (FIAcheck) vs routine CRP'
  },
  {
    section: 'B. INFLAMMATION & INFECTION',
    requestedName: 'Procalcitonin (PCT)',
    requestedPrice: 2500,
    searchCodes: ['PCT_SEPSIS', 'BIO-0068', 'IMM-0009'],
    notes: 'FIAcheck PCT'
  },
  {
    section: 'B. INFLAMMATION & INFECTION',
    requestedName: 'PCT + CRP Combo',
    requestedPrice: 3000,
    searchCodes: ['IMM-INFLAMMATION'],
    isPanel: true,
    panelComponents: ['PCT', 'hs-CRP'],
    notes: 'PCT + CRP Combo Panel'
  },
  {
    section: 'B. INFLAMMATION & INFECTION',
    requestedName: 'Interleukin-6 (IL-6)',
    requestedPrice: 3000,
    searchCodes: ['IMM-0012', 'BIO-0069', 'IL-6'],
    notes: 'Interleukin-6'
  },
  {
    section: 'B. INFLAMMATION & INFECTION',
    requestedName: 'Ferritin',
    requestedPrice: 1000,
    searchCodes: ['BIO-0050', 'IMM-0001'],
    notes: 'Ferritin'
  },

  // C. DIABETES & RENAL MARKERS
  {
    section: 'C. DIABETES & RENAL MARKERS',
    requestedName: 'HbA1c (Glycated Hemoglobin)',
    requestedPrice: 800,
    searchCodes: ['BIO-0006', 'BIO-0058', 'HEM-0008'],
    notes: 'HbA1c'
  },
  {
    section: 'C. DIABETES & RENAL MARKERS',
    requestedName: 'Microalbumin (mAlb - Urine)',
    requestedPrice: 800,
    searchCodes: ['BIO-0035', 'CLP-0004'],
    notes: 'Urine Microalbumin (distinct from serum albumin)'
  },
  {
    section: 'C. DIABETES & RENAL MARKERS',
    requestedName: 'Cystatin C (CysC)',
    requestedPrice: 1200,
    searchCodes: ['BIO-0036', 'BIO-0071'],
    notes: 'Cystatin C'
  },

  // D. THYROID & HORMONES
  {
    section: 'D. THYROID & HORMONES',
    requestedName: 'TSH',
    requestedPrice: 500,
    searchCodes: ['END-0001'],
    notes: 'TSH'
  },
  {
    section: 'D. THYROID & HORMONES',
    requestedName: 'Free T3 (fT3)',
    requestedPrice: 550,
    searchCodes: ['END-0003'],
    notes: 'Free T3 (FT3)'
  },
  {
    section: 'D. THYROID & HORMONES',
    requestedName: 'Free T4 (fT4)',
    requestedPrice: 550,
    searchCodes: ['END-0002'],
    notes: 'Free T4 (FT4)'
  },
  {
    section: 'D. THYROID & HORMONES',
    requestedName: 'Complete Thyroid Profile (T3, T4, TSH)',
    requestedPrice: 1200,
    searchCodes: ['PRO-0004', 'PRO-0026'],
    isPanel: true,
    panelComponents: ['Total T3 (END-0004)', 'Total T4 (END-0005)', 'TSH (END-0001)'],
    notes: 'Total T3 + Total T4 + TSH'
  },
  {
    section: 'D. THYROID & HORMONES',
    requestedName: 'Beta-HCG (Quantitative)',
    requestedPrice: 1000,
    searchCodes: ['END-0039'],
    notes: 'Beta-HCG (Quantitative)'
  },
  {
    section: 'D. THYROID & HORMONES',
    requestedName: 'Total Testosterone',
    requestedPrice: 1200,
    searchCodes: ['END-0009'],
    notes: 'Total Testosterone'
  },
  {
    section: 'D. THYROID & HORMONES',
    requestedName: 'LH',
    requestedPrice: 800,
    searchCodes: ['END-0006'],
    notes: 'Luteinizing Hormone (LH)'
  },
  {
    section: 'D. THYROID & HORMONES',
    requestedName: 'FSH',
    requestedPrice: 800,
    searchCodes: ['END-0007'],
    notes: 'Follicle Stimulating Hormone (FSH)'
  },
  {
    section: 'D. THYROID & HORMONES',
    requestedName: 'Prolactin',
    requestedPrice: 800,
    searchCodes: ['END-0008'],
    notes: 'Prolactin'
  },
  {
    section: 'D. THYROID & HORMONES',
    requestedName: 'AMH (Anti-Mullerian Hormone)',
    requestedPrice: 3500,
    searchCodes: ['END-0010'],
    notes: 'AMH'
  },
  {
    section: 'D. THYROID & HORMONES',
    requestedName: 'Vitamin D (25-OH-VD)',
    requestedPrice: 2000,
    searchCodes: ['BIO-0053', 'END-0012'],
    notes: 'Vitamin D, 25-OH'
  },

  // E. INFECTIOUS & FEVER
  {
    section: 'E. INFECTIOUS & FEVER',
    requestedName: 'Scrub Typhus (FIA IgM/IgG)',
    requestedPrice: 1000,
    searchCodes: ['SER-0020', 'SER-0089'],
    notes: 'Scrub Typhus'
  },
  {
    section: 'E. INFECTIOUS & FEVER',
    requestedName: 'Dengue NS1 Ag (FIA)',
    requestedPrice: 800,
    searchCodes: ['SER-0015'],
    notes: 'Dengue NS1 Ag'
  },
  {
    section: 'E. INFECTIOUS & FEVER',
    requestedName: 'Dengue Combo (NS1 + IgM/IgG)',
    requestedPrice: 1200,
    searchCodes: ['PRO-0027', 'SER-0014', 'DENGUE-COMBO'],
    isPanel: true,
    panelComponents: ['Dengue NS1 (SER-0015)', 'Dengue IgM (SER-0016)', 'Dengue IgG (SER-0017)'],
    notes: 'Dengue Combo Panel'
  },
  {
    section: 'E. INFECTIOUS & FEVER',
    requestedName: 'Anti-HCV',
    requestedPrice: 600,
    searchCodes: ['SER-0010', 'SER-0088'],
    notes: 'Reconcile SER-0010 (automated/general) vs SER-0088 (Rapid)'
  },
  {
    section: 'E. INFECTIOUS & FEVER',
    requestedName: 'HBsAg',
    requestedPrice: 600,
    searchCodes: ['SER-0004', 'SER-0087'],
    notes: 'Reconcile SER-0004 (automated/general) vs SER-0087 (Rapid)'
  },
  {
    section: 'E. INFECTIOUS & FEVER',
    requestedName: 'H. pylori Antigen (Stool)',
    requestedPrice: 1000,
    searchCodes: ['SER-0043'],
    notes: 'H. pylori Stool Antigen (distinct from serology)'
  },

  // F. RHEUMATISM & TUMOR MARKERS
  {
    section: 'F. RHEUMATISM & TUMOR MARKERS',
    requestedName: 'Anti-CCP',
    requestedPrice: 2200,
    searchCodes: ['IMM-0010'],
    notes: 'Anti-CCP'
  },
  {
    section: 'F. RHEUMATISM & TUMOR MARKERS',
    requestedName: 'ASO (Quantitative)',
    requestedPrice: 600,
    searchCodes: ['IMM-0002', 'SER-0006'],
    notes: 'ASO Quantitative (Turbidimetry/FIA)'
  },
  {
    section: 'F. RHEUMATISM & TUMOR MARKERS',
    requestedName: 'RF (Quantitative)',
    requestedPrice: 600,
    searchCodes: ['IMM-0003', 'SER-0007'],
    notes: 'RF Quantitative (Turbidimetry/FIA)'
  },
  {
    section: 'F. RHEUMATISM & TUMOR MARKERS',
    requestedName: 'Total IgE',
    requestedPrice: 1200,
    searchCodes: ['IMM-0031'],
    notes: 'Total IgE'
  },
  {
    section: 'F. RHEUMATISM & TUMOR MARKERS',
    requestedName: 'Total PSA',
    requestedPrice: 1200,
    searchCodes: ['TUM-0007'],
    notes: 'Total PSA'
  },
  {
    section: 'F. RHEUMATISM & TUMOR MARKERS',
    requestedName: 'AFP',
    requestedPrice: 1400,
    searchCodes: ['TUM-0001'],
    notes: 'AFP'
  },
  {
    section: 'F. RHEUMATISM & TUMOR MARKERS',
    requestedName: 'CEA',
    requestedPrice: 1400,
    searchCodes: ['TUM-0002'],
    notes: 'CEA'
  }
];

console.log('=== DETAILED CODE LOOKUP ===');
for (const item of mappingSpec) {
  console.log(`\n-------------------------------------------------------------`);
  console.log(`Requested: [${item.section}] ${item.requestedName} | NPR ${item.requestedPrice || 'N/A'}`);
  console.log(`Checking search codes: ${item.searchCodes.join(', ')}`);
  for (const c of item.searchCodes) {
    const t = testMap.get(c);
    if (t) {
      console.log(`  -> FOUND [${t.code}] "${t.name}" (${t.short_name}) | Dept: ${t.department} | Specimen: ${t.sample_type || t.specimen_type} | Method: ${t.method} | Unit: ${t.unit} | Current Price: NPR ${t.price_paisa / 100} | Active: ${t.is_active} | Billable: ${t.billing_enabled} | Valid: ${t.validation_status}`);
    } else {
      console.log(`  -> NOT FOUND [${c}]`);
    }
  }
}
