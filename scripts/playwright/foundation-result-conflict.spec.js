import { expect, test } from '@playwright/test';
import { loadStagingAcceptanceEnvironment, projectRefFromSupabaseUrl } from './stagingAcceptanceGuard.js';

const target = loadStagingAcceptanceEnvironment();
if (target.environment !== 'isolated-acceptance') throw new Error('This mutation test is foundation-acceptance only.');
if (!target.technicianBEmail || !target.technicianBPassword) throw new Error('A second authenticated technician fixture is required.');

async function login(page, email, password) {
  await page.goto('/login');
  await page.locator('#login-email').fill(email);
  await page.locator('#login-password').fill(password);
  await page.locator('#login-submit').click();
  await expect(page).toHaveURL(/\/$/);
}

function restrictBackend(context) {
  return context.route('**/*', async route => {
    const url = route.request().url();
    const ref = projectRefFromSupabaseUrl(url);
    if ((ref && ref !== target.projectRef) || url.includes('api.sparrowsms.com') || url.includes('/dispatch-sms')) {
      await route.abort('blockedbyclient');
      return;
    }
    await route.continue();
  });
}

test('two browser contexts expose a persistent conflict and explicit Reload Latest', async ({ browser }) => {
  const contextA = await browser.newContext();
  const contextB = await browser.newContext();
  await Promise.all([restrictBackend(contextA), restrictBackend(contextB)]);
  const pageA = await contextA.newPage();
  const pageB = await contextB.newPage();
  await Promise.all([
    login(pageA, target.technicianEmail, target.technicianPassword),
    login(pageB, target.technicianBEmail, target.technicianBPassword),
  ]);
  const entry = `/worklist/entry/${target.resultItemId}`;
  await Promise.all([pageA.goto(entry), pageB.goto(entry)]);
  const inputA = pageA.getByPlaceholder('Enter result...').first();
  const inputB = pageB.getByPlaceholder('Enter result...').first();
  await Promise.all([expect(inputA).toBeVisible(), expect(inputB).toBeVisible()]);
  await inputA.fill('11');
  await inputB.fill('12');
  const saveAResponse = pageA.waitForResponse(response => response.url().includes('/rest/v1/rpc/save_test_results') && response.request().method() === 'POST');
  await pageA.getByRole('button', { name: 'Save Draft' }).click();
  expect((await saveAResponse).ok(), 'Actor A save must commit').toBe(true);
  await expect(inputA).toHaveValue('11');
  await pageB.getByRole('button', { name: 'Save Draft' }).click();
  await expect(pageB.getByText('Results changed in another session.')).toBeVisible();
  const reload = pageB.getByRole('button', { name: 'Reload Latest' });
  await expect(reload).toBeVisible();
  await pageB.waitForTimeout(500);
  await expect(reload, 'conflict must remain until explicit operator action').toBeVisible();
  await reload.click();
  await expect(pageB.getByPlaceholder('Enter result...').first()).toHaveValue('11');
  await Promise.all([contextA.close(), contextB.close()]);
});
