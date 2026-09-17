/** Deterministic Phase 8 report-action suite; does not depend on live accounts/data. */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const schema = read('supabase/migrations/00001_initial_schema.sql');
const rls = read('supabase/migrations/00002_rls_and_permissions.sql');
const reporting = read('supabase/migrations/00005_reporting_signoff_and_pdf.sql');
const finalAuthorization = read('supabase/migrations/00087_production_catalogue_rate_management.sql');
const smsAndPublicReports = read('supabase/migrations/00006_sms_and_public_reports.sql');
const worklist = read('src/features/worklist/WorklistPage.tsx');
const worklistSearch = read('supabase/migrations/00072_worklist_server_search_pagination.sql');
let passedCount = 0;
let failedCount = 0;

function assert(condition, code, description) {
  if (condition) { console.log(`  ✅ [PASS] ${code}: ${description}`); passedCount++; }
  else { console.error(`  ❌ [FAIL] ${code}: ${description}`); failedCount++; }
}

async function runReportActionsSuite() {
  console.log('================================================================');
  console.log(' BIMAL PATHOLOGY - PHASE 8 REPORT ACTION & PRINT SUITE');
  console.log('================================================================\n');

  console.log('--- TEST GROUP 1: IMMUTABLE SNAPSHOT & STORAGE ARCHITECTURE ---');
  const reportTableExists = /CREATE TABLE diagnostic_reports\s*\(/i.test(schema);
  const reportSelectPolicy = /CREATE POLICY "diagnostic_reports_select"[\s\S]*?FOR SELECT TO authenticated[\s\S]*?can_print_reports[\s\S]*?can_sign_reports/i.test(rls);
  assert(reportTableExists && reportSelectPolicy, '1. DiagnosticReports_QueryableByAuthorizedUsers', 'Schema and RLS permit authorized staff to query diagnostic reports');

  const privateBucket = /INSERT INTO storage\.buckets[\s\S]*?'diagnostic-reports'[\s\S]*?FALSE/i.test(reporting);
  const signedUrlReadPolicy = /ON storage\.objects FOR SELECT TO authenticated[\s\S]*?bucket_id = 'diagnostic-reports'[\s\S]*?can_print_reports/i.test(reporting);
  assert(privateBucket && signedUrlReadPolicy, '2. DiagnosticReportsBucket_AccessibleForSignedUrls', 'Private diagnostic-reports bucket has authenticated read policy for signed URL creation');

  const tokenRpcExists = /CREATE OR REPLACE FUNCTION public\.create_public_report_token\s*\(/i.test(smsAndPublicReports);
  assert(tokenRpcExists, '3. PublicReportTokenRpc_IsCallable', 'create_public_report_token RPC exists in migration 00006');

  console.log('\n--- TEST GROUP 2: ROLE-BASED ACCESS CONTROL FOR REPORTS ---');
  const { ACTIVE_ROLE_CODES, SYSTEM_ROLES, PERMISSION_KEYS } = await import('../src/types/permissions.ts');
  const adminIsCompatibilityOnly = !ACTIVE_ROLE_CODES.includes(SYSTEM_ROLES.ADMIN.code);
  const finalModelIsLocked = finalAuthorization.includes('Lab Technician is the only normally assignable role.');
  assert(adminIsCompatibilityOnly && finalModelIsLocked, '4. Administrator_IsCompatibilityOnly', 'Administrator is historical compatibility only and cannot be normally assigned');

  const techCanSign = SYSTEM_ROLES.LAB_TECHNICIAN.defaultPermissions.includes(PERMISSION_KEYS.CAN_SIGN_REPORTS);
  assert(techCanSign, '5. LabTechnician_HasSignReportsPermission', 'Lab Technician can authorize reports in the single-operator workflow');

  const techCanPrint = SYSTEM_ROLES.LAB_TECHNICIAN.defaultPermissions.includes(PERMISSION_KEYS.CAN_PRINT_REPORTS);
  assert(techCanPrint, '6. LabTechnician_HasPrintReportsPermission', 'Lab Technician possesses can_print_reports');

  console.log('\n--- TEST GROUP 3: WORKLIST REPORT LINKAGE ---');
  const orderItemsPolicy = /CREATE POLICY "clinical_order_items_select"[\s\S]*?FOR SELECT TO authenticated/i.test(rls);
  const fetchesWorklistRpc = worklist.includes(".rpc('search_laboratory_worklist'");
  const linksReports = /FROM public\.diagnostic_reports r WHERE r\.order_id=coi\.order_id/.test(worklistSearch);
  const preservesRls = /SECURITY INVOKER/.test(worklistSearch) && /TO authenticated/.test(worklistSearch);
  assert(orderItemsPolicy && fetchesWorklistRpc && linksReports && preservesRls, '7. Worklist_FetchOrderItemsForReportLinkage', 'Worklist uses the RLS-preserving paginated RPC and links the latest signed report by order_id');

  console.log('\n================================================================');
  console.log(` SUMMARY: ${passedCount} PASSED, ${failedCount} FAILED`);
  console.log('================================================================\n');
  if (failedCount > 0) process.exit(1);
}

runReportActionsSuite().catch((error) => { console.error(error); process.exit(1); });
