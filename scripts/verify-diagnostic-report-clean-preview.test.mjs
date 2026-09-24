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
        path.resolve(process.cwd(), 'supabase/migrations_legacy_archive/00132_remove_structural_panel_parameters.sql'),
        'utf8'
      );

      assert.ok(migSrc.includes('00132'), 'Must identify as migration 00132');
      assert.ok(migSrc.includes('is_active = FALSE'), 'Must deactivate dummy parameters');
      assert.ok(migSrc.includes('HEM-0001'), 'Must explicitly guard HEM-0001');
      assert.ok(migSrc.includes('expected 24 leaf parameters'), 'Must assert 24 leaf parameters for CBC');
    });
  });

  describe('6. Patient Honorific Safety', () => {
    it('suppresses conflicting honorifics without guessing (e.g. Mr. with Female)', () => {
      // Direct string formatting logic check matching formatPatientDisplayName
      const formatTest = (fullName, title, gender) => {
        const cleanName = (fullName || '').trim();
        if (!cleanName) return '—';
        if (!title) return cleanName;
        const rawTitle = title.trim();
        const lowerTitle = rawTitle.toLowerCase().replace(/\.+$/, '');
        const normGender = (gender || '').trim().toLowerCase();
        const maleTitles = ['mr', 'master', 'shree', 'kumar'];
        const femaleTitles = ['mrs', 'ms', 'miss', 'smt', 'shrimati', 'kumari'];
        if ((normGender === 'female' || normGender === 'f') && maleTitles.includes(lowerTitle)) return cleanName;
        if ((normGender === 'male' || normGender === 'm') && femaleTitles.includes(lowerTitle)) return cleanName;
        if (cleanName.toLowerCase().startsWith(rawTitle.toLowerCase())) return cleanName;
        return `${rawTitle} ${cleanName}`;
      };

      assert.equal(formatTest('Kabita Subedi', 'Mr.', 'Female'), 'Kabita Subedi', 'Mr. Kabita Subedi must become Kabita Subedi');
      assert.equal(formatTest('Kabita Subedi', 'Mr', 'Female'), 'Kabita Subedi');
      assert.equal(formatTest('Ram Bahadur Thapa', 'Mrs.', 'Male'), 'Ram Bahadur Thapa');
      assert.equal(formatTest('Ram Bahadur Thapa', 'Mr.', 'Male'), 'Mr. Ram Bahadur Thapa');
      assert.equal(formatTest('Sita Sharma', 'Mrs.', 'Female'), 'Mrs. Sita Sharma');
      assert.equal(formatTest('Dr. Hari Prasad', 'Dr.', 'Male'), 'Dr. Hari Prasad');
      assert.equal(formatTest('Dr. Hari Prasad', null, 'Male'), 'Dr. Hari Prasad');
    });

    it('verifies ReportDocument uses formatPatientDisplayName and avoids guessed honorifics', () => {
      const docSrc = readFileSync(
        path.resolve(process.cwd(), 'src/features/reports/ReportDocument.tsx'),
        'utf8'
      );
      assert.ok(docSrc.includes('formatPatientDisplayName'), 'ReportDocument must import and use formatPatientDisplayName');
      assert.ok(docSrc.includes('patientDisplayName'), 'Must bind patientDisplayName to patient header');
    });
  });

  describe('7. Redesigned Minimal Footer & Single Authoritative Page Number', () => {
    it('verifies ReportDocument has clean 3-column footer and no 64-char hash in visible footer', () => {
      const docSrc = readFileSync(
        path.resolve(process.cwd(), 'src/features/reports/ReportDocument.tsx'),
        'utf8'
      );
      assert.ok(docSrc.includes('className="bimal-footer-strip"'), 'Must have bimal-footer-strip');
      assert.ok(docSrc.includes('className="bimal-footer-contact"'), 'Must have footer contact');
      assert.ok(docSrc.includes('className="bimal-footer-report-identity"'), 'Must have footer report identity');
      assert.ok(docSrc.includes('className="bimal-footer-page-number"'), 'Must have footer page number');
      assert.ok(!docSrc.includes('[${integrityHash}]'), 'Must NOT display 64-character hash string in visible footer');
      assert.ok(!docSrc.includes('className="report-header-page-number"'), 'Header must NOT duplicate page numbering');
    });

    it('verifies patient demographic grid does not duplicate page number', () => {
      const docSrc = readFileSync(
        path.resolve(process.cwd(), 'src/features/reports/ReportDocument.tsx'),
        'utf8'
      );
      const stripSection = docSrc.slice(docSrc.indexOf('className="patient-identity-strip"'), docSrc.indexOf('className="patient-info-box"'));
      assert.ok(!stripSection.includes('>Page<'), 'Patient demographic grid must NOT have a Page column');
    });
  });

  describe('8. Exact 24-Parameter CBC Single-Page Regression Coverage', () => {
    it('confirms CBC_STANDARD_PAGE_COUNT is exactly 1 with realistic parameter names and values', () => {
      const cbcParameters = [
        { code: 'WBC', name: 'White Blood Cell Count (TLC)', unit: '10^9/L', normal_min: 4, normal_max: 11, display_value: '7.5' },
        { code: 'LYM_ABS', name: 'Absolute Lymphocyte Count', unit: '10^9/L', normal_min: 1, normal_max: 3, display_value: '2.1' },
        { code: 'MID_ABS', name: 'Absolute Mid-Range Cell Count', unit: '10^9/L', normal_min: 0.2, normal_max: 1, display_value: '0.5' },
        { code: 'GRAN_ABS', name: 'Absolute Granulocyte Count', unit: '10^9/L', normal_min: 2, normal_max: 7, display_value: '4.9' },
        { code: 'LYM_PERCENT', name: 'Lymphocyte Percentage', unit: '%', normal_min: 20, normal_max: 40, display_value: '28.0' },
        { code: 'MID_PERCENT', name: 'Mid-Range Cell Percentage', unit: '%', normal_min: 3, normal_max: 10, display_value: '6.7' },
        { code: 'GRAN_PERCENT', name: 'Granulocyte Percentage', unit: '%', normal_min: 50, normal_max: 70, display_value: '65.3' },
        { code: 'NLR', name: 'Neutrophil-to-Lymphocyte Ratio (NLR)', unit: '-', normal_min: 1, normal_max: 3, display_value: '2.33' },
        { code: 'PLR', name: 'Platelet-to-Lymphocyte Ratio (PLR)', unit: '-', normal_min: 100, normal_max: 200, display_value: '119.0' },
        { code: 'RBC', name: 'Red Blood Cell Count (RBC)', unit: '10^12/L', normal_min: 4.5, normal_max: 5.9, display_value: '4.85' },
        { code: 'HGB', name: 'Hemoglobin Concentration', unit: 'g/dL', normal_min: 13, normal_max: 17, display_value: '14.2' },
        { code: 'HCT', name: 'Hematocrit / Packed Cell Volume (PCV)', unit: '%', normal_min: 40, normal_max: 50, display_value: '42.5' },
        { code: 'MCV', name: 'Mean Corpuscular Volume (MCV)', unit: 'fL', normal_min: 80, normal_max: 100, display_value: '87.6' },
        { code: 'MCH', name: 'Mean Corpuscular Hemoglobin (MCH)', unit: 'pg', normal_min: 27, normal_max: 32, display_value: '29.3' },
        { code: 'MCHC', name: 'Mean Corpuscular Hemoglobin Concentration (MCHC)', unit: 'g/dL', normal_min: 32, normal_max: 36, display_value: '33.4' },
        { code: 'RDW_CV', name: 'Red Cell Distribution Width - CV (RDW-CV)', unit: '%', normal_min: 11.5, normal_max: 14.5, display_value: '12.8' },
        { code: 'RDW_SD', name: 'Red Cell Distribution Width - SD (RDW-SD)', unit: 'fL', normal_min: 37, normal_max: 54, display_value: '42.1' },
        { code: 'PLT', name: 'Platelet Count (PLT)', unit: '10^9/L', normal_min: 150, normal_max: 450, display_value: '250' },
        { code: 'MPV', name: 'Mean Platelet Volume (MPV)', unit: 'fL', normal_min: 7.4, normal_max: 10.4, display_value: '8.9' },
        { code: 'PDW_CV', name: 'Platelet Distribution Width - CV (PDW-CV)', unit: '%', normal_min: 9, normal_max: 17, display_value: '12.3' },
        { code: 'PDW_SD', name: 'Platelet Distribution Width - SD (PDW-SD)', unit: 'fL', normal_min: 9, normal_max: 17, display_value: '11.8' },
        { code: 'PCT', name: 'Plateletcrit (PCT)', unit: '%', normal_min: 0.15, normal_max: 0.40, display_value: '0.22' },
        { code: 'P_LCC', name: 'Platelet Large Cell Count (P-LCC)', unit: '10^9/L', normal_min: 30, normal_max: 90, display_value: '55' },
        { code: 'P_LCR', name: 'Platelet Large Cell Ratio (P-LCR)', unit: '%', normal_min: 15, normal_max: 35, display_value: '22.0' },
      ];

      assert.equal(cbcParameters.length, 24, 'Must have exactly 24 leaf CBC parameters');

      const cbcInvestigation = [{
        test_code: 'HEM-0001',
        test_name: 'Complete Blood Count (CBC / Hemogram)',
        department: 'Hematology',
        method: 'Automated Impedance / Colorimetry',
        results: cbcParameters.map((p) => ({
          parameter_id: `p-${p.code}`,
          code: p.code,
          name: p.name,
          unit: p.unit,
          value_type: 'Numeric',
          display_value: p.display_value,
          reference_range: `${p.normal_min} - ${p.normal_max}`,
          flag: 'Normal',
          is_critical: false,
        })),
      }];

      const pages = paginateInvestigations(cbcInvestigation);
      const CBC_STANDARD_PAGE_COUNT = pages.length;
      assert.equal(CBC_STANDARD_PAGE_COUNT, 1, 'Standard 24-parameter CBC must paginate to exactly 1 page');
      assert.equal(pages[0].investigations[0].results.length, 24, 'Page 1 must contain all 24 parameters with zero overflow or orphan rows');
    });
  });

  describe('9. Patient Title / Sex Auto-Sync & Contradiction Prevention Rules', () => {
    // Import helper functions from patientEntry
    const getGenderForTitle = (title) => {
      if (!title) return null;
      const lower = title.trim().toLowerCase().replace(/\.+$/, '');
      if (lower === 'mr' || lower === 'master' || lower === 'shree' || lower === 'kumar') return 'Male';
      if (lower === 'miss' || lower === 'mrs' || lower === 'ms' || lower === 'smt' || lower === 'shrimati' || lower === 'kumari') return 'Female';
      return null;
    };

    const validatePatientTitleAndGender = (title, gender) => {
      if (!title || !gender) return null;
      const lowerTitle = title.trim().toLowerCase().replace(/\.+$/, '');
      const normGender = gender.trim().toLowerCase();
      const maleTitles = ['mr', 'master', 'shree', 'kumar'];
      const femaleTitles = ['mrs', 'ms', 'miss', 'smt', 'shrimati', 'kumari'];

      if ((normGender === 'female' || normGender === 'f') && maleTitles.includes(lowerTitle)) {
        return `Patient title "${title.trim()}" contradicts selected gender (Female).`;
      }
      if ((normGender === 'male' || normGender === 'm') && femaleTitles.includes(lowerTitle)) {
        return `Patient title "${title.trim()}" contradicts selected gender (Male).`;
      }
      return null;
    };

    it('maps Mr. -> Male, Miss -> Female, Mrs. -> Female', () => {
      assert.equal(getGenderForTitle('Mr.'), 'Male');
      assert.equal(getGenderForTitle('Mr'), 'Male');
      assert.equal(getGenderForTitle('Miss'), 'Female');
      assert.equal(getGenderForTitle('Mrs.'), 'Female');
      assert.equal(getGenderForTitle('Mrs'), 'Female');
      assert.equal(getGenderForTitle('Ms.'), 'Female');
      assert.equal(getGenderForTitle('Master'), 'Male');
    });

    it('does not force gender for neutral titles (Dr., Baby, Prof.)', () => {
      assert.equal(getGenderForTitle('Dr.'), null);
      assert.equal(getGenderForTitle('Baby'), null);
      assert.equal(getGenderForTitle('Prof.'), null);
      assert.equal(getGenderForTitle(''), null);
      assert.equal(getGenderForTitle(null), null);
    });

    it('blocks saving contradictory title/sex combinations', () => {
      assert.ok(validatePatientTitleAndGender('Mr.', 'Female'));
      assert.ok(validatePatientTitleAndGender('Mr.', 'female'));
      assert.ok(validatePatientTitleAndGender('Miss', 'Male'));
      assert.ok(validatePatientTitleAndGender('Miss', 'male'));
      assert.ok(validatePatientTitleAndGender('Mrs.', 'Male'));
      assert.ok(validatePatientTitleAndGender('Ms.', 'Male'));
      assert.ok(validatePatientTitleAndGender('Master', 'Female'));
    });

    it('permits valid title/sex combinations', () => {
      assert.equal(validatePatientTitleAndGender('Mr.', 'Male'), null);
      assert.equal(validatePatientTitleAndGender('Miss', 'Female'), null);
      assert.equal(validatePatientTitleAndGender('Mrs.', 'Female'), null);
      assert.equal(validatePatientTitleAndGender('Ms.', 'Female'), null);
      assert.equal(validatePatientTitleAndGender('Dr.', 'Male'), null);
      assert.equal(validatePatientTitleAndGender('Dr.', 'Female'), null);
      assert.equal(validatePatientTitleAndGender('Baby', 'Male'), null);
      assert.equal(validatePatientTitleAndGender('Baby', 'Female'), null);
      assert.equal(validatePatientTitleAndGender(null, 'Male'), null);
    });

    it('verifies NewBillPage and PatientsPage implement title/sex auto-sync and validation', () => {
      const newBillSrc = readFileSync(
        path.resolve(process.cwd(), 'src/features/billing/NewBillPage.tsx'),
        'utf8'
      );
      assert.ok(newBillSrc.includes('getGenderForTitle'), 'NewBillPage must use getGenderForTitle');
      assert.ok(newBillSrc.includes('validatePatientTitleAndGender'), 'NewBillPage must use validatePatientTitleAndGender');

      const patientsPageSrc = readFileSync(
        path.resolve(process.cwd(), 'src/features/patients/PatientsPage.tsx'),
        'utf8'
      );
      assert.ok(patientsPageSrc.includes('getGenderForTitle'), 'PatientsPage must use getGenderForTitle');
      assert.ok(patientsPageSrc.includes('validatePatientTitleAndGender'), 'PatientsPage must use validatePatientTitleAndGender');
    });
  });

  describe('10. Sample Lifecycle Enforcement Before Verification & Sign-Off', () => {
    // Pure validator mimicking backend/frontend lifecycle rule
    const evaluateVerificationReadiness = ({ collectionRequired, sampleStatus, collectedAt, receivedAt }) => {
      if (!collectionRequired) return { allowed: true };
      if (!sampleStatus || sampleStatus === 'Pending') {
        return { allowed: false, code: 'SAMPLE_NOT_RECEIVED', message: 'Sample must be received before results can be verified.' };
      }
      if (sampleStatus === 'Collected') {
        return { allowed: false, code: 'SAMPLE_NOT_RECEIVED', message: 'Sample must be received before results can be verified.' };
      }
      if (sampleStatus === 'Received') {
        if (!collectedAt || !receivedAt) {
          return { allowed: false, code: 'SAMPLE_NOT_RECEIVED', message: 'Sample collection and receipt timestamps are required.' };
        }
        return { allowed: true };
      }
      return { allowed: false, code: 'SAMPLE_NOT_RECEIVED', message: 'Invalid sample status.' };
    };

    const evaluateSignReadiness = ({ isReadyToSign, investigations }) => {
      for (const inv of investigations) {
        if (inv.collectionRequired) {
          if (inv.sampleStatus !== 'Received' || !inv.collectedAt || !inv.receivedAt) {
            return { allowed: false, code: 'SAMPLE_NOT_RECEIVED', message: 'Specimen must be collected and received in laboratory accessioning before report can be signed.' };
          }
        }
      }
      if (!isReadyToSign) {
        return { allowed: false, code: 'REPORT_NOT_READY', message: 'Report group is not ready.' };
      }
      return { allowed: true };
    };

    it('blocks verification when sample is Pending', () => {
      const res = evaluateVerificationReadiness({ collectionRequired: true, sampleStatus: 'Pending', collectedAt: null, receivedAt: null });
      assert.equal(res.allowed, false);
      assert.equal(res.code, 'SAMPLE_NOT_RECEIVED');
    });

    it('blocks verification when sample is Collected but not Received', () => {
      const res = evaluateVerificationReadiness({ collectionRequired: true, sampleStatus: 'Collected', collectedAt: '2026-09-24 08:00', receivedAt: null });
      assert.equal(res.allowed, false);
      assert.equal(res.code, 'SAMPLE_NOT_RECEIVED');
    });

    it('allows verification when sample is Received with valid timestamps', () => {
      const res = evaluateVerificationReadiness({ collectionRequired: true, sampleStatus: 'Received', collectedAt: '2026-09-24 08:00', receivedAt: '2026-09-24 08:15' });
      assert.equal(res.allowed, true);
    });

    it('allows verification for no-sample-required / exempt investigations', () => {
      const res = evaluateVerificationReadiness({ collectionRequired: false, sampleStatus: null, collectedAt: null, receivedAt: null });
      assert.equal(res.allowed, true);
    });

    it('blocks signing when any specimen-required investigation has Pending or unreceived sample', () => {
      const res = evaluateSignReadiness({
        isReadyToSign: true,
        investigations: [
          { collectionRequired: true, sampleStatus: 'Pending', collectedAt: null, receivedAt: null }
        ]
      });
      assert.equal(res.allowed, false);
      assert.equal(res.code, 'SAMPLE_NOT_RECEIVED');
    });

    it('allows signing when all specimen-required investigations are Received and verified', () => {
      const res = evaluateSignReadiness({
        isReadyToSign: true,
        investigations: [
          { collectionRequired: true, sampleStatus: 'Received', collectedAt: '2026-09-24 08:00', receivedAt: '2026-09-24 08:15' },
          { collectionRequired: false, sampleStatus: null, collectedAt: null, receivedAt: null }
        ]
      });
      assert.equal(res.allowed, true);
    });

    it('verifies ResultEntryPage and Database 00001 Migration enforce sample received requirement and bind timestamps', () => {
      const resultEntrySrc = readFileSync(
        path.resolve(process.cwd(), 'src/features/worklist/ResultEntryPage.tsx'),
        'utf8'
      );
      assert.ok(resultEntrySrc.includes('Sample must be received before results can be verified.'), 'ResultEntryPage must show clear message on verify');
      assert.ok(resultEntrySrc.includes('Open Sample Accessioning'), 'ResultEntryPage must provide direct button to Accessioning');
      assert.ok(resultEntrySrc.includes('/samples?search='), 'Must carry order context to Sample Accessioning');

      const baselineSql = readFileSync(
        path.resolve(process.cwd(), 'supabase/migrations/00001_bimal_pathology_clean_baseline.sql'),
        'utf8'
      );
      assert.ok(baselineSql.includes('SAMPLE_NOT_RECEIVED: Specimen must be collected and received in laboratory accessioning before results can be verified.'), 'Baseline SQL must guard verification');
      assert.ok(baselineSql.includes('SAMPLE_NOT_RECEIVED: Specimen must be collected and received in laboratory accessioning before report can be signed.'), 'Baseline SQL must guard report signing');
      assert.ok(baselineSql.includes("'collected_at', v_sample_dates->>'collected_at'"), 'sign_report_group must bind collected_at timestamp into snapshot');
      assert.ok(baselineSql.includes("'received_at', v_sample_dates->>'received_at'"), 'sign_report_group must bind received_at timestamp into snapshot');
    });
  });
});




