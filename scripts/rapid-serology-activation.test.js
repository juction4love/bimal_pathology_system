import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const migration00113Path = path.join(rootDir, 'supabase', 'migrations_legacy_archive', '00113_activate_rapid_serology_screening_tests.sql');

test('Migration 00113 exists and defines distinct rapid serology canonical tests', () => {
  assert.ok(fs.existsSync(migration00113Path), 'Migration 00113 must exist');
  const migration = fs.readFileSync(migration00113Path, 'utf8');
  assert.match(migration, /SER-0086/, 'Must configure distinct canonical SER-0086 for HIV Rapid');
  assert.match(migration, /SER-0087/, 'Must configure distinct canonical SER-0087 for HBsAg Rapid');
  assert.match(migration, /SER-0088/, 'Must configure distinct canonical SER-0088 for HCV Rapid');
});

test('Preserves baseline canonical tests (SER-0001, SER-0004, SER-0010) completely unchanged', () => {
  const migration = fs.readFileSync(migration00113Path, 'utf8');
  
  // Must NOT rename or mutate SER-0001, SER-0004, SER-0010 in public.tests
  assert.doesNotMatch(migration, /UPDATE\s+public\.tests[\s\S]+WHERE\s+code\s*=\s*'SER-0001'/);
  assert.doesNotMatch(migration, /UPDATE\s+public\.tests[\s\S]+WHERE\s+code\s*=\s*'SER-0004'/);
  assert.doesNotMatch(migration, /UPDATE\s+public\.tests[\s\S]+WHERE\s+code\s*=\s*'SER-0010'/);
});

test('Distinct canonical rapid tests created with valid sequential codes (SER-0086, SER-0087, SER-0088)', () => {
  const migration = fs.readFileSync(migration00113Path, 'utf8');

  // SER-0086 != SER-0001
  assert.match(migration, /'SER-0086'/);
  assert.match(migration, /'HUMAN IMMUNODEFICIENCY VIRUS \(HIV\), RAPID SCREENING TEST'/);
  assert.match(migration, /'HIV Rapid'/);

  // SER-0087 != SER-0004
  assert.match(migration, /'SER-0087'/);
  assert.match(migration, /'HEPATITIS B SURFACE ANTIGEN \(HBsAg\), RAPID SCREENING TEST'/);
  assert.match(migration, /'HBsAg Rapid'/);

  // SER-0088 != SER-0010
  assert.match(migration, /'SER-0088'/);
  assert.match(migration, /'HCV RAPID SCREENING TEST'/);
  assert.match(migration, /'HCV Rapid'/);
});

test('Patient Safety: Result entry starts blank (NO default patient result value)', () => {
  const migration = fs.readFileSync(migration00113Path, 'utf8');
  
  // interpretation_config must NOT contain a default_value for rapid tests
  assert.doesNotMatch(migration, /"default_value"/, 'Must not pre-populate default patient result in parameters interpretation_config');
  assert.match(migration, /'\{"control":\s*"Select"\}'::jsonb/);
});

test('Rapid result types are controlled qualitative Select with Negative/Reactive options', () => {
  const migration = fs.readFileSync(migration00113Path, 'utf8');
  
  assert.match(migration, /'Select'/);
  assert.match(migration, /'\["Negative", "Reactive"\]'::jsonb/);
  assert.match(migration, /REACTIVE_NON_REACTIVE/);
  assert.match(migration, /'ReactiveNonReactive'/);

  // No arbitrary numeric S/CO ranges copied into rapid tests
  assert.doesNotMatch(migration, /normal_min/);
  assert.doesNotMatch(migration, /normal_max/);
});

test('Specimen governance: Serum for HIV/HBsAg Rapid without invented handling; HCV Rapid pending verification', () => {
  const migration = fs.readFileSync(migration00113Path, 'utf8');

  // Specimen = Serum for HIV and HBsAg rapid
  assert.match(migration, /'Serum'/);
  assert.match(migration, /'Container per approved laboratory SOP'/);
  
  // Specimen pending for HCV rapid
  assert.match(migration, /'Specimen Pending Validation'/);
  assert.match(migration, /'Container Pending Lab SOP'/);

  // Unsupported handling details (48h delay, SST/Plain primary tube rules) must NOT be inserted
  assert.doesNotMatch(migration, /INSERT INTO public\.assay_specimen_governance_rules/);
  assert.doesNotMatch(migration, /48\.0/);
});

test('Billing search aliases cover all mandatory search terms and keep general and rapid distinguishable', () => {
  const migration = fs.readFileSync(migration00113Path, 'utf8');

  // HIV Rapid search terms
  assert.match(migration, /'HIV Rapid'/);
  assert.match(migration, /'HIV Rapid Screening'/);
  assert.match(migration, /'HIV Screening'/);
  assert.match(migration, /'एचआईभी र्‍यापिड'/);

  // HBsAg Rapid search terms
  assert.match(migration, /'HBsAg Rapid'/);
  assert.match(migration, /'HBs Ag Rapid'/);
  assert.match(migration, /'HBsAg Rapid Screening'/);
  assert.match(migration, /'Hepatitis B Rapid'/);
  assert.match(migration, /'हेपाटाइटिस बी र्‍यापिड'/);

  // HCV Rapid search terms
  assert.match(migration, /'HCV Rapid'/);
  assert.match(migration, /'Anti-HCV Rapid'/);
  assert.match(migration, /'HCV Rapid Screening'/);
  assert.match(migration, /'Hepatitis C Rapid'/);
  assert.match(migration, /'हेपाटाइटिस सी र्‍यापिड'/);
});

test('No analyzer mappings or premature clinical approvals created', () => {
  const migration = fs.readFileSync(migration00113Path, 'utf8');
  assert.doesNotMatch(migration, /public\.analyzer_parameter_mappings/);
  assert.doesNotMatch(migration, /public\.test_analyzer_configurations/);
  assert.doesNotMatch(migration, /INSERT INTO public\.catalogue_lab_approvals/);
});

test('No unrequested combined viral panel created', () => {
  const migration = fs.readFileSync(migration00113Path, 'utf8');
  assert.doesNotMatch(migration, /INSERT INTO public\.catalogue_panels/);
  assert.doesNotMatch(migration, /PRO-VIRAL/);
});
