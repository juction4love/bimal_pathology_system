import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const reports = read('src/features/reports/ReportsPage.tsx');
const viewer = read('src/features/reports/FinalReportViewerDialog.tsx');
const patients = read('src/features/patients/PatientsPage.tsx');
const worklist = read('src/features/worklist/WorklistPage.tsx');
const resultEntry = read('src/features/worklist/ResultEntryPage.tsx');
const routes = read('src/app/routes.tsx');
let passed = 0;
const check = (condition, message) => { if (!condition) throw new Error(message); passed += 1; console.log(`PASS ${message}`); };

check(/printReportDocument/.test(reports) && /downloadReportPdf/.test(reports) && /FinalReportViewerDialog/.test(reports), 'Reporting owns preview, print, and download actions');
check(/<ReportDocument/.test(viewer) && /printReportDocument/.test(viewer) && /downloadReportPdf/.test(viewer), 'Reporting viewer uses the single canonical renderer and isolated actions');
check(!/printReportDocument|downloadReportPdf|FinalReportViewerDialog|<ReportDocument/.test(worklist), 'Worklist has no final report renderer, print, download, or reprint action');
check(!/printReportDocument|downloadReportPdf|FinalReportViewerDialog|<ReportDocument/.test(resultEntry), 'Result Entry has no final report renderer, print, download, or reprint action');
check(/Open Final Report in Reporting/.test(resultEntry) && /\/reports\?reportId=/.test(resultEntry), 'signed Result Entry navigates to the exact report in Reporting');
check(!/FinalReportViewerDialog|CanonicalReportRecord|PictureAsPdfIcon/.test(patients) && /Open in Reporting/.test(patients) && /\/reports\?reportId=/.test(patients), 'Patient History navigates to Reporting instead of hosting a second report center');
check(/CAN_PRINT_REPORTS/.test(patients) && /CAN_PRINT_REPORTS[\s\S]*?<ReportsPage/.test(routes), 'patient navigation and Reporting route preserve can_print_reports permission gates');
check(/routeParams\.get\('reportId'\)/.test(reports) && /setPreviewOpen\(true\)/.test(reports), 'Reporting resolves deep-linked signed reports into its canonical preview');

console.log(`Reporting workspace action contracts: ${passed} passed, 0 failed`);
