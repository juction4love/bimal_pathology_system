import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const csvPath = path.join(rootDir, 'approved-data', 'Bimal_Pathology_Master_Test_Catalogue_1122.csv');
const migrationPath = path.join(rootDir, 'supabase', 'migrations', '00098_master_catalogue_1122_rebuild_and_convergence.sql');

test('Master CSV exists and contains exactly 1,122 test records', () => {
  assert.ok(fs.existsSync(csvPath), 'Master CSV must exist');
  const content = fs.readFileSync(csvPath, 'utf8');
  const lines = content.trim().split('\n');
  assert.equal(lines.length, 1123, '1 header line + 1,122 test rows');
  assert.match(lines[0], /^Test Code,Department,Subdepartment,Test Name/);
});

test('Master Catalogue covers all 18 canonical departments', () => {
  const content = fs.readFileSync(csvPath, 'utf8');
  const expectedDepartments = [
    'Hematology',
    'Coagulation',
    'Clinical Biochemistry',
    'Endocrinology',
    'Tumor Markers',
    'Immunology',
    'Allergy',
    'Serology / Infectious Disease',
    'Microbiology',
    'Clinical Pathology',
    'Histopathology',
    'Cytology',
    'Molecular Diagnostics',
    'Genetics / Cytogenetics',
    'Toxicology / TDM',
    'Special Chemistry',
    'Profiles / Packages',
    'Point of Care / Blood Gas',
  ];
  for (const dept of expectedDepartments) {
    assert.ok(content.includes(dept), `Department ${dept} must be present`);
  }
});

test('Alias normalization resolves canonical single clinical entities', () => {
  const migration = fs.readFileSync(migrationPath, 'utf8');
  
  // ALT = SGPT
  assert.match(migration, /BIO-0021/);
  assert.match(migration, /'ALT'/);
  assert.match(migration, /'SGPT'/);
  
  // AST = SGOT
  assert.match(migration, /BIO-0020/);
  assert.match(migration, /'AST'/);
  assert.match(migration, /'SGOT'/);

  // FBS = Fasting Blood Sugar
  assert.match(migration, /BIO-0001/);
  assert.match(migration, /'FBS'/);
  assert.match(migration, /'Fasting Blood Sugar'/);

  // PPBS = Post Prandial Blood Sugar
  assert.match(migration, /BIO-0003/);
  assert.match(migration, /'PPBS'/);

  // CBC = Complete Blood Count
  assert.match(migration, /HEM-0001/);
  assert.match(migration, /'CBC'/);
  assert.match(migration, /'FBC'/);

  // Hb = Hemoglobin
  assert.match(migration, /HEM-0002/);
  assert.match(migration, /'Hb'/);
  assert.match(migration, /'Hemoglobin'/);
});

test('Profile and Panel relationships are properly modeled with reusable components', () => {
  const migration = fs.readFileSync(migrationPath, 'utf8');

  // CBC Panel
  assert.match(migration, /-- Panel HEM-0001/);
  assert.match(migration, /HEM-0002/); // Hb
  assert.match(migration, /HEM-0004/); // RBC
  assert.match(migration, /HEM-0005/); // WBC
  assert.match(migration, /HEM-0006/); // Platelet

  // LFT Panel
  assert.match(migration, /-- Panel PRO-0001/);
  assert.match(migration, /BIO-0017/); // Total Bilirubin
  assert.match(migration, /BIO-0018/); // Direct Bilirubin
  assert.match(migration, /BIO-0020/); // AST
  assert.match(migration, /BIO-0021/); // ALT
  assert.match(migration, /BIO-0022/); // ALP
  assert.match(migration, /BIO-0013/); // Total Protein
  assert.match(migration, /BIO-0014/); // Albumin

  // RFT/KFT Panel
  assert.match(migration, /-- Panel PRO-0002/);
  assert.match(migration, /BIO-0008/); // Urea
  assert.match(migration, /BIO-0010/); // Creatinine
  assert.match(migration, /BIO-0012/); // Uric Acid
  assert.match(migration, /BIO-0037/); // Sodium
  assert.match(migration, /BIO-0038/); // Potassium
  assert.match(migration, /BIO-0039/); // Chloride

  // Lipid Profile
  assert.match(migration, /-- Panel PRO-0003/);
  assert.match(migration, /BIO-0027/); // Total Cholesterol
  assert.match(migration, /BIO-0028/); // Triglycerides
  assert.match(migration, /BIO-0029/); // HDL
  assert.match(migration, /BIO-0031/); // LDL Calculated
  assert.match(migration, /BIO-0032/); // VLDL

  // Thyroid Profile
  assert.match(migration, /-- Panel PRO-0004/);
  assert.match(migration, /END-0001/); // TSH
  assert.match(migration, /END-0002/); // FT4
  assert.match(migration, /END-0003/); // FT3
});

test('Result data types span all required LIS clinical models', () => {
  const content = fs.readFileSync(csvPath, 'utf8');
  for (const dt of [
    'Numeric',
    'Panel',
    'PositiveNegative',
    'ReactiveNonReactive',
    'DetectedNotDetected',
    'Categorical',
    'CultureAST',
    'PathologyNarrative',
    'Calculated',
    'Microscopic'
  ]) {
    assert.ok(content.includes(dt), `Data type ${dt} must be used in the catalogue`);
  }
});

test('Validation status is default REQUIRES_VALIDATION for clinical safety', () => {
  const content = fs.readFileSync(csvPath, 'utf8');
  const lines = content.trim().split('\n').slice(1);
  for (const line of lines) {
    assert.ok(line.includes('REQUIRES LAB VALIDATION') || line.includes('REQUIRES_VALIDATION'), 'Unvalidated tests require clinical validation');
  }
});

test('Database constraints prevent duplicate aliases and self-referencing panels', () => {
  const migration = fs.readFileSync(migrationPath, 'utf8');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.test_aliases/);
  assert.match(migration, /UNIQUE\(test_id, alias_name\)/);
  assert.match(migration, /CONSTRAINT chk_panel_no_self_ref CHECK \(panel_id != component_test_id\)/);
});
