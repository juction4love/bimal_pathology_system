import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const dialog = read('src/components/common/SmartMessageDialog.tsx');
const mapper = read('src/lib/safeError.ts');
const resultEntry = read('src/features/worklist/ResultEntryPage.tsx');
const patients = read('src/features/patients/PatientsPage.tsx');
const bills = read('src/features/billing/BillListPage.tsx');
const pageHeader = read('src/components/common/PageHeader.tsx');
const sourceFiles = [];
const collect = (directory) => {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) collect(full);
    else if (/\.(ts|tsx)$/.test(entry.name)) sourceFiles.push(read(path.relative(root, full)));
  }
};
collect(path.join(root, 'src'));
const allSource = sourceFiles.join('\n');

let passed = 0;
let failed = 0;
const check = (condition, name) => {
  if (condition) { passed++; console.log(`PASS ${name}`); }
  else { failed++; console.error(`FAIL ${name}`); }
};

check(/'success' \| 'info' \| 'warning' \| 'error' \| 'confirm'/.test(mapper), 'all required variants are typed');
check(dialog.includes('Bimal Pathology') && dialog.includes('maxWidth="xs"'), 'centered branded application dialog');
check(dialog.includes("m: { xs: 2, sm: 3 }") && dialog.includes("minHeight: 44"), '320px responsive margins and touch targets');
check(dialog.includes('aria-labelledby') && dialog.includes('aria-describedby') && dialog.includes('autoFocus'), 'accessible title description and initial focus');
check(dialog.includes("event.key === 'Enter'") && dialog.includes('disableEscapeKeyDown'), 'keyboard primary action and safe Escape behavior');
check(dialog.includes("resolvedVariant === 'confirm'") && dialog.includes('onSecondary'), 'confirmation requires explicit primary or secondary action');
check(mapper.includes('This mobile number is already registered.') && mapper.includes('use the existing patient record'), 'duplicate mobile mapping');
check(mapper.includes('You do not have permission to perform this action.'), 'permission mapping');
check(mapper.includes('Unable to connect. Check your internet connection and try again.'), 'network mapping');
check(mapper.includes('Payment amount is greater than the outstanding balance.'), 'overpayment mapping');
check(mapper.includes('This payment has already been processed.'), 'duplicate payment mapping');
check(mapper.includes('Patient details changed. Refresh and try again.'), 'stale patient mapping');
check(mapper.includes('This report can no longer be modified.'), 'signed report mapping');
check(mapper.includes("fallback = 'Something went wrong. Please try again.'") && !mapper.includes('return candidate.message'), 'unexpected failures use safe fallback without raw text');
check(!/\b(?:window\.)?(?:alert|confirm)\s*\(/.test(allSource), 'no browser-native alert or confirm');
check(!/set(?:Error|ErrorMsg|CatalogueError)\([^\n]*(?:err|error|caught)\.message/.test(allSource), 'raw backend messages are not assigned to blocking UI state');
check(pageHeader.includes('<SmartMessageDialog') && pageHeader.includes('Reference: ${this.state.reference}') && !pageHeader.includes('this.state.error?.message'), 'root runtime boundary uses a safe centered dialog without exposing exception text');
check(patients.includes('variant="confirm"') && patients.includes('Delete unused patient'), 'patient archive/delete uses smart confirmation');
check(bills.includes('finalPaymentConfirmOpen') && bills.includes('Record final payment'), 'final receipt uses smart confirmation');
check(resultEntry.includes('signOffConfirmOpen') && resultEntry.includes('Sign and finalize this diagnostic report?'), 'report sign-off uses smart confirmation');
check([
  'src/features/patients/PatientsPage.tsx',
  'src/features/billing/NewBillPage.tsx',
  'src/features/billing/BillListPage.tsx',
  'src/features/samples/SampleAccessioningPage.tsx',
  'src/features/worklist/WorklistPage.tsx',
  'src/features/worklist/ResultEntryPage.tsx',
  'src/features/reports/ReportsPage.tsx',
  'src/features/admin/SmsDeliveryPage.tsx',
].every((file) => read(file).includes('SmartMessageDialog')), 'major workflows share the dialog implementation');

console.log(`\nSmart message dialog regression: ${passed} passed, ${failed} failed`);
if (failed) process.exit(1);
