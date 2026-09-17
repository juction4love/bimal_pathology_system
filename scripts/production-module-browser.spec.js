import { test, expect } from '@playwright/test';

test('custom domain loads and evaluates every deployed JavaScript module', async ({ page }) => {
  const baseUrl = process.env.PLAYWRIGHT_BASE_URL || 'https://lis.bimalpathology.com.np';
  const pageErrors = [];
  const failedRequests = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  page.on('requestfailed', (request) => failedRequests.push({ url: request.url(), error: request.failure()?.errorText }));
  const response = await page.goto(`${baseUrl}/login`, { waitUntil: 'networkidle' });
  expect(response?.status()).toBe(200);
  await expect(page.getByText('New version available — Refresh')).toHaveCount(0);
  await expect(page.locator('body')).not.toBeEmpty();

  const html = await (await page.request.get(`${baseUrl}/`)).text();
  const entryPath = html.match(/src="(\/assets\/index-[^"]+\.js)"/)?.[1];
  expect(entryPath).toBeTruthy();
  const entrySource = await (await page.request.get(`${baseUrl}${entryPath}`)).text();
  const modulePaths = [...new Set([...entrySource.matchAll(/assets\/[A-Za-z0-9_./-]+\.js/g)].map((match) => `/${match[0]}`))];
  const moduleFailures = await page.evaluate(async (paths) => {
    const failures = [];
    for (const pathname of paths) {
      try { await import(pathname); } catch (error) { failures.push({ pathname, message: String(error) }); }
    }
    return failures;
  }, modulePaths);
  expect(moduleFailures).toEqual([]);
  expect(failedRequests.filter((failure) => failure.url.endsWith('.js'))).toEqual([]);
  expect(pageErrors).toEqual([]);

  const missing = await page.request.get(`${baseUrl}/assets/DefinitelyMissingChunk-${Date.now()}.js`);
  expect(missing.status()).toBe(404);
});
