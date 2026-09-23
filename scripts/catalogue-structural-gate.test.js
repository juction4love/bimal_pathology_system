import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql=readFileSync('supabase/migrations_legacy_archive/00075_catalogue_readiness_approval_workflow.sql','utf8');
const catalogue=readFileSync('src/features/catalogue/CataloguePage.tsx','utf8');
const billing=readFileSync('src/features/billing/NewBillPage.tsx','utf8');

test('all panels receive exactly one first-class billing resolution',()=>{
  assert.match(sql,/catalogue_panel_identity_resolution/);
  assert.match(sql,/PANEL_SERVICE_IDENTITY_COUNT_INVALID/);
  assert.match(sql,/<>11/);
  assert.match(sql,/identity_kind='Test'/);
  assert.match(sql,/identity_kind='Panel'/);
  assert.match(sql,/identity_kind='Package'/);
});

test('panel prices are versioned and snapshots are immutable',()=>{
  for(const token of ['catalogue_rate_versions','catalogue_create_rate_version','catalogue_activate_rate','bill_panel_selections','rate_version_id']) assert.ok(sql.includes(token),token);
  assert.match(sql,/Price not specified\. A Super Admin must activate a panel rate before billing\./);
  assert.match(sql,/create_patient_bill_order_with_panel_service/);
  assert.match(billing,/create_patient_bill_order_with_panel_service/);
});

test('result readiness is deterministic and never invents qualitative assignment',()=>{
  for(const token of ['catalogue_test_result_readiness','Result Structure Incomplete','option_set_id','catalogue_option_sets','catalogue_option_values','QUALITATIVE_OPTION_SET_AUTO_ASSIGNMENT_FORBIDDEN']) assert.ok(sql.includes(token),token);
  assert.match(sql,/QUALITATIVE_OPTION_SET_AUTO_ASSIGNMENT_FORBIDDEN/);
  assert.match(sql,/value_type IN \('Select','Boolean'\)/);
});

test('technical and commercial authority remain separated',()=>{
  assert.match(sql,/catalogue_require_technical/);
  assert.match(sql,/can_configure_catalogue_technical/);
  assert.match(sql,/catalogue_create_rate_version[\s\S]*catalogue_require_manager/);
  assert.match(sql,/catalogue_save_panel[\s\S]*catalogue_require_manager/);
});

test('catalogue exposes operational sections and exception-driven status',()=>{
  for(const label of ['Test Database','Categories','Test Panels','Parameters / Result Structures','Reference Ranges','Prices / Ratelist','Templates']) assert.ok(catalogue.includes(label),label);
  for(const label of ['Reportable & Ready','Reportable · Result Structure Incomplete','Billing only · No Worklist','Specialist workflow','Inactive']) assert.ok(sql.includes(label)||catalogue.includes(label),label);
});
