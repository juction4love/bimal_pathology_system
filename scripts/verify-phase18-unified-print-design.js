/** Unified print/PDF design-system source regression suite. */
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const design = read('src/lib/printDesign.ts');
const report = read('src/features/reports/ReportDocument.tsx');
const pagination = read('src/features/reports/reportPagination.js');
const printer = read('src/lib/reportPrint.ts');
const viewer = read('src/features/reports/FinalReportViewerDialog.tsx');
const publicPage = read('src/features/public/PublicReportPage.tsx');
const reportsPage = read('src/features/reports/ReportsPage.tsx');
const invoice = read('src/features/billing/BillListPage.tsx');
const worklist = read('src/features/worklist/WorklistPage.tsx');
const resultEntry = read('src/features/worklist/ResultEntryPage.tsx');
const qa = read('src/printQa.tsx');
const visualQa = read('scripts/report-print-visual.spec.js');

let passed = 0;
let failed = 0;
const assert = (condition, name, detail) => {
  if (condition) { passed++; console.log(`  ✅ [PASS] ${name}: ${detail}`); }
  else { failed++; console.error(`  ❌ [FAIL] ${name}: ${detail}`); }
};

console.log('\n================================================================');
console.log(' BIMAL PATHOLOGY - PHASE 18 UNIFIED PRINT DESIGN SUITE');
console.log('================================================================\n');

assert(/pageWidth: '210mm'/.test(design) && /pageHeight: '297mm'/.test(design) && /@page \{ size: A4 portrait; margin: 0; \}/.test(design),
  'A4Geometry', 'canonical design owns fixed 210 mm x 297 mm geometry and zero browser margin');
assert(/watermarkOpacity: 0\.045/.test(design) && /opacity: 0\.045 !important/.test(design),
  'WatermarkRestrained', 'official clinical watermark is restrained to 4.5% in tokens and print CSS');
assert(/pages\.map\(\(pageData\)/.test(report) && /className="watermark-container bimal-page-watermark"/.test(report),
  'WatermarkEveryPage', 'one watermark is rendered inside every deterministic report page');
assert(/z-index: 0 !important/.test(design) && /bimal-page-content/.test(design) && /z-index: 1 !important/.test(design),
  'WatermarkBehindContent', 'explicit stacking keeps watermark behind clinical content');
assert(/object-fit: contain !important/.test(design) && !/repeat/.test(design.match(/\.bimal-page-watermark[\s\S]*?\}/)?.[0] || ''),
  'WatermarkAspectAndNoTile', 'logo aspect ratio is preserved and watermark is not tiled');
assert(/BIMAL PATHOLOGY/.test(report) && /&amp; DIAGNOSTIC CENTER/.test(report) && /org\.name_ne/.test(report),
  'FullHeaderBranding', 'every page uses the official bilingual laboratory branding');
assert(!/PATHOLOGY REPORT \(Contd\.\)/.test(report) && /IDENTICAL OFFICIAL HEADER & PATIENT BLOCK ON EVERY PAGE/.test(report) && /Page \{pageNumber\} of \{totalPageCount\}/.test(report),
  'FullHeaderEveryPage', 'all deterministic pages share the full official header, identity block, and exact page numbering');
assert(/report-header-diagonal-accent/.test(report) && /report-header-background-wordmark/.test(report) && /BIMAL PATHOLOGY/.test(report) && /maskImage: 'linear-gradient\(to top right/.test(report) && /inset: '0 22mm 0 0'/.test(report),
  'HeaderDiagonalWordmark', 'the translucent green wordmark fades bottom-left to top-right and is clipped before the QR quiet zone');
assert(/report-header-background-logo/.test(report) && /fill-opacity='\.18'/.test(report) && /opacity: 0\.09/.test(report),
  'PremiumHeaderWatermark', 'the header combines a stronger decorative wordmark with one small low-alpha BP logo behind authoritative content');
assert(/report-identity-header/.test(design) && /report-header-diagonal-accent/.test(design) && /z-index: 0 !important/.test(design),
  'HeaderAccentPrintLayer', 'print CSS keeps the accent behind repeated header content and inside the identity region');
assert(/patient-identity-strip/.test(report) && /Patient Name/.test(report) && /UHID/.test(report) && /Lab No\./.test(report) && /Registered/.test(report),
  'PatientInformation', 'fixed compact identity strip contains core patient and report identifiers on every page');
assert(/Collected/.test(report) && /Received/.test(report) && /Reported/.test(report) && /gridTemplateRows: '1fr 1fr'/.test(report),
  'PatientTimingBand', 'the fixed identity band includes authoritative collection, receipt, and reporting timestamps without fabricating values');
assert(/bimal-workspace-texture/.test(report) && /\.bimal-workspace-texture/.test(design) && /backgroundSize: '74mm 63\.5mm'/.test(report),
  'WorkspaceMedicalTexture', 'every clinical workspace carries the same low-opacity, print-safe medical texture behind report content');
assert(/border: `1px solid \$\{BIMAL_PRINT\.border\}`/.test(report) && /className="report-interpretation"/.test(report) && /borderLeft: '2px solid #0b6b3a'/.test(report),
  'RestrainedBoxedSections', 'investigations and long interpretations use thin laboratory-document borders without dashboard styling');
assert(/TEST \/ PARAMETER/.test(report) && /REFERENCE RANGE/.test(report) && /formatResultFlag/.test(report),
  'DynamicClinicalTable', 'dynamic parameters, ranges, units, and textual flags share one table system');
assert(/Reference Laboratory Disclosure: Testing performed by/.test(report) && /OutsourceWithBimalReport/.test(report),
  'OutsourceDisclosure', 'outsource-with-Bimal-report disclosure remains inside canonical design');
assert(!/NoReporting/.test(report), 'NoReportingExcluded', 'renderer has no NoReporting template or clinical branch');
assert(/AMENDED REPORT \(v\{version\}\)/.test(report) && /amendmentReason/.test(report),
  'AmendmentDisclosure', 'amended versions and reasons are visibly distinguished');
assert(/Performed By/.test(report) && /Authorized By/.test(report) && /signature-block/.test(report),
  'DualSnapshotSignatures', 'authoritative Reporting Personnel signatures remain separate and repeat as one locked presentation block per sheet');
assert(/\* END OF REPORT \*/.test(report) && /\{isFinalPage && \(/.test(report),
  'EndOfReportFinalPage', 'end marker renders only on the final page while signature presentation is reserved on every sheet');
assert(/expectedPageCount = 1/.test(pagination) && /isFinalPage: index === packed.length - 1/.test(pagination) && /page-break-after: auto/.test(design),
  'OneTwoFivePagePagination', 'generalized N-page deterministic packing has no forced trailing blank page');
assert(/display: table-header-group/.test(design) && /page-break-inside: avoid/.test(design),
  'RepeatedHeadersNoRowSplit', 'table headings repeat and rows resist physical-page splits');
assert(/document\.createElement\('iframe'\)/.test(printer) && /BIMAL_PRINT_CSS/.test(printer) && !/window\.print\(/.test(reportsPage),
  'IsolatedPrintOnly', 'report actions use the isolated iframe with canonical CSS');
assert(/<ReportDocument/.test(viewer) && /printReportDocument\(\)/.test(viewer) && /downloadReportPdf\(report\)/.test(viewer),
  'PreviewPrintDownloadSameRenderer', 'internal preview, print, and download originate from the canonical report DOM');
assert(/<ReportDocument/.test(publicPage) && (publicPage.match(/printReportDocument\(\)/g) || []).length >= 2,
  'PublicRendererConsistency', 'public preview, print, and PDF action use the same canonical renderer');
assert(/id="printable-invoice"/.test(invoice) && /BIMAL_PRINT_CSS/.test(invoice) && /printReportDocument\('printable-invoice'\)/.test(invoice),
  'InvoiceSharedBrandAndIsolation', 'A4 invoice shares design tokens and isolated print engine without clinical templating');
assert(!/printReportDocument|downloadReportPdf|<ReportDocument/.test(worklist) && !/printReportDocument|downloadReportPdf|<ReportDocument/.test(resultEntry),
  'CentralizedReportEntryPoints', 'ordinary worklist and result entry remain free of final report actions');
assert(!/fonts\.googleapis\.com/.test(printer) && /Noto Sans Devanagari/.test(design),
  'PrintSafeTypography', 'print iframe adds no network font dependency and retains Devanagari-safe fallbacks');
assert(/\.a4-page, \.report-page/.test(design) && /height: 297mm !important/.test(design) &&
  /min-height: 297mm !important/.test(design) && /overflow: hidden !important/.test(design),
  'A4PageContainment', 'every canonical page has fixed A4 geometry, relative positioning, and clipped overflow');
assert(/\.watermark-container[\s\S]*?width: min\(110mm, 100%\) !important/.test(design) &&
  /\.watermark-container > img[\s\S]*?max-width: 110mm !important/.test(design) &&
  !/\.watermark-container[\s\S]*?(?:100vw|background-size:\s*cover|object-fit:\s*cover)/.test(design),
  'WorkspaceWatermarkAdaptive', 'clinical-workspace watermark is adaptively bounded and never uses viewport/cover sizing');
assert(/height: '68mm'/.test(report) && /height: '189mm'/.test(report) && /height: '13mm'/.test(report) && /\.clinical-workspace/.test(design),
  'FixedPhysicalZones', 'every page uses the frozen header, clinical workspace, note, and footer zones');
assert(/className="page-content bimal-page-content clinical-workspace"/.test(report) &&
  /TEST \/ PARAMETER/.test(report) && /Performed By/.test(report) && /bimal-footer-strip/.test(report) &&
  /\.clinical-workspace[\s\S]*?display: flex !important/.test(design),
  'PrintDomContainsFixedZones', 'header, clinical results/signatures, and footer remain in explicit visible physical zones');
assert(/clonePrintElement/.test(printer) && /waitForPrintAssets/.test(printer) &&
  /doc\.fonts\?\.ready/.test(printer) && /Array\.from\(doc\.images\)/.test(printer),
  'PrintWaitsForStylesImagesFonts', 'isolated print DOM retains Emotion styles and waits for images and fonts before printing');
assert(/requestedProfile === 'whole-body'/.test(qa) && /resultsPerInvestigation/.test(qa) && /whole-body-\$\{fixture\.pages\}-pages/.test(visualQa) && /pages: '100'/.test(visualQa),
  'WholeBodyStressFixture', 'QA exercises calibrated 15/24/50/100-page multi-department reports without a separate visual template');

console.log(`\nSUMMARY: ${passed} PASSED, ${failed} FAILED\n`);
if (failed) process.exit(1);
