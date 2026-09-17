import fs from 'node:fs';

const report = fs.readFileSync('src/features/reports/ReportDocument.tsx', 'utf8');
const design = fs.readFileSync('src/lib/printDesign.ts', 'utf8');
let passed = 0;
const check = (condition, label) => {
  if (!condition) throw new Error(`FAIL: ${label}`);
  passed += 1;
  console.log(`PASS: ${label}`);
};

const line1 = report.indexOf('BIMAL PATHOLOGY');
const line2 = report.indexOf('&amp; DIAGNOSTIC CENTER');
const investigations = report.indexOf('{pageInvs.map');
const endMarker = report.indexOf('className="clinical-end-marker"');
const signature = report.indexOf('className="signature-block"');
const headerStart = report.indexOf('className="report-header"');
const headerEnd = report.indexOf('className="patient-info-box"');
const header = report.slice(headerStart, headerEnd);

check(line1 >= 0 && line2 > line1, 'English laboratory name has explicit ordered line 1 and line 2');
check((report.match(/english-laboratory-name-line/g) || []).length === 2 && report.includes("whiteSpace: 'nowrap'"), 'both English name lines are controlled and cannot wrap');
check(report.includes('english-laboratory-name-primary') && report.includes("fontSize: '1.52rem'") && report.includes('fontWeight: 900'), 'BIMAL PATHOLOGY is substantially larger and extra-bold');
check(report.includes('english-laboratory-name-secondary') && report.includes("fontSize: '1.18rem'") && report.includes('fontWeight: 800'), 'diagnostic center is a slightly smaller bold second line');
check(report.includes("fontSize: '0.96rem'") && report.includes("fontFamily: \"'Mukta', 'Noto Sans Devanagari'"), 'Nepali heading is modestly enlarged with its Devanagari stack');
check(report.includes('className="report-qr-quiet-zone"') && report.includes('minWidth: \'68px\'') && report.includes('width="68"') && report.includes('height="68"'), 'QR dimensions and minimum quiet area are preserved');
check(header.includes("width: '68px'") && header.includes("whiteSpace: 'normal'"), 'QR caption wraps inside its own column instead of colliding with PAN');
check(header.includes("display: 'grid'") && header.includes("gridTemplateColumns: 'minmax(0, 1fr) 75mm'"), 'top header reserves a deterministic report column and gives the remaining width to branding');
check(header.includes('className="report-header-right"') && header.includes("gridTemplateColumns: 'minmax(0, 1fr) 68px'"), 'QR occupies an independent bounded right column');
check(header.includes('className="report-title"') && header.includes('className="report-state"') && header.includes('className="report-registration"'), 'title, report state, and registration are separate DOM blocks');
check(header.includes("className=\"report-title-stack\"") && header.includes("rowGap: '4px'") && header.includes('minWidth: 0'), 'title stack has explicit spacing and may shrink without entering the QR column');
check(!/position:\s*'absolute'|transform:|mt:\s*-[\d.]+|marginTop:\s*-[\d.]+/.test(header), 'header contains no absolute overlap, translation, or negative-margin hacks');
check(header.includes('Regd. No.:') && header.includes('PAN:') && header.includes('Scan to verify report'), 'registration, PAN, and QR caption remain present');
check(investigations >= 0 && endMarker > investigations && signature > endMarker, 'clinical End marker follows investigations and precedes signatures');
check(!report.slice(signature, report.indexOf('bimal-footer-strip')).includes('* END OF REPORT *'), 'End marker is not inside the signature container');
check((report.match(/\* END OF REPORT \*/g) || []).length === 1, 'End marker render text occurs exactly once');
check(report.slice(endMarker - 120, endMarker).includes('{isFinalPage && ('), 'End marker renders only on the final clinical-content page');
check(/className="signature-block"[^>]*sx=\{\{[^}]*flexShrink: 0/.test(report) && report.includes('border: `1px solid ${BIMAL_PRINT.brand}`') && report.includes("borderLeft: '1px solid #d5e6dc'"), 'each sheet reserves the same restrained, branded, non-shrinking signature section');
check(design.includes('Page X of Y') || (report.includes('Page {pageNumber} of {totalPageCount}') && design.includes('bimal-footer-strip')), 'footer and deterministic pagination contract remain intact');

console.log(`\nPhase 20 report header/end-marker verification: ${passed} passed, 0 failed`);
