import { chromium } from 'playwright';

const baseUrl = process.argv[2];
if (!baseUrl) throw new Error('A deployment URL is required.');
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  const response = await page.goto(`${baseUrl}/login`, { waitUntil: 'networkidle' });
  const html = await (await page.request.get(`${baseUrl}/`)).text();
  const entry = html.match(/src="(\/assets\/index-[^"]+\.js)"/)?.[1];
  if (!entry) throw new Error('Hashed entry module is missing.');
  const entrySource = await (await page.request.get(`${baseUrl}${entry}`)).text();
  const modulePaths = [...new Set([...entrySource.matchAll(/assets\/[A-Za-z0-9_./-]+\.js/g)].map((match) => `/${match[0]}`))];
  const failures = await page.evaluate(async (paths) => {
    const failed = [];
    for (const path of paths) {
      try { await import(path); } catch (error) { failed.push({ path, error: String(error) }); }
    }
    return failed;
  }, modulePaths);
  const missing = await page.request.get(`${baseUrl}/assets/DefinitelyMissingChunk.js`);
  const result = { status: response?.status(), entry, moduleCount: modulePaths.length, failures, pageErrors, missingStatus: missing.status() };
  console.log(JSON.stringify(result));
  if (result.status !== 200 || failures.length || pageErrors.length || result.missingStatus !== 404) process.exitCode = 1;
} finally {
  await browser.close();
}
