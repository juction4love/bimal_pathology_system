import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { catalogueOperationalStatus } from '../src/features/catalogue/catalogueOperationalStatus.ts';

const page = fs.readFileSync('src/features/catalogue/CataloguePage.tsx', 'utf8');
const sections = fs.readFileSync('src/features/catalogue/CatalogueMasterSections.tsx', 'utf8');
const readiness = fs.readFileSync('src/features/catalogue/CatalogueReadinessPanel.tsx', 'utf8');
const migration = fs.readFileSync('supabase/migrations_legacy_archive/00075_catalogue_readiness_approval_workflow.sql', 'utf8');

test('catalogue has the six finalized operator-facing operational sections', () => {
  for (const label of ['Test Database', 'Categories', 'Test Panels', 'Parameters / Ranges', 'Prices / Ratelist', 'Templates']) {
    assert.match(page, new RegExp(label.replaceAll('/', '\\/')));
  }
  assert.doesNotMatch(page, /<Tab[^>]+label="(?:Configuration History|Clinical catalogue readiness)"/);
  assert.match(sections, /Haematology[\s\S]*Biochemistry[\s\S]*Serology & Immunology[\s\S]*Clinical Pathology[\s\S]*Cytology[\s\S]*Microbiology[\s\S]*Endocrinology[\s\S]*Histopathology[\s\S]*Others[\s\S]*Miscellaneous/);
});

test('database category master has exactly ten canonical categories and preserves aliases', () => {
  assert.match(migration, /CANONICAL_CATEGORY_COUNT_INVALID/);
  assert.match(migration, /CREATE TABLE public\.test_category_aliases/);
  assert.match(migration, /\(1,'HEMATOLOGY','Haematology'\)[\s\S]*\(10,'MISCELLANEOUS','Miscellaneous'\)/);
  assert.match(migration, /WHEN 'Histopathology' THEN 'HISTOPATHOLOGY' WHEN 'Miscellaneous' THEN 'MISCELLANEOUS'/);
  assert.doesNotMatch(migration, /WHEN 'Miscellaneous' THEN 'GENERAL'/);
});

test('normal catalogue uses human-readable types and operational states', () => {
  for (const value of ['Single parameter', 'Multi parameter', 'Multi parameter nested', 'Document']) assert.ok(page.includes(value) || sections.includes(value));
  for (const value of ['Ready & Reportable', 'Needs Attention', 'Suspended', 'Non-Reportable Service', 'Inactive']) {
    assert.equal(catalogueOperationalStatus({ is_active: true, lifecycle_status: 'Active', reporting_type: 'InHouse', operational_state: value }), value);
  }
});

test('inactive draft tests cannot be presented as non-reportable services', () => {
  assert.match(page, /catalogue_test_operational_state/);
  assert.equal(catalogueOperationalStatus({ is_active: false, lifecycle_status: 'Draft', reporting_type: 'NoReporting', operational_state: 'Inactive' }), 'Inactive');
  assert.equal(catalogueOperationalStatus({ is_active: true, lifecycle_status: 'Active', reporting_type: 'NoReporting', operational_state: 'Needs Attention' }), 'Needs Attention');
  assert.equal(catalogueOperationalStatus({ is_active: true, lifecycle_status: 'Active', reporting_type: 'NoReporting', operational_state: 'Non-Reportable Service' }), 'Non-Reportable Service');
  assert.equal(catalogueOperationalStatus({ is_active: true, lifecycle_status: 'Active', reporting_type: 'InHouse', operational_state: 'Ready & Reportable' }), 'Ready & Reportable');
  assert.equal(catalogueOperationalStatus({ is_active: false, lifecycle_status: 'Archived', reporting_type: 'NoReporting' }), 'Inactive');
  assert.equal(catalogueOperationalStatus({ is_active: false, lifecycle_status: 'Draft', reporting_type: 'NoReporting', operational_state: 'Unexpected' }), 'Inactive');
});

test('panel composition and ratelist remain separate and data driven', () => {
  assert.match(sections, /catalogue_profile_components/);
  assert.match(sections, /health_package_components/);
  assert.match(sections, /Clinical panel composition is separate from commercial ratelist\/package linkage/);
  assert.match(sections, /Ordered component tests/);
});

test('CBC with ESR uses exactly fifteen ordered canonical components and one panel identity', () => {
  assert.match(migration, /'CBC_WITH_ESR', 'CBC with ESR'/);
  const expected = [
    'Hemoglobin','Total Leukocyte Count','Differential Leucocyte Count','Platelet Count',
    'Total RBC Count','Hematocrit Value, Hct','Mean Corpuscular Volume, MCV',
    'Mean Cell Haemoglobin, MCH','Mean Cell Haemoglobin CON, MCHC',
    'Mean Platelet Volume, MPV','R.D.W. - SD','R.D.W. - CV','P-LCR','P.D.W.',
    'Erythrocyte Sedimentation Rate (Wintrobe)',
  ];
  let previous = -1;
  expected.forEach((name, index) => {
    const marker = `'${name.replaceAll("'", "''")}', ${index + 1})`;
    const position = migration.indexOf(marker);
    assert.ok(position > previous, `${index + 1}. ${name}`);
    previous = position;
  });
  assert.match(migration, /count\(\*\) FROM public\.catalogue_panel_components WHERE panel_id=v_panel\) <> 15/);
  assert.equal((migration.match(/'CBC_WITH_ESR', 'CBC with ESR'/g) || []).length, 1);
});

test('CBC with ESR ratelist linkage is commercial and does not duplicate clinical panel', () => {
  for (const row of ["'CBC with ESR',500", "'Anemia package',100", "'Arthritis Package',100", "'Fever package',1550"]) assert.ok(migration.includes(row), row);
  assert.match(migration, /operator_rate_npr/);
  assert.match(sections, /Ratelist \/ service links/);
  assert.match(sections, /catalogue_panel_ratelist_links/);
});

test('BT & CT reuses its canonical profile and preserves two-component order', () => {
  assert.match(migration, /SELECT id INTO STRICT v_panel FROM public\.tests WHERE code='BT_CT'/);
  assert.match(migration, /'Bleeding Time',1\)[\s\S]*'Clotting Time',2\)/);
  assert.match(migration, /count\(\*\) FROM public\.catalogue_panel_components WHERE panel_id=v_panel\)<>2/);
  assert.match(migration, /VALUES\(v_panel,'BT & CT',200\)/);
});

test('BT & CT operator note is retained as readable panel content', () => {
  for (const text of [
    'The bleeding time test assesses primary hemostasis',
    '1. Thrombocytopenia',
    '4. Disorders of blood vessels',
    'Clotting time measures the time required for the blood to clot in a glass test tube kept at 37°C.',
    'Recommended test is Prothrombin Time (PT) and Activated Partial Thromboplastin time (APTT).',
  ]) assert.ok(migration.includes(text), text);
  assert.match(sections, /whiteSpace:'pre-wrap'/);
});

test('Blood Sugar Fasting & PP reuses FBS/PPBS and preserves exact order', () => {
  assert.match(migration, /'BLOOD_SUGAR_FASTING_PP','Blood Sugar Fasting & PP'/);
  assert.match(migration, /v_fbs,'Fasting Blood Sugar',1\)[\s\S]*v_ppbs,'Blood Sugar PP',2\)/);
  assert.match(migration, /'Blood Sugar Fasting & PP',100,v_package/);
  assert.match(migration, /'Diabetic package',100,NULL/);
});

test('glucose diagnostic interpretation remains panel metadata, not ranges or flags', () => {
  for (const value of ['<100','<140','100 to 125','140 to 199','Pre Diabetes','>126','>200','Diabetes']) assert.ok(migration.includes(`'${value}'`), value);
  assert.match(migration, /interpretation_rows JSONB/);
  assert.match(migration, /never promoted into parameter ranges,[\s\S]*flags, critical limits, or calculation definitions/);
  assert.match(sections, /interpretation_rows/);
  assert.match(sections, /fasting_glucose: string; pp_glucose_2h: string; diagnosis: string/);
});

test('LFT reuses its canonical profile and preserves eleven-component order', () => {
  assert.match(migration, /SELECT id INTO STRICT v_panel FROM public\.tests WHERE code='LFT'/);
  const expected = [
    'Serum Bilirubin (Total)','Serum Bilirubin (Direct)','Serum Bilirubin (Indirect)',
    'SGOT (AST)','SGPT (ALT)','SGOT/SGPT','Serum Alkaline Phosphatase','Serum Protein',
    'Serum Albumin','Globulin','A/G Ratio',
  ];
  let previous = -1;
  expected.forEach((name, index) => {
    const marker = `'${name}',${index + 1})`;
    const position = migration.indexOf(marker);
    assert.ok(position > previous, `${index + 1}. ${name}`);
    previous = position;
  });
  assert.match(migration, /count\(\*\) FROM public\.catalogue_panel_components WHERE panel_id=v_panel\)<>11/);
  assert.match(migration, /count\(DISTINCT component_parameter_id\)[\s\S]*<>11/);
});

test('LFT notes and four commercial links are preserved without panel duplication', () => {
  for (const text of [
    'Liver Function Blood Test gives an insight into your liver health',
    'Besides diagnosing liver problems, LFT’s also monitor overall liver functioning.',
    'Acute or chronic hepatitis, cirrhosis, biliary tract obstruction',
  ]) assert.ok(migration.includes(text), text);
  for (const row of [
    "'Liver Function Test (LFT)',1000", "'Fitness Package',100",
    "'Full body checkup (Female)',100", "'Full body checkup (Male)',100",
  ]) assert.ok(migration.includes(row), row);
});

test('LFT reconciliation does not invent or replace calculation formulas', () => {
  const start = migration.indexOf('-- Final operator-approved Liver Function Test panel.');
  const end = migration.indexOf('-- Approved operator panel BT & CT', start);
  const lftBlock = migration.slice(start, end);
  assert.ok(start >= 0 && end > start);
  assert.doesNotMatch(lftBlock, /INSERT INTO public\.clinical_calculation_formula_versions|UPDATE public\.clinical_calculation_formula_versions|DELETE FROM public\.clinical_calculation_formula_versions/);
  assert.match(lftBlock, /'SGOT_SGPT_RATIO','SGOT\/SGPT','Calculated'/);
});

test('operator Test Panels master consolidates all 31 panels in deterministic order', () => {
  const names = [
    'Complete Blood Count (CBC)','CBC (with absolute counts)','CBC with ESR','BT & CT',
    'Coagulation Profile','Blood Sugar Fasting & PP','Liver Function Test (LFT)',
    'Bilirubin Total, Direct & Indirect','Kidney Function Test (KFT)','KFT without eGFR',
    'Lipid Profile','Electrolytes Panel','Arthritis Profile','Protein Fraction','Torch Profile',
    'Iron Studies','AMH Panel','Viral Marker','Thyroid Function Test (TFT)',
    'Free Thyroid Function Test (FTFT)','Pcod','Urine Protein/Creatinine Ratio (UPCR)',
    'Estimated Glomerular Filtration Rate (eGFR)','CBC with Morphology','Anti-ccp',
    'Pus Culture and Sensitivity','Serum ADA','Serum Protein Electrophoresis','BRCA1 BRCA2',
    'Prolactin','CEA',
  ];
  let previous = migration.indexOf('INSERT INTO operator_panel_master_00075 VALUES');
  names.forEach((name, index) => {
    const position = migration.indexOf(`'${name}'`, previous);
    assert.ok(position > previous, `${index + 1}. ${name}`);
    previous = position;
  });
  assert.match(migration, /OPERATOR_PANEL_COUNT_INVALID/);
});

test('master reconciliation resolves every component and keeps specialist workflows safe', () => {
  assert.match(migration, /'SERUM_PROTEIN_ELECTROPHORESIS',[\s\S]*'Workflow Not Supported'/);
  assert.match(migration, /'Serum Protein Electrophoresis','SERUM_PROTEIN_ELECTROPHORESIS',NULL,NULL,NULL/);
  assert.doesNotMatch(migration, /No unambiguous canonical Serum Protein Electrophoresis test exists/);
  assert.match(migration, /'PUS_CULTURE_AND_SENSITIVITY','Pus Culture and Sensitivity'[\s\S]*FALSE,FALSE/);
  assert.match(migration, /'GENETIC_TEST','BRCA1 BRCA2'[\s\S]*FALSE,FALSE/);
  assert.match(sections, /unresolved_reason/);
  assert.match(sections, /Needs Attention · Result structure/);
  assert.match(sections, /Needs Attention · Specialist workflow/);
});

test('panel aliases reuse canonical component codes and ratelist links do not duplicate panels', () => {
  for (const mapping of [
    "'Hemoglobin','HB'", "'Total Leukocyte Count','TLC'", "'Hematocrit Value, Hct','PCV'",
    "'Platelet Count','PLT'", "'SGOT (AST)',NULL,'LFT','SGOT'",
    "'SGPT (ALT)',NULL,'LFT','SGPT'", "'Prothrombin time, PT/INR','PT_INR'",
    "'Activated partial thromboplastin time, APTT','APTT'", "'Free Thyroxine, FT4','FT4'",
  ]) assert.ok(migration.includes(mapping), mapping);
  assert.match(migration, /OPERATOR_PANEL_COMPONENT_DUPLICATE/);
  assert.match(migration, /operator_panel_rates_00075/);
});

test('CBC extends canonical composition without duplicate aliases', () => {
  assert.match(migration, /v_cbc, v_mpv, 'Measured', 15/);
  assert.match(migration, /v_cbc, v_pdw, 'Measured', 16/);
  assert.match(migration, /no duplicate Hb\/Hgb, Hct\/PCV, WBC\/TLC or PLT identities/);
  assert.doesNotMatch(migration, /INSERT INTO public\.tests[^;]+(?:'HGB'|'HCT'|'WBC')/i);
});

test('governance controls are secondary and debug payloads stay out of operational sections', () => {
  assert.doesNotMatch(page, /CatalogueReadinessPanel|Clinical catalogue readiness|Configuration queue/);
  assert.doesNotMatch(sections, /raw JSON|V1\/V2\/V3\/V4|source conflict|migration evidence/i);
  assert.doesNotMatch(page, /ClinicalSourceReviewPanel/);
  assert.match(migration, /catalogue_readiness_inventory/);
  assert.match(readiness, /Method not configured/);
});
