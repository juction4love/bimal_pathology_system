import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration116 = fs.readFileSync('supabase/migrations_legacy_archive/00116_remove_catalogue_readiness_workflow_blocks.sql', 'utf8');
const billingSearch = fs.readFileSync('src/features/billing/BillingCatalogueSearch.tsx', 'utf8');
const adminDashboard = fs.readFileSync('src/features/dashboard/DashboardPage.tsx', 'utf8');
const techDashboard = fs.readFileSync('src/features/dashboard/TechnicianDashboard.tsx', 'utf8');
const patientOrderWorklist = fs.readFileSync('src/features/dashboard/PatientOrderWorklist.tsx', 'utf8');
const sampleAccessioning = fs.readFileSync('src/features/samples/SampleAccessioningPage.tsx', 'utf8');
const worklistPage = fs.readFileSync('src/features/worklist/WorklistPage.tsx', 'utf8');
const worklistQuery = fs.readFileSync('src/features/worklist/worklistQuery.ts', 'utf8');
const resultEntryPage = fs.readFileSync('src/features/worklist/ResultEntryPage.tsx', 'utf8');
const reportsPage = fs.readFileSync('src/features/reports/ReportsPage.tsx', 'utf8');
const cataloguePage = fs.readFileSync('src/features/catalogue/CataloguePage.tsx', 'utf8');

test('1. Migration 00116 drops validation constraints and opens all reportable investigations', () => {
  assert.match(migration116, /ALTER TABLE public\.tests DROP CONSTRAINT IF EXISTS chk_tests_reporting_requires_validated;/);
  assert.match(migration116, /ALTER TABLE public\.tests DROP CONSTRAINT IF EXISTS chk_tests_active_requires_validated;/);
  assert.match(migration116, /ALTER TABLE public\.tests DROP CONSTRAINT IF EXISTS chk_tests_billing_requires_validated;/);

  assert.match(migration116, /UPDATE public\.tests\s+SET clinical_reporting_enabled = TRUE,\s+is_active = TRUE,\s+billing_enabled = TRUE\s+WHERE reporting_type IN \('InHouse', 'OutsourceWithBimalReport'\);/);
});

test('2. Guard result write trigger and save_test_results allow all InHouse and OutsourceWithBimalReport tests', () => {
  assert.match(migration116, /CREATE OR REPLACE FUNCTION public\.guard_clinical_result_write\(\)/);
  assert.match(migration116, /reporting_type IN \('InHouse', 'OutsourceWithBimalReport'\)/);

  // Result entry does not check validation_status = 'VALIDATED'
  const saveResultsBody = migration116.slice(migration116.indexOf('save_test_results_unversioned_internal'));
  const saveResultsFunc = saveResultsBody.slice(0, saveResultsBody.indexOf('$$;'));
  assert.doesNotMatch(saveResultsFunc, /validation_status/);
});

test('3. check_order_report_readiness does not block report readiness on unvalidated status', () => {
  const readinessBody = migration116.slice(migration116.indexOf('check_order_report_readiness'));
  const readinessFunc = readinessBody.slice(0, readinessBody.indexOf('$$;'));
  assert.doesNotMatch(readinessFunc, /unval_items/);
  assert.match(readinessFunc, /'unvalidated_count',\s*0/);
});

test('4. Materialize report group item and readiness check include all InHouse and OutsourceWithBimalReport tests', () => {
  assert.match(migration116, /IF NOT FOUND OR NEW\.reporting_type = 'NoReporting' THEN RETURN NEW; END IF;/);
  assert.match(migration116, /WHERE gi\.report_group_id=p_report_group_id AND oi\.reporting_type IN \('InHouse', 'OutsourceWithBimalReport'\);/);
});

test('5. Search laboratory worklist includes all reportable investigations without readiness blocking', () => {
  assert.match(migration116, /WHERE coi\.reporting_type IN \('InHouse','OutsourceWithBimalReport'\)/);
  assert.doesNotMatch(migration116, /coi\.clinical_reporting_enabled = TRUE/);
});

test('6. isReportableWorklistItem helper checks reporting_type without requiring clinical_reporting_enabled', () => {
  assert.match(worklistQuery, /\['InHouse', 'OutsourceWithBimalReport'\]\.includes\(item\.reporting_type\)/);
  assert.doesNotMatch(worklistQuery, /item\.clinical_reporting_enabled === true/);
});

test('7. No "Requires Clinical Validation" or "Reporting Blocked" UI badges in operational screens', () => {
  const operationalFiles = [
    { name: 'BillingCatalogueSearch', content: billingSearch },
    { name: 'DashboardPage', content: adminDashboard },
    { name: 'TechnicianDashboard', content: techDashboard },
    { name: 'PatientOrderWorklist', content: patientOrderWorklist },
    { name: 'SampleAccessioningPage', content: sampleAccessioning },
    { name: 'WorklistPage', content: worklistPage },
    { name: 'ResultEntryPage', content: resultEntryPage },
    { name: 'ReportsPage', content: reportsPage },
  ];

  for (const { name, content } of operationalFiles) {
    assert.doesNotMatch(content, /Requires Clinical Validation/, `${name} should not contain "Requires Clinical Validation"`);
    assert.doesNotMatch(content, /Reporting Blocked/, `${name} should not contain "Reporting Blocked"`);
  }
});

test('8. Specimen Pending Validation is not used as a workflow blocker in accessioning or worklist', () => {
  assert.doesNotMatch(worklistPage, /item\.sample\?\.specimen_type === 'Specimen Pending Validation'/);
  assert.doesNotMatch(sampleAccessioning, /sample\.specimen_type === 'Specimen Pending Validation'/);
});

test('9. ResultEntryPage does not block saving or verification on validation_status or clinical_reporting_enabled', () => {
  assert.doesNotMatch(resultEntryPage, /orderItem\?\.validation_status === 'REQUIRES_VALIDATION'/);
  assert.doesNotMatch(resultEntryPage, /orderItem\?\.test\?\.validation_status === 'REQUIRES_VALIDATION'/);
  assert.doesNotMatch(resultEntryPage, /orderItem\?\.clinical_reporting_enabled === false/);
  assert.doesNotMatch(resultEntryPage, /orderItem\?\.test\?\.clinical_reporting_enabled === false/);
});

test('10. CataloguePage does not block activating tests on validation_status', () => {
  assert.doesNotMatch(cataloguePage, /status === 'Active' && test\.validation_status !== 'VALIDATED'/);
});

test('11. search_billable_catalogue allows all active tests without validation_status gate', () => {
  const searchFunc = migration116.slice(migration116.indexOf('search_billable_catalogue'));
  const searchBlock = searchFunc.slice(0, searchFunc.indexOf('catalogue_set_test_lifecycle'));
  assert.match(searchBlock, /t\.is_active = TRUE/);
  assert.match(searchBlock, /t\.lifecycle_status = 'Active'/);
  assert.doesNotMatch(searchBlock, /t\.validation_status = 'VALIDATED'/);
});

test('12. NoReporting remains billing-only in trace and report group generation', () => {
  assert.match(migration116, /AND \(t\.collection_required OR t\.reporting_type IN \('InHouse','OutsourceWithBimalReport'\)\)/);
  assert.match(migration116, /IF NOT FOUND OR NEW\.reporting_type = 'NoReporting' THEN RETURN NEW; END IF;/);
});

test('13. Real safety & security controls remain intact in migration 0116 and ResultEntryPage', () => {
  // Authentication & RBAC checks in SQL
  assert.match(migration116, /IF auth\.uid\(\) IS NULL THEN/);
  assert.match(migration116, /public\.has_permission\('can_enter_results'\)/);
  assert.match(migration116, /public\.has_permission\('can_verify_results'\)/);
  
  // Critical panic value acknowledgement enforcement in SQL
  assert.match(migration116, /Critical results must be acknowledged before verification/);
  
  // Signed-off immutability in SQL
  assert.match(migration116, /This result can no longer be modified/);

  // Critical results acknowledgement check in ResultEntryPage
  assert.match(resultEntryPage, /hasUnackCritical/);
  assert.match(resultEntryPage, /CAN_ACKNOWLEDGE_CRITICAL/);
});
