import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

import {
  calculateINR,
  evaluateClinicalFormula,
  recalculateInvestigationParameters,
} from '../src/lib/clinicalMath.ts';

describe('PT / INR / BT / CT Clinical Configuration & Billing Regression Suite', () => {
  describe('1. INR Deterministic Calculation Engine', () => {
    it('calculates INR accurately with PT=24, MNPT=12, ISI=1.1 -> ~2.14', () => {
      const res = calculateINR(24, 12, 1.1);
      assert.strictEqual(res.isValid, true);
      assert.ok(res.inr !== null);
      // Math.pow(24/12, 1.1) = Math.pow(2.0, 1.1) = 2.1435469...
      assert.strictEqual(res.displayValue, '2.14');
      assert.ok(Math.abs(res.inr - 2.1435469) < 0.0001);
    });

    it('returns missing dependency without inventing defaults when MNPT is missing', () => {
      const resNull = calculateINR(24, null, 1.1);
      assert.strictEqual(resNull.isValid, false);
      assert.strictEqual(resNull.inr, null);
      assert.strictEqual(resNull.displayValue, '—');
      assert.ok(resNull.warning?.includes('MNPT'));

      const resUndef = calculateINR(24, undefined, 1.1);
      assert.strictEqual(resUndef.isValid, false);
      assert.strictEqual(resUndef.inr, null);
      assert.strictEqual(resUndef.displayValue, '—');
    });

    it('returns missing dependency without inventing defaults when ISI is missing', () => {
      const resNull = calculateINR(24, 12, null);
      assert.strictEqual(resNull.isValid, false);
      assert.strictEqual(resNull.inr, null);
      assert.strictEqual(resNull.displayValue, '—');
      assert.ok(resNull.warning?.includes('ISI'));

      const resUndef = calculateINR(24, 12, undefined);
      assert.strictEqual(resUndef.isValid, false);
      assert.strictEqual(resUndef.inr, null);
      assert.strictEqual(resUndef.displayValue, '—');
    });

    it('rejects zero or negative MNPT', () => {
      const resZero = calculateINR(24, 0, 1.1);
      assert.strictEqual(resZero.isValid, false);
      assert.strictEqual(resZero.inr, null);

      const resNeg = calculateINR(24, -12, 1.1);
      assert.strictEqual(resNeg.isValid, false);
      assert.strictEqual(resNeg.inr, null);
    });

    it('rejects zero or negative ISI', () => {
      const resZero = calculateINR(24, 12, 0);
      assert.strictEqual(resZero.isValid, false);
      assert.strictEqual(resZero.inr, null);

      const resNeg = calculateINR(24, 12, -1.1);
      assert.strictEqual(resNeg.isValid, false);
      assert.strictEqual(resNeg.inr, null);
    });

    it('evaluates INR formula expression (PT / MNPT) ^ ISI dynamically via formula engine', () => {
      const formula = '(PT / MNPT) ^ ISI';
      const calcResult = evaluateClinicalFormula(formula, { PT: 24, MNPT: 12, ISI: 1.1 }, 'INR');
      assert.strictEqual(calcResult.status, 'SUCCESS');
      assert.strictEqual(calcResult.displayValue, '2.14');
      assert.ok(calcResult.rawValue !== null);
      assert.ok(Math.abs(calcResult.rawValue - 2.1435469) < 0.0001);
    });

    it('recalculates investigation parameters with context variables (MNPT & ISI)', () => {
      const params = [
        {
          code: 'COA-0001',
          name: 'Prothrombin Time',
          value_type: 'Numeric',
          unit: 'sec',
          display_value: '24',
          numeric_value: 24,
        },
        {
          code: 'INR',
          name: 'International Normalized Ratio',
          value_type: 'Calculated',
          unit: '',
          formula: '(PT / MNPT) ^ ISI',
          display_value: '',
          numeric_value: null,
        },
      ];

      const recalculated = recalculateInvestigationParameters(params, undefined, { MNPT: 12, ISI: 1.1 });
      const inrParam = recalculated.find((p) => p.code === 'INR');
      assert.ok(inrParam);
      assert.strictEqual(inrParam.display_value, '2.14');
      assert.strictEqual(inrParam.calculation_status, 'SUCCESS');
    });

    it('does not calculate INR when context variables are missing', () => {
      const params = [
        {
          code: 'COA-0001',
          name: 'Prothrombin Time',
          value_type: 'Numeric',
          unit: 'sec',
          display_value: '24',
          numeric_value: 24,
        },
        {
          code: 'INR',
          name: 'International Normalized Ratio',
          value_type: 'Calculated',
          unit: '',
          formula: '(PT / MNPT) ^ ISI',
          display_value: '',
          numeric_value: null,
        },
      ];

      const recalculated = recalculateInvestigationParameters(params, undefined, undefined);
      const inrParam = recalculated.find((p) => p.code === 'INR');
      assert.ok(inrParam);
      assert.strictEqual(inrParam.display_value, '—');
      assert.strictEqual(inrParam.calculation_status, 'MISSING_DEPENDENCY');
      // Patient PT is still preserved
      const ptParam = recalculated.find((p) => p.code === 'COA-0001');
      assert.strictEqual(ptParam?.display_value, '24');
    });
  });

  describe('2. Database Migration 00119 Dry Run & Schema Verification', () => {
    it('executes migration 00119 dry-run successfully with rollback', () => {
      const migrationFile = path.resolve('supabase/migrations_legacy_archive/00119_pt_inr_bt_ct_clinical_configuration.sql');
      const migrationContent = readFileSync(migrationFile, 'utf8');

      const dryRunSql = `
      BEGIN;
      ${migrationContent.replace(/^BEGIN;/m, '-- BEGIN').replace(/^COMMIT;/m, '-- COMMIT')}
      
      SELECT json_build_object(
        'pt', (SELECT row_to_json(t) FROM (SELECT code, name, short_name, method, price_paisa FROM public.tests WHERE code = 'COA-0001') t),
        'bt', (SELECT row_to_json(t) FROM (SELECT code, name, short_name, method, price_paisa FROM public.tests WHERE code = 'COA-0007') t),
        'ct', (SELECT row_to_json(t) FROM (SELECT code, name, short_name, method, price_paisa FROM public.tests WHERE code = 'COA-0008') t),
        'combo', (SELECT row_to_json(t) FROM (SELECT code, name, short_name, method, price_paisa FROM public.tests WHERE code = 'PRO-0030') t),
        'combo_components', (SELECT json_agg(row_to_json(c)) FROM (
          SELECT pc.display_order, t.code, t.name
          FROM public.catalogue_panel_components pc
          JOIN public.tests t ON t.id = pc.component_test_id
          JOIN public.tests p ON p.id = pc.panel_id
          WHERE p.code = 'PRO-0030'
          ORDER BY pc.display_order
        ) c),
        'pt_ranges', (SELECT json_agg(row_to_json(r)) FROM (
          SELECT p.code, rr.normal_min, rr.normal_max, rr.reference_text
          FROM public.reference_ranges rr
          JOIN public.parameters p ON p.id = rr.parameter_id
          WHERE p.test_id = '2f8b4df3-40e4-4141-b003-9a124fdc75a8'
        ) r),
        'bt_ranges', (SELECT json_agg(row_to_json(r)) FROM (
          SELECT p.code, rr.normal_min, rr.normal_max, rr.reference_text
          FROM public.reference_ranges rr
          JOIN public.parameters p ON p.id = rr.parameter_id
          WHERE p.test_id = '3531fc7b-db20-4f22-85c2-4a2076763113'
        ) r),
        'ct_ranges', (SELECT json_agg(row_to_json(r)) FROM (
          SELECT p.code, rr.normal_min, rr.normal_max, rr.reference_text
          FROM public.reference_ranges rr
          JOIN public.parameters p ON p.id = rr.parameter_id
          WHERE p.test_id = '1e03e664-18f1-4893-b651-0f25642e83c1'
        ) r)
      ) AS res;
      
      ROLLBACK;
      `;

      const tmpFile = path.resolve('tmp_verify_test.sql');
      writeFileSync(tmpFile, dryRunSql, 'utf8');

      try {
        const raw = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
          encoding: 'utf8',
          shell: true,
          maxBuffer: 10 * 1024 * 1024,
        });

        const jsonStart = raw.indexOf('[');
        const jsonStartObj = raw.indexOf('{');
        const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
        const parsed = JSON.parse(raw.slice(start));
        const data = Array.isArray(parsed) ? parsed[0]?.res : parsed.rows?.[0]?.res;

        // Verify PT
        assert.strictEqual(data.pt.code, 'COA-0001');
        assert.strictEqual(data.pt.name, 'Prothrombin Time / INR');
        assert.strictEqual(data.pt.short_name, 'PT/INR');
        assert.strictEqual(data.pt.method, 'Manual Tilt Tube Method');
        assert.strictEqual(data.pt.price_paisa, 50000);

        // Verify BT
        assert.strictEqual(data.bt.code, 'COA-0007');
        assert.strictEqual(data.bt.name, 'Bleeding Time');
        assert.strictEqual(data.bt.short_name, 'BT');
        assert.strictEqual(data.bt.method, "Duke's Method");

        // Verify CT
        assert.strictEqual(data.ct.code, 'COA-0008');
        assert.strictEqual(data.ct.name, 'Clotting Time');
        assert.strictEqual(data.ct.short_name, 'CT');
        assert.strictEqual(data.ct.method, 'Capillary Tube Method');

        // Verify Combo PRO-0030
        assert.strictEqual(data.combo.code, 'PRO-0030');
        assert.strictEqual(data.combo.name, 'Bleeding Time & Clotting Time');
        assert.strictEqual(data.combo.short_name, 'BT & CT');
        assert.strictEqual(data.combo.price_paisa, 20000);

        // Verify Combo components
        assert.strictEqual(data.combo_components.length, 2);
        assert.strictEqual(data.combo_components[0].code, 'COA-0007');
        assert.strictEqual(data.combo_components[1].code, 'COA-0008');

        // Verify PT and INR reference ranges
        const ptRange = data.pt_ranges.find((r) => r.code === 'COA-0001');
        assert.strictEqual(ptRange.normal_min, 11);
        assert.strictEqual(ptRange.normal_max, 13.5);

        const inrRange = data.pt_ranges.find((r) => r.code === 'INR');
        assert.strictEqual(inrRange.normal_min, 0.8);
        assert.strictEqual(inrRange.normal_max, 1.2);

        // Verify BT reference range
        const btRange = data.bt_ranges.find((r) => r.code === 'COA-0007');
        assert.strictEqual(btRange.normal_min, 2);
        assert.strictEqual(btRange.normal_max, 7);

        // Verify CT reference range
        const ctRange = data.ct_ranges.find((r) => r.code === 'COA-0008');
        assert.strictEqual(ctRange.normal_min, 3);
        assert.strictEqual(ctRange.normal_max, 8);
      } finally {
        unlinkSync(tmpFile);
      }
    });
  });
});
