import fs from 'node:fs';

function readCsv(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split('\n').filter(l => l.trim().length > 0);
  const header = parseCsvLine(lines[0]);
  const rows = [];
  for (let i = 1; i < lines.length; i++) {
    const vals = parseCsvLine(lines[i]);
    const obj = {};
    for (let j = 0; j < header.length; j++) {
      obj[header[j]] = vals[j] !== undefined ? vals[j] : '';
    }
    rows.push(obj);
  }
  return rows;
}

function parseCsvLine(line) {
  const result = [];
  let current = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      if (inQuotes && line[i + 1] === '"') {
        current += '"';
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch === ',' && !inQuotes) {
      result.push(current.trim());
      current = '';
    } else {
      current += ch;
    }
  }
  result.push(current.trim());
  return result;
}

function esc(val) {
  if (val === null || val === undefined || val === '') return 'NULL';
  return `'${val.replace(/'/g, "''")}'`;
}

function escNum(val) {
  if (val === null || val === undefined || val === '' || isNaN(Number(val))) return 'NULL';
  return String(Number(val));
}

// 1. Categories
const categories = [
  { id: '50a22a24-84f3-4ec4-aa5c-65c52f9b1c29', code: 'HEMATOLOGY', name: 'Haematology', display_order: 1 },
  { id: '33e32ee7-a3d3-433f-a0b8-ed25da80db2c', code: 'BIOCHEMISTRY', name: 'Biochemistry', display_order: 2 },
  { id: '5c47a8e4-7519-44cb-b0b9-35a1f89f8971', code: 'SEROLOGY', name: 'Serology & Immunology', display_order: 3 },
  { id: 'cc8f47da-255c-4710-b970-26534098fd0c', code: 'CLINICAL_PATHOLOGY', name: 'Clinical Pathology', display_order: 4 },
  { id: '662f74e6-a41f-42fc-b23b-7dca003d5826', code: 'CYTOLOGY', name: 'Cytology', display_order: 5 },
  { id: '1f3a7368-f9be-47b6-8295-b5788e968e1c', code: 'MICROBIOLOGY', name: 'Microbiology', display_order: 6 },
  { id: '9e7ad776-49d7-4ba8-ad4a-3919f1933ec7', code: 'ENDOCRINOLOGY', name: 'Endocrinology', display_order: 7 },
  { id: 'c0e37ad8-86a2-4b9c-a18b-e25c246fe6c1', code: 'HISTOPATHOLOGY', name: 'Histopathology', display_order: 8 },
  { id: '00814b49-6fa6-4722-97c0-7d79ef7ac138', code: 'GENERAL', name: 'Others', display_order: 9 },
  { id: '2e79617b-60fb-4d7d-8c14-c371ef51d5aa', code: 'MISCELLANEOUS', name: 'Miscellaneous', display_order: 10 },
  { id: 'c4c52f77-ca6b-4e5e-9d65-25617c6c7a7d', code: 'COAGULATION', name: 'Coagulation', display_order: 45 }
];

const categoriesSql = `INSERT INTO public.test_categories (id, code, name, description, lifecycle_status, display_order) VALUES\n` +
  categories.map(c => `(${esc(c.id)}, ${esc(c.code)}, ${esc(c.name)}, NULL, 'Active'::public.catalogue_lifecycle_enum, ${c.display_order})`).join(',\n') +
  `\nON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, code = EXCLUDED.code, lifecycle_status = EXCLUDED.lifecycle_status;`;

// 2. Analyzers
const analyzersSql = `INSERT INTO public.analyzers (code, name, manufacturer, model, laboratory_location, lifecycle_status, row_version) VALUES
('COUNCELL_23_EXCEL', 'CounCell 23 Excel', 'Coral Clinical Systems / Tulip Diagnostics', 'CounCell 23 Excel', 'Hematology Laboratory', 'Active', 1),
('CORALAB_ACE', 'CORALAB ACE', 'Coral Clinical Systems / Tulip Diagnostics', 'CORALAB ACE', 'Clinical Biochemistry Laboratory', 'Active', 1),
('FIACHECK', 'FIAcheck', 'Goldsite Diagnostics / FIAcheck', 'FIAcheck-100', 'Immunology & Hormone Laboratory', 'Active', 1)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name, manufacturer = EXCLUDED.manufacturer, model = EXCLUDED.model,
    laboratory_location = EXCLUDED.laboratory_location, lifecycle_status = 'Active';`;

// 3. Tests
const tests = readCsv('scripts/output/final_master_catalogue_after.csv');
const rates = readCsv('scripts/output/final_master_rates.csv');
const ratesMap = new Map(rates.map(r => [r.test_code, r]));

// Default category ID map
const categoryMap = {
  'Hematology': '50a22a24-84f3-4ec4-aa5c-65c52f9b1c29',
  'Haematology': '50a22a24-84f3-4ec4-aa5c-65c52f9b1c29',
  'Biochemistry': '33e32ee7-a3d3-433f-a0b8-ed25da80db2c',
  'Clinical Biochemistry': '33e32ee7-a3d3-433f-a0b8-ed25da80db2c',
  'Serology': '5c47a8e4-7519-44cb-b0b9-35a1f89f8971',
  'Serology & Immunology': '5c47a8e4-7519-44cb-b0b9-35a1f89f8971',
  'Immunology': '5c47a8e4-7519-44cb-b0b9-35a1f89f8971',
  'Clinical Pathology': 'cc8f47da-255c-4710-b970-26534098fd0c',
  'Cytology': '662f74e6-a41f-42fc-b23b-7dca003d5826',
  'Microbiology': '1f3a7368-f9be-47b6-8295-b5788e968e1c',
  'Endocrinology': '9e7ad776-49d7-4ba8-ad4a-3919f1933ec7',
  'Histopathology': 'c0e37ad8-86a2-4b9c-a18b-e25c246fe6c1',
  'Coagulation': 'c4c52f77-ca6b-4e5e-9d65-25617c6c7a7d'
};

const testValues = tests.map(t => {
  const rate = ratesMap.get(t.test_code);
  const pricePaisa = rate ? parseInt(rate.active_rate_paisa || '0', 10) : 0;
  const isPriceConfigured = pricePaisa > 0;
  const categoryId = categoryMap[t.clinical_domain] || categoryMap[t.category] || '00814b49-6fa6-4722-97c0-7d79ef7ac138';
  let method = t.method || 'Standard Clinical Laboratory Protocol';
  if (t.test_code === 'BIO-0019') method = 'Calculated: Total Bilirubin - Direct Bilirubin';
  
  return `(${esc(t.test_id)}, ${esc(t.test_code)}, ${esc(t.test_name)}, ${esc(t.test_code)}, ${esc(t.clinical_domain)}, ${esc(t.category)}, ${esc(categoryId)}, 'InHouse'::public.reporting_type_enum, NULL, ${pricePaisa}, ${esc(t.specimen || 'Blood / Serum')}, 'Plain/SST / appropriate tube', ${esc(method)}, 24, NULL, TRUE, 0, ${t.component_count !== '0' ? "'Panel'" : "'Single'"}, ${esc(t.workflow_type || 'Routine')}, ${esc(t.reporting_model || 'NUMERIC_SINGLE_ANALYTE')}, TRUE, TRUE, ${isPriceConfigured ? 'TRUE' : 'FALSE'}, 'Fixed', 'Active')`;
});

const testsSql = `INSERT INTO public.tests (
    id, code, name, short_name, department, category, category_id,
    reporting_type, outsource_lab_name, price_paisa, sample_type, container,
    method, tat_hours, interpretation_template, is_active, display_order,
    test_type, workflow_type, reporting_model, clinical_reporting_enabled,
    billing_enabled, price_configured, pricing_policy, lifecycle_status
) VALUES\n` + testValues.join(',\n') + `\nON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name, code = EXCLUDED.code, department = EXCLUDED.department,
    category = EXCLUDED.category, category_id = EXCLUDED.category_id,
    price_paisa = EXCLUDED.price_paisa, sample_type = EXCLUDED.sample_type,
    method = EXCLUDED.method, is_active = TRUE, lifecycle_status = 'Active',
    reporting_model = EXCLUDED.reporting_model, clinical_reporting_enabled = TRUE,
    billing_enabled = TRUE;`;

// 4. Parameters
const params = readCsv('scripts/output/final_master_parameters.csv');
const paramValues = params.map(p => {
  let valType = p.value_type || 'Numeric';
  let formula = p.formula ? esc(p.formula) : 'NULL';
  let calcId = 'NULL';
  
  if (p.test_code === 'BIO-0019') {
    valType = 'Calculated';
    formula = "'TBIL - DBIL'";
    calcId = "'LFT_IBIL_V1'";
  } else if (p.parameter_code === 'BIO-0015' || p.test_code === 'BIO-0015') {
    valType = 'Calculated';
    formula = "'TP - ALB'";
    calcId = "'LFT_GLOBULIN_V1'";
  } else if (p.parameter_code === 'BIO-0016' || p.test_code === 'BIO-0016') {
    valType = 'Calculated';
    formula = "'ALB / GLOB'";
    calcId = "'LFT_AG_RATIO_V1'";
  } else if (p.parameter_code === 'BIO-0031' || p.test_code === 'BIO-0031') {
    valType = 'Calculated';
    formula = "'CHOL - HDL - (TRIG / 5)'";
    calcId = "'LIPID_LDL_CALCULATED_V1'";
  } else if (p.parameter_code === 'BIO-0032' || p.test_code === 'BIO-0032') {
    valType = 'Calculated';
    formula = "'TRIG / 5'";
    calcId = "'LIPID_VLDL_V1'";
  } else if (p.parameter_code === 'BIO-0009' || p.test_code === 'BIO-0009') {
    valType = 'Calculated';
    formula = "'UREA / 2.14'";
    calcId = "'RFT_BUN_V1'";
  }

  const optionsJson = p.options ? `'${p.options.replace(/'/g, "''")}'::JSONB` : 'NULL';

  return `(${esc(p.parameter_id)}, ${esc(p.test_id)}, ${esc(p.parameter_code)}, ${esc(p.parameter_name)}, '${valType}'::public.parameter_value_type_enum, ${esc(p.unit)}, ${optionsJson}, ${formula}, NULL, ${calcId}, ${p.display_order || 1}, TRUE, TRUE, 'Active', 'Configured', NULL)`;
});

const paramsSql = `INSERT INTO public.parameters (
    id, test_id, code, name, value_type, unit, options,
    formula, formula_dependencies, calculation_identifier,
    display_order, is_mandatory, is_active, lifecycle_status,
    clinical_configuration_status, interpretation_config
) VALUES\n` + paramValues.join(',\n') + `\nON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name, code = EXCLUDED.code, value_type = EXCLUDED.value_type,
    unit = EXCLUDED.unit, options = EXCLUDED.options, formula = EXCLUDED.formula,
    calculation_identifier = EXCLUDED.calculation_identifier,
    display_order = EXCLUDED.display_order, is_mandatory = EXCLUDED.is_mandatory,
    is_active = TRUE, lifecycle_status = 'Active', clinical_configuration_status = 'Configured';`;

// 5. Reference Ranges
const rules = readCsv('scripts/output/final_master_reference_rules.csv');
const rangeValues = rules.map(r => {
  return `(${esc(r.rule_id)}, ${esc(r.parameter_id)}, ${esc(r.gender || 'All')}, ${r.age_min_days || 0}, ${r.age_max_days || 43800}, ${escNum(r.normal_min)}, ${escNum(r.normal_max)}, ${escNum(r.critical_low)}, ${escNum(r.critical_high)}, ${esc(r.normal_text)}, ${esc(r.unit)}, ${esc(r.reference_source || 'APPROVED_LIS_CONFIG')}, TRUE, TRUE, 'Active', 'ClinicallyValidated', CURRENT_DATE)`;
});

const rangesSql = `INSERT INTO public.reference_ranges (
    id, parameter_id, gender, age_min_days, age_max_days,
    normal_min, normal_max, critical_low, critical_high,
    normal_text, unit, method, is_approved, is_active,
    lifecycle_status, validation_state, effective_from
) VALUES\n` + rangeValues.join(',\n') + `\nON CONFLICT (id) DO UPDATE SET
    normal_min = EXCLUDED.normal_min, normal_max = EXCLUDED.normal_max,
    critical_low = EXCLUDED.critical_low, critical_high = EXCLUDED.critical_high,
    normal_text = EXCLUDED.normal_text, unit = EXCLUDED.unit, method = EXCLUDED.method,
    is_approved = TRUE, is_active = TRUE, lifecycle_status = 'Active', validation_state = 'ClinicallyValidated';`;

// 6. Panel Components (from legacy migration 00098 / 00135)
const legacy0098 = fs.readFileSync('supabase/migrations_legacy_archive/00098_master_catalogue_1122_rebuild_and_convergence.sql', 'utf8');
const compStart = legacy0098.indexOf('INSERT INTO public.catalogue_panel_components');
const compEnd = legacy0098.indexOf(';', compStart);
const compsSql = legacy0098.slice(compStart, compEnd + 1);

// 7. Analyzer Mappings (68 verified channels)
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
]

const allAnalyzerMappings = [...councellRows, ...coralabRows, ...fiacheckRows];

const analyzerMappingsSql = `INSERT INTO public.analyzer_parameter_mappings (
    id, analyzer_id, channel_code, channel_name, test_id, parameter_id,
    measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
)
SELECT
    src.id, a.id, src.channel_code, src.channel_name, t.id, p.id,
    src.measurement_type, src.analytical_method, src.unit, src.differential_type,
    src.is_automated_5part_supported
FROM (
    VALUES
${allAnalyzerMappings.join(',\n')}
) AS src(id, analyzer_code, channel_code, channel_name, test_code, param_code, measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported)
JOIN public.analyzers a ON a.code = src.analyzer_code
LEFT JOIN public.tests t ON t.code = src.test_code
LEFT JOIN public.parameters p ON p.test_id = t.id AND (p.code = src.param_code OR p.code = src.channel_code)
ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
    test_id = EXCLUDED.test_id,
    parameter_id = EXCLUDED.parameter_id,
    measurement_type = EXCLUDED.measurement_type,
    analytical_method = EXCLUDED.analytical_method,
    unit = EXCLUDED.unit;`;

// 8. Rate Versions (125 approved rates)
const approvedRates = rates.filter(r => r.rate_status === 'APPROVED');
const rateValues = approvedRates.map((r, i) => {
  return `(gen_random_uuid(), (SELECT id FROM public.tests WHERE code = ${esc(r.test_code)}), 1, ${r.active_rate_paisa}, 'Approved Master Rate', CURRENT_DATE, 'Active', TRUE)`;
});

const ratesSql = `INSERT INTO public.catalogue_rate_versions (
    id, test_id, version_number, amount_paisa, reason, effective_from, status, is_approved
)
SELECT
    src.id, t.id, src.version_number, src.amount_paisa, src.reason, src.effective_from::DATE, src.status::public.catalogue_lifecycle_enum, src.is_approved
FROM (
    VALUES
${approvedRates.map(r => `(gen_random_uuid(), ${esc(r.test_code)}, 1, ${r.active_rate_paisa}, 'Approved Master Rate', CURRENT_DATE, 'Active', TRUE)`).join(',\n')}
) AS src(id, test_code, version_number, amount_paisa, reason, effective_from, status, is_approved)
JOIN public.tests t ON t.code = src.test_code
ON CONFLICT DO NOTHING;`;

// Assemble master seed block
const masterSeedSql = `
-- ============================================================================
-- 6. AUTHORITATIVE MASTER SEED DATA
-- ============================================================================

${categoriesSql}

${analyzersSql}

${testsSql}

${paramsSql}

${rangesSql}

${compsSql}

${analyzerMappingsSql}

${ratesSql}
`;

// Extract clean DDL and functions from current baseline
const baseline = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');
const ddlAndFuncs = baseline.slice(0, baseline.indexOf('-- ============================================================================\n-- 6. MASTER SEED DATA')).trim();

const finalBaseline = `${ddlAndFuncs}\n\n${masterSeedSql.trim()}\n\nCOMMIT;\n`;

fs.writeFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', finalBaseline, 'utf8');
console.log('Successfully written pristine 00001_bimal_pathology_clean_baseline.sql!');
