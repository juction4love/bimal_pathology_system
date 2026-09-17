import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

import {
  isValidMoneyIntermediate,
  validateMoneyCommitted,
  parseRupeesToPaisa,
  rupeesToPaisa,
  paisaToRupees,
  calculateBillTotals,
} from '../src/lib/currency.ts';

describe('Billing Money Input UX & Financial Integrity Regression Suite', () => {
  describe('1. Intermediate Keystroke Acceptance (No Modal Dialog / No Premature Rejection)', () => {
    it('accepts empty string during field clearing without throwing or rejecting', () => {
      assert.strictEqual(isValidMoneyIntermediate(''), true);
    });

    it('accepts "0" and leading single digits', () => {
      assert.strictEqual(isValidMoneyIntermediate('0'), true);
      assert.strictEqual(isValidMoneyIntermediate('3'), true);
      assert.strictEqual(isValidMoneyIntermediate('5'), true);
      assert.strictEqual(isValidMoneyIntermediate('500'), true);
    });

    it('accepts trailing single dot "3." without throwing or triggering modal validation', () => {
      assert.strictEqual(isValidMoneyIntermediate('3.'), true);
      assert.strictEqual(isValidMoneyIntermediate('50.'), true);
      assert.strictEqual(isValidMoneyIntermediate('500.'), true);
    });

    it('accepts one decimal place "3.5"', () => {
      assert.strictEqual(isValidMoneyIntermediate('3.5'), true);
      assert.strictEqual(isValidMoneyIntermediate('500.5'), true);
    });

    it('accepts two decimal places "3.50" and "500.00"', () => {
      assert.strictEqual(isValidMoneyIntermediate('3.50'), true);
      assert.strictEqual(isValidMoneyIntermediate('500.00'), true);
      assert.strictEqual(isValidMoneyIntermediate('0.00'), true);
    });

    it('rejects third decimal place "3.501" without popup dialog', () => {
      assert.strictEqual(isValidMoneyIntermediate('3.501'), false);
      assert.strictEqual(isValidMoneyIntermediate('500.001'), false);
    });

    it('rejects negative numbers and alphabetical characters immediately from keystroke state', () => {
      assert.strictEqual(isValidMoneyIntermediate('-1'), false);
      assert.strictEqual(isValidMoneyIntermediate('-500'), false);
      assert.strictEqual(isValidMoneyIntermediate('abc'), false);
      assert.strictEqual(isValidMoneyIntermediate('12a'), false);
      assert.strictEqual(isValidMoneyIntermediate('3..'), false);
      assert.strictEqual(isValidMoneyIntermediate('3.5.0'), false);
    });
  });

  describe('2. Committed Blur / Final Validation (Rate, Discount, Paid Amount)', () => {
    it('normalizes valid integers to two decimals on blur ("3" -> "3.00", "500" -> "500.00")', () => {
      const res3 = validateMoneyCommitted('3', { required: true, fieldName: 'Rate' });
      assert.strictEqual(res3.isValid, true);
      assert.strictEqual(res3.paisa, 300);
      assert.strictEqual(res3.normalizedText, '3.00');
      assert.strictEqual(res3.error, null);

      const res500 = validateMoneyCommitted('500', { required: true, fieldName: 'Rate' });
      assert.strictEqual(res500.isValid, true);
      assert.strictEqual(res500.paisa, 50000);
      assert.strictEqual(res500.normalizedText, '500.00');
      assert.strictEqual(res500.error, null);
    });

    it('normalizes valid decimal typing to two decimals ("3.5" -> "3.50", "3." -> "3.00")', () => {
      const res35 = validateMoneyCommitted('3.5', { required: true, fieldName: 'Rate' });
      assert.strictEqual(res35.isValid, true);
      assert.strictEqual(res35.paisa, 350);
      assert.strictEqual(res35.normalizedText, '3.50');

      const res3Dot = validateMoneyCommitted('3.', { required: true, fieldName: 'Rate' });
      assert.strictEqual(res3Dot.isValid, true);
      assert.strictEqual(res3Dot.paisa, 300);
      assert.strictEqual(res3Dot.normalizedText, '3.00');
    });

    it('returns inline validation error on blur when required rate is left empty', () => {
      const emptyRes = validateMoneyCommitted('', { required: true, fieldName: 'Rate' });
      assert.strictEqual(emptyRes.isValid, false);
      assert.strictEqual(emptyRes.paisa, null);
      assert.strictEqual(emptyRes.error, 'Rate is required.');
    });

    it('allows empty string for optional discount and treats it as zero without error', () => {
      const discountRes = validateMoneyCommitted('', { required: false, fieldName: 'Discount' });
      assert.strictEqual(discountRes.isValid, true);
      assert.strictEqual(discountRes.paisa, 0);
      assert.strictEqual(discountRes.error, null);
    });

    it('enforces maximum bounds on discount and paid amounts', () => {
      const grossPaisa = 100000; // NPR 1,000.00
      const excessiveDiscount = validateMoneyCommitted('1200', {
        required: false,
        fieldName: 'Discount',
        maxPaisa: grossPaisa,
      });
      assert.strictEqual(excessiveDiscount.isValid, false);
      assert.strictEqual(excessiveDiscount.error, 'Discount cannot exceed NPR 1000.00.');
    });

    it('enforces zero price policy when allowZero is false', () => {
      const zeroRate = validateMoneyCommitted('0', {
        required: true,
        fieldName: 'Rate',
        allowZero: false,
      });
      assert.strictEqual(zeroRate.isValid, false);
      assert.strictEqual(zeroRate.error, 'NPR 0 is not authorized for rate. Enter the agreed rate.');
    });
  });

  describe('3. Component & Page Source Contracts', () => {
    it('verifies MoneyInputField component exists and uses isValidMoneyIntermediate & validateMoneyCommitted', () => {
      const compPath = path.resolve('src/components/common/MoneyInputField.tsx');
      assert.strictEqual(fs.existsSync(compPath), true, 'MoneyInputField.tsx must exist');
      const compSource = fs.readFileSync(compPath, 'utf8');
      assert.ok(compSource.includes('isValidMoneyIntermediate'), 'Must use isValidMoneyIntermediate');
      assert.ok(compSource.includes('validateMoneyCommitted'), 'Must use validateMoneyCommitted');
      assert.ok(!compSource.includes('setErrorMsg('), 'Component must not trigger global error modals');
    });

    it('verifies NewBillPage integrates MoneyInputField for Rate, Discount, and Paid Amount', () => {
      const billPath = path.resolve('src/features/billing/NewBillPage.tsx');
      const billSource = fs.readFileSync(billPath, 'utf8');
      assert.ok(billSource.includes('MoneyInputField'), 'NewBillPage must import and use MoneyInputField');
      assert.ok(billSource.includes('handleCommitItemPrice'), 'NewBillPage must have handleCommitItemPrice');
      assert.ok(billSource.includes('parseRupeesToPaisa'), 'Must maintain parseRupeesToPaisa');
      assert.ok(billSource.includes('calculateBillTotals'), 'Must calculate totals in integer paisa');
    });

    it('verifies BillListPage uses intermediate money validation for payment amount', () => {
      const listPath = path.resolve('src/features/billing/BillListPage.tsx');
      const listSource = fs.readFileSync(listPath, 'utf8');
      assert.ok(listSource.includes('isValidMoneyIntermediate'), 'BillListPage must use isValidMoneyIntermediate');
    });
  });

  describe('4. Integer Paisa Financial Calculations Invariant', () => {
    it('accurately calculates gross, discount, net, paid, and due in integer paisa', () => {
      const items = [
        { unitPricePaisa: 50000 }, // NPR 500.00
        { unitPricePaisa: 35000 }, // NPR 350.00
      ];
      const customDiscountPaisa = 5000; // NPR 50.00
      const paidPaisa = 80000; // NPR 800.00

      const totals = calculateBillTotals(items, customDiscountPaisa, paidPaisa);
      assert.strictEqual(totals.grossPaisa, 85000);
      assert.strictEqual(totals.totalDiscountPaisa, 5000);
      assert.strictEqual(totals.netPaisa, 80000);
      assert.strictEqual(totals.paidPaisa, 80000);
      assert.strictEqual(totals.duePaisa, 0);
      assert.strictEqual(totals.paymentStatus, 'Paid');
    });

    it('preserves exact conversion between rupees and paisa without floating point drift', () => {
      assert.strictEqual(parseRupeesToPaisa('500.00'), 50000);
      assert.strictEqual(parseRupeesToPaisa('3.50'), 350);
      assert.strictEqual(parseRupeesToPaisa('1.001'), null);
      assert.strictEqual(rupeesToPaisa('500.00'), 50000);
      assert.strictEqual(rupeesToPaisa('3.50'), 350);
      assert.strictEqual(rupeesToPaisa('0.05'), 5);
      assert.strictEqual(paisaToRupees(50000), 500);
      assert.strictEqual(paisaToRupees(350), 3.5);
      assert.strictEqual(paisaToRupees(5), 0.05);
    });
  });
});
