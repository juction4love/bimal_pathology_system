import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration115 = fs.readFileSync('supabase/migrations_legacy_archive/00115_dashboard_signed_reports_and_validation_semantics.sql', 'utf8');
const migration073 = fs.readFileSync('supabase/migrations_legacy_archive/00073_server_search_pagination_convergence.sql', 'utf8');
const adminDashboard = fs.readFileSync('src/features/dashboard/DashboardPage.tsx', 'utf8');
const techDashboard = fs.readFileSync('src/features/dashboard/TechnicianDashboard.tsx', 'utf8');
const patientOrderWorklist = fs.readFileSync('src/features/dashboard/PatientOrderWorklist.tsx', 'utf8');
const worklistPage = fs.readFileSync('src/features/worklist/WorklistPage.tsx', 'utf8');
const resultEntryPage = fs.readFileSync('src/features/worklist/ResultEntryPage.tsx', 'utf8');
const sampleAccessioningPage = fs.readFileSync('src/features/samples/SampleAccessioningPage.tsx', 'utf8');
const reportsPage = fs.readFileSync('src/features/reports/ReportsPage.tsx', 'utf8');
const billListPage = fs.readFileSync('src/features/billing/BillListPage.tsx', 'utf8');
const patientsPage = fs.readFileSync('src/features/patients/PatientsPage.tsx', 'utf8');

test('1. Admin Signed Reports Today uses signed_at timestamp and Nepal date boundary', () => {
  // Migration 00115 defines Nepal timezone date boundary
  assert.match(migration115, /v_today_date DATE := \(now\(\) AT TIME ZONE 'Asia\/Kathmandu'\)::date;/);
  
  // Uses signed_at and excludes historical superseded 'Amended' rows
  assert.match(migration115, /'signed_reports_today',\s*\(SELECT count\(\*\) FROM public\.diagnostic_reports WHERE status = 'SignedOff' AND signed_at IS NOT NULL AND \(signed_at AT TIME ZONE 'Asia\/Kathmandu'\)::date = v_today_date\)/);
  
  // Does NOT use created_at for signed reports metric
  const signedReportLine = migration115.split('\n').find(line => line.includes("'signed_reports_today'"));
  assert.ok(signedReportLine && !signedReportLine.includes('created_at'), 'signed_reports_today must use signed_at, not created_at');

  // Admin dashboard uses signed_reports_today
  assert.match(adminDashboard, /signed_reports_today/);
  assert.match(adminDashboard, /Signed Reports Today/);
});

test('2. Total signed reports remains independently available without date truncation', () => {
  // Migration 00115 exposes total_signed_reports (all-time signed)
  assert.match(migration115, /'total_signed_reports',\s*\(SELECT count\(\*\) FROM public\.diagnostic_reports WHERE status = 'SignedOff'\)/);
  
  // Admin dashboard displays totalSignedReports metric in subtext
  assert.match(adminDashboard, /totalSignedReports/);
  assert.match(adminDashboard, /All-Time Total:/);
});

test('3. Technician Signed Reports Today uses identical signed_at semantics and Nepal date boundary', () => {
  // Technician operational summary uses signed_at and status = 'SignedOff'
  assert.match(migration115, /'signed_reports_today',\s*\(SELECT count\(\*\) FROM public\.diagnostic_reports WHERE status = 'SignedOff' AND signed_at IS NOT NULL AND \(signed_at AT TIME ZONE 'Asia\/Kathmandu'\)::date = v_today_date\)/);
  
  // Technician dashboard displays Signed Reports Today
  assert.match(techDashboard, /signedReports:\s*Number\(summary\?\.signed_reports_today\)\|\|0/);
  assert.match(techDashboard, /title="Signed Reports Today"/);
});

test('4. Destination ReportsPage SignedOff + date filter predicate matches Dashboard KPI count exactly', () => {
  // Destination route passes status=SignedOff and today's Nepal date
  assert.match(adminDashboard, /navigate\(`\/reports\?status=SignedOff&date=\$\{getNepalTodayAd\(\)\}`\)/);
  assert.match(techDashboard, /navigate\(`\/reports\?status=SignedOff&date=\$\{getNepalTodayAd\(\)\}`\)/);

  // ReportsPage passes statusFilter and dateFilter to search_report_registry
  assert.match(reportsPage, /p_status:\s*statusFilter\s*===\s*'All'\s*\?\s*null\s*:\s*statusFilter/);
  assert.match(reportsPage, /p_date:\s*dateFilter\s*\|\|\s*null/);

  // search_report_registry predicate in migration 00073
  assert.match(migration073, /\(p_status IS NULL OR p_status='' OR r\.status=p_status\)/);
  assert.match(migration073, /\(p_date IS NULL OR \(r\.signed_at AT TIME ZONE 'Asia\/Kathmandu'\)::date=p_date\)/);
});

test('5. Pending Results predicate includes only SampleReceived and ResultDrafted across both Dashboard and Worklist', () => {
  // Dashboard operational summary
  assert.match(migration115, /'pending_results',\s*\(SELECT count\(\*\) FROM public\.clinical_order_items WHERE status IN \('SampleReceived', 'ResultDrafted'\)\)/);
  assert.match(migration115, /'worklist_pending',\s*\(SELECT count\(\*\) FROM public\.clinical_order_items WHERE status IN \('SampleReceived', 'ResultDrafted'\)\)/);

  // Destination search_laboratory_worklist RPC with p_view = 'Pending'
  assert.match(migration115, /p_view='Pending' AND coi\.status IN \('SampleReceived','ResultDrafted'\)/);

  // Destination route navigates with view=Pending
  assert.match(adminDashboard, /navigate\('\/worklist\?view=Pending'\)/);
  assert.match(techDashboard, /navigate\('\/worklist\?view=Pending'\)/);
});

test('6. Awaiting Verification / ToVerify uses identical predicate excluding Verified/SignedOff across Dashboard and Worklist', () => {
  // Dashboard operational summary (Admin & Tech)
  assert.match(migration115, /'awaiting_verification',\s*\(\s*SELECT count\(DISTINCT coi\.id\)\s*FROM public\.clinical_order_items coi\s*WHERE coi\.status NOT IN \('Verified', 'SignedOff'\)\s*AND EXISTS \(\s*SELECT 1\s*FROM public\.test_results tr\s*WHERE tr\.order_item_id = coi\.id\s*AND tr\.status = 'SubmittedForVerification'\s*\)\s*\)/);

  // Destination search_laboratory_worklist RPC with p_view = 'ToVerify'
  assert.match(migration115, /p_view='ToVerify' AND coi\.status NOT IN \('Verified','SignedOff'\) AND EXISTS\(\s*SELECT 1 FROM public\.test_results pending_result\s*WHERE pending_result\.order_item_id=coi\.id AND pending_result\.status='SubmittedForVerification'\s*\)/);

  // Destination route navigates with view=ToVerify
  assert.match(adminDashboard, /navigate\('\/worklist\?view=ToVerify'\)/);
  assert.match(techDashboard, /navigate\('\/worklist\?view=ToVerify'\)/);
});

test('7. Today Patients and Invoices KPI use exact Nepal date boundary matching destination filters', () => {
  // Dashboard operational summary
  assert.match(migration115, /'today_patients',\s*\(SELECT count\(\*\) FROM public\.patients WHERE \(created_at AT TIME ZONE 'Asia\/Kathmandu'\)::date = v_today_date\)/);
  assert.match(migration115, /'today_invoices',\s*\(SELECT count\(\*\) FROM public\.bills WHERE \(created_at AT TIME ZONE 'Asia\/Kathmandu'\)::date = v_today_date\)/);

  // Click-through routes
  assert.match(adminDashboard, /navigate\(`\/patients\?date=\$\{getNepalTodayAd\(\)\}`\)/);
  assert.match(adminDashboard, /navigate\(`\/billing\?date=\$\{getNepalTodayAd\(\)\}`\)/);
  assert.match(techDashboard, /navigate\(`\/patients\?date=\$\{getNepalTodayAd\(\)\}`\)/);

  // Destination RPC filters
  assert.match(migration115, /\(p_date IS NULL OR \(p\.created_at AT TIME ZONE 'Asia\/Kathmandu'\)::date=p_date\)/);
  assert.match(migration073, /\(p_date IS NULL OR \(b\.created_at AT TIME ZONE 'Asia\/Kathmandu'\)::date=p_date\)/);
});

test('8. Routine operational workflows have no blocking validation badges or release blocks', () => {
  // Operational screens must not render alarming blocking badges
  assert.doesNotMatch(patientOrderWorklist, /label="Requires Clinical Validation"/);
  assert.doesNotMatch(worklistPage, /label="Requires Clinical Validation"/);
  assert.doesNotMatch(resultEntryPage, /label="Requires Clinical Validation"/);
  assert.doesNotMatch(resultEntryPage, /label="Reporting Blocked"/);
  assert.doesNotMatch(sampleAccessioningPage, /label="Requires Clinical Validation"/);

  // Result entry verify action does not block on validation_status or clinical_reporting_enabled
  assert.doesNotMatch(resultEntryPage, /orderItem\?\.validation_status === 'REQUIRES_VALIDATION'/);
  assert.doesNotMatch(resultEntryPage, /orderItem\?\.test\?\.validation_status === 'REQUIRES_VALIDATION'/);
});

test('9. Dashboard does not expose financial metrics to lab technician', () => {
  // Technician RPC does not return financial totals
  const techRpcBlock = migration115.slice(migration115.indexOf('CREATE OR REPLACE FUNCTION public.get_technician_operational_summary()'));
  const techRpcEnd = techRpcBlock.indexOf('$$;');
  const techRpcBody = techRpcBlock.slice(0, techRpcEnd);
  
  assert.doesNotMatch(techRpcBody, /today_collection_paisa/);
  assert.doesNotMatch(techRpcBody, /outstanding_due_paisa/);
  assert.doesNotMatch(techRpcBody, /payment_transactions/);
  
  // Technician dashboard does not render billing or collection KPI
  assert.doesNotMatch(techDashboard, /today_collection_paisa/);
  assert.doesNotMatch(techDashboard, /outstanding_due_paisa/);
  assert.doesNotMatch(techDashboard, /Today's Invoices/);
  assert.doesNotMatch(techDashboard, /Today's Collections/);
});

test('10. Ordinary unfiltered registry routes still work without date parameter', () => {
  assert.match(migration115, /p_date DATE DEFAULT NULL/);
  assert.match(patientsPage, /p_date:\s*dateFilter\s*\|\|\s*null/);
  assert.match(billListPage, /p_date:\s*dateFilter\s*\|\|\s*null/);
  assert.match(reportsPage, /p_date:\s*dateFilter\s*\|\|\s*null/);
});
