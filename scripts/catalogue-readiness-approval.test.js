import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql=fs.readFileSync('supabase/migrations/00075_catalogue_readiness_approval_workflow.sql','utf8');
const ui=fs.readFileSync('src/features/catalogue/CatalogueReadinessPanel.tsx','utf8');
const bill=fs.readFileSync('src/features/billing/NewBillPage.tsx','utf8');

test('00075 is forward-only and never mutates historical clinical records',()=>{
  for(const forbidden of ['UPDATE public.clinical_order_items','UPDATE public.test_results','UPDATE public.diagnostic_reports','UPDATE public.patients','INSERT INTO public.sms_queue','report_artifacts']) assert.equal(sql.includes(forbidden),false,forbidden);
  assert.match(sql,/No patient, bill, order, result, report, SMS or R2 DML/);
});
test('inventory is authorized and contains no patient/result payload',()=>{
  assert.match(sql,/catalogue_readiness_inventory/); assert.match(sql,/catalogue_require_readiness_staff/);
  assert.match(sql,/REVOKE ALL ON public\.catalogue_service_readiness[\s\S]*FROM PUBLIC, anon, authenticated, service_role/);
});
test('approval evidence is append-only and actor attributed',()=>{
  for(const field of ['configuration_version','previous_state','new_state','source_metadata','actor_id','actor_role','created_at']) assert.ok(sql.includes(field));
  assert.match(sql,/BEFORE UPDATE OR DELETE ON public\.catalogue_configuration_evidence/);
});
test('technical review and operational catalogue activation remain guarded',()=>{
  assert.match(sql,/can_configure_catalogue_technical/);
  assert.match(sql,/catalogue_technical_update_test/);
  assert.match(sql,/catalogue_technical_update_parameter/);
  assert.match(sql,/catalogue_technical_save_range/);
  assert.match(sql,/PROTECTED_CATALOGUE_FIELD/);
  assert.match(sql,/PROTECTED_REFERENCE_RANGE_FIELD/);
  assert.match(sql,/catalogue_record_configuration_review[\s\S]*catalogue_require_readiness_staff/);
  const current=fs.readFileSync('supabase/migrations/00088_runtime_contract_gap_fixes.sql','utf8');
  assert.match(current,/catalogue_decide_readiness[\s\S]*catalogue_require_manager\(\)/);
  assert.doesNotMatch(current,/SUPER_ADMIN_APPROVAL_REQUIRED/);
});
test('approval fails closed on actionable readiness requirements',()=>{
  for(const requirement of ['Specimen and container are required','At least one active parameter','Clinically validated reference ranges are missing','Approved calculation formula/rounding configuration is missing','Method not configured']) assert.ok(sql.includes(requirement),requirement);
  assert.match(sql,/CATALOGUE_NOT_READY/);
});
test('operator-approved CBC and placeholder provenance are reconciled without duplicate active ranges',()=>{
  for(const value of ["('CBC','MPV'","('CBC','PDW'",'Explicit final CBC operator specification','Default reference interval - verify with analyzer/reagent']) assert.ok(sql.includes(value),value);
  assert.match(sql,/method TEXT,source_provenance TEXT/);
});

test('all FTFT profile ranges resolve without flattening standalone thyroid tests',()=>{
  assert.match(sql,/VALUES\(1,'FT3','FT3','FT3_VAL'\),\(2,'FT4','FT4','FT4_VAL'\),\(3,'TSH','TSH','TSH_VAL'\)/);
  assert.doesNotMatch(sql,/a\.test_code<>'THYROID_ECLIA'/);
  assert.doesNotMatch(sql,/clinical_reporting_enabled=FALSE WHERE code='THYROID_ECLIA'/);
});
test('specialist, billing-only and package classifications cannot become generic results',()=>{
  assert.match(sql,/Specialist workflow implementation is required/);
  assert.ok(sql.indexOf("('MicrobiologyCulture','MicrobiologyMicroscopy','Cytology','Histopathology','Molecular')") < sql.indexOf("p_test.reporting_type='NoReporting'"));
  assert.match(sql,/classification','CommercialPackage'/);
  assert.match(sql,/classification' NOT IN \('InHouse','OutsourceWithBimalReport'\)/);
});
test('optimistic concurrency and future-booking activation are explicit',()=>{
  assert.ok((sql.match(/CATALOGUE_CONFIGURATION_REVISION_CONFLICT/g)||[]).length>=3);
  assert.match(sql,/UPDATE public\.tests SET clinical_reporting_enabled=TRUE/);
  assert.equal(/UPDATE public\.clinical_order_items SET clinical_reporting_enabled/.test(sql),false);
});
test('UI exposes exception-driven operational status and Technician actions',()=>{
  for(const label of ['Ready & Reportable','Needs Attention','Suspended','Non-Reportable Service','Record configuration','Mark Not Reportable','Keep Ready']) assert.ok(ui.includes(label),label);
  assert.match(ui,/CAN_MANAGE_CATALOGUE/);
  assert.doesNotMatch(ui,/profile\?\.isSuperAdmin/);
  assert.match(ui,/Method not configured/);
  assert.match(ui,/Save technical configuration/);
  assert.doesNotMatch(fs.readFileSync('src/features/catalogue/CataloguePage.tsx','utf8'),/ClinicalSourceReviewPanel/);
});
test('New Bill shows all four operator-facing states',()=>{
  for(const label of ['Ready & Reportable','Non-Reportable Service','Needs Attention · Result structure','Needs Attention · Specialist workflow','Open readiness']) assert.ok(bill.includes(label),label);
  assert.match(bill,/catalogue_test_operational_state/);
});

test('model: CBC review to approval is revision-safe and old snapshots stay unchanged',()=>{
  const historical={clinical_reporting_enabled:false,reporting_type:'InHouse'};
  const service={state:'NeedsConfiguration',revision:1,enabled:false};
  const review=(expected)=>{ if(expected!==service.revision) throw new Error('CATALOGUE_CONFIGURATION_REVISION_CONFLICT'); service.revision++; };
  for(let i=0;i<6;i++) review(service.revision);
  service.state='ReadyForReview'; service.revision++;
  const stale=service.revision-1;
  assert.throws(()=>review(stale),/REVISION_CONFLICT/);
  service.state='Approved';service.enabled=true;service.revision++;
  assert.deepEqual(historical,{clinical_reporting_enabled:false,reporting_type:'InHouse'});
  assert.equal(service.enabled,true);
});
