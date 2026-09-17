import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const baseUrl = process.env.PRINT_QA_BASE_URL || 'http://127.0.0.1:4180';
const artifactDir = 'qa-artifacts/report-real-path';

test('Reporting iframe print path preserves the canonical Serum Creatinine presentation', async ({ page }) => {
  fs.mkdirSync(artifactDir, { recursive: true });
  await page.goto(`${baseUrl}/print-qa.html?pages=1&profile=serum-creatinine`, { waitUntil: 'networkidle' });
  await expect.poll(() => page.locator('body').getAttribute('data-print-clone-ready')).toBe('true');

  await page.evaluate(async () => {
    const { printReportDocument } = await import('/src/lib/reportPrint.ts');
    await printReportDocument();
  });

  const printFrame = page.locator('#bimal-print-frame');
  await expect(printFrame).toHaveCount(1);
  const frame = page.frames().find((candidate) => candidate !== page.mainFrame());
  expect(frame).toBeTruthy();

  const evidence = await frame.evaluate(() => {
    const sheet = document.querySelector('.report-page');
    const rect = (selector) => document.querySelector(selector)?.getBoundingClientRect();
    const mm = (px) => Number((px * 25.4 / 96).toFixed(2));
    const pageRect = sheet.getBoundingClientRect();
    const header = rect('.report-header');
    const patient = rect('.patient-identity-strip');
    const qr = rect('.report-qr-quiet-zone');
    const section = document.querySelector('.department-header-block');
    const signature = rect('.signature-block');
    const footer = rect('.bimal-footer-strip');
    const watermark = rect('.bimal-page-watermark');
    const styleRuleCount = [...document.styleSheets].reduce((count, stylesheet) => {
      try { return count + stylesheet.cssRules.length; } catch { return count; }
    }, 0);
    return {
      styleRuleCount,
      page: { widthMm: mm(pageRect.width), heightMm: mm(pageRect.height) },
      margins: { leftMm: mm(header.left - pageRect.left), rightMm: mm(pageRect.right - header.right) },
      zonesPresent: Boolean(header && patient && qr && signature && footer && watermark),
      greenSection: getComputedStyle(section).backgroundColor,
      signatureBorder: getComputedStyle(document.querySelector('.signature-block')).borderTopWidth,
      footerColor: getComputedStyle(document.querySelector('.bimal-footer-strip')).backgroundColor,
      logoLoaded: [...document.images].every((image) => image.complete && image.naturalWidth > 0),
      oneResult: document.querySelectorAll('.clinical-result-row').length,
      secureQr: document.querySelectorAll('.report-qr-quiet-zone svg').length,
      footerInside: footer.bottom <= pageRect.bottom,
      watermarkInside: watermark.top >= rect('.clinical-workspace').top && watermark.bottom <= signature.top,
    };
  });

  expect(evidence.styleRuleCount).toBeGreaterThan(100);
  expect(evidence.page).toEqual({ widthMm: 210, heightMm: 297 });
  expect(evidence.margins).toEqual({ leftMm: 10, rightMm: 10 });
  expect(evidence.zonesPresent && evidence.logoLoaded && evidence.footerInside && evidence.watermarkInside).toBe(true);
  expect(evidence.greenSection).toBe('rgb(11, 107, 58)');
  expect(evidence.signatureBorder).not.toBe('0px');
  expect(evidence.footerColor).toBe('rgb(11, 107, 58)');
  expect(evidence.oneResult).toBe(1);
  expect(evidence.secureQr).toBe(1);

  fs.writeFileSync(`${artifactDir}/serum-creatinine-real-path-geometry.json`, JSON.stringify(evidence, null, 2));
  const html = await frame.content();
  await page.setContent(html, { waitUntil: 'load' });
  await page.emulateMedia({ media: 'print' });
  await page.screenshot({ path: `${artifactDir}/serum-creatinine-after-page-1.png`, fullPage: true });
  await page.pdf({
    path: `${artifactDir}/serum-creatinine-after.pdf`,
    preferCSSPageSize: true,
    printBackground: true,
    scale: 1,
    margin: { top: '0', right: '0', bottom: '0', left: '0' },
  });
});
