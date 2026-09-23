/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Phase 13 Admin Dashboard Top-Level Collection Summary Verification Suite
 * Tests all 9 acceptance criteria for financial collection summaries
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

let passedCount = 0;
let failedCount = 0;

function assert(condition, testCode, description) {
  if (condition) {
    console.log(`  ✅ [PASS] ${testCode}: ${description}`);
    passedCount++;
  } else {
    console.error(`  ❌ [FAIL] ${testCode}: ${description}`);
    failedCount++;
  }
}

async function runTests() {
  console.log('================================================================');
  console.log(' BIMAL PATHOLOGY - PHASE 13 ADMIN COLLECTION SUMMARY SUITE');
  console.log('================================================================\n');

  const { getNepalDateBoundaries } = await import('../src/lib/dateTime.ts');
  const { formatPaisa } = await import('../src/lib/currency.ts');
  const { PERMISSION_KEYS, SYSTEM_ROLES } = await import('../src/types/permissions.ts');

  // --- GROUP 1: NEPAL TIMEZONE BOUNDARY & INTEGER PAISA MATH ---
  console.log('--- TEST GROUP 1: NEPAL TIMEZONE BOUNDARIES & INTEGER PAISA ---');

  // 1. DashboardSummary_NepalTimezoneBoundary
  const boundaries = getNepalDateBoundaries(new Date('2026-08-19T11:00:00.000Z')); // 16:45 Nepal Time
  const todayStartExpected = '2026-08-18T18:15:00.000Z'; // 00:00:00 Nepal Time (+05:45)
  const monthStartExpected = '2026-07-31T18:15:00.000Z'; // 1st Aug 00:00:00 Nepal Time (+05:45)

  assert(
    boundaries.todayStartIso === todayStartExpected &&
      boundaries.monthStartIso === monthStartExpected &&
      boundaries.currentMonthLabel === 'August 2026',
    '1. DashboardSummary_NepalTimezoneBoundary',
    `Calculates exact Asia/Kathmandu (UTC+05:45) boundaries: Today ${boundaries.todayStartIso}, Month ${boundaries.monthStartIso} (${boundaries.currentMonthLabel})`
  );

  // 2. DashboardSummary_UsesIntegerPaisa
  const formatted1 = formatPaisa(1245000); // 12,450.00 NPR
  const formatted2 = formatPaisa(38420000); // 384,200.00 NPR
  const formatted3 = formatPaisa(184275000); // 1,842,750.00 NPR

  assert(
    formatted1 === 'NPR 12450.00' && formatted2 === 'NPR 384200.00' && formatted3 === 'NPR 1842750.00',
    '2. DashboardSummary_UsesIntegerPaisa',
    `Converts authoritative integer paisa to display without float drift: 184,275,000 paisa -> ${formatted3}`
  );

  // 3. DashboardSummary_ZeroPaymentsReturnsZero
  const zeroFormatted = formatPaisa(0);
  assert(
    zeroFormatted === 'NPR 0.00',
    '3. DashboardSummary_ZeroPaymentsReturnsZero',
    `Zero payment collection safely resolves to "NPR 0.00" (never null or NaN): ${zeroFormatted}`
  );

  // --- GROUP 2: MIGRATION & AGGREGATE FUNCTION INSPECTION ---
  console.log('\n--- TEST GROUP 2: MIGRATION & DATA SOURCE INSPECTION ---');

  const mig16Path = path.resolve(__dirname, '../supabase/migrations_legacy_archive/00016_dashboard_collection_summary.sql');
  const mig16Exists = fs.existsSync(mig16Path);
  const mig16Sql = mig16Exists ? fs.readFileSync(mig16Path, 'utf8') : '';
  const mig51Sql = fs.readFileSync(path.resolve(__dirname, '../supabase/migrations_legacy_archive/00051_inactive_user_permission_enforcement.sql'), 'utf8');

  // 4. DashboardSummary_UsesPaymentTransactions
  const usesPaymentTable =
    mig16Sql.includes('FROM public.payment_transactions pt') &&
    mig16Sql.includes('pt.amount_paisa') &&
    !mig16Sql.includes('FROM public.bills'); // Must use actual received payment ledger
  assert(
    mig16Exists && usesPaymentTable,
    '4. DashboardSummary_UsesPaymentTransactions',
    'Migration 00016 aggregates actual received money strictly from public.payment_transactions'
  );

  // 5. DashboardSummary_TodayCollection
  const hasTodayAgg =
    mig16Sql.includes("pt.created_at >= v_today_start THEN pt.amount_paisa") &&
    mig16Sql.includes("today_collection_paisa");
  assert(
    hasTodayAgg,
    '5. DashboardSummary_TodayCollection',
    'Calculates today_collection_paisa from payments received on or after 00:00:00 Asia/Kathmandu'
  );

  // 6. DashboardSummary_MonthCollection
  const hasMonthAgg =
    mig16Sql.includes("pt.created_at >= v_month_start THEN pt.amount_paisa") &&
    mig16Sql.includes("month_collection_paisa");
  assert(
    hasMonthAgg,
    '6. DashboardSummary_MonthCollection',
    'Calculates month_collection_paisa from payments received on or after 1st day of current Nepal month'
  );

  // 7. DashboardSummary_TotalCollection
  const hasTotalAgg =
    mig16Sql.includes("SUM(pt.amount_paisa)") &&
    mig16Sql.includes("total_collection_paisa");
  assert(
    hasTotalAgg,
    '7. DashboardSummary_TotalCollection',
    'Calculates total_collection_paisa as lifetime sum of all payment transactions'
  );

  // --- GROUP 3: RBAC & DASHBOARD INTEGRATION ---
  console.log('\n--- TEST GROUP 3: RBAC PERMISSIONS & UI PLACEMENT ---');

  // 8. DashboardSummary_AdminOnlyFinancials
  const technicianHasFin = SYSTEM_ROLES.LAB_TECHNICIAN.defaultPermissions.includes(PERMISSION_KEYS.CAN_VIEW_FINANCIALS);
  assert(
    technicianHasFin === false,
    '8. DashboardSummary_AdminOnlyFinancials',
    'Financial summaries are restricted from Lab Technician and reserved for Admin'
  );

  // 9. DashboardSummary_AnonymousDeniedFinancials
  const isAnonDenied = /REVOKE ALL ON FUNCTION public\.get_dashboard_collection_summary\(\) FROM PUBLIC, anon/.test(mig51Sql) &&
    /has_permission\('can_view_financials'\)/.test(mig51Sql);
  assert(
    isAnonDenied,
    '9. DashboardSummary_AnonymousDeniedFinancials',
    'Unauthenticated callers are strictly blocked from executing collection summary RPC'
  );

  // 10. Dashboard UI Top-Level Placement Check
  const dashboardCode = fs.readFileSync(
    path.resolve(__dirname, '../src/features/dashboard/DashboardPage.tsx'),
    'utf8'
  );
  const hasOperationalTopCards =
    dashboardCode.includes("title=\"Today's Patients\"") &&
    dashboardCode.includes("title=\"Today's Invoices\"") &&
    dashboardCode.includes("title=\"Today's Collections\"") &&
    dashboardCode.includes('Payments received today (by receipt time)') &&
    dashboardCode.includes('title="Outstanding Due"') &&
    dashboardCode.includes('PatientOrderWorklist') &&
    !dashboardCode.includes('monthCollectionPaisa') &&
    !dashboardCode.includes('totalCollectionPaisa');

  assert(
    hasOperationalTopCards,
    '10. Dashboard_TopLevelCardsRendered',
    'Dashboard prioritizes today KPIs and searchable operational worklist; historical collection cards are retired'
  );

  console.log('\n================================================================');
  console.log(` SUMMARY: ${passedCount} PASSED, ${failedCount} FAILED`);
  console.log('================================================================\n');

  if (failedCount > 0) {
    process.exit(1);
  }
}

runTests().catch((err) => {
  console.error('Test runner execution failed:', err);
  process.exit(1);
});
