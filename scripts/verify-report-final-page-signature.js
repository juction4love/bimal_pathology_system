/** Executable regression suite for generalized final-page signatory pagination. */
import fs from 'node:fs';
import { paginateInvestigations, REPORT_PAGINATION_MM, resultHeightMm, signatoryReserveMm } from '../src/features/reports/reportPagination.js';

const report = fs.readFileSync('src/features/reports/ReportDocument.tsx', 'utf8');
const design = fs.readFileSync('src/lib/printDesign.ts', 'utf8');
const qa = fs.readFileSync('src/printQa.tsx', 'utf8');
let passed = 0;
function check(condition, message) { if (!condition) throw new Error(message); passed++; console.log(`  PASS ${message}`); }
function results(count, options = {}) { return Array.from({ length: count }, (_, index) => ({ name: options.long ? `Parameter ${index + 1} with a realistically long diagnostic parameter name that wraps onto additional lines` : `Parameter ${index + 1}`, unit: options.long ? 'international units per litre (IU/L)' : 'g/dL', reference_range: options.long ? 'Age and sex adjusted interval: 5.0 - 20.0; correlate with clinical history and prior results' : '5.0 - 20.0', display_value: `${index + 1}.5`, flag: index === 1 ? 'High' : index === 2 ? 'CriticalHigh' : 'Normal', is_critical: index === 2 })); }
function fixture(count, options = {}) { return [{ test_name: options.long ? 'A very long investigation and profile name that wraps safely across the report heading' : 'Pagination QA Profile', results: results(count, options), interpretation_template: options.interpretation ?? null }]; }

const exactFixtures = new Map([[1, 8], [2, 30], [3, 45], [4, 62], [5, 78], [8, 130]]);
for (const [expectedPages, rowCount] of exactFixtures) {
  const pages = paginateInvestigations(fixture(rowCount));
  check(pages.length === expectedPages, `${expectedPages}-page fixture calculates exactly ${expectedPages} page(s)`);
  check(pages.filter((page) => page.isFinalPage).length === 1, `${expectedPages}-page fixture has exactly one final page`);
  check(pages.at(-1).isFinalPage && pages.at(-1).pageNumber === expectedPages, `${expectedPages}-page fixture reserves signatures on page N`);
  check(pages.slice(0, -1).every((page) => !page.isFinalPage), `${expectedPages}-page fixture marks only Page N as final`);
  check(pages.every((page) => page.usedMm <= page.capacityMm), `${expectedPages}-page fixture content stays within physical capacity`);
}

const wrapped = paginateInvestigations(fixture(28, { long: true, interpretation: 'First multiline clinical interpretation.\nSecond line near a page boundary.\nThird line remains above signatures and footer.' }));
check(wrapped.length > 2 && wrapped.every((page) => page.usedMm <= page.capacityMm), 'wrapped names, units, ranges, flags, and multiline comments repaginate without overflow');
const multipleInvestigations = paginateInvestigations([...fixture(45), { ...fixture(45, { interpretation: 'Final investigation interpretation.' })[0], test_name: 'Second Investigation' }, { ...fixture(45)[0], test_name: 'Third Investigation' }]);
check(multipleInvestigations.length >= 4 && multipleInvestigations.every((page) => page.usedMm <= page.capacityMm), 'multiple investigations span arbitrary page boundaries safely');
const safeSplit = paginateInvestigations([
  { test_name: 'Complete Blood Count (CBC / Hemogram)', results: results(11), interpretation_template: null },
  { test_name: 'Liver Function Test (LFT)', results: results(10), interpretation_template: null },
]);
const firstPageLft = safeSplit[0].investigations.find((investigation) => investigation.test_name === 'Liver Function Test (LFT)');
const continuedLft = safeSplit[1].investigations.find((investigation) => investigation.test_name === 'Liver Function Test (LFT)');
check(Boolean(firstPageLft?.results.length && continuedLft?.is_continuation && continuedLft.results.length), 'large investigation begins only when heading, table header, and first result fit, then continues safely');
check(safeSplit.flatMap((page) => page.investigations).filter((investigation) => investigation.test_name === 'Liver Function Test (LFT)').reduce((count, investigation) => count + investigation.results.length, 0) === 10, 'split investigation preserves every result exactly once');

const oneLineHeight = resultHeightMm(results(1)[0]);
const finalCapacity = paginateInvestigations(fixture(1))[0].capacityMm;
check(finalCapacity + signatoryReserveMm() + REPORT_PAGINATION_MM.clinicalEndMarker + REPORT_PAGINATION_MM.clinicalNote + REPORT_PAGINATION_MM.footer + REPORT_PAGINATION_MM.fullPageHeader === REPORT_PAGINATION_MM.printableHeight, 'final capacity includes the repeated full header, per-page signature, note, footer, end-marker, and safety reserves');
check(resultHeightMm({ ...results(1)[0], name: 'x'.repeat(41) }) > oneLineHeight, 'one wrapped line beyond the measured parameter-column boundary expands row height');
check((report.match(/className="signature-block"/g) || []).length === 1 && !report.slice(report.indexOf('className="signature-block"') - 80, report.indexOf('className="signature-block"')).includes('{isFinalPage && ('), 'renderer maps one legitimate signatory block onto every physical page');
check(report.includes("{inv.test_name}{isContinuation ? ' — continued' : ''}") && report.includes('data-investigation-continuation'), 'renderer gives split investigations a compact explicit continuation identity');
check(report.includes('border: `1px solid ${BIMAL_PRINT.brand}`') && report.includes("gridTemplateColumns: signatories?.authorized_by ? '1fr 1fr' : '1fr'"), 'final signatories use one restrained branded section with natural one/two-column geometry');
check(report.includes('flexShrink: 0'), 'signatory and footer are non-shrinking');
check(design.includes('.signature-block') && design.includes('break-inside: avoid'), 'print CSS keeps the signatory block together');
check(qa.includes("requested === 'N'") && qa.includes('1: 8') && qa.includes('4: 62') && qa.includes('8: 130'), 'browser QA exposes explicit 1-5 and 8-page fixtures recalibrated for per-sheet signature zones');
check(qa.includes("requestedProfile === 'urea-cbc-creatinine'") && qa.includes("test_name: 'Blood Urea'") && qa.includes("test_name: 'Complete Blood Count (CBC / Hemogram)'") && qa.includes("test_name: 'Serum Creatinine'"), 'QA includes the supplied Blood Urea, CBC, and Serum Creatinine regression report');
check(qa.includes('qaSignatureOnEveryPage') && qa.includes('qaContentBeforeSignature') && qa.includes('qaSignatureBeforeFooter') && qa.includes('qaFinalPageContained'), 'browser QA records per-page signatures, ordering, overlap, and clipping geometry');
check(qa.includes("requestedProfile === 'one-signatory'") && qa.includes("'q'.repeat(40)"), 'QA covers one/two signatories and secure QR');
check(qa.includes("requestedProfile === 'identity'") && qa.includes('श्रीमती प्रज्ञा कुमारी अधिकारी लामिछाने') && qa.includes('A Very Long Referring Clinician Name'), 'browser QA covers Devanagari and long patient/referrer identity wrapping');
check(report.includes("gridTemplateColumns: signatories?.authorized_by ? '1fr 1fr' : '1fr'") && report.includes("{signatories?.authorized_by && <Box"), 'one-signatory report uses one real signatory panel without an invented placeholder');
check(!report.includes("formatAdDateTime(new Date())") && !report.includes("patient.address || 'Bharatpur, Chitwan'") && !report.includes("order.referring_doctor_name || 'Self / Walk-in'"), 'missing snapshot metadata is never fabricated by the report renderer');
check(report.includes("textDecoration: isCritical ? 'double underline'") && report.includes("textDecoration: isCritical ? 'double underline' : isAbnormal ? 'underline'"), 'abnormal and critical results remain distinguishable in grayscale without color alone');
console.log(`Generalized final-page signatory regression: ${passed} passed, 0 failed`);
