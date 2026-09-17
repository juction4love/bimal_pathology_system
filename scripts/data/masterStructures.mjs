// Complete list of all departments, canonical names, alias dictionaries, and master catalogue processor

// Standardized Department taxonomy
export const DEPARTMENTS = [
  { id: 1, code: 'HEMATOLOGY', name: 'Hematology', display_order: 1 },
  { id: 2, code: 'COAGULATION', name: 'Coagulation', display_order: 2 },
  { id: 3, code: 'BIOCHEMISTRY', name: 'Clinical Biochemistry', display_order: 3 },
  { id: 4, code: 'ENDOCRINOLOGY', name: 'Endocrinology', display_order: 4 },
  { id: 5, code: 'TUMOR_MARKERS', name: 'Tumor Markers', display_order: 5 },
  { id: 6, code: 'IMMUNOLOGY', name: 'Immunology', display_order: 6 },
  { id: 7, code: 'ALLERGY', name: 'Allergy', display_order: 7 },
  { id: 8, code: 'SEROLOGY', name: 'Serology / Infectious Disease', display_order: 8 },
  { id: 9, code: 'MICROBIOLOGY', name: 'Microbiology', display_order: 9 },
  { id: 10, code: 'CLINICAL_PATHOLOGY', name: 'Clinical Pathology', display_order: 10 },
  { id: 11, code: 'HISTOPATHOLOGY', name: 'Histopathology', display_order: 11 },
  { id: 12, code: 'CYTOLOGY', name: 'Cytology', display_order: 12 },
  { id: 13, code: 'MOLECULAR', name: 'Molecular Diagnostics', display_order: 13 },
  { id: 14, code: 'GENETICS', name: 'Genetics / Cytogenetics', display_order: 14 },
  { id: 15, code: 'TOXICOLOGY', name: 'Toxicology / TDM', display_order: 15 },
  { id: 16, code: 'SPECIAL_CHEMISTRY', name: 'Special Chemistry', display_order: 16 },
  { id: 17, code: 'PROFILES', name: 'Profiles / Packages', display_order: 17 },
  { id: 18, code: 'POINT_OF_CARE', name: 'Point of Care / Blood Gas', display_order: 18 },
];

// Reusable Panel Component mappings
export const PANEL_DEFINITIONS = {
  'HEM-0001': { // Complete Blood Count (CBC)
    name: 'Complete Blood Count (CBC)',
    components: [
      { code: 'HEM-0002', name: 'Hemoglobin (Hb)', order: 1, required: true },
      { code: 'HEM-0004', name: 'RBC Count', order: 2, required: true },
      { code: 'HEM-0003', name: 'Hematocrit (HCT/PCV)', order: 3, required: true },
      { code: 'HEM-0007', name: 'MCV', order: 4, required: true, calculated: true },
      { code: 'HEM-0008', name: 'MCH', order: 5, required: true, calculated: true },
      { code: 'HEM-0009', name: 'MCHC', order: 6, required: true, calculated: true },
      { code: 'HEM-0010', name: 'RDW-CV', order: 7, required: true },
      { code: 'HEM-0011', name: 'RDW-SD', order: 8, required: false },
      { code: 'HEM-0005', name: 'WBC Count / TLC', order: 9, required: true },
      { code: 'HEM-0015', name: 'Neutrophil %', order: 10, required: true },
      { code: 'HEM-0016', name: 'Lymphocyte %', order: 11, required: true },
      { code: 'HEM-0017', name: 'Monocyte %', order: 12, required: true },
      { code: 'HEM-0018', name: 'Eosinophil %', order: 13, required: true },
      { code: 'HEM-0019', name: 'Basophil %', order: 14, required: true },
      { code: 'HEM-0020', name: 'Absolute Neutrophil Count', order: 15, required: false, calculated: true },
      { code: 'HEM-0021', name: 'Absolute Lymphocyte Count', order: 16, required: false, calculated: true },
      { code: 'HEM-0022', name: 'Absolute Eosinophil Count', order: 17, required: false, calculated: true },
      { code: 'HEM-0006', name: 'Platelet Count', order: 18, required: true },
      { code: 'HEM-0012', name: 'MPV', order: 19, required: false },
      { code: 'HEM-0013', name: 'PDW', order: 20, required: false },
      { code: 'HEM-0014', name: 'PCT (Plateletcrit)', order: 21, required: false },
    ]
  },
  'PRO-0001': { // Liver Function Test (LFT)
    name: 'Liver Function Test (LFT)',
    components: [
      { code: 'BIO-0017', name: 'Total Bilirubin', order: 1, required: true },
      { code: 'BIO-0018', name: 'Direct Bilirubin', order: 2, required: true },
      { code: 'BIO-0019', name: 'Indirect Bilirubin', order: 3, required: true, calculated: true },
      { code: 'BIO-0020', name: 'AST (SGOT)', order: 4, required: true },
      { code: 'BIO-0021', name: 'ALT (SGPT)', order: 5, required: true },
      { code: 'BIO-0022', name: 'Alkaline Phosphatase (ALP)', order: 6, required: true },
      { code: 'BIO-0013', name: 'Total Protein', order: 7, required: true },
      { code: 'BIO-0014', name: 'Albumin', order: 8, required: true },
      { code: 'BIO-0015', name: 'Globulin', order: 9, required: true, calculated: true },
      { code: 'BIO-0016', name: 'A/G Ratio', order: 10, required: true, calculated: true },
      { code: 'BIO-0023', name: 'GGT', order: 11, required: false },
    ]
  },
  'PRO-0002': { // Renal Function Test (RFT/KFT)
    name: 'Renal Function Test (RFT/KFT)',
    components: [
      { code: 'BIO-0008', name: 'Urea', order: 1, required: true },
      { code: 'BIO-0009', name: 'Blood Urea Nitrogen (BUN)', order: 2, required: false, calculated: true },
      { code: 'BIO-0010', name: 'Creatinine', order: 3, required: true },
      { code: 'BIO-0011', name: 'eGFR', order: 4, required: false, calculated: true },
      { code: 'BIO-0012', name: 'Uric Acid', order: 5, required: true },
      { code: 'BIO-0037', name: 'Sodium', order: 6, required: true },
      { code: 'BIO-0038', name: 'Potassium', order: 7, required: true },
      { code: 'BIO-0039', name: 'Chloride', order: 8, required: true },
    ]
  },
  'PRO-0003': { // Lipid Profile
    name: 'Lipid Profile',
    components: [
      { code: 'BIO-0027', name: 'Total Cholesterol', order: 1, required: true },
      { code: 'BIO-0028', name: 'Triglycerides', order: 2, required: true },
      { code: 'BIO-0029', name: 'HDL Cholesterol', order: 3, required: true },
      { code: 'BIO-0031', name: 'LDL Cholesterol, Calculated', order: 4, required: true, calculated: true },
      { code: 'BIO-0032', name: 'VLDL Cholesterol', order: 5, required: true, calculated: true },
      { code: 'BIO-0033', name: 'Non-HDL Cholesterol', order: 6, required: true, calculated: true },
    ]
  },
  'PRO-0004': { // Thyroid Profile
    name: 'Thyroid Profile',
    components: [
      { code: 'END-0001', name: 'TSH', order: 1, required: true },
      { code: 'END-0002', name: 'Free T4 (FT4)', order: 2, required: true },
      { code: 'END-0003', name: 'Free T3 (FT3)', order: 3, required: true },
    ]
  },
  'PRO-0005': { // Iron Profile
    name: 'Iron Profile',
    components: [
      { code: 'BIO-0045', name: 'Iron', order: 1, required: true },
      { code: 'BIO-0046', name: 'TIBC', order: 2, required: true },
      { code: 'BIO-0047', name: 'UIBC', order: 3, required: false, calculated: true },
      { code: 'BIO-0049', name: 'Transferrin Saturation', order: 4, required: true, calculated: true },
      { code: 'BIO-0050', name: 'Ferritin', order: 5, required: true },
    ]
  },
  'PRO-0006': { // Diabetes Profile
    name: 'Diabetes Profile',
    components: [
      { code: 'BIO-0001', name: 'Glucose, Fasting', order: 1, required: true },
      { code: 'BIO-0003', name: 'Glucose, Postprandial 2 hr', order: 2, required: true },
      { code: 'BIO-0006', name: 'HbA1c', order: 3, required: true },
    ]
  },
  'PRO-0007': { // Cardiac Marker Panel
    name: 'Cardiac Marker Panel',
    components: [
      { code: 'BIO-0063', name: 'Troponin I, High Sensitivity', order: 1, required: true },
      { code: 'BIO-0061', name: 'CK-MB Mass', order: 2, required: true },
      { code: 'BIO-0065', name: 'Myoglobin', order: 3, required: false },
    ]
  },
  'PRO-0008': { // Electrolyte Panel
    name: 'Electrolyte Panel',
    components: [
      { code: 'BIO-0037', name: 'Sodium', order: 1, required: true },
      { code: 'BIO-0038', name: 'Potassium', order: 2, required: true },
      { code: 'BIO-0039', name: 'Chloride', order: 3, required: true },
      { code: 'BIO-0040', name: 'Bicarbonate / Total CO2', order: 4, required: true },
    ]
  },
  'PRO-0009': { // Bone Mineral Profile
    name: 'Bone Mineral Profile',
    components: [
      { code: 'BIO-0041', name: 'Calcium, Total', order: 1, required: true },
      { code: 'BIO-0043', name: 'Phosphorus', order: 2, required: true },
      { code: 'BIO-0022', name: 'Alkaline Phosphatase (ALP)', order: 3, required: true },
      { code: 'BIO-0053', name: 'Vitamin D, 25-OH', order: 4, required: true },
      { code: 'END-0011', name: 'PTH, Intact', order: 5, required: true },
    ]
  },
  'PRO-0014': { // Coagulation Screen
    name: 'Coagulation Screen',
    components: [
      { code: 'COA-0001', name: 'Prothrombin Time (PT)', order: 1, required: true },
      { code: 'COA-0002', name: 'INR', order: 2, required: true, calculated: true },
      { code: 'COA-0003', name: 'Activated Partial Thromboplastin Time (APTT)', order: 3, required: true },
    ]
  },
  'CLP-0001': { // Urine Routine Examination (RE/ME)
    name: 'Urine Routine Examination (RE/ME)',
    components: [
      { code: 'CLP-0002', name: 'Urine Color', order: 1, required: true },
      { code: 'CLP-0003', name: 'Urine Appearance', order: 2, required: true },
      { code: 'CLP-0004', name: 'Urine Specific Gravity', order: 3, required: true },
      { code: 'CLP-0005', name: 'Urine pH', order: 4, required: true },
      { code: 'CLP-0006', name: 'Urine Protein, Dipstick', order: 5, required: true },
      { code: 'CLP-0007', name: 'Urine Glucose, Dipstick', order: 6, required: true },
      { code: 'CLP-0008', name: 'Urine Ketone', order: 7, required: true },
      { code: 'CLP-0009', name: 'Urine Blood/Hemoglobin', order: 8, required: true },
      { code: 'CLP-0010', name: 'Urine Bilirubin', order: 9, required: true },
      { code: 'CLP-0011', name: 'Urine Urobilinogen', order: 10, required: true },
      { code: 'CLP-0012', name: 'Urine Nitrite', order: 11, required: true },
      { code: 'CLP-0013', name: 'Urine Leukocyte Esterase', order: 12, required: true },
      { code: 'CLP-0014', name: 'Urine RBC Microscopy', order: 13, required: true },
      { code: 'CLP-0015', name: 'Urine WBC/Pus Cells', order: 14, required: true },
      { code: 'CLP-0016', name: 'Urine Epithelial Cells', order: 15, required: true },
      { code: 'CLP-0017', name: 'Urine Casts', order: 16, required: false },
      { code: 'CLP-0018', name: 'Urine Crystals', order: 17, required: false },
      { code: 'CLP-0019', name: 'Urine Bacteria', order: 18, required: false },
    ]
  },
  'CLP-0021': { // Stool Routine Examination
    name: 'Stool Routine Examination',
    components: [
      { code: 'CLP-0022', name: 'Stool Color', order: 1, required: true },
      { code: 'CLP-0023', name: 'Stool Consistency', order: 2, required: true },
      { code: 'CLP-0024', name: 'Stool Mucus', order: 3, required: true },
      { code: 'CLP-0025', name: 'Stool Occult Blood', order: 4, required: true },
      { code: 'CLP-0028', name: 'Stool Reducing Substance', order: 5, required: false },
      { code: 'CLP-0032', name: 'Stool Ova & Parasite Examination', order: 6, required: true },
      { code: 'CLP-0033', name: 'Stool RBC', order: 7, required: true },
      { code: 'CLP-0034', name: 'Stool WBC/Pus Cells', order: 8, required: true },
    ]
  },
  'CLP-0038': { // Semen Analysis
    name: 'Semen Analysis',
    components: [
      { code: 'CLP-0039', name: 'Semen Volume', order: 1, required: true },
      { code: 'CLP-0040', name: 'Semen pH', order: 2, required: true },
      { code: 'CLP-0041', name: 'Sperm Concentration', order: 3, required: true },
      { code: 'CLP-0042', name: 'Total Sperm Count', order: 4, required: true, calculated: true },
      { code: 'CLP-0043', name: 'Progressive Motility', order: 5, required: true },
      { code: 'CLP-0044', name: 'Non-progressive Motility', order: 6, required: true },
      { code: 'CLP-0045', name: 'Immotile Sperm', order: 7, required: true },
      { code: 'CLP-0046', name: 'Normal Morphology', order: 8, required: true },
      { code: 'CLP-0047', name: 'Sperm Vitality', order: 9, required: true },
      { code: 'CLP-0048', name: 'Round Cells', order: 10, required: false },
    ]
  },
  'POC-0001': { // Arterial Blood Gas (ABG)
    name: 'Arterial Blood Gas (ABG)',
    components: [
      { code: 'POC-0003', name: 'pH, Blood Gas', order: 1, required: true },
      { code: 'POC-0004', name: 'pCO2, Blood Gas', order: 2, required: true },
      { code: 'POC-0005', name: 'pO2, Blood Gas', order: 3, required: true },
      { code: 'POC-0006', name: 'HCO3-, Blood Gas', order: 4, required: true, calculated: true },
      { code: 'POC-0007', name: 'Base Excess', order: 5, required: true, calculated: true },
      { code: 'POC-0008', name: 'Oxygen Saturation, Blood Gas', order: 6, required: true },
      { code: 'POC-0009', name: 'Lactate, Blood Gas', order: 7, required: false },
    ]
  },
};
