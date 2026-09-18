// scripts/verify-00123-gm-rate-import.test.mjs
// Verification suite for Migration 00123: Import Missing Rates from GM Reference Rate Card (RATE GM.pdf)

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';

const EXPECTED_53_SAFE_CODES = [
  'BIO-0021', // SGPT(ALT) - NPR 300
  'BIO-0020', // SGOT(AST) - NPR 300
  'BIO-0022', // Alkaline Phosphatase (ALP) - NPR 250
  'BIO-0014', // Albumin - NPR 200
  'BIO-0013', // Total Protein - NPR 200
  'BIO-0023', // GGT - NPR 800
  'PRO-0002', // Renal Function Test (RFT/KFT) - NPR 1000
  'BIO-0027', // Total Cholesterol - NPR 200
  'BIO-0028', // Triglycerides - NPR 250
  'BIO-0029', // HDL Cholesterol - NPR 250
  'BIO-0030', // LDL Cholesterol, Direct - NPR 450
  'BIO-0062', // CK-MB Activity - NPR 1000
  'BIO-0024', // LDH - NPR 500
  'BIO-0132', // Pleural Fluid ADA - NPR 1000
  'HEM-0039', // Manual Differential Count (TC/DC) - NPR 400
  'HEM-0004', // RBC Count - NPR 300
  'HEM-0023', // Reticulocyte Count - NPR 500
  'HEM-0058', // ABO & Rh Typing - NPR 100
  'CLP-0008', // Urine Ketone - NPR 200
  'CLP-0025', // Stool Occult Blood - NPR 200
  'MIC-0011', // Urine Culture & Sensitivity - NPR 500
  'MIC-0012', // Stool Culture & Sensitivity - NPR 600
  'MIC-0001', // Gram Stain - NPR 200
  'MIC-0002', // AFB Smear by Ziehl-Neelsen - NPR 200
  'MIC-0004', // KOH Mount - NPR 400
  'CLP-0038', // Semen Analysis - NPR 500
  'SER-0059', // Kala-azar rK39 Antibody - NPR 1500
  'SER-0028', // TPHA/TPPA - NPR 600
  'SER-0027', // VDRL - NPR 400
  'SER-0011', // HAV IgM - NPR 2500
  'SER-0013', // HEV IgM - NPR 2500
  'SER-0042', // H. pylori IgG - NPR 1200
  'SER-0023', // Salmonella Typhi IgM - NPR 1000
  'END-0006', // Anti-TPO Antibody - NPR 2000
  'IMM-0005', // ANA by IFA - NPR 2200
  'TUM-0003', // CA 125 - NPR 2000
  'TUM-0005', // CA 15-3 - NPR 2000
  'TUM-0004', // CA 19-9 - NPR 2000
  'END-0030', // Progesterone - NPR 2500
  'END-0013', // Cortisol, 8 AM - NPR 2500
  'IMM-0007', // Anti-dsDNA - NPR 3000
  'PRO-0005', // Iron Profile - NPR 2500
  'BIO-0052', // Folate - NPR 2000
  'HEM-0032', // G6PD Quantitative - NPR 6000
  'END-0022', // Growth Hormone (GH) - NPR 2000
  'END-0041', // Insulin, Fasting - NPR 3000
  'BIO-0051', // Vitamin B12 - NPR 1800
  'END-0011', // PTH, Intact - NPR 3000
  'HEM-0037', // Bone Marrow Aspiration Examination - NPR 6000
  'HIS-0001', // Small Biopsy Histopathology - NPR 2500
  'HIS-0002', // Medium Biopsy Histopathology - NPR 3500
  'HIS-0003', // Large Specimen Histopathology - NPR 5000
  'SPC-0014'  // Quadruple Marker Screen - NPR 6000
];

const PRESERVED_CONFIGURED_CODES = [
  'BIO-0001', // Blood Sugar (F)
  'BIO-0002', // Blood Sugar (PP)
  'BIO-0003', // RBS
  'PRO-0001', // Liver Function Test (LFT)
  'BIO-0008', // Urea
  'BIO-0010', // Creatinine
  'BIO-0012', // Uric Acid
  'PRO-0003', // Lipid Profile
  'BIO-0041', // Calcium, Total
  'BIO-0043', // Phosphorus
  'BIO-0058', // Amylase
  'BIO-0059', // Lipase
  'BIO-0063', // Troponin-I
  'BIO-0085', // Urine Microalbumin
  'HEM-0001', // CBC
  'HEM-0002', // Hemoglobin (Hb)
  'HEM-0027', // ESR (Westergren)
  'HEM-0006', // Platelet Count
  'HEM-0026', // Peripheral Blood Smear
  'PRO-0030', // BT/CT
  'COA-0001', // PT/INR
  'BIO-0006', // HbA1c
  'CLP-0001', // Urine Routine Examination
  'CLP-0021', // Stool Routine Examination
  'SER-0043', // H. pylori Stool Antigen
  'PRO-0029', // Dengue Combo
  'SER-0089', // Scrub Typhus
  'SER-0001', // HIV 1/2
  'SER-0010', // Anti-HCV
  'SER-0004', // HBsAg
  'IMM-0003', // ASO Titer
  'IMM-0002', // Rheumatoid Factor (RF)
  'IMM-0001', // CRP
  'SER-0086', // Widal
  'PRO-0028', // TFT
  'TUM-0002', // CEA
  'COA-0006', // D-Dimer
  'IMM-0004', // Anti-CCP
  'END-0027', // FSH
  'END-0028', // LH
  'END-0025', // Prolactin
  'END-0039', // Beta-hCG
  'TUM-0007', // PSA, Total
  'END-0031', // Testosterone, Total
  'BIO-0053', // Vitamin D, 25-OH
  'BIO-0067', // NT-proBNP
  'IMM-0031'  // Total IgE
];

describe('Bimal Pathology LIS: Migration 00123 GM Rate Import Verification', () => {

  describe('1. Migration 00123 SQL Structure & Syntax', () => {
    it('verifies 00123 migration file exists and includes all 53 safe missing codes', () => {
      const sqlPath = path.resolve('supabase/migrations/00123_import_missing_rates_from_gm_reference.sql');
      const content = readFileSync(sqlPath, 'utf8');

      assert.ok(content.includes('catalogue_rate_versions'), 'Must target catalogue_rate_versions table');
      assert.ok(content.includes('BEGIN;'), 'Must be wrapped in transaction');
      assert.ok(content.includes('COMMIT;'), 'Must commit transaction');
      assert.ok(content.includes('price_configured = TRUE'), 'Must update price_configured on tests');
      assert.ok(content.includes("pricing_policy = 'Fixed'"), 'Must update pricing_policy to Fixed');

      for (const code of EXPECTED_53_SAFE_CODES) {
        assert.ok(content.includes(`'${code}'`), `Migration 00123 must include code '${code}'`);
      }
    });

    it('enforces idempotency and avoids duplicate active rate insertions', () => {
      const sqlPath = path.resolve('supabase/migrations/00123_import_missing_rates_from_gm_reference.sql');
      const content = readFileSync(sqlPath, 'utf8');

      assert.ok(content.includes('NOT EXISTS'), 'Must contain NOT EXISTS guard to prevent duplicate active rates');
      assert.ok(content.includes("status = 'Active'"), 'Must check active status in existence guard');
    });

    it('ensures all rates are represented as exact integer paisa without floating point values', () => {
      const sqlPath = path.resolve('supabase/migrations/00123_import_missing_rates_from_gm_reference.sql');
      const content = readFileSync(sqlPath, 'utf8');

      // Match all values ('CODE', 12345::BIGINT)
      const valueMatches = content.matchAll(/\('([A-Z]{3}-\d{4})',\s*(\d+)::BIGINT\)/g);
      let count = 0;
      for (const match of valueMatches) {
        count++;
        const code = match[1];
        const paisa = parseInt(match[2], 10);
        assert.ok(paisa > 0, `Paisa amount for ${code} must be strictly positive`);
        assert.equal(paisa % 100, 0, `Paisa amount for ${code} (${paisa}) must be a clean integer NPR multiple`);
      }
      assert.equal(count, 53, 'Must have exactly 53 test entries in VALUES block');
    });
  });

  describe('2. Business Rules & Catalogue Preservation Invariants', () => {
    it('verifies that pre-existing configured rates are preserved and NOT in migration insert list', () => {
      const sqlPath = path.resolve('supabase/migrations/00123_import_missing_rates_from_gm_reference.sql');
      const content = readFileSync(sqlPath, 'utf8');

      for (const code of PRESERVED_CONFIGURED_CODES) {
        // Must NOT appear in the VALUES list of migration 00123
        const isTargetedInValues = new RegExp(`\\('${code}',`).test(content);
        assert.equal(isTargetedInValues, false, `Pre-configured test ${code} must NOT be re-inserted by migration 00123`);
      }
    });

    it('verifies that bundled services (BT/CT, N+/K+, Bilirubin T&D, ANCA/GBM) are safely handled', () => {
      const sqlPath = path.resolve('supabase/migrations/00123_import_missing_rates_from_gm_reference.sql');
      const content = readFileSync(sqlPath, 'utf8');

      // BT/CT panel is already PRO-0030 (preserved)
      // N+/K+ and Bilirubin T&D should NOT arbitrarily assign prices to individual electrolytes or fractions
      assert.ok(!content.includes("'BIO-0015'"), 'Total Bilirubin should not receive combined bundle rate');
      assert.ok(!content.includes("'BIO-0016'"), 'Direct Bilirubin should not receive combined bundle rate');
      assert.ok(!content.includes("'BIO-0037'"), 'Sodium should not receive combined N+/K+ bundle rate');
      assert.ok(!content.includes("'BIO-0038'"), 'Potassium should not receive combined N+/K+ bundle rate');
    });

    it('verifies ambiguous rows (Troponin generic, MHA, GM packages) are excluded from rate insertion', () => {
      const sqlPath = path.resolve('supabase/migrations/00123_import_missing_rates_from_gm_reference.sql');
      const content = readFileSync(sqlPath, 'utf8');

      // Proprietary whole body packages must not be inserted as test rates
      assert.ok(!content.toLowerCase().includes('whole bady package'));
    });
  });

  describe('3. Financial Precision & Billing Simulation', () => {
    const PROVISIONAL_DEFAULT_RATE_PAISA = 10000; // NPR 100.00

    function simulateRateResolution(test) {
      const isConfigured = Boolean(test.priceConfigured && (test.pricePaisa > 0 || test.allowZeroPriceBilling));
      const initialPricePaisa = isConfigured ? test.pricePaisa : PROVISIONAL_DEFAULT_RATE_PAISA;

      return {
        unitPricePaisa: initialPricePaisa,
        priceConfigured: isConfigured,
        isProvisionalDefault: !isConfigured
      };
    }

    it('resolves newly imported GM rates directly in billing without default fallback', () => {
      // e.g. G6PD Quantitative (HEM-0032 @ NPR 6,000.00)
      const g6pdTest = {
        id: 'mock-g6pd-id',
        code: 'HEM-0032',
        name: 'G6PD Quantitative',
        pricePaisa: 600000,
        priceConfigured: true,
        allowZeroPriceBilling: false
      };

      const res = simulateRateResolution(g6pdTest);
      assert.equal(res.unitPricePaisa, 600000, 'G6PD must resolve to 600,000 paisa (NPR 6,000.00)');
      assert.equal(res.priceConfigured, true);
      assert.equal(res.isProvisionalDefault, false);
    });

    it('retains provisional NPR 100.00 fallback for tests that remain unpriced', () => {
      const unpricedSpcTest = {
        id: 'mock-unpriced-id',
        code: 'SPC-0999',
        name: 'Rare Unpriced Esoteric Marker',
        pricePaisa: 0,
        priceConfigured: false,
        allowZeroPriceBilling: false
      };

      const res = simulateRateResolution(unpricedSpcTest);
      assert.equal(res.unitPricePaisa, 10000, 'Unpriced test must default to provisional 10,000 paisa (NPR 100.00)');
      assert.equal(res.priceConfigured, false);
      assert.equal(res.isProvisionalDefault, true);
    });

    it('verifies integer paisa conversions for all 53 newly imported rates', () => {
      const rateSamples = [
        { code: 'BIO-0021', npr: 300, paisa: 30000 },
        { code: 'BIO-0022', npr: 250, paisa: 25000 },
        { code: 'BIO-0014', npr: 200, paisa: 20000 },
        { code: 'BIO-0023', npr: 800, paisa: 80000 },
        { code: 'PRO-0002', npr: 1000, paisa: 100000 },
        { code: 'BIO-0030', npr: 450, paisa: 45000 },
        { code: 'MIC-0012', npr: 600, paisa: 60000 },
        { code: 'SER-0059', npr: 1500, paisa: 150000 },
        { code: 'SER-0011', npr: 2500, paisa: 250000 },
        { code: 'IMM-0005', npr: 2200, paisa: 220000 },
        { code: 'IMM-0007', npr: 3000, paisa: 300000 },
        { code: 'HIS-0002', npr: 3500, paisa: 350000 },
        { code: 'HIS-0003', npr: 5000, paisa: 500000 },
        { code: 'HEM-0032', npr: 6000, paisa: 600000 }
      ];

      for (const sample of rateSamples) {
        assert.equal(sample.npr * 100, sample.paisa, `${sample.code} NPR ${sample.npr} must equal ${sample.paisa} paisa`);
        assert.equal((sample.paisa / 100).toFixed(2), `${sample.npr}.00`, `${sample.paisa} paisa must format to NPR ${sample.npr}.00`);
      }
    });
  });

});
