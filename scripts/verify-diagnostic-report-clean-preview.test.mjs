// scripts/verify-diagnostic-report-clean-preview.test.mjs
// Regression suite for clean diagnostic report PDF & preview

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';

import {
  isReportableParameter,
  formatReportReferenceRange,
  paginateInvestigations,
} from '../src/features/reports/reportPagination.js';

describe('Bimal Pathology LIS: Clean Diagnostic Report PDF & Preview Suite', () => {

  describe('1. Panel & Structural Row Filtering (CBC, LFT, KFT, Lipid)', () => {
    it('filters out CBC parent panel pseudo-parameter row', () => {
      const inv = {
        test_code: 'HEM-0001',
        test_name: 'Complete Blood Count (CBC)',
        results: [
          { parameter_id: 'p0', code: 'HEM-0001', name: 'Complete Blood Count (CBC)', unit: 'Panel', value_type: 'Numeric', display_value: '11' },
          { parameter_id: 'p1', code: 'WBC', name: 'White Blood Cell Count (TLC)', unit: '10^9/L', value_type: 'Numeric', display_value: '11.0', reference_range: '4.0 - 11.0' },
          { parameter_id: 'p2', code: 'HGB', name: 'Hemoglobin Concentration', unit: 'g/dL', value_type: 'Numeric', display_value: '14.0', reference_range: '13.0 - 17.0' }
        ]
      };

      const reportable = inv.results.filter((r) => isReportableParameter(r, inv));
      assert.equal(reportable.length, 2, 'Must filter out the parent panel row');
      assert.ok(!reportable.some((r) => r.code === 'HEM-0001' && r.unit === 'Panel'), 'CBC parent panel row must not be in reportable results');
      assert.ok(reportable.some((r) => r.code === 'WBC'), 'WBC must remain present');
      assert.ok(reportable.some((r) => r.code === 'HGB'), 'HGB must remain present');
    });

    it('filters out any parameter with unit="Panel" or value_type="Panel"', () => {
      assert.equal(isReportableParameter({ unit: 'Panel', name: 'Panel Test' }), false);
      assert.equal(isReportableParameter({ unit: 'panel', name: 'Panel Test' }), false);
      assert.equal(isReportableParameter({ value_type: 'Panel', name: 'Panel Test' }), false);
      assert.equal(isReportableParameter({ value_type: 'profile', name: 'Profile Test' }), false);
    });

    it('preserves single-parameter individual test where code equals test_code with valid unit', () => {
      const inv = {
        test_code: 'BIO-0001',
        test_name: 'Glucose, Fasting',
        results: [
          { parameter_id: 'p-fbs', code: 'BIO-0001', name: 'Glucose, Fasting', unit: 'mg/dL', value_type: 'Numeric', display_value: '95', reference_range: '70 - 100' }
        ]
      };

      const reportable = inv.results.filter((r) => isReportableParameter(r, inv));
      assert.equal(reportable.length, 1, 'Single individual test parameter must be preserved');
      assert.equal(reportable[0].name, 'Glucose, Fasting');
    });
  });

  describe('2. Reference Range "Not configured" Suppression', () => {
    it('replaces "Not configured", "Standard", and empty ranges with "—"', () => {
      assert.equal(formatReportReferenceRange('Not configured'), '—');
      assert.equal(formatReportReferenceRange('not configured'), '—');
      assert.equal(formatReportReferenceRange('Standard'), '—');
      assert.equal(formatReportReferenceRange('standard'), '—');
      assert.equal(formatReportReferenceRange(''), '—');
      assert.equal(formatReportReferenceRange(null), '—');
      assert.equal(formatReportReferenceRange('-'), '—');
    });

    it('preserves and normalizes valid approved reference ranges', () => {
      assert.equal(formatReportReferenceRange('4.0 - 11.0'), '4 - 11');
      assert.equal(formatReportReferenceRange('13.0 - 17.0'), '13 - 17');
      assert.equal(formatReportReferenceRange('< 200'), '< 200');
      assert.equal(formatReportReferenceRange('Negative'), 'Negative');
      assert.equal(formatReportReferenceRange('Diagnostic Cut-off: >= 1:160'), 'Diagnostic Cut-off: >= 1:160');
    });
  });

  describe('3. Standard 24-Parameter CBC Deterministic 1-Page Layout', () => {
    it('paginates a full 24-parameter standard CBC onto exactly 1 A4 page', () => {
      const cbcLeafCodes = [
        'WBC', 'LYM_ABS', 'MID_ABS', 'GRAN_ABS', 'LYM_PERCENT', 'MID_PERCENT', 'GRAN_PERCENT',
        'NLR', 'PLR', 'RBC', 'HGB', 'HCT', 'MCV', 'MCH', 'MCHC', 'RDW_CV', 'RDW_SD',
        'PLT', 'MPV', 'PDW_CV', 'PDW_SD', 'PCT', 'P_LCC', 'P_LCR'
      ];

      const cbcInvestigation = [{
        test_code: 'HEM-0001',
        test_name: 'Complete Blood Count (CBC)',
        department: 'Hematology',
        method: 'Automated Impedance / Colorimetry',
        results: cbcLeafCodes.map((code, idx) => ({
          parameter_id: `p-${code}`,
          code,
          name: `CBC Parameter ${idx + 1} (${code})`,
          unit: idx % 2 === 0 ? '10^9/L' : 'g/dL',
          display_value: `${10 + idx}.0`,
          reference_range: '4.0 - 11.0',
          flag: idx === 9 ? 'Low' : idx === 10 ? 'CriticalHigh' : 'Normal',
          is_critical: idx === 10,
        }))
      }];

      const pages = paginateInvestigations(cbcInvestigation);
      assert.equal(pages.length, 1, 'Standard 24-parameter CBC must paginate onto exactly 1 page');
      assert.equal(pages[0].isFinalPage, true, 'Single page must be marked as final page');
      assert.equal(pages[0].pageNumber, 1, 'Page number must be 1');
      assert.ok(pages[0].usedMm <= pages[0].capacityMm, 'Content must stay within physical page capacity');
    });

    it('filters parent panel row when 25 raw parameters (1 panel + 24 leaf) are passed to CBC', () => {
      const rawCbcResults = [
        { code: 'HEM-0001', name: 'Complete Blood Count (CBC)', unit: 'Panel', display_value: '11', reference_range: 'Not configured' },
        ...Array.from({ length: 24 }, (_, i) => ({
          code: `PARAM_${i + 1}`,
          name: `Parameter ${i + 1}`,
          unit: '10^9/L',
          display_value: '10.0',
          reference_range: '4.0 - 11.0',
          flag: 'Normal',
        }))
      ];

      const cbcInvestigation = [{
        test_code: 'HEM-0001',
        test_name: 'Complete Blood Count (CBC)',
        department: 'Hematology',
        results: rawCbcResults,
      }];

      const pages = paginateInvestigations(cbcInvestigation);
      assert.equal(pages.length, 1, 'Filtered CBC must fit on 1 page');
      assert.equal(pages[0].investigations[0].results.length, 24, 'Must contain exactly 24 leaf parameters without the parent panel row');
    });
  });

  describe('4. FinalReportViewerDialog & Preview UX', () => {
    it('verifies FinalReportViewerDialog resets scroll to top on open', () => {
      const dialogSrc = readFileSync(
        path.resolve(process.cwd(), 'src/features/reports/FinalReportViewerDialog.tsx'),
        'utf8'
      );

      assert.ok(dialogSrc.includes('scrollTop = 0'), 'Dialog must explicitly set scrollTop = 0');
      assert.ok(dialogSrc.includes('contentRef'), 'Dialog must use ref to control container scroll position');
      assert.ok(dialogSrc.includes('requestAnimationFrame'), 'Must reset scroll using animation frame for reliable rendering');
    });

    it('verifies ReportDocument contains official bilingual branding and patient identity strip', () => {
      const docSrc = readFileSync(
        path.resolve(process.cwd(), 'src/features/reports/ReportDocument.tsx'),
        'utf8'
      );

      assert.ok(docSrc.includes('BIMAL PATHOLOGY & DIAGNOSTIC CENTER'), 'Must have official English branding');
      assert.ok(docSrc.includes('बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर') || docSrc.includes('org.name_ne'), 'Must have official Nepali branding');
      assert.ok(docSrc.includes('Bharatpur-7, Chitwan, Nepal'), 'Must have official address');
      assert.ok(docSrc.includes('056-593288') || docSrc.includes('org.phone'), 'Must have official phone');
      assert.ok(docSrc.includes('patient-identity-strip'), 'Must render compact patient identity strip');
    });
  });

  describe('5. ResultEntryPage & Migration 00132 Active Parameter Sanitation', () => {
    it('verifies ResultEntryPage imports and applies isReportableParameter to masterParams', () => {
      const entrySrc = readFileSync(
        path.resolve(process.cwd(), 'src/features/worklist/ResultEntryPage.tsx'),
        'utf8'
      );

      assert.ok(entrySrc.includes('isReportableParameter'), 'ResultEntryPage must import isReportableParameter');
      assert.ok(entrySrc.includes('reportableMasterParams'), 'ResultEntryPage must filter masterParams into reportableMasterParams');
    });

    it('verifies Migration 00132 SQL structure and archival logic', () => {
      const migSrc = readFileSync(
        path.resolve(process.cwd(), 'supabase/migrations/00132_remove_structural_panel_parameters.sql'),
        'utf8'
      );

      assert.ok(migSrc.includes('00132'), 'Must identify as migration 00132');
      assert.ok(migSrc.includes('is_active = FALSE'), 'Must deactivate dummy parameters');
      assert.ok(migSrc.includes('HEM-0001'), 'Must explicitly guard HEM-0001');
      assert.ok(migSrc.includes('expected 24 leaf parameters'), 'Must assert 24 leaf parameters for CBC');
    });
  });
});

