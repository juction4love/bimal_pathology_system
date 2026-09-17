import { test, expect } from '@playwright/test';
import { makeState, installSyntheticBackend, observe, login, IDS } from './synthetic00092Adapter.js';

test.describe('LFT Result Entry & Verification Acceptance Suite', () => {
  test('A & F & G: Complete valid LFT -> live calculation preview -> 1-click Verify -> auto-next sign ready', async ({ page, context }) => {
    const state = makeState();
    // Configure LFT as the active test to enter
    state.items[1].status = 'Received'; // LFT
    await installSyntheticBackend(context, state);
    observe(page, state);
    await login(page);

    await page.goto(`/worklist/order/${IDS.order}?item=${state.items[1].id}`);
    await expect(page.getByText('Synthetic Acceptance', { exact: true }).first()).toBeVisible();
    await expect(page.getByText('LFT', { exact: true }).first()).toBeVisible();

    // Verify all 10 LFT parameters are rendered
    await expect(page.getByText('Bilirubin Total')).toBeVisible();
    await expect(page.getByText('Bilirubin Direct')).toBeVisible();
    await expect(page.getByText('Bilirubin Indirect')).toBeVisible();
    await expect(page.getByText('AST / SGOT')).toBeVisible();
    await expect(page.getByText('ALT / SGPT')).toBeVisible();
    await expect(page.getByText('Alkaline Phosphatase')).toBeVisible();
    await expect(page.getByText('Total Protein')).toBeVisible();
    await expect(page.getByText('Albumin')).toBeVisible();
    await expect(page.getByText('Globulin')).toBeVisible();
    await expect(page.getByText('A:G Ratio')).toBeVisible();

    // Fill in Total Bilirubin (1.01) and Direct Bilirubin (0.25)
    const tbilInput = page.getByRole('row', { name: /Bilirubin Total/i }).getByRole('textbox');
    const dbilInput = page.getByRole('row', { name: /Bilirubin Direct/i }).getByRole('textbox');
    await tbilInput.fill('1.01');
    await dbilInput.fill('0.25');

    // Live calculation of Indirect Bilirubin (1.01 - 0.25 = 0.76)
    const ibilRow = page.getByRole('row', { name: /Bilirubin Indirect/i });
    await expect(ibilRow.getByRole('textbox')).toHaveValue('0.76');

    // Fill in AST, ALT, ALP
    await page.getByRole('row', { name: /AST \/ SGOT/i }).getByRole('textbox').fill('35');
    await page.getByRole('row', { name: /ALT \/ SGPT/i }).getByRole('textbox').fill('40');
    await page.getByRole('row', { name: /Alkaline Phosphatase/i }).getByRole('textbox').fill('120');

    // Fill in Total Protein (7.2) and Albumin (4.2)
    const tpInput = page.getByRole('row', { name: /Total Protein/i }).getByRole('textbox');
    const albInput = page.getByRole('row', { name: /Albumin/i }).getByRole('textbox');
    await tpInput.fill('7.2');
    await albInput.fill('4.2');

    // Live calculation of Globulin (7.2 - 4.2 = 3.00) and A:G Ratio (4.2 / 3.00 = 1.40)
    const globRow = page.getByRole('row', { name: /Globulin/i });
    const agRow = page.getByRole('row', { name: /A:G Ratio/i });
    await expect(globRow.getByRole('textbox')).toHaveValue('3.00');
    await expect(agRow.getByRole('textbox')).toHaveValue('1.40');

    // Verify Results button is directly available for the Lab Technician
    const verifyBtn = page.getByRole('button', { name: 'Verify Results' });
    await expect(verifyBtn).toBeVisible();
    await expect(verifyBtn).toBeEnabled();

    // Click Verify Results
    await verifyBtn.click();

    // Auto-next workflow advances to the next step
    expect(state.items[1].status).toBe('Verified');
    expect(state.issues).toEqual([]);
  });

  test('C: Direct Bilirubin exceeds Total Bilirubin -> actionable validation alert blocks verification', async ({ page, context }) => {
    const state = makeState();
    state.items[1].status = 'Received';
    await installSyntheticBackend(context, state);
    observe(page, state);
    await login(page);

    await page.goto(`/worklist/order/${IDS.order}?item=${state.items[1].id}`);

    // Fill DBIL (1.50) > TBIL (1.00)
    await page.getByRole('row', { name: /Bilirubin Total/i }).getByRole('textbox').fill('1.00');
    await page.getByRole('row', { name: /Bilirubin Direct/i }).getByRole('textbox').fill('1.50');
    await page.getByRole('row', { name: /AST \/ SGOT/i }).getByRole('textbox').fill('35');
    await page.getByRole('row', { name: /ALT \/ SGPT/i }).getByRole('textbox').fill('40');
    await page.getByRole('row', { name: /Alkaline Phosphatase/i }).getByRole('textbox').fill('120');
    await page.getByRole('row', { name: /Total Protein/i }).getByRole('textbox').fill('7.2');
    await page.getByRole('row', { name: /Albumin/i }).getByRole('textbox').fill('4.2');

    const verifyBtn = page.getByRole('button', { name: 'Verify Results' });
    await verifyBtn.click();

    // Actionable error message shown and verify prevented
    await expect(page.getByText('Direct Bilirubin cannot exceed Total Bilirubin.')).toBeVisible();
    expect(state.items[1].status).toBe('Received');
  });

  test('E: Missing Total Protein -> actionable blocker prevents verification', async ({ page, context }) => {
    const state = makeState();
    state.items[1].status = 'Received';
    await installSyntheticBackend(context, state);
    observe(page, state);
    await login(page);

    await page.goto(`/worklist/order/${IDS.order}?item=${state.items[1].id}`);

    await page.getByRole('row', { name: /Bilirubin Total/i }).getByRole('textbox').fill('1.00');
    await page.getByRole('row', { name: /Bilirubin Direct/i }).getByRole('textbox').fill('0.20');
    await page.getByRole('row', { name: /AST \/ SGOT/i }).getByRole('textbox').fill('35');
    await page.getByRole('row', { name: /ALT \/ SGPT/i }).getByRole('textbox').fill('40');
    await page.getByRole('row', { name: /Alkaline Phosphatase/i }).getByRole('textbox').fill('120');
    // Total Protein left blank, Albumin entered
    await page.getByRole('row', { name: /Albumin/i }).getByRole('textbox').fill('4.2');

    const verifyBtn = page.getByRole('button', { name: 'Verify Results' });
    await verifyBtn.click();

    await expect(page.getByText(/Total Protein is required/i)).toBeVisible();
    expect(state.items[1].status).toBe('Received');
  });
});
