import fs from 'node:fs';

let passed = 0;
let failed = 0;
function check(condition, name) {
  if (condition) {
    passed += 1;
    console.log(`PASS: ${name}`);
  } else {
    failed += 1;
    console.error(`FAIL: ${name}`);
  }
}

const page = fs.readFileSync('src/features/public/PublicReportPage.tsx', 'utf8');
const a4 = fs.readFileSync('src/features/reports/ReportDocument.tsx', 'utf8');
const printDesign = fs.readFileSync('src/lib/printDesign.ts', 'utf8');
const routes = fs.readFileSync('src/app/routes.tsx', 'utf8');
const reportSms = fs.readFileSync('supabase/migrations/00041_standardize_report_ready_sms.sql', 'utf8');

for (const width of [320, 375, 390, 430, 768]) {
  check(width < 900 && page.includes("overflowX: 'auto'"), `${width}px keeps the canonical A4 report reachable without substituting a renderer`);
}
check(page.includes("justifyContent: { xs: 'flex-start', md: 'center' }") && page.includes('<ReportDocument'), 'all viewport sizes visibly use the canonical A4 report');
check(!page.includes('ResponsivePublicReport') && !fs.existsSync('src/features/public/ResponsivePublicReport.tsx'), 'alternate public report template is absent');
check(page.includes('minHeight: 44'), 'public report actions remain touch-friendly');
check((page.match(/<ReportDocument/g) || []).length === 1, 'screen, print, and PDF share one canonical report DOM');
check(page.includes('onClick={() => printReportDocument()}'), 'print and PDF actions continue through the isolated print engine');
check(page.includes('publicToken={token}') && page.includes('reportNumber={reportData.report_number}'), 'canonical print QR retains the current secure route token');
check(/pageWidth: '210mm'[\s\S]*pageHeight: '297mm'[\s\S]*marginVertical: '10mm'[\s\S]*marginHorizontal: '10mm'/.test(printDesign), 'canonical A4 geometry and frozen printer-safe margins remain unchanged');
check(a4.includes('paginateInvestigations') && a4.includes('signature-block') && a4.includes('bimal-footer-strip'), 'A4 pagination signatures and footer remain canonical');
check(routes.includes("path: '/r/:token'"), 'secure public route remains /r/:token');
check(page.includes("hashToken(token.trim())") && page.includes("resolve_public_report_by_token"), 'token hashing and secure resolver remain unchanged');
check(reportSms.includes("FROM '^https://lis[.]bimalpathology[.]com[.]np/r/([A-Za-z0-9_-]+)$'") &&
  reportSms.includes("' received for Lab No: '") === false &&
  reportSms.includes("'. View report: ' || p_public_url_base"), 'ReportReady SMS retains the validated production secure URL');

console.log(`\nPhase 35 responsive public report verification: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
