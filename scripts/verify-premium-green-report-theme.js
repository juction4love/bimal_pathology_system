import fs from 'node:fs';

const report = fs.readFileSync('src/features/reports/ReportDocument.tsx', 'utf8');
const design = fs.readFileSync('src/lib/printDesign.ts', 'utf8');
const qa = fs.readFileSync('src/printQa.tsx', 'utf8');
let passed = 0;

function check(condition, label) {
  if (!condition) throw new Error(`FAIL: ${label}`);
  passed += 1;
  console.log(`PASS: ${label}`);
}

check(design.includes("brand: '#0b6b3a'") && design.includes("brandDeep: '#07562f'"), 'canonical print tokens use Bimal green');
check(report.includes('data-report-theme="bimal-premium-green"'), 'one canonical renderer declares the premium green theme');
check(report.includes("height: '68mm'") && report.includes("height: '189mm'") && report.includes("height: '13mm'"), 'fixed physical geometry is frozen');
check(report.includes('report-header-diagonal-accent') && report.includes("inset: '0 22mm 0 0'"), 'header branding remains clipped outside the QR quiet zone');
check(report.includes("bgcolor: 'rgba(237,247,241,0.94)'") && report.includes('patient-identity-strip'), 'patient information uses the approved light-green band');
check(report.includes('className="department-header-block"') && report.includes('bgcolor: BIMAL_PRINT.brand'), 'investigation headings use full-width Bimal green hierarchy');
check(report.includes("bgcolor: 'rgba(237,247,241,0.72)'") && report.includes('TEST / PARAMETER'), 'result column heading uses a pale-green print-safe treatment');
check(report.includes("color: isCritical ? '#b91c1c' : isAbnormal ? '#c2410c'"), 'clinical abnormal and critical emphasis is preserved');
check(report.includes('className="signature-block"') && report.includes('border: `1px solid ${BIMAL_PRINT.brand}`'), 'every-page signature section retains a green professional border');
check(report.includes('bgcolor: BIMAL_PRINT.brand') && report.includes("color: '#ffffff'") && report.includes('className="bimal-footer-strip"'), 'fixed footer uses the premium green theme');
check(design.includes('-webkit-print-color-adjust: exact !important') && design.includes('print-color-adjust: exact !important'), 'color and grayscale print treatments are explicitly preserved');
check(report.includes("fill='rgb(11,107,58)'") && report.includes('bimal-workspace-texture'), 'header and workspace branding remain subtle Bimal green');
check(report.includes("gridTemplateColumns: 'minmax(0, 1.3fr) minmax(0, 1.5fr) auto'") && report.includes('bimal-footer-contact') && report.includes('bimal-footer-report-identity') && report.includes('bimal-footer-page-number'), 'footer has deterministic non-overlapping three-column ownership');
check(report.includes("overflowWrap: 'anywhere'") && report.includes("whiteSpace: 'nowrap'") && !report.includes('integrityHash.substring'), 'footer wraps long identity fields without truncating integrity or wrapping page count');
check(qa.includes('laboratory.reporting.office@bimalpathology.com.np') && qa.includes('REP-2026-00010-WHOLE-BODY-COMPREHENSIVE') && qa.includes('version={version}') && qa.includes('12'), 'QA exercises long email, report identity, integrity hash, and version 12+');

console.log(`Premium green report theme: ${passed} passed, 0 failed`);
