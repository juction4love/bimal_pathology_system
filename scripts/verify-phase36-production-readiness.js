import fs from 'node:fs';
const smsPolicy = fs.readFileSync('supabase/migrations/00122_url_free_sms_notifications.sql', 'utf8');

const read = (path) => fs.readFileSync(path, 'utf8');
let passed = 0;
let failed = 0;
const check = (condition, name) => {
  if (condition) {
    passed += 1;
    console.log(`PASS: ${name}`);
  } else {
    failed += 1;
    console.error(`FAIL: ${name}`);
  }
};

const auth = read('src/context/AuthContext.tsx');
const layout = read('src/app/AppLayout.tsx');
const routes = read('src/app/routes.tsx');
const lazyPages = read('src/app/lazyPages.ts');
const audit = read('src/features/admin/AuditLogPage.tsx');
const catalogue75 = read('supabase/migrations/00075_catalogue_readiness_approval_workflow.sql');
const report = read('src/features/reports/ReportDocument.tsx');
const publicReport = read('src/features/public/PublicReportPage.tsx');
const token = read('src/lib/sms/tokenHelper.ts');
const renderer = read('src/lib/reportRenderer.ts');
const outsource = read('src/features/outsource/OutsourceTrackingPage.tsx');
const dateTime = read('src/lib/dateTime.ts');
const payment = read('supabase/migrations/00040_short_payment_confirmation_sms.sql');
const signoff = read('src/features/worklist/ResultEntryPage.tsx');
const publicGateway = read('supabase/functions/public-report/index.ts');

check(!auth.includes('demo-admin-001'), 'unconfigured authentication has no synthetic super-admin');
check(auth.includes('LIS cloud configuration is unavailable'), 'unconfigured sign-in fails closed with operator-safe guidance');
check(layout.includes('Configuration Required') && !layout.includes('Phase 0 Demo Scaffold'), 'shell identifies missing production configuration without demo mode');
check(lazyPages.includes('lazyWithChunkRecovery(') && lazyPages.includes("import('@/features/") && routes.includes('Suspense'), 'route-level lazy loading with bounded chunk recovery is active');
check(audit.includes("rpc('search_audit_log'") && catalogue75.includes('FROM public.audit_logs a') && !audit.includes('mockLogs'), 'audit page reads immutable production audit rows through bounded server search instead of demo records');
check(!audit.includes('old_data') && !audit.includes('new_data'), 'audit viewer omits sensitive payload columns');
check(report.includes('/^[A-Za-z0-9_-]{32,256}$/') && !report.includes('publicToken || reportNumber'), 'report QR accepts only a secure token and never predictable identifiers');
check(publicReport.includes("overflowX: 'auto'") &&
  !publicReport.includes("left: { xs: '-10000px', md: 'auto' }") &&
  !publicReport.includes('ResponsivePublicReport'), 'canonical A4 report remains the visible mobile preview and print/PDF source');
check(!publicReport.includes('setError(err.message'), 'public report errors do not expose backend internals');
check(!token.includes('Math.random') && token.includes('Secure random token generation is unavailable'), 'public tokens fail closed without cryptographic randomness');
check(!token.includes('Fallback simple hash') && !renderer.includes('Fallback simple hash'), 'security/integrity hashes have no non-cryptographic fallback');
check(!/\balert\s*\(/.test(outsource) && outsource.includes('<Snackbar'), 'outsource workflow uses LIS feedback UI instead of browser alert');
check(!outsource.includes("useState('National Reference Lab')") && !outsource.includes("useState('1 Block + 3 Slides')"), 'outsource forms contain no acceptance/demo transaction defaults');
check(dateTime.includes("return '-';"), 'missing age renders as unknown instead of fabricated zero years');
check(signoff.includes("(supabase.rpc as any)('sign_and_queue_report_group'"), 'report sign-off uses the group-scoped atomic orchestration RPC');
check(payment.includes('Bimal Pathology: Payment of NPR '), 'payment SMS uses the approved short template');
check(smsPolicy.includes('Bimal Pathology: Your laboratory report is ready. Please collect it from the lab or contact 056-593288. Thank you.') && !smsPolicy.includes('. View report'), 'ReportReady SMS uses the neutral URL-free template');
check(publicGateway.includes("'https://lis.bimalpathology.com.np'") && !publicGateway.includes('localhost'), 'public report Edge gateway allows only the canonical production origin');
check(publicGateway.includes('/^[A-Za-z0-9_-]{32,256}$/') && !publicGateway.includes('rpcErr.message'), 'public report Edge gateway validates tokens and suppresses backend internals');

console.log(`\nPhase 36 production-readiness verification: ${passed} passed, ${failed} failed`);
if (failed) process.exit(1);
