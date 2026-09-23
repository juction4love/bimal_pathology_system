import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..');

// Let's parse all migrations to see what tests, parameters, panel components, and reference ranges are defined
const m98 = fs.readFileSync(path.join(rootDir, 'supabase/migrations_legacy_archive/00098_master_catalogue_1122_rebuild_and_convergence.sql'), 'utf8');
const m103 = fs.readFileSync(path.join(rootDir, 'supabase/migrations_legacy_archive/00103_standard_clinical_presets_library.sql'), 'utf8');
const m130 = fs.readFileSync(path.join(rootDir, 'supabase/migrations_legacy_archive/00130_focused_approved_catalogue.sql'), 'utf8');
const m132 = fs.readFileSync(path.join(rootDir, 'supabase/migrations_legacy_archive/00132_remove_structural_panel_parameters.sql'), 'utf8');
const m133 = fs.readFileSync(path.join(rootDir, 'supabase/migrations_legacy_archive/00133_catalogue_configuration_expansion.sql'), 'utf8');
const m134 = fs.readFileSync(path.join(rootDir, 'supabase/migrations_legacy_archive/00134_p0_lab_approved_configuration.sql'), 'utf8');

// Parse tests in 00098
const testRegex = /INSERT INTO public\.tests \([^)]+\) VALUES \(\s*'([^']+)',\s*'([^']+)',\s*'([^']*)',\s*'([^']+)',\s*'([^']+)',\s*'([^']+)',\s*'([^']+)',\s*'([^']*)',\s*'([^']*)',\s*'([^']*)',\s*'([^']*)',\s*'([^']*)',\s*'([^']*)'/g;

const tests = new Map();
let match;
while ((match = testRegex.exec(m98)) !== null) {
  const [_, code, name, shortName, dept, subdept, cat, testType, spec, cont, contType, sampleType, method, unit] = match;
  tests.set(code, {
    code,
    name,
    dept,
    cat,
    testType,
    sampleType: sampleType || spec,
    method,
    unit,
    parameters: [],
    components: []
  });
}

console.log(`Found ${tests.size} tests in 00098 migration.`);

// Parse parameters in 00098
// Format: VALUES (v_test_id, 'PARAM_CODE', 'PARAM_NAME', 'UNIT', 'VALUE_TYPE', ORDER, MANDATORY, ACTIVE)
const paramRegex = /VALUES \(v_test_id,\s*'([^']+)',\s*'([^']+)',\s*(?:'([^']*)'|NULL),\s*'([^']+)',\s*(\d+),\s*(TRUE|FALSE),\s*(TRUE|FALSE)\)/g;
// We need to match with test context in 00098
// Let's split 00098 by 'INSERT INTO public.tests'
const blocks = m98.split("INSERT INTO public.tests (");
for (let i = 1; i < blocks.length; i++) {
  const block = blocks[i];
  const codeMatch = block.match(/VALUES \(\s*'([^']+)'/);
  if (!codeMatch) continue;
  const testCode = codeMatch[1];
  const t = tests.get(testCode);
  if (!t) continue;

  const pMatches = block.matchAll(/INSERT INTO public\.parameters \([^)]+\)\s*VALUES \(v_test_id,\s*'([^']+)',\s*'([^']+)',\s*(?:'([^']*)'|NULL),\s*'([^']+)',\s*(\d+),\s*(TRUE|FALSE),\s*(TRUE|FALSE)\)/g);
  for (const pm of pMatches) {
    t.parameters.push({
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

// Parse panel components in 00098
const panelCompBlocks = m98.matchAll(/SELECT id INTO v_panel_id FROM public\.tests WHERE code = '([^']+)';[\s\S]*?(?=(?:SELECT id INTO v_panel_id|COMMIT|\Z))/g);
for (const pb of panelCompBlocks) {
  const panelCode = pb[1];
  const panelTest = tests.get(panelCode);
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

console.log('Profiles with components in 00098:');
for (const [code, t] of tests.entries()) {
  if (t.components.length > 0) {
    console.log(`  ${code} (${t.name}): ${t.components.length} components -> ${t.components.map(c => c.component_code).join(', ')}`);
  }
}

// Check how 00132 affects parameters
let archivedCount = 0;
let activeParamCount = 0;
for (const [code, t] of tests.entries()) {
  for (const p of t.parameters) {
    const isArchivedBy132 = (p.unit && p.unit.toLowerCase() === 'panel') ||
      (p.value_type && (p.value_type.toLowerCase() === 'panel' || p.value_type.toLowerCase() === 'profile')) ||
      (p.code === code && (p.unit?.toLowerCase() === 'panel' || p.name === t.name));
    
    // In 00133:
    // Non-panel leaf params are activated.
    // Panel dummy params remain archived.
    if ((p.unit && p.unit.toLowerCase() === 'panel') ||
        (p.value_type && (p.value_type.toLowerCase() === 'panel' || p.value_type.toLowerCase() === 'profile'))) {
      p.current_active = false;
      archivedCount++;
    } else {
      p.current_active = true;
      activeParamCount++;
    }
  }
}

console.log(`Total parameters across catalogue: active=${activeParamCount}, archived_dummy=${archivedCount}`);

// Find tests with 0 active parameters AND 0 components
const missingReporting = [];
const profileTests = [];
const singleParamTests = [];
const multiParamTests = [];

for (const [code, t] of tests.entries()) {
  const activeParams = t.parameters.filter(p => p.current_active);
  if (t.components.length > 0) {
    profileTests.push(t);
  } else if (activeParams.length === 0) {
    missingReporting.push(t);
  } else if (activeParams.length === 1) {
    singleParamTests.push(t);
  } else {
    multiParamTests.push(t);
  }
}

console.log(`Summary of 1122 tests:`);
console.log(`  Profile tests with child components: ${profileTests.length}`);
console.log(`  Single-parameter tests: ${singleParamTests.length}`);
console.log(`  Multi-parameter tests: ${multiParamTests.length}`);
console.log(`  Tests with 0 active parameters & 0 components: ${missingReporting.length}`);

if (missingReporting.length > 0) {
  console.log('Tests with 0 active parameters & 0 components:');
  for (const t of missingReporting) {
    console.log(`  ${t.code}: ${t.name} (dept: ${t.dept}, type: ${t.testType}, params: ${JSON.stringify(t.parameters)})`);
  }
}
