import { chromium } from 'playwright';
import readline from 'node:readline';

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
const errors = [];
const failedModules = [];
page.on('pageerror', (error) => errors.push(error.message));
page.on('requestfailed', (request) => { if (request.url().endsWith('.js')) failedModules.push(request.url()); });
await page.goto('https://lis.bimalpathology.com.np/login', { waitUntil: 'networkidle' });
const oldEntry = await page.locator('script[type="module"][src^="/assets/"]').getAttribute('src');
console.log(JSON.stringify({ state: 'OLD_TAB_READY', oldEntry }));

const input = readline.createInterface({ input: process.stdin, terminal: false });
for await (const line of input) {
  if (line.trim() === 'stop') break;
  const routes = ['/', '/worklist', '/patients', '/billing', '/reports', '/catalogue', '/settings', '/admin/sms', '/r/invalid-controlled-audit-token'];
  for (const route of routes) {
    await page.goto(`https://lis.bimalpathology.com.np${route}`, { waitUntil: 'networkidle' });
    const fallback = await page.getByText('New version available — Refresh').count();
    if (fallback) errors.push(`version fallback at ${route}`);
  }
  console.log(JSON.stringify({ state: 'OLD_TAB_CHECKED', oldEntry, errors, failedModules }));
}
await browser.close();
