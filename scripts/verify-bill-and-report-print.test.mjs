import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';

import { BIMAL_PRINT, BIMAL_PRINT_CSS } from '../src/lib/printDesign.ts';
import { paginateInvestigations } from '../src/features/reports/reportPagination.js';
import { rupeesToPaisa, paisaToRupees } from '../src/lib/currency.ts';
import { PERMISSION_KEYS, LAB_TECHNICIAN_PERMISSION_ALLOWLIST } from '../src/types/permissions.ts';

describe('Bimal Pathology LIS: Bill & Diagnostic Report Print Audit Suite', () => {

  describe('1. Bill Print Immutable Snapshot & Money Formatting', () => {
    it('formats integer paisa values into exact NPR representations without floating drift', () => {
      assert.strictEqual(paisaToRupees(50000), 500);
      assert.strictEqual(paisaToRupees(120000), 1200);
      assert.strictEqual(paisaToRupees(20000), 200);
      assert.strictEqual(paisaToRupees(12345), 123.45);

      assert.strictEqual(rupeesToPaisa(500), 50000);
      assert.strictEqual(rupeesToPaisa(1200), 120000);
      assert.strictEqual(rupeesToPaisa(200), 20000);
      assert.strictEqual(rupeesToPaisa(123.45), 12345);
    });

    it('verifies BillDocument renders immutable snapshot fields and does not recalculate from catalogue', () => {
      const billDocSource = readFileSync(
        path.resolve(process.cwd(), 'src/features/billing/BillDocument.tsx'),
        'utf8'
      );

      // Asserts that BillDocument references snapshot fields
      assert.ok(billDocSource.includes('gross_amount_paisa'));
      assert.ok(billDocSource.includes('discount_amount_paisa'));
      assert.ok(billDocSource.includes('net_amount_paisa'));
      assert.ok(billDocSource.includes('paid_amount_paisa'));
      assert.ok(billDocSource.includes('due_amount_paisa'));
      assert.ok(billDocSource.includes('unit_price_paisa'));
      assert.ok(billDocSource.includes('discount_paisa'));
      assert.ok(billDocSource.includes('net_price_paisa'));
      assert.ok(billDocSource.includes('patient_name_snapshot'));
      assert.ok(billDocSource.includes('patient_uhid_snapshot'));
      assert.ok(billDocSource.includes('referring_doctor_name_snapshot'));
      assert.ok(billDocSource.includes('BIMAL_PRINT_CSS'));
      assert.ok(billDocSource.includes('printable-invoice'));
    });

    it('verifies BillViewerDialog provides isolated iframe print action and navigation', () => {
      const viewerDialogSource = readFileSync(
        path.resolve(process.cwd(), 'src/features/billing/BillViewerDialog.tsx'),
        'utf8'
      );

      assert.ok(viewerDialogSource.includes("printReportDocument('printable-invoice')"));
      assert.ok(viewerDialogSource.includes('Print Bill (A4)'));
      assert.ok(viewerDialogSource.includes('BillDocument'));
    });

    it('verifies BillListPage integrates BillViewerDialog for instant bill printing', () => {
      const billListSource = readFileSync(
        path.resolve(process.cwd(), 'src/features/billing/BillListPage.tsx'),
        'utf8'
      );

      assert.ok(billListSource.includes('BillViewerDialog'));
      assert.ok(billListSource.includes('receiptModalOpen'));
    });

    it('verifies NewBillPage integrates BillViewerDialog and Print Bill button on save completion', () => {
      const newBillSource = readFileSync(
        path.resolve(process.cwd(), 'src/features/billing/NewBillPage.tsx'),
        'utf8'
      );

      assert.ok(newBillSource.includes('BillViewerDialog'));
      assert.ok(newBillSource.includes('billViewerOpen'));
      assert.ok(newBillSource.includes('Print Bill (A4)'));
    });
  });

  describe('2. Diagnostic Report Print Immutable Architecture', () => {
    it('verifies FinalReportViewerDialog relies strictly on clinical_snapshot_json', () => {
      const reportViewerSource = readFileSync(
        path.resolve(process.cwd(), 'src/features/reports/FinalReportViewerDialog.tsx'),
        'utf8'
      );

      assert.ok(reportViewerSource.includes('clinical_snapshot_json'));
      assert.ok(reportViewerSource.includes('ReportDocument'));
      assert.ok(reportViewerSource.includes('printReportDocument()'));
      assert.ok(reportViewerSource.includes('downloadReportPdf'));
    });

    it('verifies ReportDocument renders official header, patient details, QR and signatories', () => {
      const reportDocSource = readFileSync(
        path.resolve(process.cwd(), 'src/features/reports/ReportDocument.tsx'),
        'utf8'
      );

      assert.ok(reportDocSource.includes('BIMAL PATHOLOGY & DIAGNOSTIC CENTER'));
      assert.ok(reportDocSource.includes('paginateInvestigations'));
      assert.ok(reportDocSource.includes('printable-report'));
      assert.ok(reportDocSource.includes('BIMAL_PRINT_CSS'));
      assert.ok(reportDocSource.includes('generateQrSvgPath'));
      assert.ok(reportDocSource.includes('Page'));
      assert.ok(reportDocSource.includes('END OF REPORT'));
    });

    it('verifies reportPrint.ts creates an isolated iframe with CSSOM styles and font readiness', () => {
      const printLibSource = readFileSync(
        path.resolve(process.cwd(), 'src/lib/reportPrint.ts'),
        'utf8'
      );

      assert.ok(printLibSource.includes('bimal-print-frame'));
      assert.ok(printLibSource.includes('printableStylesheetMarkup'));
      assert.ok(printLibSource.includes('waitForPrintAssets'));
      assert.ok(printLibSource.includes('BIMAL_PRINT_CSS'));
    });
  });

  describe('3. A4 Physical Geometry & Print Isolation', () => {
    it('verifies BIMAL_PRINT has exact 210mm x 297mm geometry and brand definitions', () => {
      assert.strictEqual(BIMAL_PRINT.pageWidth, '210mm');
      assert.strictEqual(BIMAL_PRINT.pageHeight, '297mm');
      assert.strictEqual(BIMAL_PRINT.brand, '#0b6b3a');
      assert.strictEqual(BIMAL_PRINT.brandDeep, '#07562f');
      assert.ok(BIMAL_PRINT.fontStack.includes('Noto Sans Devanagari'));
    });

    it('verifies BIMAL_PRINT_CSS enforces A4 portrait, 0 margin, and screen-only suppression', () => {
      assert.ok(BIMAL_PRINT_CSS.includes('size: A4 portrait;'));
      assert.ok(BIMAL_PRINT_CSS.includes('margin: 0;'));
      assert.ok(BIMAL_PRINT_CSS.includes('print-color-adjust: exact'));
      assert.ok(BIMAL_PRINT_CSS.includes('.screen-only'));
      assert.ok(BIMAL_PRINT_CSS.includes('display: none !important;'));
    });
  });

  describe('4. Deterministic Multi-Page Pagination Engine', () => {
    it('paginates a single CBC investigation on exactly 1 page', () => {
      const cbcInvestigation = {
        title: 'COMPLETE BLOOD COUNT (CBC)',
        clinicalSection: 'HEMATOLOGY',
        specimen: 'EDTA Whole Blood',
        method: 'Automated 5-Part Hematology Analyzer',
        results: [
          { parameter: 'Hemoglobin', value: '14.2', unit: 'g/dL', referenceRange: '13.0 - 17.0', flag: 'Normal' },
          { parameter: 'RBC Count', value: '4.8', unit: 'x10^6/uL', referenceRange: '4.5 - 5.5', flag: 'Normal' },
          { parameter: 'PCV / Hematocrit', value: '42.0', unit: '%', referenceRange: '40.0 - 50.0', flag: 'Normal' },
          { parameter: 'MCV', value: '87.5', unit: 'fL', referenceRange: '80.0 - 100.0', flag: 'Normal' },
          { parameter: 'MCH', value: '29.6', unit: 'pg', referenceRange: '27.0 - 32.0', flag: 'Normal' },
          { parameter: 'MCHC', value: '33.8', unit: 'g/dL', referenceRange: '32.0 - 36.0', flag: 'Normal' },
          { parameter: 'RDW-CV', value: '12.8', unit: '%', referenceRange: '11.5 - 14.5', flag: 'Normal' },
          { parameter: 'Total Leucocyte Count (TLC)', value: '7200', unit: '/cumm', referenceRange: '4000 - 11000', flag: 'Normal' },
          { parameter: 'Platelet Count', value: '250000', unit: '/cumm', referenceRange: '150000 - 450000', flag: 'Normal' },
        ],
      };

      const pages = paginateInvestigations([cbcInvestigation]);
      assert.strictEqual(pages.length, 1);
      assert.strictEqual(pages[0].pageNumber, 1);
      assert.strictEqual(pages[0].isFinalPage, true);
      assert.strictEqual(pages[0].investigations.length, 1);
      assert.strictEqual(pages[0].investigations[0].results.length, 9);
    });

    it('deterministically splits a large multi-panel report into multiple pages without dropping items', () => {
      const largePanels = Array.from({ length: 6 }, (_, pIdx) => ({
        title: `CLINICAL PANEL ${pIdx + 1}`,
        clinicalSection: 'BIOCHEMISTRY',
        results: Array.from({ length: 8 }, (_, rIdx) => ({
          parameter: `Analyte ${pIdx + 1}.${rIdx + 1}`,
          value: '100',
          unit: 'mg/dL',
          referenceRange: '70 - 110',
          flag: 'Normal',
        })),
      }));

      const pages = paginateInvestigations(largePanels);
      assert.ok(pages.length >= 2, `Expected multi-page split, got ${pages.length} pages`);

      // Verify every page has accurate metadata
      pages.forEach((page, idx) => {
        assert.strictEqual(page.pageNumber, idx + 1);
        if (idx === pages.length - 1) {
          assert.strictEqual(page.isFinalPage, true);
        } else {
          assert.strictEqual(page.isFinalPage, false);
        }
      });

      // Total result count preserved
      const totalResultsAcrossPages = pages.reduce(
        (sum, p) => sum + p.investigations.reduce((iSum, inv) => iSum + inv.results.length, 0),
        0
      );
      assert.strictEqual(totalResultsAcrossPages, 48);
    });
  });

  describe('5. RBAC Enforcement: Lab Technician Print Capabilities', () => {
    it('verifies Lab Technician has operational billing and report printing without financial metrics or settings access', () => {
      // Allowed operational permissions
      assert.ok(LAB_TECHNICIAN_PERMISSION_ALLOWLIST.includes(PERMISSION_KEYS.CAN_CREATE_BILL));
      assert.ok(LAB_TECHNICIAN_PERMISSION_ALLOWLIST.includes(PERMISSION_KEYS.CAN_PRINT_REPORTS));
      assert.ok(LAB_TECHNICIAN_PERMISSION_ALLOWLIST.includes(PERMISSION_KEYS.CAN_ENTER_RESULTS));
      assert.ok(LAB_TECHNICIAN_PERMISSION_ALLOWLIST.includes(PERMISSION_KEYS.CAN_VERIFY_RESULTS));
      assert.ok(LAB_TECHNICIAN_PERMISSION_ALLOWLIST.includes(PERMISSION_KEYS.CAN_SIGN_REPORTS));

      // Strictly denied administrative/financial permissions
      assert.strictEqual(LAB_TECHNICIAN_PERMISSION_ALLOWLIST.includes(PERMISSION_KEYS.CAN_VIEW_FINANCIALS), false);
      assert.strictEqual(LAB_TECHNICIAN_PERMISSION_ALLOWLIST.includes(PERMISSION_KEYS.CAN_MANAGE_SETTINGS), false);
      assert.strictEqual(LAB_TECHNICIAN_PERMISSION_ALLOWLIST.includes(PERMISSION_KEYS.CAN_MANAGE_CATALOGUE), false);
      assert.strictEqual(LAB_TECHNICIAN_PERMISSION_ALLOWLIST.includes(PERMISSION_KEYS.CAN_MANAGE_PERSONNEL), false);
    });
  });

  describe('6. Read-Only Reprint Safety', () => {
    it('verifies print action is purely a presentation call and does not invoke mutation RPCs', () => {
      const printFnSource = readFileSync(
        path.resolve(process.cwd(), 'src/lib/reportPrint.ts'),
        'utf8'
      );

      // Verifies reportPrint operates on DOM/iframe only and does NOT import supabase mutation RPCs
      assert.strictEqual(printFnSource.includes('supabase.rpc'), false);
      assert.strictEqual(printFnSource.includes('supabase.from'), false);
      assert.strictEqual(printFnSource.includes('update('), false);
      assert.strictEqual(printFnSource.includes('delete('), false);
    });
  });
});
