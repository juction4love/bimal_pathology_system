import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const css = read('src/index.css');
const theme = read('src/app/theme.ts');
const billing = read('src/features/billing/NewBillPage.tsx');
const status = read('src/components/common/StatusChip.tsx');
const tech = read('src/features/dashboard/TechnicianDashboard.tsx');
const layout = read('src/app/AppLayout.tsx');
const printDocument = read('src/features/reports/ReportDocument.tsx');
const printDesign = read('src/lib/printDesign.ts');

let passed = 0;
const check = (condition, label) => {
  if (!condition) throw new Error(`FAIL: ${label}`);
  passed += 1;
  console.log(`PASS: ${label}`);
};

check(css.includes('--color-primary: #0b6b3a') && css.includes('--color-sidebar: #063f2c') && css.includes('--color-sidebar-active: #0b8f55'), 'green brand, sidebar, and active-route tokens');
check(theme.includes("main: '#0b6b3a'") && theme.includes("containedPrimary") && theme.includes("backgroundColor: '#075f34'"), 'green primary buttons and darker hover');
check(theme.includes("backgroundColor: '#e9f7ef'") && theme.includes("backgroundColor: '#ddf4e7'"), 'shared mint table header and selected-row styling');
check(layout.includes("bgcolor: 'var(--color-sidebar)'") && layout.includes("var(--color-sidebar-active) !important") && layout.includes('opacity: 1'), 'dark sidebar, active state, and full-opacity navigation');
check(billing.includes("position: 'sticky', top: 80") && billing.includes('Search Test / Profile / Package'), 'billing fast search and sticky financial action column');
check(billing.includes("e.key === 'Enter'") && billing.includes('selectCatalogueResult(match)'), 'keyboard Add action remains immediate and visible through search results');
check(!billing.includes('Configure catalogue price') && billing.includes('Price not configured'), 'catalogue mutation is excluded from reception billing');
check(billing.includes('parseRupeesToPaisa') && billing.includes('create_patient_bill_order_with_packages'), 'integer-paisa billing and guarded server transaction are reused');
check(status.includes('--color-verification-soft') && status.includes('--color-danger-soft') && !status.includes("animation: 'pulse"), 'semantic status colors include text and avoid flashing');
check(status.includes("status === REPORTING_TYPES.IN_HOUSE") && status.includes("color: 'var(--color-primary)'"), 'In-House reporting chip uses clinical green');
check(!tech.includes('Revenue') && !tech.includes('Outstanding Due') && !tech.includes('Today\'s Collection'), 'technician dashboard remains financially isolated');
check(billing.includes('xs={12} lg={8}') && billing.includes('xs={12} lg={4}') && billing.includes('overflow: \'auto\''), 'billing responsive columns and bounded table overflow');
check(printDocument.includes('BIMAL_PRINT.watermarkOpacity') && printDesign.includes('watermarkOpacity: 0.045') && printDesign.includes('110mm') && printDesign.includes('.clinical-workspace'), 'adaptive canonical clinical-workspace watermark and renderer contract remains present');
check(
  printDocument.includes("signatories?.authorized_by ? 'FINAL SIGNED REPORT' : 'FINAL REPORT'") &&
  printDocument.includes("gridTemplateColumns: signatories?.authorized_by ? '1fr 1fr' : '1fr'") &&
  printDocument.includes('{signatories?.authorized_by && <Box') &&
  printDesign.includes('@page { size: A4 portrait; margin: 0; }') &&
  read('src/lib/reportPrint.ts').includes('clonePrintElement'),
  'optional authorizer remains explicit while canonical A4 and isolated print contracts remain intact',
);

console.log(`\nPhase 19 UI theme verification: ${passed} passed, 0 failed`);
