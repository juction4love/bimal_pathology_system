import { expect, test } from '@playwright/test';
import {
  PRODUCTION_PROJECT_REF,
  loadStagingAcceptanceEnvironment,
  projectRefFromSupabaseUrl,
} from './stagingAcceptanceGuard.js';

const staging = loadStagingAcceptanceEnvironment();

const readOnlyRpcAllowlist = new Set([
  'catalogue_expand_package',
  'check_order_report_readiness',
  'get_dashboard_operational_summary',
  'get_report_secure_link_status',
  'get_sms_delivery_status',
  'search_billable_catalogue',
]);

const adminPages = [
  ['/', 'Laboratory Operations Dashboard'],
  ['/patients', 'Patient Master Registry'],
  ['/billing', 'Bills & Financial Invoices'],
  ['/catalogue', 'Investigation & Test Catalogue'],
  ['/samples', 'Sample Accessioning & Barcode Lifecycle'],
  ['/worklist', 'Laboratory Worklist & Results'],
  ['/reports', 'Diagnostic Pathology Reports'],
  ['/admin/users', 'User Accounts & Access Control'],
  ['/admin/roles', 'Granular Roles & Permissions Matrix'],
  ['/personnel/reporting', 'Clinical & Reporting Personnel'],
  ['/personnel/doctors', 'Referring Clinicians Master'],
  ['/admin/sms', 'SMS Delivery Status'],
  ['/admin/audit', 'Append-Only Audit Trail'],
];

const technicianAllowedPages = [
  ['/', 'Lab Operations Dashboard'],
  ['/samples', 'Sample Accessioning & Barcode Lifecycle'],
  ['/worklist', 'Laboratory Worklist & Results'],
  ['/reports', 'Diagnostic Pathology Reports'],
];

const technicianDeniedPages = [
  '/patients',
  '/billing/new',
  '/billing',
  '/catalogue',
  '/admin/users',
  '/admin/roles',
  '/personnel/reporting',
  '/personnel/doctors',
  '/admin/sms',
  '/admin/audit',
];

function installFailClosedNetworkGuard(context) {
  const state = {
    observedProjectRefs: new Set(),
    blockedTargets: [],
    forbiddenSmsAttempts: [],
    forbiddenMutationAttempts: [],
  };

  context.route('**/*', async (route) => {
    const request = route.request();
    const rawUrl = request.url();
    let url;
    try {
      url = new URL(rawUrl);
    } catch {
      state.blockedTargets.push(rawUrl);
      await route.abort('blockedbyclient');
      return;
    }

    const projectRef = projectRefFromSupabaseUrl(rawUrl);
    if (projectRef) state.observedProjectRefs.add(projectRef);

    if (projectRef && projectRef !== staging.projectRef) {
      state.blockedTargets.push(rawUrl);
      await route.abort('blockedbyclient');
      return;
    }
    if (rawUrl.includes(PRODUCTION_PROJECT_REF) || url.hostname === 'lis.bimalpathology.com.np') {
      state.blockedTargets.push(rawUrl);
      await route.abort('blockedbyclient');
      return;
    }
    if (url.hostname === 'api.sparrowsms.com' || /\/functions\/v1\/dispatch-sms(?:\/|$)/.test(url.pathname)) {
      state.forbiddenSmsAttempts.push(rawUrl);
      await route.abort('blockedbyclient');
      return;
    }
    if (url.origin === staging.supabaseOrigin && url.pathname.startsWith('/rest/v1/')) {
      const rpcMatch = /^\/rest\/v1\/rpc\/([^/]+)$/.exec(url.pathname);
      const isReadMethod = ['GET', 'HEAD', 'OPTIONS'].includes(request.method());
      const isAllowedReadOnlyRpc = rpcMatch && readOnlyRpcAllowlist.has(decodeURIComponent(rpcMatch[1]));
      if (!isReadMethod && !isAllowedReadOnlyRpc) {
        state.forbiddenMutationAttempts.push(rawUrl);
        await route.abort('blockedbyclient');
        return;
      }
    }

    await route.continue();
  });

  return state;
}

function observeRuntime(page) {
  const issues = [];

  page.on('pageerror', (error) => issues.push(`pageerror: ${error.message}`));
  page.on('console', (message) => {
    if (message.type() === 'error') issues.push(`console.error: ${message.text()}`);
  });
  page.on('requestfailed', (request) => {
    const cancelledRead = request.failure()?.errorText === 'net::ERR_ABORTED'
      && ['GET', 'HEAD'].includes(request.method())
      && projectRefFromSupabaseUrl(request.url()) === staging.projectRef;
    // React route cleanup and Vite's first-run dependency optimization cancel
    // superseded read requests. These never reached a mutation authority and
    // are distinct from backend/HTTP failures, which remain fatal below.
    if (cancelledRead) return;
    issues.push(`requestfailed: ${request.method()} ${request.url()} (${request.failure()?.errorText ?? 'unknown'})`);
  });
  page.on('response', (response) => {
    if (response.status() >= 400) {
      const url = response.url();
      const isApplicationResource = ['document', 'script', 'xhr', 'fetch'].includes(response.request().resourceType());
      if (isApplicationResource || projectRefFromSupabaseUrl(url)) {
        issues.push(`http ${response.status()}: ${response.request().method()} ${url}`);
      }
    }
  });

  return {
    checkpoint: () => issues.length,
    since: (checkpoint) => issues.slice(checkpoint),
  };
}

async function assertNoRuntimeFailure(page, observer, checkpoint, label) {
  await page.waitForLoadState('networkidle', { timeout: 20_000 });
  await page.waitForTimeout(150);
  await expect(page.getByText('This page could not be loaded', { exact: true })).toHaveCount(0);
  await expect(page.getByText('Something went wrong. Please reload the application.', { exact: true })).toHaveCount(0);
  expect(observer.since(checkpoint), `${label} emitted browser/runtime failures`).toEqual([]);
}

async function signIn(page, observer, email, password, expectedDashboard) {
  const checkpoint = observer.checkpoint();
  const response = await page.goto('/login', { waitUntil: 'domcontentloaded' });
  expect(response?.status()).toBe(200);
  await page.locator('#login-email').fill(email);
  await page.locator('#login-password').fill(password);

  const authResponse = page.waitForResponse((candidate) => {
    const url = new URL(candidate.url());
    return url.origin === staging.supabaseOrigin
      && url.pathname === '/auth/v1/token'
      && candidate.request().method() === 'POST';
  });
  await page.locator('#login-submit').click();
  expect((await authResponse).ok(), 'staging Auth password grant must succeed').toBe(true);
  await expect(page).toHaveURL(/\/$/);
  await expect(page.getByRole('heading', { name: expectedDashboard, exact: true })).toBeVisible();
  await assertNoRuntimeFailure(page, observer, checkpoint, 'authenticated login/dashboard');
}

async function assertPageRenders(page, observer, path, heading) {
  const checkpoint = observer.checkpoint();
  const response = await page.goto(path, { waitUntil: 'domcontentloaded' });
  expect(response?.status(), `${path} document status`).toBe(200);
  await expect(page.getByRole('heading', { name: heading, exact: true })).toBeVisible();
  await assertNoRuntimeFailure(page, observer, checkpoint, path);
}

async function assertResultEntryRenders(page, observer) {
  const checkpoint = observer.checkpoint();
  const response = await page.goto(`/worklist/entry/${staging.resultItemId}`, { waitUntil: 'domcontentloaded' });
  expect(response?.status()).toBe(200);
  await expect(page.getByRole('button', { name: 'Back to Laboratory Worklist', exact: true })).toBeVisible();
  await expect(page.getByRole('columnheader', { name: 'TEST / PARAMETER', exact: true })).toBeVisible();
  await expect(page.getByText('Investigation & Dept', { exact: true })).toBeVisible();
  await assertNoRuntimeFailure(page, observer, checkpoint, 'synthetic Result Entry fixture');
}

async function assertNetworkGuard(state) {
  expect([...state.observedProjectRefs], 'browser must contact only the isolated Supabase project').toEqual([staging.projectRef]);
  expect(state.blockedTargets, 'production or unintended backend request attempted').toEqual([]);
  expect(state.forbiddenSmsAttempts, 'browser attempted an SMS provider/dispatcher send').toEqual([]);
  expect(state.forbiddenMutationAttempts, 'read-only UI acceptance attempted a clinical/financial mutation').toEqual([]);
}

test.describe('isolated staging authenticated UI acceptance', () => {
  test('Admin renders every main workspace and uses keyboard-first unified catalogue search', async ({ page, context }) => {
    const guard = installFailClosedNetworkGuard(context);
    const observer = observeRuntime(page);
    await signIn(page, observer, staging.adminEmail, staging.adminPassword, 'Laboratory Operations Dashboard');

    for (const label of ['Dashboard', 'New Bill / Booking', 'Bills & Invoices', 'Patient Registry', 'Sample Accessioning', 'Lab Worklist & Results', 'Diagnostic Reports', 'Test Catalogue', 'Referring Doctors', 'Reporting Personnel', 'User Management', 'Roles & Permissions', 'SMS Delivery', 'Audit Logs']) {
      await expect(page.getByRole('link', { name: label, exact: true })).toBeVisible();
    }

    for (const [path, heading] of adminPages) await assertPageRenders(page, observer, path, heading);
    await assertResultEntryRenders(page, observer);

    for (const query of staging.searches) {
      const checkpoint = observer.checkpoint();
      await page.goto('/billing/new', { waitUntil: 'domcontentloaded' });
      await expect(page.getByRole('heading', { name: 'New Bill & Lab Booking', exact: true })).toBeVisible();
      await expect(page.getByText(/^Tier [1-4]$/i)).toHaveCount(0);

      const search = page.getByLabel('Search Test / Profile / Package', { exact: true });
      await search.fill(query);
      await expect(page.getByText('No configured billable match.', { exact: true })).toHaveCount(0, { timeout: 10_000 });
      await expect(page.getByText(/ · (Test|Profile|Package)( · |$)/).first()).toBeVisible();
      await search.press('ArrowDown');
      await search.press('Enter');

      await expect(search).toHaveValue('');
      await expect.poll(() => search.evaluate((element) => document.activeElement === element)).toBe(true);
      await expect(page.getByText(/^Selected Tests for Invoice \([1-9][0-9]*\)$/)).toBeVisible();
      await expect(page.getByRole('columnheader', { name: 'Test', exact: true })).toBeVisible();
      await expect(page.getByRole('columnheader', { name: 'Rate (NPR)', exact: true })).toBeVisible();
      await expect(page.getByRole('columnheader', { name: 'Amount', exact: true })).toBeVisible();
      await expect(page.getByRole('columnheader', { name: 'Remove', exact: true })).toBeVisible();
      await assertNoRuntimeFailure(page, observer, checkpoint, `${query.length}-character unified search`);
    }

    await assertNetworkGuard(guard);
  });

  test('Lab Technician renders clinical workspaces and is isolated from billing/admin masters', async ({ page, context }) => {
    const guard = installFailClosedNetworkGuard(context);
    const observer = observeRuntime(page);
    await signIn(page, observer, staging.technicianEmail, staging.technicianPassword, 'Lab Operations Dashboard');

    for (const label of ['Dashboard', 'Sample Accessioning', 'Outsource Tracking', 'Lab Worklist & Results', 'Diagnostic Reports']) {
      await expect(page.getByRole('link', { name: label, exact: true })).toBeVisible();
    }
    for (const label of ['New Bill / Booking', 'Bills & Invoices', 'Patient Registry', 'Test Catalogue', 'User Management', 'Roles & Permissions', 'SMS Delivery', 'Audit Logs']) {
      await expect(page.getByRole('link', { name: label, exact: true })).toHaveCount(0);
    }

    for (const [path, heading] of technicianAllowedPages) await assertPageRenders(page, observer, path, heading);
    await assertResultEntryRenders(page, observer);

    for (const path of technicianDeniedPages) {
      const checkpoint = observer.checkpoint();
      const response = await page.goto(path, { waitUntil: 'domcontentloaded' });
      expect(response?.status(), `${path} document status`).toBe(200);
      await expect(page.getByRole('heading', { name: 'Access Denied', exact: true })).toBeVisible();
      await assertNoRuntimeFailure(page, observer, checkpoint, `Technician denial ${path}`);
    }

    await assertNetworkGuard(guard);
  });
});
