import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync('supabase/migrations/00075_catalogue_readiness_approval_workflow.sql','utf8');
const sections=fs.readFileSync('src/features/catalogue/CatalogueMasterSections.tsx','utf8');

test('TM256 becomes a clean ordered operational Test Database',()=>{
  assert.match(migration,/CREATE TABLE public\.catalogue_test_database_entries/);
  assert.match(migration,/source_order INT PRIMARY KEY CHECK\(source_order BETWEEN 1 AND 256\)/);
  assert.match(migration,/TEST_DATABASE_256_ORDER_ASSERTION_FAILED/);
  assert.match(sections,/Master Test Database/);
  for(const heading of ['Order','Test Name','Test Type','Short Name','Category','Operational Status','Actions']) assert.ok(sections.includes(heading),heading);
});

test('all four operator-facing types and canonical categories are preserved',()=>{
  for(const type of ['Single parameter','Multi parameter','Multi parameter nested','Document']) assert.ok(migration.includes(`'${type}'`)||sections.includes(`'${type}'`),type);
  for(const mapping of ["'Haematology' THEN 'HEMATOLOGY'","'Biochemistry' THEN 'BIOCHEMISTRY'","'Serology & Immunology' THEN 'SEROLOGY'","'Clinical Pathology' THEN 'CLINICAL_PATHOLOGY'","'Cytology' THEN 'CYTOLOGY'","'Microbiology' THEN 'MICROBIOLOGY'","'Endocrinology' THEN 'ENDOCRINOLOGY'"]) assert.ok(migration.includes(mapping),mapping);
});

test('profile-only aliases reuse canonical parameters instead of duplicate tests',()=>{
  for(const mapping of [
    "(10,'BT_CT','BLEEDING_TIME')","(18,'CBC','MCV')","(49,'LFT','TBIL')",
    "(62,'LIPID_PROFILE','VLDL')","(69,'KFT','BUN_CREAT_RATIO')",
    "(80,'LFT','AG_RATIO')","(130,'KFT','EGFR_CATEGORY')","(137,'LFT','SGOT_SGPT_RATIO')",
  ]) assert.ok(migration.includes(mapping),mapping);
  assert.match(sections,/Master Test Database/);
  assert.doesNotMatch(migration,/INSERT INTO public\.tests[^;]+(?:'HGB'|'HCT'|'WBC')/i);
});

test('derived identities are structural only and no formula is invented',()=>{
  for(const code of ['LDL_HDL_RATIO','TC_HDL_RATIO','TG_HDL_RATIO','NON_HDL','EGFR_CATEGORY','UREA_CREAT_RATIO','BUN_CREAT_RATIO']) assert.ok(migration.includes(`'${code}'`),code);
  const start=migration.indexOf('-- Operator-approved Test Database identities');
  const end=migration.indexOf('-- Consolidated operator Test Panels master',start);
  assert.doesNotMatch(migration.slice(start,end),/clinical_calculation_formula_versions/);
});

test('Test Database is active-user read-only and technician configuration remains narrow',()=>{
  assert.match(migration,/ALTER TABLE public\.catalogue_test_database_entries ENABLE ROW LEVEL SECURITY/);
  assert.match(migration,/REVOKE ALL ON public\.catalogue_test_database_entries FROM PUBLIC, anon, authenticated, service_role/);
  assert.match(migration,/GRANT SELECT ON public\.catalogue_test_database_entries TO authenticated/);
  assert.match(migration,/catalogue_test_database_staff_read[\s\S]*public\.is_active_user\(\)/);
  assert.match(sections,/canConfigure/);
});
