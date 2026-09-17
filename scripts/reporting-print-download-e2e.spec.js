import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const baseUrl = process.env.PRINT_QA_BASE_URL || 'http://127.0.0.1:4180';
const canonicalBaseUrl = process.env.CANONICAL_QA_BASE_URL || baseUrl;
const artifactDir = 'qa-artifacts/report-real-path';
const userId = '11111111-1111-4111-8111-111111111111';
const secureToken = 'q'.repeat(40);

function envValue(name) {
  const source = fs.readFileSync('.env.local', 'utf8');
  return source.match(new RegExp(`^${name}=(.*)$`, 'm'))?.[1]?.trim();
}

function base64url(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

const snapshot = {
  organization: {
    name_en: 'BIMAL PATHOLOGY & DIAGNOSTIC CENTER', name_ne: 'बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर',
    address_en: 'Bharatpur-7, Chitwan, Nepal', address_ne: 'भरतपुर-७, चितवन, नेपाल',
    reg_no: '7-1496', pan_no: '302481477', phone: '056-593288',
    email: 'laboratory.reporting.office@bimalpathology.com.np',
  },
  patient: {
    uhid: 'QA-2026-0001', full_name: 'SERUM CREATININE PRODUCTION-SHAPE PATIENT', mobile: '9800000000',
    gender: 'Female', age_years: 32, address: 'Bharatpur, Chitwan',
  },
  order: {
    order_number: 'LAB-QA-0001', bill_number: 'INV-QA-0001',
    registered_date_ad: '2026-08-20T10:00:00+05:45', registered_date_bs: '2083-05-04 BS',
    collected_at: '2026-08-20T10:10:00+05:45', received_at: '2026-08-20T10:25:00+05:45',
    reported_at: '2026-08-20T11:30:00+05:45', referring_doctor_name: 'Self',
  },
  signatories: {
    performed_by: { id: 'qa-performer', full_name: 'QA Technologist', qualification: 'BMLT', professional_type: 'Medical Laboratory Technologist', registration_council: 'NHPC', registration_number: 'QA-001' },
    authorized_by: { id: 'qa-authorizer', full_name: 'QA Pathologist', qualification: 'MD Pathology', professional_type: 'Pathologist', specialization: 'Pathology', registration_council: 'NMC', registration_number: 'QA-002' },
  },
  investigations: [{
    order_item_id: 'qa-serum-creatinine', test_id: 'qa-serum-creatinine', test_name: 'Serum Creatinine',
    department: 'Biochemistry', reporting_type: 'InHouse', method: 'Enzymatic', specimen_type: 'Serum',
    container_type: 'SST', interpretation_template: null,
    results: [{ parameter_id: 'serum-creatinine', code: 'CREAT', name: 'Serum Creatinine', value_type: 'Numeric', display_value: '1.0', numeric_value: 1, unit: 'mg/dL', flag: 'Normal', is_critical: false, reference_range: 'Male: 0.7 - 1.3; Female: 0.6 - 1.1', normal_min: 0.6, normal_max: 1.3 }],
  }],
  meta: { version: 1, is_amendment: false, signed_at: '2026-08-20T11:30:00+05:45' },
};

const report = {
  id: '22222222-2222-4222-8222-222222222222', order_id: '33333333-3333-4333-8333-333333333333',
  patient_id: '44444444-4444-4444-8444-444444444444', report_number: 'REP-2026-00010-WHOLE-BODY-COMPREHENSIVE',
  version: 12, is_amendment: false, status: 'SignedOff', integrity_hash: 'a'.repeat(64),
  performed_by_personnel_name: 'QA Technologist', signed_by_personnel_name: 'QA Pathologist',
  signed_at: snapshot.meta.signed_at, clinical_snapshot_json: snapshot,
  patient: { uhid: snapshot.patient.uhid, full_name: snapshot.patient.full_name, mobile: snapshot.patient.mobile },
  order: { order_number: snapshot.order.order_number },
};

async function installAuthenticatedReadMocks(page) {
  const supabaseUrl = envValue('VITE_SUPABASE_URL');
  const projectRef = new URL(supabaseUrl).hostname.split('.')[0];
  const now = Math.floor(Date.now() / 1000);
  const accessToken = `${base64url({ alg: 'none', typ: 'JWT' })}.${base64url({ sub: userId, role: 'authenticated', exp: now + 3600 })}.signature`;
  const user = { id: userId, aud: 'authenticated', role: 'authenticated', email: 'print-e2e@example.invalid', app_metadata: {}, user_metadata: {}, created_at: new Date(0).toISOString() };
  const session = { access_token: accessToken, refresh_token: 'non-production-e2e-refresh', expires_in: 3600, expires_at: now + 3600, token_type: 'bearer', user };
  await page.addInitScript(({ key, value }) => localStorage.setItem(key, JSON.stringify(value)), {
    key: `sb-${projectRef}-auth-token`, value: session,
  });
  await page.addInitScript(() => {
    const install = () => new MutationObserver((records) => {
      for (const record of records) for (const node of record.addedNodes) {
        if (node instanceof HTMLIFrameElement && node.id === 'bimal-print-frame' && node.contentWindow) {
          // Keep the exact Reporting iframe construction path but suppress the
          // interactive OS print dialog; CDP emits the asserted PDF below.
          node.contentWindow.print = () => {};
        }
      }
    }).observe(document.documentElement, { childList: true, subtree: true });
    if (document.documentElement) install(); else addEventListener('DOMContentLoaded', install, { once: true });
  });

  await page.route(`${supabaseUrl}/auth/v1/**`, (route) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(user) }));
  await page.route(`${supabaseUrl}/rest/v1/**`, async (route) => {
    const url = new URL(route.request().url());
    const endpoint = url.pathname.split('/').at(-1);
    let body = [];
    if (endpoint === 'user_profiles') body = { id: userId, email: user.email, full_name: 'Print E2E', phone: null, is_active: true, is_super_admin: true, created_at: new Date(0).toISOString(), updated_at: new Date(0).toISOString() };
    if (endpoint === 'diagnostic_reports') body = [report];
    if (endpoint === 'get_report_secure_link_status') body = { report_id: report.id, report_version: report.version, state: 'Active', public_url: `https://lis.bimalpathology.com.np/r/${secureToken}` };
    await route.fulfill({ status: 200, contentType: 'application/json', headers: { 'content-range': '0-0/1' }, body: JSON.stringify(body) });
  });
}

async function waitForPrintFrame(page) {
  const frameLocator = page.locator('#bimal-print-frame');
  await expect(frameLocator).toHaveCount(1, { timeout: 10_000 });
  const frameHandle = await frameLocator.elementHandle();
  const frame = await frameHandle?.contentFrame();
  expect(frame).toBeTruthy();
  await frame.waitForSelector('.report-page');
  // doc.open()/doc.close() creates the final iframe realm after insertion;
  // suppress print in that final realm before asset readiness triggers it.
  await frame.evaluate(() => { window.print = () => {}; });
  await frame.evaluate(async () => {
    await Promise.all([...document.images].map((image) => image.complete ? Promise.resolve() : new Promise((resolve) => {
      image.addEventListener('load', resolve, { once: true });
      image.addEventListener('error', resolve, { once: true });
    })));
    if (document.fonts?.ready) await document.fonts.ready;
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  });
  return frame;
}

async function renderFramePdf(context, html, stem) {
  const output = await context.newPage();
  await output.setContent(html, { waitUntil: 'load' });
  await output.emulateMedia({ media: 'print' });
  const image = await output.locator('.report-page').screenshot({ path: `${artifactDir}/${stem}-page-1.png` });
  await output.pdf({ path: `${artifactDir}/${stem}.pdf`, preferCSSPageSize: true, printBackground: true, scale: 1, margin: { top: '0', right: '0', bottom: '0', left: '0' } });
  const geometry = await output.locator('.report-page').evaluate((sheet) => {
    const mm = (px) => Number((px * 25.4 / 96).toFixed(2));
    const page = sheet.getBoundingClientRect();
    const header = sheet.querySelector('.report-header').getBoundingClientRect();
    return { widthMm: mm(page.width), heightMm: mm(page.height), leftMarginMm: mm(header.left - page.left), rightMarginMm: mm(page.right - header.right) };
  });
  const presentation = await output.locator('.report-page').evaluate((sheet) => {
    const page = sheet.getBoundingClientRect();
    const box = (selector) => {
      const element = sheet.querySelector(selector);
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      return {
        x: Math.round(rect.left - page.left), y: Math.round(rect.top - page.top),
        width: Math.round(rect.width), height: Math.round(rect.height),
        background: style.backgroundColor, borderTop: style.borderTopWidth,
      };
    };
    return {
      header: box('.report-identity-header'), patient: box('.patient-identity-strip'),
      qr: box('.report-qr-quiet-zone'), clinical: box('.clinical-workspace'),
      section: box('.department-header-block'), watermark: box('.bimal-page-watermark'),
      signature: box('.signature-block'), note: box('.report-clinical-note'), footer: box('.bimal-footer-strip'),
      resultCount: sheet.querySelectorAll('.clinical-result-row').length,
      qrCount: sheet.querySelectorAll('.report-qr-quiet-zone svg').length,
    };
  });
  await output.close();
  return { image, geometry, presentation };
}

async function visualDifference(context, first, second) {
  const comparison = await context.newPage();
  const result = await comparison.evaluate(async ({ firstData, secondData }) => {
    const load = (data) => new Promise((resolve, reject) => {
      const image = new Image(); image.onload = () => resolve(image); image.onerror = reject;
      image.src = `data:image/png;base64,${data}`;
    });
    const [a, b] = await Promise.all([load(firstData), load(secondData)]);
    const canvas = document.createElement('canvas'); canvas.width = a.width; canvas.height = a.height;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(a, 0, 0); const left = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
    ctx.clearRect(0, 0, canvas.width, canvas.height); ctx.drawImage(b, 0, 0);
    const right = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
    let changed = 0; let squared = 0;
    for (let index = 0; index < left.length; index += 4) {
      let pixelChanged = false;
      for (let channel = 0; channel < 3; channel += 1) {
        const delta = left[index + channel] - right[index + channel];
        squared += delta * delta; if (delta !== 0) pixelChanged = true;
      }
      if (pixelChanged) changed += 1;
    }
    const pixels = canvas.width * canvas.height;
    return { changedRatio: changed / pixels, rmse: Math.sqrt(squared / (pixels * 3)) };
  }, { firstData: first.toString('base64'), secondData: second.toString('base64') });
  await comparison.close();
  return result;
}

function expectEquivalentPresentation(actual, canonical) {
  expect(actual.resultCount).toBe(canonical.resultCount);
  expect(actual.qrCount).toBe(canonical.qrCount);
  for (const zone of ['header', 'patient', 'qr', 'clinical', 'section', 'watermark', 'signature', 'note', 'footer']) {
    expect(actual[zone].background).toBe(canonical[zone].background);
    expect(actual[zone].borderTop).toBe(canonical[zone].borderTop);
    for (const metric of ['x', 'y', 'width', 'height']) {
      expect(Math.abs(actual[zone][metric] - canonical[zone][metric]), `${zone}.${metric}`).toBeLessThanOrEqual(4);
    }
  }
}

test('actual Reporting Print and Download equal canonical ReportDocument presentation', async ({ page, context }) => {
  test.setTimeout(120_000);
  fs.mkdirSync(artifactDir, { recursive: true });
  await installAuthenticatedReadMocks(page);
  // Supabase Auth maintains background channels; the operational page is ready
  // when its Reporting row appears, not when the browser has zero connections.
  await page.goto(`${baseUrl}/reports`, { waitUntil: 'domcontentloaded' });
  await expect(page.getByText(report.report_number).first()).toBeVisible();

  await page.getByRole('button', { name: 'Print', exact: true }).click();
  const printFrame = await waitForPrintFrame(page);
  const printOutput = await renderFramePdf(context, await printFrame.content(), 'reporting-print-after');

  // Exercise Download from a fresh operational Reporting page. Native
  // window.print can keep its originating renderer occupied in headless mode;
  // real browsers release it when the OS dialog closes.
  const downloadPage = await context.newPage();
  await installAuthenticatedReadMocks(downloadPage);
  await downloadPage.goto(`${baseUrl}/reports`, { waitUntil: 'domcontentloaded' });
  await expect(downloadPage.getByText(report.report_number).first()).toBeVisible();
  await downloadPage.getByRole('button', { name: 'Download', exact: true }).click();
  const downloadFrame = await waitForPrintFrame(downloadPage);
  const downloadOutput = await renderFramePdf(context, await downloadFrame.content(), 'reporting-download-after');

  const canonical = await context.newPage();
  await canonical.goto(`${canonicalBaseUrl}/print-qa.html?pages=1&profile=serum-creatinine&source=react`, { waitUntil: 'networkidle' });
  await expect.poll(() => canonical.locator('body').getAttribute('data-print-clone-ready')).toBe('true');
  await canonical.evaluate(async () => {
    const { printReportDocument } = await import('/src/lib/reportPrint.ts');
    await printReportDocument();
  });
  const canonicalFrame = await waitForPrintFrame(canonical);
  const canonicalOutput = await renderFramePdf(context, await canonicalFrame.content(), 'canonical-serum-creatinine');
  await canonical.close();

  expect(printOutput.geometry).toEqual({ widthMm: 210, heightMm: 297, leftMarginMm: 10, rightMarginMm: 10 });
  expect(downloadOutput.geometry).toEqual(printOutput.geometry);
  expect(canonicalOutput.geometry).toEqual(printOutput.geometry);
  expect(downloadOutput.presentation).toEqual(printOutput.presentation);
  expectEquivalentPresentation(printOutput.presentation, canonicalOutput.presentation);
  expect(downloadOutput.image.equals(printOutput.image)).toBe(true);
  const visual = await visualDifference(context, printOutput.image, canonicalOutput.image);
  expect(visual.changedRatio).toBeLessThan(0.1);
  expect(visual.rmse).toBeLessThan(40);
  fs.writeFileSync(`${artifactDir}/reporting-vs-canonical-visual.json`, JSON.stringify(visual, null, 2));
});
