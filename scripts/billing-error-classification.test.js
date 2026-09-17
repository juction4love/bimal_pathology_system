import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const errors = fs.readFileSync('src/lib/safeError.ts', 'utf8');
const billing = fs.readFileSync('src/features/billing/NewBillPage.tsx', 'utf8');

test('billing exposes only stable diagnostic classifications', () => {
  for (const code of ['BILL-AUTH','BILL-VALIDATION','BILL-DUPLICATE','BILL-CATALOGUE','BILL-CONNECTIVITY','BILL-TRANSACTION']) {
    assert.match(errors, new RegExp(code));
  }
  assert.match(billing, /safeBillingDiagnosticCode\(err\)/);
  assert.doesNotMatch(billing, /console\.error\('\[Billing Error\]', err\)/);
});

test('billing diagnostic output excludes raw server messages', () => {
  assert.match(billing, /console\.error\('\[Billing Error\]', \{ reference, code: diagnostic\.code, status: diagnostic\.status \}\)/);
  assert.match(errors, /never includes server error text/);
});
