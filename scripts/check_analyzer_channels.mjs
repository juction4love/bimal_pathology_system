import fs from 'node:fs';

const content = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');

// Parse tests
const testMatches = content.matchAll(/\('([a-f0-9-]+)',\s*'([^']+)',\s*'([^']+)'/g);
const tests = new Map();
for (const m of testMatches) {
  tests.set(m[2], { id: m[1], name: m[3] });
}

// Parse parameters
const paramMatches = content.matchAll(/\('([a-f0-9-]+)',\s*'([a-f0-9-]+)',\s*'([^']+)',\s*'([^']+)'/g);
const params = new Map();
for (const m of paramMatches) {
  // test_id -> param_code -> { id, name }
  const testId = m[2];
  const paramCode = m[3];
  const paramId = m[1];
  const paramName = m[4];
  params.set(`${testId}:${paramCode}`, { id: paramId, name: paramName });
}

console.log(`Found ${tests.size} tests in baseline`);
console.log(`Found ${params.size} parameters in baseline`);

const coralabChannels = [
  { channel: 'ALT', test: 'BIO-0021', name: 'Alanine Aminotransferase (ALT/SGPT)', method: 'UV Kinetic (IFCC)', unit: 'U/L' },
  { channel: 'AST', test: 'BIO-0020', name: 'Aspartate Aminotransferase (AST/SGOT)', method: 'UV Kinetic (IFCC)', unit: 'U/L' },
  { channel: 'ALP', test: 'BIO-0022', name: 'Alkaline Phosphatase (ALP)', method: 'p-NPP Kinetic (IFCC)', unit: 'U/L' },
  { channel: 'TBIL', test: 'BIO-0017', name: 'Total Bilirubin', method: 'Modified Jendrassik-Grof / DPD', unit: 'mg/dL' },
  { channel: 'DBIL', test: 'BIO-0018', name: 'Direct Bilirubin', method: 'Modified Jendrassik-Grof / DPD', unit: 'mg/dL' },
  { channel: 'TP', test: 'BIO-0013', name: 'Total Protein', method: 'Biuret End Point', unit: 'g/dL' },
  { channel: 'ALB', test: 'BIO-0014', name: 'Albumin', method: 'Bromocresol Green (BCG)', unit: 'g/dL' },
  { channel: 'GGT', test: 'BIO-0023', name: 'Gamma-Glutamyl Transferase (GGT)', method: 'Szasz Kinetic (IFCC)', unit: 'U/L' },
  { channel: 'CREAT', test: 'BIO-0010', name: 'Creatinine', method: 'Modified Jaffé Kinetic', unit: 'mg/dL' },
  { channel: 'UREA', test: 'BIO-0008', name: 'Urea', method: 'GLDH / Urease Kinetic', unit: 'mg/dL' },
  { channel: 'URIC', test: 'BIO-0012', name: 'Uric Acid', method: 'Uricase / POD End Point', unit: 'mg/dL' },
  { channel: 'GLU_FASTING', test: 'BIO-0001', name: 'Glucose, Fasting (FBS)', method: 'GOD-POD End Point', unit: 'mg/dL' },
  { channel: 'GLU_PP', test: 'BIO-0003', name: 'Glucose, Postprandial 2 hr (PPBS)', method: 'GOD-POD End Point', unit: 'mg/dL' },
  { channel: 'GLU_RANDOM', test: 'BIO-0002', name: 'Glucose, Random (RBS)', method: 'GOD-POD End Point', unit: 'mg/dL' },
  { channel: 'CHOL', test: 'BIO-0027', name: 'Total Cholesterol', method: 'CHOD-PAP End Point', unit: 'mg/dL' },
  { channel: 'TRIG', test: 'BIO-0028', name: 'Triglycerides', method: 'GPO-PAP End Point', unit: 'mg/dL' },
  { channel: 'HDL', test: 'BIO-0029', name: 'HDL Cholesterol', method: 'Direct Immunoinhibition / Detergent', unit: 'mg/dL' },
  { channel: 'LDL_DIRECT', test: 'BIO-0030', name: 'LDL Cholesterol, Direct', method: 'Direct Clearance / Selective Detergent', unit: 'mg/dL' },
  { channel: 'CALC', test: 'BIO-0041', name: 'Calcium, Total', method: 'Arsenazo III / O-CPC', unit: 'mg/dL' },
  { channel: 'PHOS', test: 'BIO-0043', name: 'Phosphorus', method: 'Phosphomolybdate UV', unit: 'mg/dL' },
  { channel: 'MAG', test: 'BIO-0044', name: 'Magnesium', method: 'Calmagite / Xylidyl Blue', unit: 'mg/dL' },
  { channel: 'NA_PHOTOMETRIC', test: 'BIO-0037', name: 'Sodium (Photometric)', method: 'Enzymatic / Colorimetric (Photometric Non-ISE)', unit: 'mmol/L' },
  { channel: 'K_PHOTOMETRIC', test: 'BIO-0038', name: 'Potassium (Photometric)', method: 'Enzymatic / Turbidimetric (Photometric Non-ISE)', unit: 'mmol/L' },
  { channel: 'CL_PHOTOMETRIC', test: 'BIO-0039', name: 'Chloride (Photometric)', method: 'Mercuric Thiocyanate (Photometric Non-ISE)', unit: 'mmol/L' },
  { channel: 'CK_TOTAL', test: 'BIO-0060', name: 'CK Total (Creatine Kinase)', method: 'CK-NAC / Modified IFCC Kinetic', unit: 'U/L' },
  { channel: 'CK_MB', test: 'BIO-0062', name: 'CK-MB Activity', method: 'Immunoinhibition Kinetic', unit: 'U/L' },
  { channel: 'LDH', test: 'BIO-0024', name: 'Lactate Dehydrogenase (LDH)', method: 'DGKC / IFCC UV Kinetic', unit: 'U/L' },
  { channel: 'AMYLASE', test: 'BIO-0058', name: 'Amylase', method: 'CNP-G3 Direct Substrate', unit: 'U/L' }
];

const fiacheckChannels = [
  { channel: 'TSH', test: 'END-0001', name: 'Thyroid Stimulating Hormone (TSH)', method: 'Fluorescence Immunoassay', unit: 'µIU/mL' },
  { channel: 'FT3', test: 'END-0003', name: 'Free Triiodothyronine (FT3)', method: 'Fluorescence Immunoassay', unit: 'pg/mL' },
  { channel: 'FT4', test: 'END-0002', name: 'Free Thyroxine (FT4)', method: 'Fluorescence Immunoassay', unit: 'ng/dL' },
  { channel: 'TT3', test: 'END-0005', name: 'Total Triiodothyronine (Total T3)', method: 'Fluorescence Immunoassay', unit: 'ng/mL' },
  { channel: 'TT4', test: 'END-0004', name: 'Total Thyroxine (Total T4)', method: 'Fluorescence Immunoassay', unit: 'µg/dL' },
  { channel: 'VIT_D', test: 'BIO-0053', name: '25-OH Vitamin D', method: 'Fluorescence Immunoassay', unit: 'ng/mL' },
  { channel: 'VIT_B12', test: 'BIO-0051', name: 'Vitamin B12', method: 'Fluorescence Immunoassay', unit: 'pg/mL' },
  { channel: 'CTNI', test: 'BIO-0063', name: 'Cardiac Troponin I (cTnI)', method: 'Fluorescence Immunoassay', unit: 'ng/mL' },
  { channel: 'CKMB_MASS', test: 'BIO-0061', name: 'CK-MB Mass', method: 'Fluorescence Immunoassay', unit: 'ng/mL' },
  { channel: 'MYO', test: 'BIO-0065', name: 'Myoglobin', method: 'Fluorescence Immunoassay', unit: 'ng/mL' },
  { channel: 'NT_PROBNP', test: 'BIO-0067', name: 'NT-proBNP', method: 'Fluorescence Immunoassay', unit: 'pg/mL' },
  { channel: 'D_DIMER', test: 'COA-0006', name: 'D-Dimer (FEU)', method: 'Fluorescence Immunoassay', unit: 'µg/mL FEU' },
  { channel: 'HS_CRP', test: 'BIO-0068', name: 'High Sensitivity CRP (hs-CRP)', method: 'Fluorescence Immunoassay', unit: 'mg/L' },
  { channel: 'PCT_SEPSIS', test: 'PCT_SEPSIS', name: 'Procalcitonin (PCT Sepsis)', method: 'Fluorescence Immunoassay', unit: 'ng/mL' },
  { channel: 'B_HCG', test: 'END-0039', name: 'Quantitative Beta-hCG', method: 'Fluorescence Immunoassay', unit: 'mIU/mL' },
  { channel: 'FERRITIN', test: 'BIO-0050', name: 'Ferritin', method: 'Fluorescence Immunoassay', unit: 'ng/mL' }
];

console.log('\n--- Checking CORALAB ACE Channels against baseline ---');
for (const c of coralabChannels) {
  const t = tests.get(c.test);
  if (!t) console.log(`  MISSING TEST: ${c.test} for ${c.channel}`);
  else {
    const p = params.get(`${t.id}:${c.test}`);
    console.log(`  MATCH: ${c.channel.padEnd(15)} -> Test ${c.test} (${t.name}) -> Param ID ${p ? p.id : 'default'}`);
  }
}

console.log('\n--- Checking FIAcheck Channels against baseline ---');
for (const c of fiacheckChannels) {
  const t = tests.get(c.test);
  if (!t) console.log(`  MISSING TEST: ${c.test} for ${c.channel}`);
  else {
    const p = params.get(`${t.id}:${c.test}`);
    console.log(`  MATCH: ${c.channel.padEnd(15)} -> Test ${c.test} (${t.name}) -> Param ID ${p ? p.id : 'default'}`);
  }
}
