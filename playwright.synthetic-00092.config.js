import { defineConfig, devices } from '@playwright/test';

const backend = 'http://127.0.0.1:54329';

export default defineConfig({
  testDir: './scripts/playwright',
  testMatch: ['synthetic-00092-lifecycle.spec.js', 'smart-auto-next-workflow.spec.js', 'lft-result-entry-verification.spec.js'],
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 120_000,
  expect: { timeout: 15_000 },
  reporter: [['list']],
  outputDir: 'test-results/synthetic-00092',
  webServer: process.env.SYNTHETIC_00092_EXTERNAL_SERVER === '1' ? undefined : {
    command: 'node node_modules/vite/bin/vite.js --host 127.0.0.1 --port 41794',
    url: 'http://127.0.0.1:41794/login',
    reuseExistingServer: true,
    timeout: 120_000,
    gracefulShutdown: { signal: 'SIGINT', timeout: 1_000 },
    env: {
      VITE_SUPABASE_URL: backend,
      VITE_SUPABASE_ANON_KEY: 'sb_publishable_synthetic_00092_browser_only',
    },
  },
  use: {
    ...devices['Desktop Chrome'],
    baseURL: 'http://127.0.0.1:41794',
    serviceWorkers: 'block',
    trace: 'off',
    screenshot: 'only-on-failure',
    video: 'off',
  },
});
