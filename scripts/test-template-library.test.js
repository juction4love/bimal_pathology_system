import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';
const sql=fs.readFileSync('supabase/migrations/00075_catalogue_readiness_approval_workflow.sql','utf8');
const ui=fs.readFileSync('src/features/catalogue/CatalogueMasterSections.tsx','utf8');
const page=fs.readFileSync('src/features/catalogue/CataloguePage.tsx','utf8');

test('111 templates resolve through the canonical Test Database',()=>{
  assert.match(sql,/CREATE TABLE public\.catalogue_test_templates/);
  assert.match(sql,/test_database_source_order INT NOT NULL REFERENCES public\.catalogue_test_database_entries/);
  assert.match(sql,/count\(\*\) FROM public\.catalogue_test_templates\)<>111/);
  assert.doesNotMatch(sql,/INSERT INTO public\.tests[\s\S]{0,200}operator_test_templates_00075/);
});
test('template order and approved names are explicit',()=>{
  assert.match(sql,/\(1,'Hemoglobin'\)/); assert.match(sql,/\(111,'Folic Acid'\)/);
  assert.match(sql,/\(85,'Beta Human Chorionic Gonodotropin \(HCG\)'\)/);
});
test('view is human-readable and does not expose serialization',()=>{
  assert.match(ui,/Basic/); assert.match(ui,/Reference ranges/); assert.match(ui,/Method not configured/);
  assert.doesNotMatch(ui,/JSON\.stringify/); assert.doesNotMatch(ui,/>UUID</);
});
test('copy creates a private isolated draft with collision checks',()=>{
  assert.match(sql,/catalogue_start_template_copy/); assert.match(sql,/CATALOGUE_TEMPLATE_DESTINATION_COLLISION/);
  assert.match(ui,/does not copy orders, results, reports, approvals, or audit actors/);
  assert.doesNotMatch(sql,/GRANT (?:SELECT,)?INSERT.*catalogue_test_template_drafts TO authenticated/);
});
test('least privilege and panel separation remain enforced',()=>{
  assert.match(sql,/catalogue_require_readiness_staff\(\)/);
  assert.match(sql,/REVOKE ALL ON public\.catalogue_test_templates,public\.catalogue_test_template_drafts FROM PUBLIC, anon, authenticated, service_role/);
  assert.match(page,/View & Copy Library/);
  assert.doesNotMatch(sql,/catalogue_panel_components[\s\S]{0,100}catalogue_test_templates/);
});
