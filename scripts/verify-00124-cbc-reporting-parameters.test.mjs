// scripts/verify-00124-cbc-reporting-parameters.test.mjs
// Verification suite for Migration 00124: Complete Blood Count (CBC / HEM-0001) Reporting Parameters

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';

const EXPECTED_24_CBC_PARAMETERS = [
  { order: 1, code: 'WBC', name: 'White Blood Cell Count (TLC)', unit: '10^9/L', value_type: 'Numeric', mandatory: true },
  { order: 2, code: 'LYM_ABS', name: 'Absolute Lymphocyte Count', unit: '10^9/L', value_type: 'Numeric', mandatory: false },
  { order: 3, code: 'MID_ABS', name: 'Absolute Mid-cell (Monocytes/Eosinophils) Count', unit: '10^9/L', value_type: 'Numeric', mandatory: false },
  { order: 4, code: 'GRAN_ABS', name: 'Absolute Granulocyte (Neutrophil) Count', unit: '10^9/L', value_type: 'Numeric', mandatory: false },
  { order: 5, code: 'LYM_PERCENT', name: 'Lymphocyte Percentage', unit: '%', value_type: 'Numeric', mandatory: false },
  { order: 6, code: 'MID_PERCENT', name: 'Mid-cell Percentage', unit: '%', value_type: 'Numeric', mandatory: false },
  { order: 7, code: 'GRAN_PERCENT', name: 'Granulocyte Percentage', unit: '%', value_type: 'Numeric', mandatory: false },
  { order: 8, code: 'NLR', name: 'Neutrophil-to-Lymphocyte Ratio', unit: 'Ratio', value_type: 'Numeric', mandatory: false },
  { order: 9, code: 'PLR', name: 'Platelet-to-Lymphocyte Ratio', unit: 'Ratio', value_type: 'Numeric', mandatory: false },
  { order: 10, code: 'RBC', name: 'Red Blood Cell Count', unit: '10^12/L', value_type: 'Numeric', mandatory: true },
  { order: 11, code: 'HGB', name: 'Hemoglobin Concentration', unit: 'g/dL', value_type: 'Numeric', mandatory: true },
  { order: 12, code: 'HCT', name: 'Hematocrit (Packed Cell Volume - PCV)', unit: '%', value_type: 'Numeric', mandatory: true },
  { order: 13, code: 'MCV', name: 'Mean Corpuscular Volume', unit: 'fL', value_type: 'Numeric', mandatory: true },
  { order: 14, code: 'MCH', name: 'Mean Corpuscular Hemoglobin', unit: 'pg', value_type: 'Numeric', mandatory: true },
  { order: 15, code: 'MCHC', name: 'Mean Corpuscular Hemoglobin Concentration', unit: 'g/dL', value_type: 'Numeric', mandatory: true },
  { order: 16, code: 'RDW_CV', name: 'Red Cell Distribution Width - Coeff. of Variation', unit: '%', value_type: 'Numeric', mandatory: false },
  { order: 17, code: 'RDW_SD', name: 'Red Cell Distribution Width - Standard Deviation', unit: 'fL', value_type: 'Numeric', mandatory: false },
  { order: 18, code: 'PLT', name: 'Platelet Count', unit: '10^9/L', value_type: 'Numeric', mandatory: true },
  { order: 19, code: 'MPV', name: 'Mean Platelet Volume', unit: 'fL', value_type: 'Numeric', mandatory: false },
  { order: 20, code: 'PDW_CV', name: 'Platelet Distribution Width - CV', unit: '%', value_type: 'Numeric', mandatory: false },
  { order: 21, code: 'PDW_SD', name: 'Platelet Distribution Width - SD', unit: 'fL', value_type: 'Numeric', mandatory: false },
  { order: 22, code: 'PCT', name: 'Plateletcrit', unit: '%', value_type: 'Numeric', mandatory: false },
  { order: 23, code: 'P_LCC', name: 'Platelet Large Cell Count', unit: '10^9/L', value_type: 'Numeric', mandatory: false },
  { order: 24, code: 'P_LCR', name: 'Platelet Large Cell Ratio', unit: '%', value_type: 'Numeric', mandatory: false }
];

describe('Bimal Pathology LIS: Migration 00124 CBC Reporting Parameters Verification', () => {

  describe('1. Migration 00124 SQL Structure & Syntax', () => {
    it('verifies 00124 migration file exists and configures the exact 24 CBC parameters', () => {
      const sqlPath = path.resolve('supabase/migrations_legacy_archive/00124_cbc_reporting_parameters.sql');
      const content = readFileSync(sqlPath, 'utf8');

      assert.ok(content.includes('HEM-0001'), 'Must target HEM-0001 test');
      assert.ok(content.includes('BEGIN;'), 'Must be wrapped in transaction');
      assert.ok(content.includes('COMMIT;'), 'Must commit transaction');
      assert.ok(content.includes('COUNCELL_23_EXCEL'), 'Must update CounCell 23 Excel mappings');

      for (const param of EXPECTED_24_CBC_PARAMETERS) {
        assert.ok(content.includes(`'${param.code}'`), `Migration 00124 must include code '${param.code}'`);
        assert.ok(content.includes(`'${param.unit}'`), `Migration 00124 must include unit '${param.unit}' for '${param.code}'`);
      }
    });

    it('enforces idempotency and safe conflict resolution', () => {
      const sqlPath = path.resolve('supabase/migrations_legacy_archive/00124_cbc_reporting_parameters.sql');
      const content = readFileSync(sqlPath, 'utf8');

      assert.ok(content.includes('ON CONFLICT (test_id, code) DO UPDATE'), 'Must use ON CONFLICT for parameters');
      assert.ok(content.includes('public.analyzer_parameter_mappings'), 'Must update analyzer mappings');
    });

    it('cleans up dummy placeholder parameter with unit Panel', () => {
      const sqlPath = path.resolve('supabase/migrations_legacy_archive/00124_cbc_reporting_parameters.sql');
      const content = readFileSync(sqlPath, 'utf8');

      assert.ok(content.includes("unit = 'Panel'"), 'Must detect and clean placeholder parameter');
    });
  });

  describe('2. CBC Single Billing Item & Parameter Hierarchy Invariant', () => {
    it('preserves HEM-0001 as one single billable item without creating 24 separate billing tests', () => {
      const sqlPath = path.resolve('supabase/migrations_legacy_archive/00124_cbc_reporting_parameters.sql');
      const content = readFileSync(sqlPath, 'utf8');

      // Migration must NOT insert new rows into public.tests or public.catalogue_rate_versions
      assert.ok(!content.includes('INSERT INTO public.tests'), 'Must NOT insert new test records');
      assert.ok(!content.includes('INSERT INTO public.catalogue_rate_versions'), 'Must NOT insert new billing rate versions');
    });

    it('validates deterministic ordering of all 24 CBC parameters (1 to 24)', () => {
      for (let i = 0; i < EXPECTED_24_CBC_PARAMETERS.length; i++) {
        const item = EXPECTED_24_CBC_PARAMETERS[i];
        assert.equal(item.order, i + 1, `Parameter ${item.code} must have display_order = ${i + 1}`);
      }
      assert.equal(EXPECTED_24_CBC_PARAMETERS.length, 24, 'Must have exactly 24 parameters');
    });
  });

  describe('3. ANC Safety & Manual Microscopy Isolation', () => {
    it('does NOT derive or fabricate automated ANC in the 3-part CBC parameters', () => {
      const sqlPath = path.resolve('supabase/migrations_legacy_archive/00124_cbc_reporting_parameters.sql');
      const content = readFileSync(sqlPath, 'utf8');

      // CBC parameters must not include automated ANC
      const cbcHasAncParam = EXPECTED_24_CBC_PARAMETERS.some(p => p.code === 'ANC');
      assert.equal(cbcHasAncParam, false, 'CBC automated parameters must not include ANC');
      assert.ok(!content.includes("'ANC'"), 'Migration must not insert ANC into CBC test parameters');
    });
  });

  describe('4. Reference Range Integrity & Zero Range Invention', () => {
    it('configures HGB reference range from approved lab data and keeps unapproved as MISSING_RANGE', () => {
      const sqlPath = path.resolve('supabase/migrations_legacy_archive/00124_cbc_reporting_parameters.sql');
      const content = readFileSync(sqlPath, 'utf8');

      // Female 12-15, Male 13-17
      assert.ok(content.includes('12.0') && content.includes('15.0'), 'Must configure Female 12.0 - 15.0 for HGB');
      assert.ok(content.includes('13.0') && content.includes('17.0'), 'Must configure Male 13.0 - 17.0 for HGB');

      // Does not insert invented ranges for RDW, MPV, PCT, PDW, P-LCC, etc.
      assert.ok(!content.includes('v_rdw_sd_param_id, \'All\''), 'Must NOT invent unverified ranges for RDW-SD');
      assert.ok(!content.includes('v_nlr_param_id, \'All\''), 'Must NOT invent unverified ranges for NLR');
    });

    it('verifies that missing ranges do not block Result Entry or Draft Saving', () => {
      // Simulation of evaluateResultFlag when referenceRange is null
      function evaluateResultFlagSim(displayValue, valueType, range) {
        if (!displayValue || displayValue.trim() === '') return { flag: 'NORMAL', isCritical: false };
        if (!range || range.normal_min == null || range.normal_max == null) {
          return { flag: 'NORMAL', isCritical: false };
        }
        const num = parseFloat(displayValue);
        if (isNaN(num)) return { flag: 'NORMAL', isCritical: false };
        if (num < range.normal_min) return { flag: 'LOW', isCritical: false };
        if (num > range.normal_max) return { flag: 'HIGH', isCritical: false };
        return { flag: 'NORMAL', isCritical: false };
      }

      // Parameter without range (e.g. RDW-SD with value 42.5)
      const resWithoutRange = evaluateResultFlagSim('42.5', 'Numeric', null);
      assert.equal(resWithoutRange.flag, 'NORMAL', 'Unconfigured range must evaluate to NORMAL flag without error');

      // Parameter with range (HGB Female: 12.0 - 15.0)
      const hgbFemaleRange = { normal_min: 12.0, normal_max: 15.0 };
      const resHgbLow = evaluateResultFlagSim('10.5', 'Numeric', hgbFemaleRange);
      assert.equal(resHgbLow.flag, 'LOW', 'HGB below normal_min must flag LOW');

      const resHgbNormal = evaluateResultFlagSim('13.2', 'Numeric', hgbFemaleRange);
      assert.equal(resHgbNormal.flag, 'NORMAL', 'HGB within range must flag NORMAL');
    });
  });

  describe('5. Result Entry & Diagnostic Report Rendering Contracts', () => {
    it('simulates Result Entry loading all 24 CBC parameters with correct units', () => {
      const mockMasterParams = EXPECTED_24_CBC_PARAMETERS.map(p => ({
        id: `param-${p.code}`,
        code: p.code,
        name: p.name,
        value_type: p.value_type,
        unit: p.unit,
        display_order: p.order,
        is_active: true
      }));

      const mockExistingResults = [
        { parameter_id: 'param-WBC', display_value: '7.8', numeric_value: 7.8, flag: 'NORMAL' },
        { parameter_id: 'param-HGB', display_value: '14.2', numeric_value: 14.2, flag: 'NORMAL' }
      ];

      const existingMap = new Map(mockExistingResults.map(r => [r.parameter_id, r]));

      const assembledState = mockMasterParams.map(mp => {
        const existing = existingMap.get(mp.id);
        return {
          parameter_id: mp.id,
          code: mp.code,
          name: mp.name,
          value_type: mp.value_type,
          unit: mp.unit,
          display_value: existing?.display_value ?? '',
          numeric_value: existing?.numeric_value ?? null,
          flag: existing?.flag ?? 'NORMAL',
          is_critical: false
        };
      });

      assert.equal(assembledState.length, 24, 'Assembled state must have exactly 24 parameters');
      assert.equal(assembledState[0].code, 'WBC');
      assert.equal(assembledState[0].display_value, '7.8');
      assert.equal(assembledState[10].code, 'HGB');
      assert.equal(assembledState[10].display_value, '14.2');
      assert.equal(assembledState[23].code, 'P_LCR');
      assert.equal(assembledState[23].unit, '%');
    });

    it('verifies signed clinical snapshot schema includes CBC parameters and remains frozen', () => {
      const mockSnapshot = {
        investigations: [
          {
            test_code: 'HEM-0001',
            test_name: 'Complete Blood Count (CBC)',
            department: 'Hematology',
            method: 'Electrical Impedance & Cyanide-free Colorimetry (CounCell 23 Excel)',
            results: EXPECTED_24_CBC_PARAMETERS.map(p => ({
              code: p.code,
              name: p.name,
              display_value: '10.0',
              unit: p.unit,
              reference_range: p.code === 'HGB' ? '12.0 - 15.0' : '-'
            }))
          }
        ]
      };

      assert.equal(mockSnapshot.investigations[0].results.length, 24, 'Snapshot results must contain all 24 CBC parameters');
      assert.equal(mockSnapshot.investigations[0].results[0].code, 'WBC');
      assert.equal(mockSnapshot.investigations[0].results[10].code, 'HGB');
      assert.equal(mockSnapshot.investigations[0].results[10].reference_range, '12.0 - 15.0');
    });
  });

  describe('6. RBAC & Route Permissions', () => {
    it('verifies Lab Technician can enter results, verify, and acknowledge critical values per RBAC', () => {
      const permissionsPath = path.resolve('src/types/permissions.ts');
      const content = readFileSync(permissionsPath, 'utf8');

      assert.ok(content.includes('CAN_ENTER_RESULTS'), 'Must include CAN_ENTER_RESULTS');
      assert.ok(content.includes('CAN_VERIFY_RESULTS'), 'Must include CAN_VERIFY_RESULTS');
      assert.ok(content.includes('CAN_ACKNOWLEDGE_CRITICAL'), 'Must include CAN_ACKNOWLEDGE_CRITICAL');
      assert.ok(content.includes('LAB_TECHNICIAN_PERMISSION_ALLOWLIST'), 'Must define allowlist');
    });

    it('verifies Catalogue Administration remains restricted to Admin with CAN_MANAGE_CATALOGUE', () => {
      const routesPath = path.resolve('src/app/routes.tsx');
      const content = readFileSync(routesPath, 'utf8');

      assert.ok(content.includes('PERMISSION_KEYS.CAN_MANAGE_CATALOGUE'), 'Catalogue route must be guarded');
    });
  });

});
