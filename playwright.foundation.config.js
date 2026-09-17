import { defineConfig, devices } from '@playwright/test';
import { loadStagingAcceptanceEnvironment } from './scripts/playwright/stagingAcceptanceGuard.js';

const target = loadStagingAcceptanceEnvironment();
if (target.environment !== 'isolated-acceptance') throw new Error('Foundation Playwright config refuses legacy staging.');
console.log(`[foundation-browser] project_ref=${target.projectRef} frontend=${target.baseURL} backend=${target.supabaseOrigin}`);

export default defineConfig({
  testDir: './scripts/playwright',
  testMatch: ['staging-authenticated-acceptance.spec.js', 'foundation-result-conflict.spec.js', 'canonical-clinical-role-browser.spec.js'],
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 120_000,
  expect: { timeout: 20_000 },
  reporter: [['list']],
  outputDir: 'test-results/foundation-hosted-acceptance',
  use: { ...devices['Desktop Chrome'], baseURL: target.baseURL, serviceWorkers: 'block', trace: 'off', screenshot: 'only-on-failure', video: 'off' },
});
