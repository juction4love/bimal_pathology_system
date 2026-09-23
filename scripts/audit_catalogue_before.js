import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..');
const outputDir = path.join(rootDir, 'scripts/output');

if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir, { recursive: true });
}

// Read migration 00098, 00103, 00130, 00132, 00133, 00134
const m98 = fs.readFileSync(path.join(rootDir, 'supabase/migrations_legacy_archive/00098_master_catalogue_1122_rebuild_and_convergence.sql'), 'utf8');
const m103 = fs.readFileSync(path.join(rootDir, 'supabase/migrations_legacy_archive/00103_standard_clinical_presets_library.sql'), 'utf8');
const m130 = fs.readFileSync(path.join(rootDir, 'supabase/migrations_legacy_archive/00130_focused_approved_catalogue.sql'), 'utf8');
const m132 = fs.readFileSync(path.join(rootDir, 'supabase/migrations_legacy_archive/00132_remove_structural_panel_parameters.sql'), 'utf8');
const m133 = fs.readFileSync(path.join(rootDir, 'supabase/migrations_legacy_archive/00133_catalogue_configuration_expansion.sql'), 'utf8');
const m134 = fs.readFileSync(path.join(rootDir, 'supabase/migrations_legacy_archive/00134_p0_lab_approved_configuration.sql'), 'utf8');

// Parse all tests from 00098
const testBlocks = m98.split("INSERT INTO public.tests (");
const allTests = new Map();

for (let i = 1; i < testBlocks.length; i++) {
  const block = testBlocks[i];
  const codeMatch = block.match(/VALUES \(\s*'([^']+)',\s*'([^']+)',\s*'([^']*)',\s*'([^']+)',\s*'([^']+)',\s*'([^']+)',\s*'([^']+)',\s*'([^']*)',\s*'([^']*)',\s*'([^']*)',\s*'([^']*)',\s*'([^']*)',\s*'([^']*)'/);
  if (!codeMatch) continue;

  const [_, code, name, shortName, dept, subdept, cat, testType, spec, cont, contType, sampleType, method, unit] = codeMatch;
  const notesMatch = block.match(/notes,\s*price_paisa[\s\S]*?'([^']*)',\s*\d+/);
  const notes = notesMatch ? notesMatch[1] : '';

  allTests.set(code, {
    code,
    name,
    shortName,
    dept,
    subdept,
    cat,
    testType,
    sampleType: sampleType || spec,
    method,
    unit,
    notes,
    parameters: [],
    components: []
  });

  // Extract parameters in this block
  const pMatches = block.matchAll(/INSERT INTO public\.parameters \([^)]+\)\s*VALUES \(v_test_id,\s*'([^']+)',\s*'([^']+)',\s*(?:'([^']*)'|NULL),\s*'([^']+)',\s*(\d+),\s*(TRUE|FALSE),\s*(TRUE|FALSE)\)/g);
  for (const pm of pMatches) {
    allTests.get(code).parameters.push({
      code: pm[1],
      name: pm[2],
      unit: pm[3] || null,
      value_type: pm[4],
      display_order: parseInt(pm[5]),
      is_mandatory: pm[6] === 'TRUE',
      is_active: pm[7] === 'TRUE'
    });
  }
}

console.log(`Total tests parsed from 00098: ${allTests.size}`);

// Parse panel components from 00098
const panelCompBlocks = m98.matchAll(/SELECT id INTO v_panel_id FROM public\.tests WHERE code = '([^']+)';[\s\S]*?(?=(?:SELECT id INTO v_panel_id|COMMIT|\Z))/g);
for (const pb of panelCompBlocks) {
  const panelCode = pb[1];
  const panelTest = allTests.get(panelCode);
  if (!panelTest) continue;
  const compMatches = pb[0].matchAll(/SELECT id INTO v_comp_id FROM public\.tests WHERE code = '([^']+)';\s*IF v_comp_id IS NOT NULL THEN\s*INSERT INTO public\.catalogue_panel_components \([^)]+\)\s*VALUES \(v_panel_id, v_panel_id, v_comp_id, (\d+), (TRUE|FALSE), '([^']+)'\)/g);
  for (const cm of compMatches) {
    panelTest.components.push({
      component_code: cm[1],
      display_order: parseInt(cm[2]),
      is_required: cm[3] === 'TRUE',
      component_role: cm[4]
    });
  }
}

// Parse 00130 specific overrides (Widal, CBC, KFT, Lipid, Urine)
// SER-0024 Widal in 00130 has 4 parameters
const widalTest = allTests.get('SER-0024');
if (widalTest) {
  widalTest.parameters = [
    { code: 'SER-0024-01', name: 'Salmonella Typhi O', value_type: 'Qualitative', unit: 'Titer', display_order: 1, is_mandatory: true, is_active: true },
    { code: 'SER-0024-02', name: 'Salmonella Typhi H', value_type: 'Qualitative', unit: 'Titer', display_order: 2, is_mandatory: true, is_active: true },
    { code: 'SER-0024-03', name: 'Salmonella Paratyphi AH', value_type: 'Qualitative', unit: 'Titer', display_order: 3, is_mandatory: true, is_active: true },
    { code: 'SER-0024-04', name: 'Salmonella Paratyphi BH', value_type: 'Qualitative', unit: 'Titer', display_order: 4, is_mandatory: true, is_active: true }
  ];
}

// Parse 00134 P0 overrides (15 tests)
const p0Codes = ['BIO-0141', 'IMM-0093', 'SER-0089', 'END-0056', 'END-0057', 'END-0058', 'END-0059', 'END-0060', 'END-0061', 'END-0062', 'END-0063', 'END-0064', 'END-0065', 'POC-0002', 'SPC-0007'];
for (const p0 of p0Codes) {
  const t = allTests.get(p0);
  if (!t) continue;
  if (p0 === 'BIO-0141') {
    t.parameters = [{ code: 'BIO-0141-01', name: 'Cystatin C', value_type: 'Numeric', unit: 'mg/L', display_order: 1, is_mandatory: true, is_active: true }];
  } else if (p0 === 'IMM-0093') {
    t.parameters = [{ code: 'IMM-0093-01', name: 'Interleukin-6 (IL-6)', value_type: 'Numeric', unit: 'pg/mL', display_order: 1, is_mandatory: true, is_active: true }];
  } else if (p0 === 'SER-0089') {
    t.parameters = [
      { code: 'SER-0089-01', name: 'Scrub Typhus IgM', value_type: 'Numeric', unit: 'Index', display_order: 1, is_mandatory: true, is_active: true },
      { code: 'SER-0089-02', name: 'Scrub Typhus IgG', value_type: 'Numeric', unit: 'Index', display_order: 2, is_mandatory: true, is_active: true }
    ];
  } else if (p0 === 'END-0056') {
    t.parameters = [
      { code: 'END-0056-01', name: 'Fasting Glucose (0 min)', value_type: 'Numeric', unit: 'mg/dL', display_order: 1, is_mandatory: true, is_active: true },
      { code: 'END-0056-02', name: '1-Hour Glucose (60 min)', value_type: 'Numeric', unit: 'mg/dL', display_order: 2, is_mandatory: true, is_active: true },
      { code: 'END-0056-03', name: '2-Hour Glucose (120 min)', value_type: 'Numeric', unit: 'mg/dL', display_order: 3, is_mandatory: true, is_active: true }
    ];
  } else if (p0 === 'END-0057') {
    t.parameters = [
      { code: 'END-0057-01', name: 'Fasting Glucose (0 min)', value_type: 'Numeric', unit: 'mg/dL', display_order: 1, is_mandatory: true, is_active: true },
      { code: 'END-0057-02', name: '1-Hour Glucose (60 min)', value_type: 'Numeric', unit: 'mg/dL', display_order: 2, is_mandatory: true, is_active: true },
      { code: 'END-0057-03', name: '2-Hour Glucose (120 min)', value_type: 'Numeric', unit: 'mg/dL', display_order: 3, is_mandatory: true, is_active: true }
    ];
  } else if (p0 === 'END-0058') {
    t.parameters = [{ code: 'END-0058-01', name: '1-Hour Post-50g Glucose', value_type: 'Numeric', unit: 'mg/dL', display_order: 1, is_mandatory: true, is_active: true }];
  } else if (p0 === 'END-0059') {
    t.parameters = [
      { code: 'END-0059-01', name: 'Baseline Cortisol (8 AM)', value_type: 'Numeric', unit: 'µg/dL', display_order: 1, is_mandatory: false, is_active: true },
      { code: 'END-0059-02', name: 'Post-1mg Dex Cortisol (8 AM)', value_type: 'Numeric', unit: 'µg/dL', display_order: 2, is_mandatory: true, is_active: true }
    ];
  } else if (p0 === 'END-0060') {
    t.parameters = [
      { code: 'END-0060-01', name: 'Baseline Cortisol (Day 0, 8 AM)', value_type: 'Numeric', unit: 'µg/dL', display_order: 1, is_mandatory: true, is_active: true },
      { code: 'END-0060-02', name: 'Day 2 Cortisol (8 AM)', value_type: 'Numeric', unit: 'µg/dL', display_order: 2, is_mandatory: true, is_active: true },
      { code: 'END-0060-03', name: '24h Urine Free Cortisol (Day 2)', value_type: 'Numeric', unit: 'µg/24h', display_order: 3, is_mandatory: false, is_active: true }
    ];
  } else if (p0 === 'END-0061') {
    t.parameters = [
      { code: 'END-0061-01', name: 'Baseline Cortisol (8 AM)', value_type: 'Numeric', unit: 'µg/dL', display_order: 1, is_mandatory: true, is_active: true },
      { code: 'END-0061-02', name: 'Post-8mg Dex Cortisol (8 AM)', value_type: 'Numeric', unit: 'µg/dL', display_order: 2, is_mandatory: true, is_active: true },
      { code: 'END-0061-03', name: 'Suppression Percentage', value_type: 'Calculated', unit: '%', display_order: 3, is_mandatory: true, is_active: true }
    ];
  } else if (p0 === 'END-0062') {
    t.parameters = [
      { code: 'END-0062-01', name: 'Baseline Cortisol (0 min)', value_type: 'Numeric', unit: 'µg/dL', display_order: 1, is_mandatory: true, is_active: true },
      { code: 'END-0062-02', name: 'Cortisol 30 min Post-Synacthen', value_type: 'Numeric', unit: 'µg/dL', display_order: 2, is_mandatory: true, is_active: true },
      { code: 'END-0062-03', name: 'Cortisol 60 min Post-Synacthen', value_type: 'Numeric', unit: 'µg/dL', display_order: 3, is_mandatory: true, is_active: true }
    ];
  } else if (p0 === 'END-0063') {
    t.parameters = [
      { code: 'END-0063-01', name: 'Fasting GH (0 min)', value_type: 'Numeric', unit: 'ng/mL', display_order: 1, is_mandatory: true, is_active: true },
      { code: 'END-0063-02', name: 'GH 30 min Post-Glucose', value_type: 'Numeric', unit: 'ng/mL', display_order: 2, is_mandatory: true, is_active: true },
      { code: 'END-0063-03', name: 'GH 60 min Post-Glucose', value_type: 'Numeric', unit: 'ng/mL', display_order: 3, is_mandatory: true, is_active: true },
      { code: 'END-0063-04', name: 'GH 90 min Post-Glucose', value_type: 'Numeric', unit: 'ng/mL', display_order: 4, is_mandatory: true, is_active: true },
      { code: 'END-0063-05', name: 'GH 120 min Post-Glucose', value_type: 'Numeric', unit: 'ng/mL', display_order: 5, is_mandatory: true, is_active: true }
    ];
  } else if (p0 === 'END-0064') {
    t.parameters = [
      { code: 'END-0064-01', name: 'Baseline GH (0 min)', value_type: 'Numeric', unit: 'ng/mL', display_order: 1, is_mandatory: true, is_active: true },
      { code: 'END-0064-02', name: 'GH 30 min Post-Stimulation', value_type: 'Numeric', unit: 'ng/mL', display_order: 2, is_mandatory: true, is_active: true },
      { code: 'END-0064-03', name: 'GH 60 min Post-Stimulation', value_type: 'Numeric', unit: 'ng/mL', display_order: 3, is_mandatory: true, is_active: true },
      { code: 'END-0064-04', name: 'GH 90 min Post-Stimulation', value_type: 'Numeric', unit: 'ng/mL', display_order: 4, is_mandatory: true, is_active: true },
      { code: 'END-0064-05', name: 'GH 120 min Post-Stimulation', value_type: 'Numeric', unit: 'ng/mL', display_order: 5, is_mandatory: true, is_active: true }
    ];
  } else if (p0 === 'END-0065') {
    t.parameters = [
      { code: 'END-0065-01', name: 'Baseline Urine Osmolality', value_type: 'Numeric', unit: 'mOsm/kg', display_order: 1, is_mandatory: true, is_active: true },
      { code: 'END-0065-02', name: 'Baseline Plasma Osmolality', value_type: 'Numeric', unit: 'mOsm/kg', display_order: 2, is_mandatory: true, is_active: true },
      { code: 'END-0065-03', name: 'Baseline Serum Sodium', value_type: 'Numeric', unit: 'mmol/L', display_order: 3, is_mandatory: true, is_active: true },
      { code: 'END-0065-04', name: 'Post-Deprivation Urine Osmolality', value_type: 'Numeric', unit: 'mOsm/kg', display_order: 4, is_mandatory: true, is_active: true },
      { code: 'END-0065-05', name: 'Post-DDAVP Urine Osmolality', value_type: 'Numeric', unit: 'mOsm/kg', display_order: 5, is_mandatory: true, is_active: true }
    ];
  } else if (p0 === 'POC-0002') {
    t.parameters = [
      { code: 'POC-0002-01', name: 'pH (Venous)', value_type: 'Numeric', unit: 'pH units', display_order: 1, is_mandatory: true, is_active: true },
      { code: 'POC-0002-02', name: 'pvCO2 (Venous pCO2)', value_type: 'Numeric', unit: 'mmHg', display_order: 2, is_mandatory: true, is_active: true },
      { code: 'POC-0002-03', name: 'pvO2 (Venous pO2)', value_type: 'Numeric', unit: 'mmHg', display_order: 3, is_mandatory: true, is_active: true },
      { code: 'POC-0002-04', name: 'HCO3- (Venous Bicarbonate)', value_type: 'Numeric', unit: 'mmol/L', display_order: 4, is_mandatory: true, is_active: true },
      { code: 'POC-0002-05', name: 'Base Excess (Venous)', value_type: 'Numeric', unit: 'mmol/L', display_order: 5, is_mandatory: true, is_active: true },
      { code: 'POC-0002-06', name: 'Venous Oxygen Saturation (SvO2)', value_type: 'Numeric', unit: '%', display_order: 6, is_mandatory: true, is_active: true },
      { code: 'POC-0002-07', name: 'Lactate (Venous)', value_type: 'Numeric', unit: 'mmol/L', display_order: 7, is_mandatory: false, is_active: true }
    ];
  } else if (p0 === 'SPC-0007') {
    t.parameters = [
      { code: 'SPC-0007-01', name: 'Organic Acid Profile Interpretation', value_type: 'Text', unit: null, display_order: 1, is_mandatory: true, is_active: true },
      { code: 'SPC-0007-02', name: 'Diagnostic Impression / Referral Note', value_type: 'Text', unit: null, display_order: 2, is_mandatory: false, is_active: true }
    ];
  }
}

// Evaluate BEFORE state:
// A test is unresolved if:
// 1. It is a panel/profile but has 0 components AND 0 active non-dummy parameters, OR
// 2. It is a single test and has 0 active non-dummy parameters.
const missingBefore = [];

function isReportableParam(p, testCode) {
  if (!p || !p.is_active) return false;
  const unit = (p.unit || '').trim().toLowerCase();
  if (unit === 'panel') return false;
  const valType = (p.value_type || '').trim().toLowerCase();
  if (valType === 'panel' || valType === 'profile') return false;
  return true;
}

for (const [code, t] of allTests.entries()) {
  const activeParams = t.parameters.filter(p => isReportableParam(p, code));
  const hasComponents = t.components.length > 0;

  if (activeParams.length === 0 && !hasComponents) {
    missingBefore.push({
      test_code: code,
      test_name: t.name,
      department: t.dept,
      test_type: t.testType,
      current_parameter_count: t.parameters.length,
      active_parameter_count: activeParams.length,
      component_count: t.components.length,
      notes: t.notes,
      unresolved_reason: 'ZERO_REPORTABLE_PARAMETERS_AND_ZERO_COMPONENTS'
    });
  }
}

console.log(`Unresolved tests BEFORE fix: ${missingBefore.length}`);

// Write catalogue_missing_parameters_before.csv
function csvEscape(val) {
  if (val === null || val === undefined) return '""';
  const str = String(val);
  if (str.includes(',') || str.includes('"') || str.includes('\n')) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return `"${str}"`;
}

const headersBefore = Object.keys(missingBefore[0] || { test_code: '', test_name: '', department: '', test_type: '', current_parameter_count: 0, active_parameter_count: 0, component_count: 0, notes: '', unresolved_reason: '' });
fs.writeFileSync(
  path.join(outputDir, 'catalogue_missing_parameters_before.csv'),
  [
    headersBefore.map(csvEscape).join(','),
    ...missingBefore.map(r => headersBefore.map(h => csvEscape(r[h])).join(','))
  ].join('\n'),
  'utf8'
);

console.log('Written scripts/output/catalogue_missing_parameters_before.csv');
