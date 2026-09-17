import { defineConfig, devices } from '@playwright/test';
import { loadStagingAcceptanceEnvironment } from './scripts/playwright/stagingAcceptanceGuard.js';

// Deliberately evaluated while Playwright loads its configuration. A missing or
// mismatched target aborts before a browser, credential, or remote call exists.
const staging = loadStagingAcceptanceEnvironment();
console.log(`[staging-acceptance] environment=${staging.environment} project_ref=${staging.projectRef} expected_project_ref=${staging.projectRef} frontend=${staging.baseURL} backend=${staging.supabaseOrigin} mode=read-only`);

export default defineConfig({
  testDir: './scripts/playwright',
  testMatch: [
    'staging-authenticated-acceptance.spec.js',
    'canonical-clinical-role-browser.spec.js',
  ],
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 120_000,
  expect: { timeout: 20_000 },
  reporter: [['list']],
  outputDir: 'test-results/staging-ui-acceptance',
  use: {
    ...devices['Desktop Chrome'],
    baseURL: staging.baseURL,
    serviceWorkers: 'block',
    // Auth request bodies must never be retained in a trace artifact.
    trace: 'off',
    screenshot: 'only-on-failure',
    video: 'off',
  },
});
