import fs from 'node:fs';

const content = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');

const councellRows = [
  "('80051f74-7015-42da-af5b-3d91a0b20824'::UUID, 'COUNCELL_23_EXCEL', 'GRAN_ABS', 'Absolute Granulocyte Count (3-Part GRAN#)', 'HEM-0001', 'GRAN_ABS', 'ANALYZER_CALCULATED', 'Analyzer Differential GRAN#', '10^9/L', '3-Part', FALSE)",
  "('1f2f379b-7a1d-48c3-a9c8-54535e83c30a'::UUID, 'COUNCELL_23_EXCEL', 'GRAN_PERCENT', 'Granulocyte % (Neutrophils/Eos/Baso)', 'HEM-0001', 'GRAN_PERCENT', 'DIRECT_MEASURED', 'Electrical Impedance (Large cell cluster)', '%', '3-Part', FALSE)",
  "('60db7b77-573f-443b-8c43-50089440e0c5'::UUID, 'COUNCELL_23_EXCEL', 'HCT', 'Hematocrit (HCT/PCV)', 'HEM-0001', 'HCT', 'ANALYZER_CALCULATED', 'Analyzer Calculated HCT', '%', 'Not Applicable', FALSE)",
  "('3ac33bf3-d809-4001-9aae-61febdd5712e'::UUID, 'COUNCELL_23_EXCEL', 'HGB', 'Hemoglobin (HGB)', 'HEM-0001', 'HGB', 'DIRECT_MEASURED', 'Cyanide-free Colorimetry', 'g/dL', 'Not Applicable', FALSE)",
  "('b4c2bf01-42f8-46bb-9457-fd134762c3dc'::UUID, 'COUNCELL_23_EXCEL', 'LYM_ABS', 'Absolute Lymphocyte Count (3-Part LYM#)', 'HEM-0001', 'LYM_ABS', 'ANALYZER_CALCULATED', 'Analyzer Differential LYM#', '10^9/L', '3-Part', FALSE)",
  "('d604ab6b-b4ca-432c-9591-98d3d8e75aad'::UUID, 'COUNCELL_23_EXCEL', 'LYM_PERCENT', 'Lymphocyte % (3-Part)', 'HEM-0001', 'LYM_PERCENT', 'DIRECT_MEASURED', 'Electrical Impedance (Small cell cluster)', '%', '3-Part', FALSE)",
  "('7d34dad1-d431-47ab-bc7e-ed5884557ec5'::UUID, 'COUNCELL_23_EXCEL', 'MCH', 'Mean Corpuscular Hemoglobin (MCH)', 'HEM-0001', 'MCH', 'ANALYZER_CALCULATED', 'Analyzer Calculated MCH', 'pg', 'Not Applicable', FALSE)",
  "('477fa01e-ab93-4636-a3de-6df3d4bf5741'::UUID, 'COUNCELL_23_EXCEL', 'MCHC', 'Mean Corpuscular Hemoglobin Conc. (MCHC)', 'HEM-0001', 'MCHC', 'ANALYZER_CALCULATED', 'Analyzer Calculated MCHC', 'g/dL', 'Not Applicable', FALSE)",
  "('46e9ab94-db4c-4ae0-a267-53a2b9ecd587'::UUID, 'COUNCELL_23_EXCEL', 'MCV', 'Mean Corpuscular Volume (MCV)', 'HEM-0001', 'MCV', 'ANALYZER_DERIVED', 'Derived from RBC histogram peak', 'fL', 'Not Applicable', FALSE)",
  "('2524931d-04a9-4586-9667-f70f36583bc7'::UUID, 'COUNCELL_23_EXCEL', 'MID_ABS', 'Absolute Mid-Cell Count (3-Part MID#)', 'HEM-0001', 'MID_ABS', 'ANALYZER_CALCULATED', 'Analyzer Differential MID#', '10^9/L', '3-Part', FALSE)",
  "('3d63a0a7-19c2-4adc-a5e9-3c23e057ffec'::UUID, 'COUNCELL_23_EXCEL', 'MID_PERCENT', 'Mid-Cell % (Monocytes/Eos/Baso cluster)', 'HEM-0001', 'MID_PERCENT', 'DIRECT_MEASURED', 'Electrical Impedance (Mid-size cell cluster)', '%', '3-Part', FALSE)",
  "('61818bdd-e86c-48ac-a02f-144af9b8a975'::UUID, 'COUNCELL_23_EXCEL', 'MPV', 'Mean Platelet Volume (MPV)', 'HEM-0001', 'MPV', 'ANALYZER_DERIVED', 'PLT size histogram analysis', 'fL', 'Not Applicable', FALSE)",
  "('55733a1b-3a67-453c-a875-2207be07c2e3'::UUID, 'COUNCELL_23_EXCEL', 'NLR', 'Neutrophil-to-Lymphocyte Ratio (NLR)', 'HEM-0001', 'NLR', 'ANALYZER_CALCULATED', 'Analyzer Calculated NLR', 'Ratio', 'Not Applicable', FALSE)",
  "('53a36f80-3404-4edf-95e1-36cd1f9e0e54'::UUID, 'COUNCELL_23_EXCEL', 'P_LCC', 'Platelet Large Cell Count (P-LCC)', 'HEM-0001', 'P_LCC', 'ANALYZER_CALCULATED', 'Analyzer Calculated P-LCC', '10^9/L', 'Not Applicable', FALSE)",
  "('1604ed4f-fdaf-494d-9e59-320c7f3afa0b'::UUID, 'COUNCELL_23_EXCEL', 'P_LCR', 'Platelet Large Cell Ratio (P-LCR)', 'HEM-0001', 'P_LCR', 'ANALYZER_DERIVED', 'PLT histogram analysis (>12 fL)', '%', 'Not Applicable', FALSE)",
  "('422a3d23-96c2-40a0-a5d1-24502e8129ea'::UUID, 'COUNCELL_23_EXCEL', 'PCT', 'Plateletcrit (PCT)', 'HEM-0001', 'PCT', 'ANALYZER_CALCULATED', 'Analyzer Calculated PCT', '%', 'Not Applicable', FALSE)",
  "('bf7729ed-39eb-4122-9114-fa65540858b5'::UUID, 'COUNCELL_23_EXCEL', 'PDW_CV', 'Platelet Distribution Width (PDW-CV)', 'HEM-0001', 'PDW_CV', 'ANALYZER_DERIVED', 'PLT volume variation coefficient', '%', 'Not Applicable', FALSE)",
  "('ab686259-3dfa-45c1-8406-8ee3c2394a11'::UUID, 'COUNCELL_23_EXCEL', 'PDW_SD', 'Platelet Distribution Width (PDW-SD)', 'HEM-0001', 'PDW_SD', 'ANALYZER_DERIVED', 'PLT volume standard deviation', 'fL', 'Not Applicable', FALSE)",
  "('f618b769-e74f-4ee0-8ea2-1cfaaaee00b8'::UUID, 'COUNCELL_23_EXCEL', 'PLR', 'Platelet-to-Lymphocyte Ratio (PLR)', 'HEM-0001', 'PLR', 'ANALYZER_CALCULATED', 'Analyzer Calculated PLR', 'Ratio', 'Not Applicable', FALSE)",
  "('32fb1cf2-be3b-4c07-b08a-2736b42b9180'::UUID, 'COUNCELL_23_EXCEL', 'PLT', 'Platelet Count (PLT)', 'HEM-0001', 'PLT', 'DIRECT_MEASURED', 'Electrical Impedance', '10^3/µL', 'Not Applicable', FALSE)",
  "('b3f1598f-0925-45a7-96a3-76a9eec03d6d'::UUID, 'COUNCELL_23_EXCEL', 'RBC', 'Red Blood Cell Count (RBC)', 'HEM-0001', 'RBC', 'DIRECT_MEASURED', 'Electrical Impedance', '10^6/µL', 'Not Applicable', FALSE)",
  "('fb0c2f6d-3174-4b55-a0cf-84ae0df2f3ca'::UUID, 'COUNCELL_23_EXCEL', 'RDW_CV', 'RBC Distribution Width (RDW-CV)', 'HEM-0001', 'RDW_CV', 'ANALYZER_DERIVED', 'RBC volume variation coefficient', '%', 'Not Applicable', FALSE)",
  "('f261947b-117c-48c9-9486-17e923e20ec6'::UUID, 'COUNCELL_23_EXCEL', 'RDW_SD', 'RBC Distribution Width (RDW-SD)', 'HEM-0001', 'RDW_SD', 'ANALYZER_DERIVED', 'RBC histogram width at 20% height', 'fL', 'Not Applicable', FALSE)",
  "('7d21c435-0818-4712-ba2c-7b44747dbcc7'::UUID, 'COUNCELL_23_EXCEL', 'WBC', 'Total Leukocyte Count (WBC)', 'HEM-0001', 'WBC', 'DIRECT_MEASURED', 'Electrical Impedance', '10^3/µL', 'Not Applicable', FALSE)"
];

const coralabRows = [
  "('a01a0001-0000-4000-8000-000000000001'::UUID, 'CORALAB_ACE', 'ALT', 'Alanine Aminotransferase (ALT/SGPT)', 'BIO-0021', 'BIO-0021', 'DIRECT_MEASURED', 'UV Kinetic (IFCC)', 'U/L', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000002'::UUID, 'CORALAB_ACE', 'AST', 'Aspartate Aminotransferase (AST/SGOT)', 'BIO-0020', 'BIO-0020', 'DIRECT_MEASURED', 'UV Kinetic (IFCC)', 'U/L', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000003'::UUID, 'CORALAB_ACE', 'ALP', 'Alkaline Phosphatase (ALP)', 'BIO-0022', 'BIO-0022', 'DIRECT_MEASURED', 'p-NPP Kinetic (IFCC)', 'U/L', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000004'::UUID, 'CORALAB_ACE', 'TBIL', 'Total Bilirubin', 'BIO-0017', 'BIO-0017', 'DIRECT_MEASURED', 'Modified Jendrassik-Grof / DPD', 'mg/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000005'::UUID, 'CORALAB_ACE', 'DBIL', 'Direct Bilirubin', 'BIO-0018', 'BIO-0018', 'DIRECT_MEASURED', 'Modified Jendrassik-Grof / DPD', 'mg/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000006'::UUID, 'CORALAB_ACE', 'TP', 'Total Protein', 'BIO-0013', 'BIO-0013', 'DIRECT_MEASURED', 'Biuret End Point', 'g/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000007'::UUID, 'CORALAB_ACE', 'ALB', 'Albumin', 'BIO-0014', 'BIO-0014', 'DIRECT_MEASURED', 'Bromocresol Green (BCG)', 'g/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000008'::UUID, 'CORALAB_ACE', 'GGT', 'Gamma-Glutamyl Transferase (GGT)', 'BIO-0023', 'BIO-0023', 'DIRECT_MEASURED', 'Szasz Kinetic (IFCC)', 'U/L', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000009'::UUID, 'CORALAB_ACE', 'CREAT', 'Creatinine', 'BIO-0010', 'BIO-0010', 'DIRECT_MEASURED', 'Modified Jaffé Kinetic', 'mg/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000010'::UUID, 'CORALAB_ACE', 'UREA', 'Urea', 'BIO-0008', 'BIO-0008', 'DIRECT_MEASURED', 'GLDH / Urease Kinetic', 'mg/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000011'::UUID, 'CORALAB_ACE', 'URIC', 'Uric Acid', 'BIO-0012', 'BIO-0012', 'DIRECT_MEASURED', 'Uricase / POD End Point', 'mg/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000012'::UUID, 'CORALAB_ACE', 'GLU_FASTING', 'Glucose, Fasting (FBS)', 'BIO-0001', 'BIO-0001', 'DIRECT_MEASURED', 'GOD-POD End Point', 'mg/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000013'::UUID, 'CORALAB_ACE', 'GLU_PP', 'Glucose, Postprandial 2 hr (PPBS)', 'BIO-0003', 'BIO-0003', 'DIRECT_MEASURED', 'GOD-POD End Point', 'mg/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000014'::UUID, 'CORALAB_ACE', 'GLU_RANDOM', 'Glucose, Random (RBS)', 'BIO-0002', 'BIO-0002', 'DIRECT_MEASURED', 'GOD-POD End Point', 'mg/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000015'::UUID, 'CORALAB_ACE', 'CHOL', 'Total Cholesterol', 'BIO-0027', 'BIO-0027', 'DIRECT_MEASURED', 'CHOD-PAP End Point', 'mg/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000016'::UUID, 'CORALAB_ACE', 'TRIG', 'Triglycerides', 'BIO-0028', 'BIO-0028', 'DIRECT_MEASURED', 'GPO-PAP End Point', 'mg/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000017'::UUID, 'CORALAB_ACE', 'HDL', 'HDL Cholesterol', 'BIO-0029', 'BIO-0029', 'DIRECT_MEASURED', 'Direct Immunoinhibition / Detergent', 'mg/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000018'::UUID, 'CORALAB_ACE', 'LDL_DIRECT', 'LDL Cholesterol, Direct', 'BIO-0030', 'BIO-0030', 'DIRECT_MEASURED', 'Direct Clearance / Selective Detergent', 'mg/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000019'::UUID, 'CORALAB_ACE', 'CALC', 'Calcium, Total', 'BIO-0041', 'BIO-0041', 'DIRECT_MEASURED', 'Arsenazo III / O-CPC', 'mg/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000020'::UUID, 'CORALAB_ACE', 'PHOS', 'Phosphorus', 'BIO-0043', 'BIO-0043', 'DIRECT_MEASURED', 'Phosphomolybdate UV', 'mg/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000021'::UUID, 'CORALAB_ACE', 'MAG', 'Magnesium', 'BIO-0044', 'BIO-0044', 'DIRECT_MEASURED', 'Calmagite / Xylidyl Blue', 'mg/dL', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000022'::UUID, 'CORALAB_ACE', 'NA_PHOTOMETRIC', 'Sodium (Photometric)', 'BIO-0037', 'BIO-0037', 'DIRECT_MEASURED', 'Enzymatic / Colorimetric (Photometric Non-ISE)', 'mmol/L', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000023'::UUID, 'CORALAB_ACE', 'K_PHOTOMETRIC', 'Potassium (Photometric)', 'BIO-0038', 'BIO-0038', 'DIRECT_MEASURED', 'Enzymatic / Turbidimetric (Photometric Non-ISE)', 'mmol/L', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000024'::UUID, 'CORALAB_ACE', 'CL_PHOTOMETRIC', 'Chloride (Photometric)', 'BIO-0039', 'BIO-0039', 'DIRECT_MEASURED', 'Mercuric Thiocyanate (Photometric Non-ISE)', 'mmol/L', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000025'::UUID, 'CORALAB_ACE', 'CK_TOTAL', 'CK Total (Creatine Kinase)', 'BIO-0060', 'BIO-0060', 'DIRECT_MEASURED', 'CK-NAC / Modified IFCC Kinetic', 'U/L', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000026'::UUID, 'CORALAB_ACE', 'CK_MB', 'CK-MB Activity', 'BIO-0062', 'BIO-0062', 'DIRECT_MEASURED', 'Immunoinhibition Kinetic', 'U/L', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000027'::UUID, 'CORALAB_ACE', 'LDH', 'Lactate Dehydrogenase (LDH)', 'BIO-0024', 'BIO-0024', 'DIRECT_MEASURED', 'DGKC / IFCC UV Kinetic', 'U/L', 'Not Applicable', FALSE)",
  "('a01a0001-0000-4000-8000-000000000028'::UUID, 'CORALAB_ACE', 'AMYLASE', 'Amylase', 'BIO-0058', 'BIO-0058', 'DIRECT_MEASURED', 'CNP-G3 Direct Substrate', 'U/L', 'Not Applicable', FALSE)"
];

const fiacheckRows = [
  "('b01b0001-0000-4000-8000-000000000001'::UUID, 'FIACHECK', 'TSH', 'Thyroid Stimulating Hormone (TSH)', 'END-0001', 'END-0001', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'µIU/mL', 'Not Applicable', FALSE)",
  "('b01b0001-0000-4000-8000-000000000002'::UUID, 'FIACHECK', 'FT3', 'Free Triiodothyronine (FT3)', 'END-0003', 'END-0003', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'pg/mL', 'Not Applicable', FALSE)",
  "('b01b0001-0000-4000-8000-000000000003'::UUID, 'FIACHECK', 'FT4', 'Free Thyroxine (FT4)', 'END-0002', 'END-0002', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/dL', 'Not Applicable', FALSE)",
  "('b01b0001-0000-4000-8000-000000000004'::UUID, 'FIACHECK', 'TT3', 'Total Triiodothyronine (Total T3)', 'END-0005', 'END-0005', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE)",
  "('b01b0001-0000-4000-8000-000000000005'::UUID, 'FIACHECK', 'TT4', 'Total Thyroxine (Total T4)', 'END-0004', 'END-0004', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'µg/dL', 'Not Applicable', FALSE)",
  "('b01b0001-0000-4000-8000-000000000006'::UUID, 'FIACHECK', 'VIT_D', '25-OH Vitamin D', 'BIO-0053', 'BIO-0053', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE)",
  "('b01b0001-0000-4000-8000-000000000007'::UUID, 'FIACHECK', 'VIT_B12', 'Vitamin B12', 'BIO-0051', 'BIO-0051', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'pg/mL', 'Not Applicable', FALSE)",
  "('b01b0001-0000-4000-8000-000000000008'::UUID, 'FIACHECK', 'CTNI', 'Cardiac Troponin I (cTnI)', 'BIO-0063', 'BIO-0063', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE)",
  "('b01b0001-0000-4000-8000-000000000009'::UUID, 'FIACHECK', 'CKMB_MASS', 'CK-MB Mass', 'BIO-0061', 'BIO-0061', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE)",
  "('b01b0001-0000-4000-8000-000000000010'::UUID, 'FIACHECK', 'MYO', 'Myoglobin', 'BIO-0065', 'BIO-0065', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE)",
  "('b01b0001-0000-4000-8000-000000000011'::UUID, 'FIACHECK', 'NT_PROBNP', 'NT-proBNP', 'BIO-0067', 'BIO-0067', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'pg/mL', 'Not Applicable', FALSE)",
  "('b01b0001-0000-4000-8000-000000000012'::UUID, 'FIACHECK', 'D_DIMER', 'D-Dimer (FEU)', 'COA-0006', 'COA-0006', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'µg/mL FEU', 'Not Applicable', FALSE)",
  "('b01b0001-0000-4000-8000-000000000013'::UUID, 'FIACHECK', 'HS_CRP', 'High Sensitivity CRP (hs-CRP)', 'BIO-0068', 'BIO-0068', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'mg/L', 'Not Applicable', FALSE)",
  "('b01b0001-0000-4000-8000-000000000014'::UUID, 'FIACHECK', 'PCT_SEPSIS', 'Procalcitonin (PCT Sepsis)', 'PCT_SEPSIS', 'PCT_SEPSIS', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE)",
  "('b01b0001-0000-4000-8000-000000000015'::UUID, 'FIACHECK', 'B_HCG', 'Quantitative Beta-hCG', 'END-0039', 'END-0039', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'mIU/mL', 'Not Applicable', FALSE)",
  "('b01b0001-0000-4000-8000-000000000016'::UUID, 'FIACHECK', 'FERRITIN', 'Ferritin', 'BIO-0050', 'BIO-0050', 'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE)"
];

const allRows = [...councellRows, ...coralabRows, ...fiacheckRows];
console.log(`Total combined physical mappings: ${allRows.length}`);

const newValuesSql = allRows.join(',\n');

// Replace the VALUES in 00001_bimal_pathology_clean_baseline.sql
const startMarker = 'INSERT INTO public.analyzer_parameter_mappings (';
const valMarker = 'VALUES\n';
const endMarker = ') AS src(id, analyzer_code, channel_code, channel_name, test_code, param_code, measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported)';

const p1 = content.indexOf(startMarker);
const p2 = content.indexOf(valMarker, p1) + valMarker.length;
const p3 = content.indexOf(endMarker, p2);

const updatedSql = content.slice(0, p2) + newValuesSql + '\n' + content.slice(p3);
fs.writeFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', updatedSql, 'utf8');
console.log('Successfully updated 00001_bimal_pathology_clean_baseline.sql with all 68 physical analyzer mappings!');
