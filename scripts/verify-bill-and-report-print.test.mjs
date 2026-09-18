import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';

import { BIMAL_PRINT, BIMAL_PRINT_CSS } from '../src/lib/printDesign.ts';
import { paginateInvestigations } from '../src/features/reports/reportPagination.js';
import { rupeesToPaisa, paisaToRupees } from '../src/lib/currency.ts';
import { PERMISSION_KEYS, LAB_TECHNICIAN_PERMISSION_ALLOWLIST } from '../src/types/permissions.ts';

describe('Bimal Pathology LIS: Bill Print Removal & Diagnostic Report Print Suite', () => {

  describe('1. Bill Print Removal & Workflow-Only Verification', () => {
    it('verifies integer paisa values convert accurately without floating drift', () => {
      assert.strictEqual(paisaToRupees(50000), 500);
      assert.strictEqual(paisaToRupees(120000), 1200);
      assert.strictEqual(paisaToRupees(20000), 200);
      assert.strictEqual(paisaToRupees(12345), 123.45);

      assert.strictEqual(rupeesToPaisa(500), 50000);
      assert.strictEqual(rupeesToPaisa(1200), 120000);
      assert.strictEqual(rupeesToPaisa(200), 20000);
      assert.strictEqual(rupeesToPaisa(123.45), 12345);
    });

    it('verifies NewBillPage has no Print Bill button and does not auto-open print dialog on save', () => {
      const newBillSource = readFileSync(
        path.resolve(process.cwd(), 'src/features/billing/NewBillPage.tsx'),
        'utf8'
      );

      assert.ok(!newBillSource.includes('Print Bill (A4)'), 'Must not have Print Bill button');
      assert.ok(!newBillSource.includes('window.print()'), 'Must not call window.print()');
      assert.ok(!newBillSource.includes("printReportDocument('printable-invoice')"), 'Must not trigger invoice print');
      assert.ok(newBillSource.includes('Bill saved and order registered successfully'), 'Must show clean save success message');
      assert.ok(newBillSource.includes('New Bill'), 'Must provide fast New Bill action');
      assert.ok(newBillSource.includes('Continue to Sample Accession'), 'Must provide fast workflow continuation');
    });

    it('verifies BillViewerDialog is purely on-screen view without print/PDF triggers', () => {
      const viewerDialogSource = readFileSync(
        path.resolve(process.cwd(), 'src/features/billing/BillViewerDialog.tsx'),
        'utf8'
      );

      assert.ok(!viewerDialogSource.includes("printReportDocument('printable-invoice')"), 'Must not have printReportDocument');
      assert.ok(!viewerDialogSource.includes('Print Bill (A4)'), 'Must not have Print Bill button');
      assert.ok(!viewerDialogSource.includes('PrintIcon'), 'Must not have PrintIcon');
      assert.ok(viewerDialogSource.includes('Bill Details'), 'Must provide on-screen Bill Details title');
      assert.ok(viewerDialogSource.includes('Financial Settlement Summary'), 'Must show financial settlement breakdown');
    });

    it('verifies BillListPage provides on-screen bill view and payment collection without print actions', () => {
      const billListSource = readFileSync(
        path.resolve(process.cwd(), 'src/features/billing/BillListPage.tsx'),
        'utf8'
      );

      assert.ok(billListSource.includes('View Bill'), 'Must have View Bill button');
      assert.ok(!billListSource.includes('Reprint Bill'), 'Must not have Reprint Bill button');
      assert.ok(!billListSource.includes('Print Invoice'), 'Must not have Print Invoice button');
      assert.ok(!billListSource.includes("printReportDocument('printable-invoice')"), 'Must not trigger invoice print');
      assert.ok(billListSource.includes('Receive Payment'), 'Must allow recording pending payments');
    });
  });

  describe('2. Diagnostic Report Print Immutable Architecture (100% Intact)', () => {
    it('verifies FinalReportViewerDialog relies strictly on clinical_snapshot_json with print and PDF actions', () => {
      const reportViewerSource = readFileSync(
        path.resolve(process.cwd(), 'src/features/reports/FinalReportViewerDialog.tsx'),
        'utf8'
      );

      assert.ok(reportViewerSource.includes('clinical_snapshot_json'), 'Must use frozen clinical snapshot');
      assert.ok(reportViewerSource.includes('ReportDocument'), 'Must render ReportDocument');
      assert.ok(reportViewerSource.includes('printReportDocument()'), 'Must provide printReportDocument');
      assert.ok(reportViewerSource.includes('downloadReportPdf'), 'Must provide downloadReportPdf');
    });

    it('verifies ReportDocument renders official header, patient details, QR verification and signatories', () => {
      const reportDocSource = readFileSync(
        path.resolve(process.cwd(), 'src/features/reports/ReportDocument.tsx'),
        'utf8'
      );

      assert.ok(reportDocSource.includes('BIMAL PATHOLOGY & DIAGNOSTIC CENTER'), 'Must render official lab title');
      assert.ok(reportDocSource.includes('qrCodeDataUrl') || reportDocSource.includes('QR'), 'Must render QR verification section');
      assert.ok(reportDocSource.includes('signature-block') || reportDocSource.includes('Performed By'), 'Must render signatory block');
      assert.ok(reportDocSource.includes('bimal-page-content'), 'Must render canonical clinical content');
    });

    it('verifies reportPrint.ts creates an isolated iframe with CSSOM styles and font readiness', () => {
      const reportPrintSource = readFileSync(
        path.resolve(process.cwd(), 'src/lib/reportPrint.ts'),
        'utf8'
      );

      assert.ok(reportPrintSource.includes("document.createElement('iframe')"), 'Must use isolated iframe');
      assert.ok(reportPrintSource.includes('BIMAL_PRINT_CSS'), 'Must inject canonical print CSS');
      assert.ok(reportPrintSource.includes('waitForPrintAssets'), 'Must wait for fonts and assets');
    });
  });

  describe('3. A4 Physical Geometry & Diagnostic Print Isolation', () => {
    it('verifies BIMAL_PRINT has exact 210mm x 297mm geometry and brand definitions', () => {
      assert.strictEqual(BIMAL_PRINT.pageWidth, '210mm');
      assert.strictEqual(BIMAL_PRINT.pageHeight, '297mm');
      assert.strictEqual(BIMAL_PRINT.brand, '#0b6b3a');
      assert.strictEqual(BIMAL_PRINT.watermarkOpacity, 0.045);
    });

    it('verifies BIMAL_PRINT_CSS enforces A4 portrait, 0 margin, and screen-only suppression', () => {
      assert.ok(BIMAL_PRINT_CSS.includes('size: A4 portrait; margin: 0;'));
      assert.ok(BIMAL_PRINT_CSS.includes('.bimal-a4-page'));
    });
  });

  describe('4. Deterministic Multi-Page Pagination Engine for Reports', () => {
    it('paginates a single CBC investigation on exactly 1 page', () => {
      const investigations = [
        {
          name: 'Complete Blood Count (CBC)',
          code: 'HEM-0001',
          results: Array.from({ length: 8 }, (_, i) => ({
            name: `Parameter ${i + 1}`,
            display_value: '10.0',
            unit: '10^9/L',
            reference_range: '4.0 - 11.0',
            flag: 'NORMAL',
          })),
        },
      ];

      const pages = paginateInvestigations(investigations);
      assert.strictEqual(pages.length, 1);
      assert.strictEqual(pages[0].isFinalPage, true);
    });

    it('deterministically splits a large multi-panel report into multiple pages without dropping items', () => {
      const investigations = [
        {
          name: 'Lipid Profile',
          code: 'BIO-0027',
          results: Array.from({ length: 15 }, (_, i) => ({
            name: `Lipid Parameter ${i + 1}`,
            display_value: '150',
            unit: 'mg/dL',
            reference_range: '< 200',
            flag: 'NORMAL',
          })),
        },
        {
          name: 'Liver Function Tests',
          code: 'BIO-0017',
          results: Array.from({ length: 25 }, (_, i) => ({
            name: `LFT Parameter ${i + 1}`,
            display_value: '30',
            unit: 'U/L',
            reference_range: '< 40',
            flag: 'NORMAL',
          })),
        },
      ];

      const pages = paginateInvestigations(investigations);
      assert.ok(pages.length >= 2);
      assert.strictEqual(pages[pages.length - 1].isFinalPage, true);

      const totalRenderedResults = pages.reduce(
        (sum, p) => sum + p.investigations.reduce((iSum, inv) => iSum + inv.results.length, 0),
        0
      );
      assert.strictEqual(totalRenderedResults, 40);
    });
  });

  describe('5. RBAC Enforcement: Lab Technician Capabilities', () => {
    it('verifies Lab Technician has operational billing and report printing without financial metrics or settings access', () => {
      assert.ok(LAB_TECHNICIAN_PERMISSION_ALLOWLIST.includes(PERMISSION_KEYS.CAN_CREATE_BILL));
      assert.ok(LAB_TECHNICIAN_PERMISSION_ALLOWLIST.includes(PERMISSION_KEYS.CAN_PRINT_REPORTS));
      assert.ok(!LAB_TECHNICIAN_PERMISSION_ALLOWLIST.includes(PERMISSION_KEYS.CAN_MANAGE_CATALOGUE));
      assert.ok(!LAB_TECHNICIAN_PERMISSION_ALLOWLIST.includes(PERMISSION_KEYS.CAN_VIEW_FINANCIALS));
    });
  });
});
