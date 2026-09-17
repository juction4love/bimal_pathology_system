/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Billing Catalogue Metadata, Bilingual Titles, Categories & Safe Clinical Info
 */

export interface BillingCategoryFilter {
  id: string;
  labelNp: string;
  labelEn: string;
  fullLabel: string;
  keywords: string[];
  departments: string[];
  codePrefixes: string[];
}

export const BILLING_CATEGORY_FILTERS: BillingCategoryFilter[] = [
  {
    id: 'ALL',
    labelNp: 'सबै',
    labelEn: 'All Tests',
    fullLabel: 'सबै (All Tests)',
    keywords: [],
    departments: [],
    codePrefixes: [],
  },
  {
    id: 'HEMATOLOGY',
    labelNp: 'हेमेटोलोजी',
    labelEn: 'CBC',
    fullLabel: 'हेमेटोलोजी (CBC)',
    keywords: ['cbc', 'hemogram', 'blood count', 'esr', 'platelet', 'wbc', 'rbc', 'hemoglobin', 'reticulocyte', 'smear', 'leukocyte', 'coagulation', 'pt', 'aptt', 'd-dimer'],
    departments: ['Hematology', 'Coagulation'],
    codePrefixes: ['HEM-', 'COA-'],
  },
  {
    id: 'BIOCHEMISTRY',
    labelNp: 'बायोकेमिस्ट्री',
    labelEn: 'LFT/KFT',
    fullLabel: 'बायोकेमिस्ट्री (LFT/KFT)',
    keywords: ['lft', 'kft', 'rft', 'liver', 'kidney', 'renal', 'urea', 'creatinine', 'bilirubin', 'sgot', 'sgpt', 'alt', 'ast', 'alp', 'protein', 'albumin', 'electrolytes', 'uric acid', 'sodium', 'potassium', 'chloride', 'calcium', 'amylase', 'lipase'],
    departments: ['Clinical Biochemistry', 'Biochemistry', 'Profiles / Packages'],
    codePrefixes: ['BIO-', 'PRO-0001', 'PRO-0002', 'PRO-0008'],
  },
  {
    id: 'DIABETES',
    labelNp: 'मधुमेह',
    labelEn: 'Diabetes',
    fullLabel: 'मधुमेह (Diabetes)',
    keywords: ['glucose', 'sugar', 'fbs', 'ppbs', 'rbs', 'hba1c', 'diabetes', 'insulin', 'microalbumin', 'c-peptide', 'ogtt'],
    departments: ['Clinical Biochemistry'],
    codePrefixes: ['BIO-0001', 'BIO-0002', 'BIO-0003', 'BIO-0004', 'PRO-0006'],
  },
  {
    id: 'LIPID',
    labelNp: 'लिपिड',
    labelEn: 'Lipid',
    fullLabel: 'लिपिड (Lipid)',
    keywords: ['lipid', 'cholesterol', 'triglycerides', 'hdl', 'ldl', 'vldl', 'non-hdl', 'apolipoprotein', 'lipoprotein'],
    departments: ['Clinical Biochemistry', 'Profiles / Packages'],
    codePrefixes: ['BIO-0027', 'BIO-0028', 'BIO-0029', 'BIO-0030', 'BIO-0031', 'BIO-0032', 'BIO-0033', 'PRO-0003'],
  },
  {
    id: 'THYROID',
    labelNp: 'थाइरोइड',
    labelEn: 'Thyroid',
    fullLabel: 'थाइरोइड (Thyroid)',
    keywords: ['tsh', 'ft3', 'ft4', 't3', 't4', 'thyroid', 'tft', 'anti-tpo', 'thyroglobulin', 'trab'],
    departments: ['Endocrinology', 'Profiles / Packages'],
    codePrefixes: ['END-0001', 'END-0002', 'END-0003', 'END-0004', 'END-0005', 'END-0006', 'END-0007', 'END-0008', 'END-0009', 'PRO-0004'],
  },
  {
    id: 'VITAMINS',
    labelNp: 'भिटामिन',
    labelEn: 'Vitamins',
    fullLabel: 'भिटामिन (Vitamins)',
    keywords: ['vitamin', 'vit d', 'vit b12', '25-oh', 'folate', 'folic acid', 'cobalamin', 'b12', 'd3'],
    departments: ['Clinical Biochemistry', 'Profiles / Packages'],
    codePrefixes: ['BIO-0051', 'BIO-0052', 'BIO-0053', 'IMM-VITAMINS'],
  },
  {
    id: 'CARDIAC',
    labelNp: 'कार्डियाक',
    labelEn: 'Cardiac',
    fullLabel: 'कार्डियाक (Cardiac)',
    keywords: ['troponin', 'ctni', 'ctnt', 'hs-ctni', 'hs-ctnt', 'bnp', 'nt-probnp', 'ck-mb', 'cpk', 'myoglobin', 'cardiac', 'ldh'],
    departments: ['Clinical Biochemistry', 'Profiles / Packages'],
    codePrefixes: ['BIO-0024', 'BIO-0025', 'BIO-0061', 'BIO-0062', 'BIO-0063', 'BIO-0064', 'BIO-0065', 'BIO-0067', 'PRO-0007'],
  },
  {
    id: 'URINE',
    labelNp: 'पिसाब',
    labelEn: 'Urine',
    fullLabel: 'पिसाब (Urine)',
    keywords: ['urine', 'urinalysis', 're/me', 'routine', 'microscopic', 'sediment', 'bence jones', 'stool', 'semen', 'sputum'],
    departments: ['Clinical Pathology'],
    codePrefixes: ['CLP-'],
  },
  {
    id: 'SEROLOGY',
    labelNp: 'सेरोलोजी',
    labelEn: 'Serology',
    fullLabel: 'सेरोलोजी (Serology)',
    keywords: ['widal', 'typhoid', 'dengue', 'hiv', 'hbsag', 'hcv', 'vdrl', 'tpha', 'crp', 'ra factor', 'aso', 'ana', 'chikungunya', 'malaria', 'rapid'],
    departments: ['Serology', 'Immunology', 'Infectious Disease Serology'],
    codePrefixes: ['SER-', 'IMM-'],
  },
];

export interface ClinicalMeta {
  titleNp?: string;
  abbreviation?: string;
  safeDescription: string;
  specimenGuide: string;
  prepInstructions: string;
  tatEstimate: string;
}

const KNOWN_CLINICAL_META: Record<string, ClinicalMeta> = {
  'HEM-0001': {
    titleNp: 'पूर्ण रक्त गणना (सीबीसी / हेमोग्राम)',
    abbreviation: 'CBC',
    safeDescription: 'Automated 24-parameter hemogram including WBC, RBC, Hemoglobin, Platelets, red cell indices and 3-part differential.',
    specimenGuide: 'EDTA Whole Blood (Lavender Top Tube)',
    prepInstructions: 'No special fasting required. Gentle mixing required.',
    tatEstimate: '2–4 Hours (Same Day)',
  },
  'PRO-0001': {
    titleNp: 'कलेजो कार्यक्षमता परीक्षण (LFT)',
    abbreviation: 'LFT',
    safeDescription: 'Total & Direct Bilirubin, SGOT/AST, SGPT/ALT, Alkaline Phosphatase, Total Protein, Albumin, Globulin & A/G Ratio.',
    specimenGuide: 'Blood Serum (Gold / Red SST Tube)',
    prepInstructions: '8–10 hours overnight fasting recommended.',
    tatEstimate: '2–4 Hours (Same Day)',
  },
  'PRO-0002': {
    titleNp: 'मिर्गौला कार्यक्षमता परीक्षण (KFT/RFT)',
    abbreviation: 'KFT / RFT',
    safeDescription: 'Renal panel evaluating Blood Urea, BUN, Serum Creatinine, Uric Acid, and Electrolytes.',
    specimenGuide: 'Blood Serum (Gold / Red SST Tube)',
    prepInstructions: 'Adequate hydration recommended. Normal diet.',
    tatEstimate: '2–4 Hours (Same Day)',
  },
  'PRO-0003': {
    titleNp: 'लिपिड प्रोफाइल (कोलेस्ट्रोल प्यानल)',
    abbreviation: 'LIPID',
    safeDescription: 'Total Cholesterol, Triglycerides, HDL, LDL, VLDL and Non-HDL cholesterol fractions.',
    specimenGuide: 'Blood Serum (Gold / Red SST Tube)',
    prepInstructions: '10–12 hours overnight fasting mandatory.',
    tatEstimate: '2–4 Hours (Same Day)',
  },
  'PRO-0004': {
    titleNp: 'थाइरोइड प्रोफाइल (FT3, FT4, TSH)',
    abbreviation: 'TFT / Free Thyroid',
    safeDescription: 'Canonical Free Thyroid Profile evaluating Free T3, Free T4, and Thyroid Stimulating Hormone (TSH).',
    specimenGuide: 'Blood Serum (Gold / Red SST Tube)',
    prepInstructions: 'Morning sample before thyroid medication recommended.',
    tatEstimate: '3–6 Hours (Same Day)',
  },
  'PRO-0006': {
    titleNp: 'मधुमेह प्रोफाइल (Diabetes Panel)',
    abbreviation: 'Diabetes Profile',
    safeDescription: 'Comprehensive glycaemic assessment including Fasting Glucose, HbA1c, and Urine Microalbumin.',
    specimenGuide: 'Blood Serum + EDTA Whole Blood',
    prepInstructions: '8–10 hours overnight fasting required.',
    tatEstimate: '3–6 Hours (Same Day)',
  },
  'PRO-0007': {
    titleNp: 'कार्डियाक मार्कर प्यानल (Cardiac Panel)',
    abbreviation: 'Cardiac Panel',
    safeDescription: 'High-Sensitivity Troponin I, CK-MB, CPK, and LDH myocardial biomarker evaluation.',
    specimenGuide: 'Blood Serum (Gold / Red SST Tube)',
    prepInstructions: 'STAT Emergency or Routine laboratory evaluation.',
    tatEstimate: '1–2 Hours (STAT / Same Day)',
  },
  'PRO-0008': {
    titleNp: 'इलेक्ट्रोलाइट प्यानल (Electrolytes)',
    abbreviation: 'Electrolytes',
    safeDescription: 'Serum Sodium (Na+), Potassium (K+), and Chloride (Cl-) electrolyte balance.',
    specimenGuide: 'Blood Serum (Gold / Red SST Tube)',
    prepInstructions: 'No special preparation. Avoid hemolysis.',
    tatEstimate: '2–3 Hours (Same Day)',
  },
  'CLP-0001': {
    titleNp: 'पिसाब साधारण तथा सूक्ष्मदर्शीय परीक्षण (RE/ME)',
    abbreviation: 'Urine RE/ME',
    safeDescription: 'Complete physical, chemical (pH, protein, glucose, ketones) and microscopic sediment examination.',
    specimenGuide: 'Fresh Midstream Urine (Sterile Container)',
    prepInstructions: 'Clean catch midstream sample, preferably first morning void.',
    tatEstimate: '1–2 Hours (Same Day)',
  },
  'BIO-0001': {
    titleNp: 'खाली पेटको रक्त ग्लुकोज (FBS)',
    abbreviation: 'FBS',
    safeDescription: 'Quantitative plasma glucose measurement after overnight fasting.',
    specimenGuide: 'Fluoride Plasma / Blood Serum (Grey/Gold Tube)',
    prepInstructions: '8–10 hours overnight fasting mandatory.',
    tatEstimate: '1–2 Hours (Same Day)',
  },
  'BIO-0003': {
    titleNp: 'खाना खाएपछिको रक्त ग्लुकोज (PPBS)',
    abbreviation: 'PPBS',
    safeDescription: 'Quantitative plasma glucose measurement exactly 2 hours after meal.',
    specimenGuide: 'Fluoride Plasma / Blood Serum (Grey/Gold Tube)',
    prepInstructions: 'Sample collection exactly 2 hours after starting meal.',
    tatEstimate: '1–2 Hours (Same Day)',
  },
  'BIO-0004': {
    titleNp: 'ग्लाइकेटेड हेमोग्लोबिन (HbA1c)',
    abbreviation: 'HbA1c',
    safeDescription: 'Standardized evaluation of average 2–3 months glycaemic control.',
    specimenGuide: 'EDTA Whole Blood (Lavender Top Tube)',
    prepInstructions: 'No fasting required. Any time of day.',
    tatEstimate: '2–4 Hours (Same Day)',
  },
  'BIO-0053': {
    titleNp: 'भिटामिन डी (25-OH Vitamin D Total)',
    abbreviation: 'Vit D (25-OH)',
    safeDescription: 'Quantitative measurement of Total 25-Hydroxyvitamin D [D2 + D3].',
    specimenGuide: 'Blood Serum (Gold / Red SST Tube)',
    prepInstructions: 'No special fasting required.',
    tatEstimate: '4–6 Hours (Same Day)',
  },
  'BIO-0051': {
    titleNp: 'भिटामिन बी१२ (Cyanocobalamin)',
    abbreviation: 'Vit B12',
    safeDescription: 'Quantitative measurement of Serum Vitamin B12 (Cobalamin).',
    specimenGuide: 'Blood Serum (Gold / Red SST Tube)',
    prepInstructions: 'Overnight fasting preferred. Protect from light.',
    tatEstimate: '4–6 Hours (Same Day)',
  },
  'BIO-0063': {
    titleNp: 'कार्डियाक ट्रोपोनिन (hs-cTnI)',
    abbreviation: 'hs-cTnI',
    safeDescription: 'Quantitative High-Sensitivity Cardiac Troponin I myocardial injury biomarker.',
    specimenGuide: 'Blood Serum / Plasma (Gold / Red Tube)',
    prepInstructions: 'Emergency STAT / Routine evaluation.',
    tatEstimate: '1–2 Hours (STAT / Same Day)',
  },
  'END-0001': {
    titleNp: 'थाइरोइड स्टिमुलेटिङ हर्मोन (TSH)',
    abbreviation: 'TSH',
    safeDescription: 'Ultrasensitive chemiluminescent/fluorescence thyroid stimulating hormone assay.',
    specimenGuide: 'Blood Serum (Gold / Red SST Tube)',
    prepInstructions: 'Morning sample before medication intake preferred.',
    tatEstimate: '2–4 Hours (Same Day)',
  },
  'COA-0006': {
    titleNp: 'डी-डाइमर (D-Dimer Quantitative)',
    abbreviation: 'D-Dimer',
    safeDescription: 'Quantitative fibrin degradation product D-Dimer (FEU) for coagulation assessment.',
    specimenGuide: 'Citrated Plasma (Light Blue 3.2% Citrate Tube, 9:1 ratio)',
    prepInstructions: 'Strict 9:1 blood-to-anticoagulant fill ratio required.',
    tatEstimate: '1–2 Hours (Same Day)',
  },
  'BIO-0068': {
    titleNp: 'हाई-सेन्सिटिभिटी सीआरपी (hs-CRP)',
    abbreviation: 'hs-CRP',
    safeDescription: 'Quantitative high-sensitivity C-Reactive Protein inflammatory evaluation.',
    specimenGuide: 'Blood Serum (Gold / Red SST Tube)',
    prepInstructions: 'No special preparation required.',
    tatEstimate: '2–4 Hours (Same Day)',
  },
  'IMM-VITAMINS': {
    titleNp: 'भिटामिन सुइट (Vit D & B12)',
    abbreviation: 'Vit D + B12',
    safeDescription: 'Combined assessment of 25-OH Vitamin D Total and Vitamin B12 (Cobalamin).',
    specimenGuide: 'Blood Serum (Gold / Red SST Tube)',
    prepInstructions: 'Overnight fasting preferred.',
    tatEstimate: '4–6 Hours (Same Day)',
  },
  'SER-0001': {
    titleNp: 'एच.आई.भी. र्‍यापिड स्क्रिनिङ (HIV Rapid)',
    abbreviation: 'HIV Rapid',
    safeDescription: 'Qualitative rapid screening immunochromatographic test for Human Immunodeficiency Virus.',
    specimenGuide: 'Blood Serum (Gold / Red SST Tube)',
    prepInstructions: 'No special fasting required.',
    tatEstimate: '1–2 Hours (Same Day)',
  },
  'SER-0004': {
    titleNp: 'हेपाटाइटिस बी र्‍यापिड (HBsAg Rapid)',
    abbreviation: 'HBsAg Rapid',
    safeDescription: 'Qualitative rapid screening immunochromatographic test for Hepatitis B Surface Antigen.',
    specimenGuide: 'Blood Serum (Gold / Red SST Tube)',
    prepInstructions: 'No special fasting required.',
    tatEstimate: '1–2 Hours (Same Day)',
  },
  'SER-0010': {
    titleNp: 'हेपाटाइटिस सी र्‍यापिड (HCV Rapid)',
    abbreviation: 'HCV Rapid',
    safeDescription: 'Qualitative rapid screening immunochromatographic test for Hepatitis C Virus antibodies.',
    specimenGuide: 'Blood Serum / Plasma (Gold / Red SST Tube)',
    prepInstructions: 'No special fasting required.',
    tatEstimate: '1–2 Hours (Same Day)',
  },
};

/**
 * Returns safe clinical educational info, specimen guidelines and preparation instructions.
 */
export function getSafeClinicalMeta(
  code: string,
  name: string,
  department?: string | null,
  specimen?: string | null,
  container?: string | null
): ClinicalMeta {
  if (KNOWN_CLINICAL_META[code]) {
    return KNOWN_CLINICAL_META[code];
  }

  // Generate safe generic clinical metadata based on department / naming
  const isPanel = name.toLowerCase().includes('profile') || name.toLowerCase().includes('panel') || name.toLowerCase().includes('examination');
  const cleanSpecimen = specimen || (department === 'Hematology' ? 'EDTA Whole Blood' : department === 'Clinical Pathology' ? 'Fresh Specimen' : 'Blood Serum');
  const cleanContainer = container || (cleanSpecimen.includes('EDTA') ? 'Lavender Top Tube' : cleanSpecimen.includes('Urine') ? 'Sterile Container' : 'Gold/Red SST Tube');

  return {
    titleNp: undefined,
    abbreviation: code,
    safeDescription: isPanel 
      ? `Comprehensive clinical ${name} panel evaluating standard diagnostic parameters.` 
      : `Standard laboratory investigation for ${name}.`,
    specimenGuide: `${cleanSpecimen} (${cleanContainer})`,
    prepInstructions: cleanSpecimen.toLowerCase().includes('fasting') || name.toLowerCase().includes('fasting')
      ? '8–10 hours overnight fasting recommended.'
      : 'Standard laboratory collection protocol. No special fasting unless instructed.',
    tatEstimate: 'Routine (Same Day)',
  };
}

/**
 * Checks if a search item matches a given category filter.
 */
export function matchesCategoryFilter(
  category: BillingCategoryFilter,
  item: { code: string; name: string; category?: string | null; department?: string | null }
): boolean {
  if (category.id === 'ALL') return true;

  const itemCode = (item.code || '').toUpperCase();
  const itemName = (item.name || '').toLowerCase();
  const itemDept = (item.department || '').toLowerCase();
  const itemCat = (item.category || '').toLowerCase();

  // Check code prefixes
  if (category.codePrefixes.some((p) => itemCode.startsWith(p.toUpperCase()))) {
    return true;
  }

  // Check department matches
  if (category.departments.some((d) => itemDept.includes(d.toLowerCase()) || itemCat.includes(d.toLowerCase()))) {
    return true;
  }

  // Check keyword matches in name
  if (category.keywords.some((k) => itemName.includes(k) || itemCode.includes(k.toUpperCase()))) {
    return true;
  }

  return false;
}
