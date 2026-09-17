import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const baseUrl = process.env.PRINT_QA_BASE_URL || 'http://127.0.0.1:4174';
const fixtures = [
  { pages: '1', profile: 'cbc', expected: 1 },
  { pages: '1', profile: 'dense', expected: 1 },
  { pages: '2', expected: 2 },
  { pages: '3', expected: 3 },
  { pages: '4', expected: 4 },
  { pages: '5', expected: 5 },
  { pages: 'N', expected: 8 },
  { pages: '15', profile: 'whole-body', expected: 15, wholeBody: true, resultCount: 168 },
  { pages: '24', profile: 'whole-body', expected: 24, wholeBody: true, extended: true, resultCount: 300 },
  { pages: '50', profile: 'whole-body', expected: 50, wholeBody: true, extended: true, resultCount: 648 },
  { pages: '100', profile: 'whole-body', expected: 100, wholeBody: true, extended: true, resultCount: 1359 },
  { pages: '2', profile: 'boundary' },
  { pages: '1', profile: 'identity', expected: 1 },
  { pages: '1', profile: 'one-signatory', expected: 1 },
  { pages: '1', profile: 'urea-cbc-creatinine', expected: 2 },
  { pages: '1', profile: 'sparse-serology', expected: 1, sparseSerology: true },
  { pages: '1', profile: 'historical-signed', expected: 1, generation: 'historical' },
  { pages: '1', profile: 'historical-amended', expected: 1, generation: 'historical' },
  { pages: '1', profile: 'cbc', expected: 1, generation: 'current' },
  { pages: '2', profile: 'historical-multipage', expected: 2, generation: 'historical-multipage' },
  { pages: '2', profile: 'current-multipage', expected: 2, generation: 'current-multipage' },
  { pages: '2', profile: 'real-cbc-lft-electrolytes', expected: 2, realClinical: true },
];

test('canonical report fixtures preserve A4 geometry and final-page composition', async ({ page }) => {
  test.setTimeout(600_000);
  fs.mkdirSync('qa-artifacts/report-print', { recursive: true });
  const generationGeometry = new Map();
  for (const fixture of fixtures) {
    const query = new URLSearchParams({ pages: fixture.pages, ...(fixture.profile ? { profile: fixture.profile } : {}) }).toString();
    await page.goto(`${baseUrl}/print-qa.html?${query}`, { waitUntil: 'networkidle' });
    await expect.poll(() => page.locator('body').getAttribute('data-print-clone-ready'), { timeout: 15_000 }).toBe('true');
    if (fixture.expected) await expect(page.locator('.report-page')).toHaveCount(fixture.expected);
    if (fixture.expectedMin) expect(await page.locator('.report-page').count()).toBeGreaterThanOrEqual(fixture.expectedMin);
    const physicalPageCount = await page.locator('.report-page').count();
    await expect(page.locator('.signature-block')).toHaveCount(physicalPageCount);
    await expect(page.locator('#printable-report')).toHaveAttribute('data-canonical-report-design', 'current');
    await expect(page.locator('.report-page').last().locator('.signature-block')).toHaveCount(1);
    await expect(page.locator('.report-page:not(:last-child) .signature-block')).toHaveCount(Math.max(0, physicalPageCount - 1));
    await expect(page.locator('.clinical-end-marker')).toHaveCount(1);
    await expect(page.locator('.report-page:not(:last-child) .clinical-end-marker')).toHaveCount(0);
    await expect(page.locator('.report-page .report-header')).toHaveCount(await page.locator('.report-page').count());
    await expect(page.locator('.report-page .patient-identity-strip')).toHaveCount(await page.locator('.report-page').count());
    await expect(page.locator('.report-page .report-qr-quiet-zone')).toHaveCount(await page.locator('.report-page').count());
    await expect(page.locator('.report-page .report-header-diagonal-accent')).toHaveCount(await page.locator('.report-page').count());
    await expect(page.locator('.report-page .report-header-background-wordmark')).toHaveCount(await page.locator('.report-page').count());
    await expect(page.locator('.report-page .report-header-background-logo')).toHaveCount(await page.locator('.report-page').count());
    await expect(page.locator('.report-page .bimal-workspace-texture')).toHaveCount(await page.locator('.report-page').count());
    await expect(page.locator('.report-page .patient-identity-strip').first()).toContainText('Collected');
    await expect(page.locator('.report-page .patient-identity-strip').first()).toContainText('Received');
    const headerGeometry = await page.locator('.report-header').evaluateAll((headers) => headers.map((header) => {
      const rect = header.getBoundingClientRect();
      return { width: Math.round(rect.width), height: Math.round(rect.height) };
    }));
    expect(new Set(headerGeometry.map(({ width, height }) => `${width}x${height}`)).size).toBe(1);
    const accentGeometry = await page.locator('.report-header-diagonal-accent').evaluateAll((accents) => accents.map((accent) => {
      const accentRect = accent.getBoundingClientRect();
      const headerRect = accent.closest('.report-identity-header').getBoundingClientRect();
      const qrRect = accent.closest('.report-identity-header').querySelector('.report-qr-quiet-zone')?.getBoundingClientRect();
      const wordmark = accent.querySelector('.report-header-background-wordmark');
      const backgroundLogo = accent.querySelector('.report-header-background-logo');
      const background = wordmark ? getComputedStyle(wordmark).backgroundImage : '';
      const logoRect = backgroundLogo?.getBoundingClientRect();
      return {
        contained: accentRect.bottom <= headerRect.bottom && accentRect.top >= headerRect.top,
        avoidsQr: !qrRect || accentRect.right <= qrRect.left,
        oneDecorativeWordmark: accent.querySelectorAll('.report-header-background-wordmark').length === 1,
        oneDecorativeLogo: accent.querySelectorAll('.report-header-background-logo').length === 1,
        logoContained: Boolean(logoRect) && logoRect.top >= accentRect.top && logoRect.bottom <= accentRect.bottom && logoRect.right <= accentRect.right,
        requestedBrandStrength: background.includes("fill-opacity=\".18\"") || background.includes("fill-opacity='.18'"),
      };
    }));
    expect(accentGeometry.every(({ contained, avoidsQr, oneDecorativeWordmark, oneDecorativeLogo, logoContained, requestedBrandStrength }) => contained && avoidsQr && oneDecorativeWordmark && oneDecorativeLogo && logoContained && requestedBrandStrength)).toBe(true);
    const zones = await page.locator('.report-page').evaluateAll((pages) => pages.map((sheet) => {
      const pageRect = sheet.getBoundingClientRect();
      const header = sheet.querySelector('.report-identity-header').getBoundingClientRect();
      const strip = sheet.querySelector('.patient-identity-strip').getBoundingClientRect();
      const workspace = sheet.querySelector('.clinical-workspace').getBoundingClientRect();
      const footer = sheet.querySelector('.bimal-footer-strip').getBoundingClientRect();
      const footerContact = sheet.querySelector('.bimal-footer-contact').getBoundingClientRect();
      const footerIdentity = sheet.querySelector('.bimal-footer-report-identity').getBoundingClientRect();
      const footerPage = sheet.querySelector('.bimal-footer-page-number').getBoundingClientRect();
      const watermark = sheet.querySelector('.bimal-page-watermark')?.getBoundingClientRect();
      const texture = sheet.querySelector('.bimal-workspace-texture').getBoundingClientRect();
      const signature = sheet.querySelector('.signature-block')?.getBoundingClientRect();
      const clinicalNodes = [...sheet.querySelectorAll('.clinical-workspace > [class*="MuiBox-root"]')].filter((node) => !node.classList.contains('bimal-page-watermark') && !node.classList.contains('bimal-workspace-texture'));
      const modeledAvailable = Number(sheet.dataset.paginationCapacityMm) - Number(sheet.dataset.paginationUsedMm);
      const watermarkSize = Number(sheet.querySelector('.bimal-page-watermark')?.getAttribute('data-watermark-size-mm') || 0);
      return {
        headerTop: Math.round(header.top - pageRect.top), headerHeight: Math.round(header.height),
        stripTop: Math.round(strip.top - pageRect.top), stripHeight: Math.round(strip.height),
        workspaceTop: Math.round(workspace.top - pageRect.top), workspaceHeight: Math.round(workspace.height),
        footerTop: Math.round(footer.top - pageRect.top), footerHeight: Math.round(footer.height),
        footerColumnsClear: footerContact.right <= footerIdentity.left + 0.5 && footerIdentity.right <= footerPage.left + 0.5,
        footerColumnsContained: [footerContact, footerIdentity, footerPage].every((rect) => rect.left >= footer.left - 0.5 && rect.right <= footer.right + 0.5 && rect.top >= footer.top - 0.5 && rect.bottom <= footer.bottom + 0.5),
        footerRects: { footer: [footer.left, footer.top, footer.right, footer.bottom], contact: [footerContact.left, footerContact.top, footerContact.right, footerContact.bottom], identity: [footerIdentity.left, footerIdentity.top, footerIdentity.right, footerIdentity.bottom], page: [footerPage.left, footerPage.top, footerPage.right, footerPage.bottom] },
        footerInsidePage: footer.left >= pageRect.left && footer.right <= pageRect.right && footer.bottom <= pageRect.bottom,
        footerContentFits: [sheet.querySelector('.bimal-footer-contact'), sheet.querySelector('.bimal-footer-report-identity'), sheet.querySelector('.bimal-footer-page-number')].every((node) => node.scrollHeight <= footer.height + 1),
        footerPageVisible: sheet.querySelector('.bimal-footer-page-number').textContent.trim() === `Page ${sheet.dataset.reportPage} of ${pages.length}` && getComputedStyle(sheet.querySelector('.bimal-footer-page-number')).whiteSpace === 'nowrap',
        watermarkContained: !watermark || (watermark.top >= workspace.top && watermark.bottom <= signature.top),
        adaptiveWatermarkCorrect: watermark
          ? watermarkSize >= 10 && watermarkSize <= 110 && watermarkSize <= Math.max(0, modeledAvailable - 6) + 0.01
          : modeledAvailable < 16,
        textureContained: texture.top >= workspace.top && texture.bottom <= workspace.bottom,
        signatureClear: !signature || (signature.bottom <= workspace.bottom && getComputedStyle(sheet.querySelector('.signature-block')).backgroundColor === 'rgb(255, 255, 255)'),
        clinicalContained: clinicalNodes.every((node) => node.getBoundingClientRect().bottom <= workspace.bottom + 0.5),
      };
    }));
    expect(new Set(zones.map(({ headerTop, headerHeight, stripTop, stripHeight, workspaceTop, workspaceHeight, footerTop, footerHeight }) => `${headerTop}:${headerHeight}:${stripTop}:${stripHeight}:${workspaceTop}:${workspaceHeight}:${footerTop}:${footerHeight}`)).size).toBe(1);
    const footerFailures = zones.filter(({ footerColumnsClear, footerColumnsContained, footerInsidePage, footerContentFits, footerPageVisible }) => !(footerColumnsClear && footerColumnsContained && footerInsidePage && footerContentFits && footerPageVisible));
    if (footerFailures.length) console.log('FOOTER_GEOMETRY_FAILURE', JSON.stringify(footerFailures));
    expect(zones.every(({ watermarkContained, adaptiveWatermarkCorrect, textureContained, signatureClear, clinicalContained, footerColumnsClear, footerColumnsContained, footerInsidePage, footerContentFits, footerPageVisible }) => watermarkContained && adaptiveWatermarkCorrect && textureContained && signatureClear && clinicalContained && footerColumnsClear && footerColumnsContained && footerInsidePage && footerContentFits && footerPageVisible)).toBe(true);
    const screenPageGaps = await page.locator('.report-page').evaluateAll((sheets) => sheets.slice(0, -1).map((sheet, index) => sheets[index + 1].getBoundingClientRect().top - sheet.getBoundingClientRect().bottom));
    expect(screenPageGaps.every((gap) => gap >= 20)).toBe(true);
    const sectionBoxes = await page.locator('.investigation-block').evaluateAll((blocks) => blocks.every((block) => {
      const style = getComputedStyle(block);
      return ['borderTopWidth', 'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth'].every((property) => Number.parseFloat(style[property]) >= 1);
    }));
    expect(sectionBoxes).toBe(true);
    if (fixture.generation) {
      const zoneSignature = zones.map(({ headerTop, headerHeight, stripTop, stripHeight, workspaceTop, workspaceHeight, footerTop, footerHeight }) => `${headerTop}:${headerHeight}:${stripTop}:${stripHeight}:${workspaceTop}:${workspaceHeight}:${footerTop}:${footerHeight}`).join('|');
      generationGeometry.set(fixture.profile, zoneSignature);
      if (fixture.profile === 'historical-signed') {
        await expect(page.locator('.patient-identity-strip')).toContainText('HISTORICAL SIGNED PATIENT');
        await expect(page.locator('.patient-identity-strip')).toContainText('LAB-2018-SIGNED');
        await expect(page.locator('.report-state')).toContainText('FINAL SIGNED REPORT');
      }
      if (fixture.profile === 'historical-amended') {
        await expect(page.locator('.patient-identity-strip')).toContainText('HISTORICAL AMENDED PATIENT');
        await expect(page.locator('.patient-identity-strip')).toContainText('LAB-2019-AMENDED');
        await expect(page.locator('.report-state')).toContainText('AMENDED REPORT (v3)');
        await expect(page.locator('.clinical-workspace')).toContainText('Historical corrected result retained in its frozen version.');
      }
    }
    const qa = await page.locator('body').evaluate((body) => ({ ...body.dataset }));
    expect(qa.qaContentBeforeSignature).toBe('true');
    expect(qa.qaSignatureOnEveryPage).toBe('true');
    expect(qa.qaSignatureBeforeFooter).toBe('true');
    expect(qa.qaFinalPageContained).toBe('true');
    expect(qa.qaSnapshotUnchanged).toBe('true');
    expect(qa.qaRenderedInvestigationCount).toBe(qa.qaSnapshotInvestigationCount);
    expect(qa.qaRenderedResultCount).toBe(qa.qaSnapshotResultCount);
    if (fixture.wholeBody) {
      const stressGeometry = JSON.parse(qa.qaPageGeometry);
      expect(stressGeometry).toHaveLength(await page.locator('.report-page').count());
      // A new investigation's measured heading + columns + first row can
      // legitimately leave roughly 54 mm when the model's font-fallback
      // reserve is included. Larger gaps indicate avoidable packing drift.
      expect(stressGeometry.slice(0, -1).every((entry) => entry.actualRemainingMm < 60)).toBe(true);
      expect(Number(qa.qaSnapshotInvestigationCount)).toBe(12);
      expect(Number(qa.qaSnapshotResultCount)).toBe(fixture.resultCount);
      console.log(`WHOLE_BODY_GEOMETRY ${JSON.stringify({ pageCount: stressGeometry.length, investigations: Number(qa.qaRenderedInvestigationCount), results: Number(qa.qaRenderedResultCount), maxIntermediateRemainingMm: Math.max(...stressGeometry.slice(0, -1).map((entry) => entry.actualRemainingMm)) })}`);
    }
    if (fixture.realClinical) {
      const investigationIds = await page.locator('.investigation-block').evaluateAll((nodes) => nodes.map((node) => node.getAttribute('data-investigation-id')));
      const parameterIds = await page.locator('.clinical-result-row').evaluateAll((nodes) => nodes.map((node) => node.getAttribute('data-parameter-id')));
      expect(new Set(investigationIds).size).toBe(Number(qa.qaSnapshotInvestigationCount));
      expect(new Set(parameterIds).size).toBe(parameterIds.length);
      expect(parameterIds).toHaveLength(Number(qa.qaSnapshotResultCount));
      await expect(page.locator('[data-investigation-id="real-creatinine"] [data-parameter-id="creatinine"]')).toHaveCount(1);
      const lftChunks = page.locator('[data-investigation-id="real-lft"]');
      await expect(lftChunks).toHaveCount(2);
      await expect(page.locator('.report-page').nth(0).locator('[data-investigation-id="real-lft"]')).toHaveCount(1);
      await expect(page.locator('.report-page').nth(1).locator('[data-investigation-id="real-lft"][data-investigation-continuation="true"]')).toContainText('Liver Function Test (LFT) — continued');
      expect(await page.locator('.report-page').nth(0).locator('[data-investigation-id="real-lft"] .clinical-result-row').count()).toBeGreaterThan(0);
      const compactLabels = await page.locator('.compact-single-investigation').evaluateAll((blocks) => blocks.map((block) => {
        const title = block.querySelector('.department-header-block > *:nth-child(2)');
        const parameter = block.querySelector('.clinical-result-row td:first-child');
        return {
          title: title?.textContent?.trim(),
          titleSingleLine: Boolean(title) && getComputedStyle(title).whiteSpace === 'nowrap' && title.scrollWidth <= title.clientWidth + 1,
          parameter: parameter?.textContent?.trim(),
          parameterSingleLine: Boolean(parameter) && getComputedStyle(parameter).whiteSpace === 'nowrap' && parameter.scrollWidth <= parameter.clientWidth + 1,
        };
      }));
      expect(compactLabels.map(({ title }) => title)).toEqual(['Serum Creatinine', 'Serum Sodium', 'Serum Potassium', 'Blood Urea']);
      expect(compactLabels.every(({ titleSingleLine, parameterSingleLine }) => titleSingleLine && parameterSingleLine)).toBe(true);
      const orphaned = await page.locator('.investigation-block').evaluateAll((blocks) => blocks.some((block) => block.querySelectorAll('.clinical-result-row').length === 0));
      expect(orphaned).toBe(false);
      const firstRowsContained = await page.locator('.investigation-block').evaluateAll((blocks) => blocks.every((block) => {
        const firstRow = block.querySelector('.clinical-result-row');
        const workspace = block.closest('.clinical-workspace');
        return firstRow && firstRow.getBoundingClientRect().bottom <= workspace.getBoundingClientRect().bottom - 2;
      }));
      expect(firstRowsContained).toBe(true);
      const geometryRows = JSON.parse(qa.qaPageGeometry);
      expect(geometryRows).toHaveLength(2);
      expect(geometryRows.every((entry) => entry.actualRemainingMm >= 0)).toBe(true);
      expect(geometryRows[0].actualRemainingMm).toBeLessThan(35);
      expect(Number(qa.qaFinalizationReserveMm)).toBeGreaterThan(0);
      expect(Number(qa.qaSignatureFooterGapMm)).toBeGreaterThanOrEqual(0);
      const signatureBox = await page.locator('.signature-block').last().evaluate((block) => {
        const style = getComputedStyle(block);
        const panels = [...block.firstElementChild.children].map((panel) => panel.getBoundingClientRect().width);
        return {
          heightMm: Number((block.getBoundingClientRect().height * 25.4 / 96).toFixed(2)),
          bordered: ['borderTopWidth', 'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth'].every((property) => Number.parseFloat(style[property]) >= 1),
          equalColumns: panels.length < 2 || Math.abs(panels[0] - panels[1]) < 1,
        };
      });
      expect(signatureBox.bordered && signatureBox.equalColumns).toBe(true);
      console.log(`REAL_FIXTURE_GEOMETRY ${JSON.stringify({ pages: geometryRows, lftChunks: await lftChunks.count(), results: { snapshot: Number(qa.qaSnapshotResultCount), rendered: parameterIds.length }, signatureBox, signatureFooterGapMm: Number(qa.qaSignatureFooterGapMm), finalizationReserveMm: Number(qa.qaFinalizationReserveMm) })}`);
    }
    const geometry = await page.locator('.report-page').first().evaluate((element) => {
      const rect = element.getBoundingClientRect();
      return { width: rect.width, height: rect.height, overflow: getComputedStyle(element).overflow };
    });
    expect(geometry.width / geometry.height).toBeCloseTo(210 / 297, 2);
    expect(geometry.overflow).toBe('hidden');
    const physicalGeometry = await page.locator('.report-page').first().evaluate((sheet) => {
      const mm = (px) => Number((px * 25.4 / 96).toFixed(2));
      const page = sheet.getBoundingClientRect();
      const rect = (selector) => sheet.querySelector(selector).getBoundingClientRect();
      const header = rect('.report-header');
      const patient = rect('.patient-identity-strip');
      const clinical = rect('.clinical-workspace');
      const signature = rect('.signature-block');
      const footer = rect('.bimal-footer-strip');
      const style = getComputedStyle(sheet);
      const wrapperStyle = getComputedStyle(sheet.closest('.printable-report-wrapper'));
      return {
        pageWidthMm: mm(page.width), pageHeightMm: mm(page.height),
        outerLeftMm: mm(header.left - page.left), outerRightMm: mm(page.right - header.right),
        headerWidthMm: mm(header.width), patientBandWidthMm: mm(patient.width),
        clinicalWidthMm: mm(clinical.width), signatureWidthMm: mm(signature.width), footerWidthMm: mm(footer.width),
        footerToPageBottomMm: mm(page.bottom - footer.bottom),
        pageTransform: style.transform, pageZoom: style.zoom,
        wrapperTransform: wrapperStyle.transform, wrapperZoom: wrapperStyle.zoom,
      };
    });
    expect(physicalGeometry).toMatchObject({
      pageWidthMm: 210, pageHeightMm: 297, outerLeftMm: 10, outerRightMm: 10,
      headerWidthMm: 190, patientBandWidthMm: 190, clinicalWidthMm: 190,
      signatureWidthMm: 190, footerWidthMm: 190, footerToPageBottomMm: 10,
      pageTransform: 'none', wrapperTransform: 'none',
    });
    expect(Number(physicalGeometry.pageZoom)).toBe(1);
    expect(Number(physicalGeometry.wrapperZoom)).toBe(1);
    if (fixture.pages === '1' && fixture.profile === 'cbc') {
      await page.pdf({ path: 'qa-artifacts/report-print/cbc-one-page.pdf', format: 'A4', printBackground: true, margin: { top: '0', right: '0', bottom: '0', left: '0' } });
      await page.locator('.report-page').screenshot({ path: 'qa-artifacts/report-print/cbc-one-page.png' });
    }
    if (fixture.profile === 'urea-cbc-creatinine') {
      await page.pdf({ path: 'qa-artifacts/report-print/urea-cbc-creatinine.pdf', preferCSSPageSize: true, scale: 1, printBackground: true, margin: { top: '0', right: '0', bottom: '0', left: '0' } });
    }
    if (fixture.sparseSerology) {
      const pdfPath = 'qa-artifacts/report-print/sparse-serology-a4.pdf';
      // Exercise the same CSS-authoritative A4 path used by browser printing.
      await page.pdf({ path: pdfPath, preferCSSPageSize: true, scale: 1, printBackground: true, margin: { top: '0', right: '0', bottom: '0', left: '0' } });
      await page.locator('.report-page').screenshot({ path: 'qa-artifacts/report-print/sparse-serology-a4.png' });
      const pdf = fs.readFileSync(pdfPath).toString('latin1');
      const mediaBox = pdf.match(/\/MediaBox\s*\[\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\]/);
      expect(mediaBox, 'generated PDF must expose an A4 MediaBox').not.toBeNull();
      const widthPt = Number(mediaBox[3]) - Number(mediaBox[1]);
      const heightPt = Number(mediaBox[4]) - Number(mediaBox[2]);
      // Chromium quantizes CSS millimetres to device units (currently 594.96
      // x 841.92 pt); keep acceptance within 0.18 mm of ISO A4.
      expect(widthPt).toBeCloseTo(595.28, 0);
      expect(heightPt).toBeCloseTo(841.89, 0);
      expect(await page.locator('.clinical-result-row')).toHaveCount(4);
      expect(Number(await page.locator('.bimal-page-watermark').getAttribute('data-watermark-size-mm'))).toBeGreaterThanOrEqual(60);
      fs.writeFileSync('qa-artifacts/report-print/sparse-serology-physical-geometry.json', JSON.stringify({ mediaBoxPt: { width: widthPt, height: heightPt }, measuredMm: physicalGeometry }, null, 2));
    }
    if (fixture.pages === '2' && !fixture.profile) {
      await page.pdf({ path: 'qa-artifacts/report-print/profile-two-page.pdf', format: 'A4', printBackground: true, margin: { top: '0', right: '0', bottom: '0', left: '0' } });
    }
    if (fixture.pages === '3') await page.pdf({ path: 'qa-artifacts/report-print/profile-three-page.pdf', format: 'A4', printBackground: true, margin: { top: '0', right: '0', bottom: '0', left: '0' } });
    if (fixture.pages === '4') await page.pdf({ path: 'qa-artifacts/report-print/profile-four-page.pdf', format: 'A4', printBackground: true, margin: { top: '0', right: '0', bottom: '0', left: '0' } });
    if (fixture.pages === '5') {
      await page.pdf({ path: 'qa-artifacts/report-print/profile-five-page.pdf', format: 'A4', printBackground: true, margin: { top: '0', right: '0', bottom: '0', left: '0' } });
    }
    if (fixture.pages === 'N') {
      await page.pdf({ path: 'qa-artifacts/report-print/large-eight-page.pdf', format: 'A4', printBackground: true, margin: { top: '0', right: '0', bottom: '0', left: '0' } });
    }
    if (fixture.wholeBody) {
      const artifactStem = `whole-body-${fixture.pages}-pages`;
      await page.pdf({ path: `qa-artifacts/report-print/${artifactStem}.pdf`, format: 'A4', printBackground: true, margin: { top: '0', right: '0', bottom: '0', left: '0' } });
      if (!fixture.extended) {
        await page.locator('.report-page').first().screenshot({ path: 'qa-artifacts/report-print/whole-body-first-page.png' });
        await page.locator('.report-page').last().screenshot({ path: 'qa-artifacts/report-print/whole-body-final-page.png' });
      }
    }
    if (fixture.profile === 'identity') await page.pdf({ path: 'qa-artifacts/report-print/nepali-long-identity.pdf', format: 'A4', printBackground: true, margin: { top: '0', right: '0', bottom: '0', left: '0' } });
    if (fixture.profile === 'historical-signed') {
      await page.pdf({ path: 'qa-artifacts/report-print/historical-signed-current-canonical.pdf', preferCSSPageSize: true, scale: 1, printBackground: true });
      await page.locator('.report-page').screenshot({ path: 'qa-artifacts/report-print/historical-signed-current-canonical.png' });
    }
    if (fixture.profile === 'historical-amended') {
      await page.pdf({ path: 'qa-artifacts/report-print/historical-amended-current-canonical.pdf', preferCSSPageSize: true, scale: 1, printBackground: true });
      await page.locator('.report-page').screenshot({ path: 'qa-artifacts/report-print/historical-amended-current-canonical.png' });
    }
    if (fixture.profile === 'historical-multipage') {
      await page.pdf({ path: 'qa-artifacts/report-print/historical-multipage-current-canonical.pdf', preferCSSPageSize: true, scale: 1, printBackground: true });
      await page.locator('.report-page').first().screenshot({ path: 'qa-artifacts/report-print/historical-multipage-page-1.png' });
      await page.locator('.report-page').last().screenshot({ path: 'qa-artifacts/report-print/historical-multipage-page-2.png' });
    }
    if (fixture.profile === 'current-multipage') {
      await page.pdf({ path: 'qa-artifacts/report-print/current-multipage-canonical.pdf', preferCSSPageSize: true, scale: 1, printBackground: true });
      await page.locator('.report-page').first().screenshot({ path: 'qa-artifacts/report-print/current-multipage-page-1.png' });
      await page.locator('.report-page').last().screenshot({ path: 'qa-artifacts/report-print/current-multipage-page-2.png' });
    }
    if (fixture.profile === 'boundary') {
      await page.pdf({ path: 'qa-artifacts/report-print/long-ranges-interpretation.pdf', format: 'A4', printBackground: true, margin: { top: '0', right: '0', bottom: '0', left: '0' } });
      await page.locator('.report-page').last().screenshot({ path: 'qa-artifacts/report-print/long-ranges-interpretation-final-page.png' });
    }
    if (fixture.profile === 'one-signatory') await page.pdf({ path: 'qa-artifacts/report-print/one-signatory.pdf', format: 'A4', printBackground: true, margin: { top: '0', right: '0', bottom: '0', left: '0' } });
    if (fixture.realClinical) {
      await page.pdf({ path: 'qa-artifacts/report-print/real-cbc-lft-electrolytes-corrected.pdf', format: 'A4', printBackground: true, margin: { top: '0', right: '0', bottom: '0', left: '0' } });
      await page.locator('.report-page').nth(0).screenshot({ path: 'qa-artifacts/report-print/real-cbc-lft-electrolytes-page-1.png' });
      await page.locator('.report-page').nth(1).screenshot({ path: 'qa-artifacts/report-print/real-cbc-lft-electrolytes-page-2.png' });
    }
  }
  expect(generationGeometry.get('historical-signed')).toBe(generationGeometry.get('cbc'));
  expect(generationGeometry.get('historical-amended')).toBe(generationGeometry.get('cbc'));
  expect(generationGeometry.get('historical-multipage')).toBe(generationGeometry.get('current-multipage'));
});
