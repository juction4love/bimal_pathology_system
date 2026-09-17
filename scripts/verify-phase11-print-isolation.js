/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Phase 11 Automated Print Isolation & A4 Pagination Test Suite
 */

import fs from 'fs';
import path from 'path';

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

function runPrintIsolationSuite() {
  console.log('================================================================');
  console.log(' BIMAL PATHOLOGY - PHASE 11 PRINT ISOLATION & PAGINATION SUITE');
  console.log('================================================================\n');

  console.log('--- TEST GROUP 1: ISOLATED PRINT ENGINE INSPECTION ---');

  // Test 1: reportPrint.ts exists and creates isolated iframe
  const reportPrintPath = path.resolve('src/lib/reportPrint.ts');
  const reportPrintContent = fs.readFileSync(reportPrintPath, 'utf8');
  const printDesignContent = fs.readFileSync(path.resolve('src/lib/printDesign.ts'), 'utf8');
  assert(
    reportPrintContent.includes('document.createElement(\'iframe\')') &&
    reportPrintContent.includes('printReportDocument'),
    '1. IsolatedIframeEngine',
    'reportPrint.ts creates isolated iframe for zero-bleed printing'
  );

  // Test 2: reportPrint.ts enforces A4 portrait geometry and print margins
  assert(
    reportPrintContent.includes('BIMAL_PRINT_CSS') &&
    printDesignContent.includes('@page { size: A4 portrait; margin: 0; }') &&
    printDesignContent.includes("marginVertical: '10mm'") && printDesignContent.includes("marginHorizontal: '10mm'"),
    '2. A4Geometry_Margins',
    'A4 portrait geometry and print margins strictly declared'
  );

  // Test 3: reportPrint.ts enforces print-color-adjust exact
  assert(
    printDesignContent.includes('print-color-adjust: exact !important'),
    '3. PrintColorAdjustExact',
    'print-color-adjust exact enforced for letterhead/footer fidelity'
  );

  console.log('\n--- TEST GROUP 2: PAGE-BREAK & PAGINATION RULES ---');

  // Test 4: ReportDocument.tsx has page-break-inside avoid on patient info box
  assert(
    printDesignContent.includes('.patient-info-box') &&
    printDesignContent.includes('page-break-inside: avoid'),
    '4. PatientInfoBox_PageBreakAvoid',
    'patient-info-box prevents page-break splits'
  );

  // Test 5: Department header and signature block prevent orphan splits
  assert(
    printDesignContent.includes('.department-header-block') &&
    printDesignContent.includes('.signature-block') &&
    printDesignContent.includes('page-break-after: avoid'),
    '5. Signature_Footer_Lock',
    'signature-block and department header prevent orphaned breaks'
  );

  // Test 6: Contact footer avoids forced overflow page
  assert(
    printDesignContent.includes('.bimal-footer-strip') &&
    printDesignContent.includes('page-break-before: avoid'),
    '6. FooterStrip_PageBreakBeforeAvoid',
    'bimal-footer-strip prevents creating an overflow page'
  );

  console.log('\n--- TEST GROUP 3: CALLSITE ISOLATION ENFORCEMENT ---');

  // Test 7: reportDownload.ts uses printReportDocument
  const downloadPath = path.resolve('src/lib/reportDownload.ts');
  const downloadContent = fs.readFileSync(downloadPath, 'utf8');
  assert(
    downloadContent.includes('printReportDocument'),
    '7. DownloadPdf_UsesIsolatedPrint',
    'reportDownload.ts delegates to printReportDocument'
  );

  // Test 8: ReportsPage.tsx uses printReportDocument
  const reportsPagePath = path.resolve('src/features/reports/ReportsPage.tsx');
  const reportsPageContent = fs.readFileSync(reportsPagePath, 'utf8');
  const finalViewerPath = path.resolve('src/features/reports/FinalReportViewerDialog.tsx');
  const finalViewerContent = fs.readFileSync(finalViewerPath, 'utf8');
  assert(
    reportsPageContent.includes('FinalReportViewerDialog') &&
      finalViewerContent.includes('printReportDocument()') &&
      finalViewerContent.includes('<ReportDocument'),
    '8. ReportsPage_UsesIsolatedPrint',
    'ReportsPage delegates canonical rendering and isolated print to FinalReportViewerDialog'
  );

  // Test 9: WorklistPage.tsx maintains clean operational boundaries without print buttons
  const worklistPagePath = path.resolve('src/features/worklist/WorklistPage.tsx');
  const worklistPageContent = fs.readFileSync(worklistPagePath, 'utf8');
  assert(
    !worklistPageContent.includes('printReportDocument()') &&
    !worklistPageContent.includes('downloadReportPdf('),
    '9. WorklistPage_ZeroPrintPollution',
    'WorklistPage.tsx maintains clean operational boundaries with zero print buttons'
  );

  // Test 10: Result entry keeps report delivery in Diagnostic Reports
  const resultEntryPath = path.resolve('src/features/worklist/ResultEntryPage.tsx');
  const resultEntryContent = fs.readFileSync(resultEntryPath, 'utf8');
  assert(
    !resultEntryContent.includes('printReportDocument') &&
      !resultEntryContent.includes('downloadReportPdf') &&
      !resultEntryContent.includes('<ReportDocument'),
    '10. ResultEntryPage_ZeroPrintPollution',
    'ResultEntryPage keeps preview, print, and PDF delivery inside Diagnostic Reports'
  );

  // Test 11: PublicReportPage.tsx uses printReportDocument
  const publicReportPath = path.resolve('src/features/public/PublicReportPage.tsx');
  const publicReportContent = fs.readFileSync(publicReportPath, 'utf8');
  assert(
    publicReportContent.includes('printReportDocument()'),
    '11. PublicReportPage_UsesIsolatedPrint',
    'PublicReportPage.tsx uses printReportDocument()'
  );

  console.log('\n================================================================');
  console.log(` SUMMARY: ${passedCount} PASSED, ${failedCount} FAILED`);
  console.log('================================================================\n');

  if (failedCount > 0) {
    process.exit(1);
  }
}

runPrintIsolationSuite();
