import fs from 'node:fs';

let passed = 0;
const check = (condition, message) => {
  if (!condition) throw new Error(`FAIL: ${message}`);
  passed += 1;
  console.log(`PASS: ${message}`);
};
const read = (path) => fs.readFileSync(path, 'utf8');

const documentSource = read('src/features/reports/ReportDocument.tsx');
const reportsSource = read('src/features/reports/ReportsPage.tsx');
const viewerSource = read('src/features/reports/FinalReportViewerDialog.tsx');
const publicSource = read('src/features/public/PublicReportPage.tsx');
const printSource = read('src/lib/reportPrint.ts');
const downloadSource = read('src/lib/reportDownload.ts');

check(documentSource.includes('data-canonical-report-design="current"'), 'ReportDocument identifies one current canonical presentation');
check(!/created_at|signed_at\s*[<>]=?|creation.*date|legacy.*template|old.*template/i.test(documentSource), 'ReportDocument has no date-based or legacy-template selection');
check(reportsSource.includes("rpc('search_report_registry'") && reportsSource.includes('clinical_snapshot_json'), 'Reporting loads persisted frozen snapshots through the bounded RLS-preserving registry RPC');
check(reportsSource.includes("p_status:statusFilter==='All'?null:statusFilter") && reportsSource.includes("value=\"Amended\""), 'Reporting includes signed and amended historical records through server-side status filtering');
check(viewerSource.includes('<ReportDocument') && viewerSource.includes('snapshot={report.clinical_snapshot_json}'), 'Authenticated preview/reprint renders the stored snapshot with ReportDocument');
check(publicSource.includes('<ReportDocument') && publicSource.includes('snapshot={reportData.snapshot}'), 'Public print/PDF source renders the resolved frozen snapshot with ReportDocument');
check(!publicSource.includes('ResponsivePublicReport') && !fs.existsSync('src/features/public/ResponsivePublicReport.tsx'), 'Secure public preview has no alternate viewport or legacy report renderer');
check((publicSource.match(/<ReportDocument/g) || []).length === 1, 'Secure public route has exactly one report presentation branch');
check(printSource.includes('printable-report'), 'Print targets the canonical report element');
check(downloadSource.includes('printReportDocument'), 'Download/Save as PDF delegates to canonical print rendering');
check(!/update\(|upsert\(|insert\(|\.rpc\(/.test(viewerSource), 'Canonical viewer is read-only and cannot rewrite historical report data');
check(!/update\(|upsert\(|insert\(/.test(documentSource), 'Canonical renderer has no persistence mutation path');
check(documentSource.includes("height: '68mm'") && documentSource.includes("height: '189mm'") && documentSource.includes("height: '13mm'"), 'One renderer owns the frozen full-sheet page geometry');
check(documentSource.includes('report-header-diagonal-accent') && documentSource.includes('report-header-background-wordmark') && documentSource.includes('patient-identity-strip'), 'One renderer owns the current wordmark accent and compact identity strip');
const wordmarkStart = documentSource.indexOf('className="report-header-background-wordmark"');
const wordmarkEnd = documentSource.indexOf('/>', wordmarkStart);
const wordmarkNode = documentSource.slice(wordmarkStart, wordmarkEnd + 2);
check(wordmarkNode.includes('backgroundImage:') && wordmarkNode.includes('data:image/svg+xml') && !wordmarkNode.includes('>BIMAL PATHOLOGY<'), 'Decorative wordmark is a background image, not duplicate extractable document text');
check(documentSource.includes("data-final-page={isFinalPage ? 'true' : 'false'}") && documentSource.includes("className=\"signature-block\""), 'Final-page composition remains renderer-controlled');
check(!fs.readdirSync('supabase/migrations').some((name) => /report.*template.*continuity|historical.*report.*design/i.test(name)), 'No data migration or historical backfill was introduced for presentation');

console.log(`\n${passed} report template continuity contracts passed.`);
