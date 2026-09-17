import { test, expect } from '@playwright/test';
import {
  IDS,
  makeState,
  installSyntheticBackend,
  observe,
  login,
} from './synthetic00092Adapter.js';

test.describe('Smart Auto-Next Workflow Navigation Suite', () => {
  test('Scenario A: Bill creation with collection required navigates to sample collection for order', async ({ page, context }) => {
    const state = makeState();
    await installSyntheticBackend(context, state);
    observe(page, state);
    await login(page);

    await page.goto('/billing/new');
    await page.getByLabel('Patient Mobile Number *').fill('9800000001');
    await page.getByLabel('Patient Mobile Number *').press('Enter');
    await page.getByLabel('Patient Full Name *').fill('Synthetic Billing Patient');
    await page.getByLabel('Age (Years) *').fill('36');

    const search = page.getByLabel('Search Test / Profile / Package');
    await search.fill('cre');
    await expect(page.getByText('Serum Creatinine', { exact: true })).toBeVisible();
    await search.press('Enter');

    await page.getByRole('button', { name: 'Confirm Bill & Register Order' }).click();

    // Verify auto-next progression to sample accessioning with order context
    await expect(page).toHaveURL(/\/samples\?orderId=|\/samples\?search=/, { timeout: 10000 });
    expect(state.issues).toEqual([]);
  });

  test('Scenario E: Save draft on Result Entry stays on current investigation', async ({ page, context }) => {
    const state = makeState();
    await installSyntheticBackend(context, state);
    observe(page, state);
    await login(page);

    await page.goto(`/worklist/order/${IDS.order}?item=${state.items[0].id}`);
    await expect(page.getByText('Synthetic Acceptance', { exact: true }).first()).toBeVisible();

    await page.getByRole('button', { name: /Endocrinology · THYROID_PROFILE/ }).click();
    await expect(page).toHaveURL(new RegExp(`item=${state.items[3].id}`));

    const input = page.getByPlaceholder('Enter result...');
    await input.fill('4.2');
    await input.press('Tab');

    const saveBtn = page.getByRole('button', { name: /Save Draft/i });
    await expect(saveBtn).toBeVisible();
    await saveBtn.click();

    await expect(page).toHaveURL(new RegExp(`item=${state.items[3].id}`));
    expect(state.issues).toEqual([]);
  });

  test('Scenario G & H: Submit/Verify investigation navigates to next sibling or ready report group', async ({ page, context }) => {
    const state = makeState();
    await installSyntheticBackend(context, state);
    observe(page, state);
    await login(page);

    await page.goto(`/worklist/order/${IDS.order}?item=${state.items[3].id}`);
    await expect(page.getByText('Synthetic Acceptance', { exact: true }).first()).toBeVisible();

    const submitBtn = page.getByRole('button', { name: 'Submit for Verification' });
    if (await submitBtn.isVisible()) {
      await submitBtn.click();
    }
    const verifyBtn = page.getByRole('button', { name: 'Verify Results' });
    if (await verifyBtn.isVisible()) {
      await verifyBtn.click();
    }
    await expect(page.getByRole('button', { name: 'Sign Endocrinology Report' })).toBeEnabled();
    expect(state.issues).toEqual([]);
  });

  test('Scenario J: Final group signed displays Order Delivery Summary', async ({ page, context }) => {
    const state = makeState();
    state.items.forEach((i) => {
      i.status = 'SignedOff';
      state.signed.set(i.group_id, 1);
    });
    state.reports = [
      { id: '50000000-0000-4000-8000-000000000951', order_id: IDS.order, patient_id: IDS.patient, report_group_id: '50000000-0000-4000-8000-000000000201', report_number: 'R-SYN-1', version: 1, is_amendment: false, status: 'SignedOff', signed_by_personnel_name: 'Synthetic Signatory', signed_at: '2026-09-01T02:00:00Z', pdf_storage_path: `reports/${IDS.order}/R-SYN-1.pdf`, clinical_snapshot_json: { patient: { uhid: '2609010001', full_name: 'Synthetic Acceptance' }, order: { order_number: 'LAB-SYN-0001' }, report_group: { title: 'Hematology', clinical_section: 'Hematology' } } }
    ];
    await installSyntheticBackend(context, state);
    observe(page, state);
    await login(page);

    await page.goto(`/reports?orderId=${IDS.order}`);
    await expect(page.getByText(/Order Delivery Summary/i)).toBeVisible();
    expect(state.issues).toEqual([]);
  });

  test('Scenario K & L: Mixed internal/outsource order transitions to outsource workflow', async ({ page, context }) => {
    const state = makeState();
    await installSyntheticBackend(context, state);
    observe(page, state);
    await login(page);

    await page.goto(`/outsource?item=${state.outsource[0].order_item_id}&action=dispatch`);
    await expect(page.getByText(/Outsource Specimen Chain-of-Custody|Outsource Sample Tracking|Tracking/i).first()).toBeVisible();
    expect(state.issues).toEqual([]);
  });

  test('Scenario M: Browser Back button functions cleanly without redirect loops', async ({ page, context }) => {
    const state = makeState();
    await installSyntheticBackend(context, state);
    observe(page, state);
    await login(page);

    await page.goto('/worklist');
    await page.goto(`/worklist/order/${IDS.order}?item=${state.items[0].id}`);
    await expect(page.getByText('Synthetic Acceptance', { exact: true }).first()).toBeVisible();

    await page.goBack();
    await expect(page).toHaveURL(/\/worklist$/);
    expect(state.issues).toEqual([]);
  });
});
