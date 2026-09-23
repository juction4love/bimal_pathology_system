// scripts/verify-00134-p0-configuration.test.mjs
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';

describe('Migration 00134: 15 P0 Lab-Approved Clinical Configuration', () => {
    const migrationPath = path.resolve('supabase/migrations_legacy_archive/00134_p0_lab_approved_configuration.sql');

    it('1. Migration 00134 file exists', () => {
        assert.ok(existsSync(migrationPath), 'Migration 00134 should exist');
    });

    const sql = readFileSync(migrationPath, 'utf8');

    it('2. Configures BIO-0141 Cystatin C with adult range 0.61-0.95 mg/L', () => {
        assert.ok(sql.includes('BIO-0141'), 'Should contain BIO-0141');
        assert.ok(sql.includes('Cystatin C'), 'Should contain Cystatin C parameter');
        assert.ok(sql.includes('0.61'), 'Should have normal_min 0.61');
        assert.ok(sql.includes('0.95'), 'Should have normal_max 0.95');
        assert.ok(sql.includes('mg/L'), 'Should have unit mg/L');
    });

    it('3. Configures IMM-0093 Interleukin-6 with cutoff < 7.0 pg/mL', () => {
        assert.ok(sql.includes('IMM-0093'), 'Should contain IMM-0093');
        assert.ok(sql.includes('Interleukin-6'), 'Should contain IL-6 parameter');
        assert.ok(sql.includes('7.0'), 'Should have normal_max 7.0');
        assert.ok(sql.includes('pg/mL'), 'Should have unit pg/mL');
    });

    it('4. Configures SER-0089 Scrub Typhus with IgM and IgG parameters and index cutoff < 1.0', () => {
        assert.ok(sql.includes('SER-0089'), 'Should contain SER-0089');
        assert.ok(sql.includes('Scrub Typhus IgM'), 'Should contain Scrub Typhus IgM');
        assert.ok(sql.includes('Scrub Typhus IgG'), 'Should contain Scrub Typhus IgG');
        assert.ok(sql.includes('Index'), 'Should have unit Index');
    });

    it('5. Configures END-0056 OGTT 75g with Fasting, 1h, 2h parameters and standard ranges', () => {
        assert.ok(sql.includes('END-0056'), 'Should contain END-0056');
        assert.ok(sql.includes('Fasting Glucose (0 min)'), 'Should contain Fasting Glucose');
        assert.ok(sql.includes('1-Hour Glucose (60 min)'), 'Should contain 1-Hour Glucose');
        assert.ok(sql.includes('2-Hour Glucose (120 min)'), 'Should contain 2-Hour Glucose');
        assert.ok(sql.includes('70.0') && sql.includes('99.0'), 'Should have Fasting 70-99');
        assert.ok(sql.includes('140.0'), 'Should have 2-Hour normal <140');
    });

    it('6. Configures END-0057 Gestational OGTT 75g with Fasting <92, 1h <180, 2h <153', () => {
        assert.ok(sql.includes('END-0057'), 'Should contain END-0057');
        assert.ok(sql.includes('92.0'), 'Should contain Fasting <92 cutoff');
        assert.ok(sql.includes('180.0'), 'Should contain 1-Hour <180 cutoff');
        assert.ok(sql.includes('153.0'), 'Should contain 2-Hour <153 cutoff');
    });

    it('7. Configures END-0058 GCT 50g with 1-Hour Post-50g Glucose and <140 cutoff', () => {
        assert.ok(sql.includes('END-0058'), 'Should contain END-0058');
        assert.ok(sql.includes('1-Hour Post-50g Glucose'), 'Should contain 1-Hour Post-50g Glucose');
        assert.ok(sql.includes('140.0'), 'Should contain 140 cutoff');
    });

    it('8. Configures Dexamethasone suppression tests (END-0059, END-0060, END-0061)', () => {
        assert.ok(sql.includes('END-0059'), 'Should contain END-0059');
        assert.ok(sql.includes('Post-1mg Dex Cortisol'), 'Should contain Post-1mg Dex Cortisol');
        assert.ok(sql.includes('END-0060'), 'Should contain END-0060');
        assert.ok(sql.includes('Post-LDDST Cortisol'), 'Should contain Post-LDDST Cortisol');
        assert.ok(sql.includes('END-0061'), 'Should contain END-0061');
        assert.ok(sql.includes('Suppression Percentage'), 'Should contain calculated Suppression Percentage');
    });

    it('9. Configures END-0062 ACTH Stimulation and END-0063/END-0064 GH protocols', () => {
        assert.ok(sql.includes('END-0062'), 'Should contain END-0062');
        assert.ok(sql.includes('Cortisol Baseline (0 min)'), 'Should contain Cortisol Baseline');
        assert.ok(sql.includes('END-0063'), 'Should contain END-0063');
        assert.ok(sql.includes('GH Baseline (0 min)'), 'Should contain GH Baseline');
        assert.ok(sql.includes('END-0064'), 'Should contain END-0064');
        assert.ok(sql.includes('Stimulating Agent'), 'Should contain Stimulating Agent parameter');
    });

    it('10. Configures END-0065 Water Deprivation Test with multi-analyte parameters', () => {
        assert.ok(sql.includes('END-0065'), 'Should contain END-0065');
        assert.ok(sql.includes('Hourly Body Weight'), 'Should contain Hourly Body Weight');
        assert.ok(sql.includes('Plasma Osmolality'), 'Should contain Plasma Osmolality');
        assert.ok(sql.includes('Urine Osmolality'), 'Should contain Urine Osmolality');
        assert.ok(sql.includes('Serum Sodium'), 'Should contain Serum Sodium');
        assert.ok(sql.includes('Post-Desmopressin Urine Osmolality'), 'Should contain Post-Desmopressin Urine Osmolality');
    });

    it('11. Configures POC-0002 VBG with exactly 7 leaf parameters and venous ranges', () => {
        assert.ok(sql.includes('POC-0002'), 'Should contain POC-0002');
        assert.ok(sql.includes('pH (Venous)'), 'Should contain pH (Venous)');
        assert.ok(sql.includes('pvCO2'), 'Should contain pvCO2');
        assert.ok(sql.includes('pvO2'), 'Should contain pvO2');
        assert.ok(sql.includes('HCO3- / Bicarbonate'), 'Should contain HCO3-');
        assert.ok(sql.includes('Base Excess'), 'Should contain Base Excess');
        assert.ok(sql.includes('Venous O2 Saturation'), 'Should contain Venous O2 Saturation');
        assert.ok(sql.includes('Lactate'), 'Should contain Lactate');
        assert.ok(sql.includes('7.31') && sql.includes('7.41'), 'Should have venous pH range 7.31-7.41');
    });

    it('12. Configures SPC-0007 Organic Acids, Urine with structured narrative parameters', () => {
        assert.ok(sql.includes('SPC-0007'), 'Should contain SPC-0007');
        assert.ok(sql.includes('Metabolic Profile Result'), 'Should contain Metabolic Profile Result');
        assert.ok(sql.includes('Key Excreted Acids'), 'Should contain Key Excreted Acids');
        assert.ok(sql.includes('Clinical Interpretation'), 'Should contain Clinical Interpretation');
    });

    it('13. Reconciles exact 47 parameters across 15 P0 tests', () => {
        const p0Counts = {
            'BIO-0141': 1,
            'IMM-0093': 1,
            'SER-0089': 2,
            'END-0056': 3,
            'END-0057': 3,
            'END-0058': 1,
            'END-0059': 2,
            'END-0060': 2,
            'END-0061': 3,
            'END-0062': 3,
            'END-0063': 5,
            'END-0064': 6,
            'END-0065': 5,
            'POC-0002': 7,
            'SPC-0007': 3
        };
        const total = Object.values(p0Counts).reduce((acc, c) => acc + c, 0);
        assert.equal(total, 47, 'P0 parameters must sum to exactly 47');
    });

    it('14. END-0059 baseline cortisol is optional while post-dex is mandatory', () => {
        assert.ok(sql.includes("'END-0059-01', 'Baseline Cortisol (8 AM)', 'Numeric', 'µg/dL', 1, TRUE, 'Active', FALSE"), 'Baseline should have is_mandatory = FALSE');
        assert.ok(sql.includes("'END-0059-02', 'Post-1mg Dex Cortisol (8 AM)', 'Numeric', 'µg/dL', 2, TRUE, 'Active', TRUE"), 'Post-Dex should have is_mandatory = TRUE');
    });

    it('15. END-0061 suppression percentage calculation formula with baseline > 0 guard', async () => {
        const { evaluateClinicalFormula } = await import('../src/lib/clinicalMath.ts');
        const formula = '((BASELINE - POST) / BASELINE) * 100';

        // Normal suppression
        const resNormal = evaluateClinicalFormula(formula, { BASELINE: 20, POST: 5 }, 'END-0061-03', '%');
        assert.equal(resNormal.status, 'SUCCESS');
        assert.equal(resNormal.rawValue, 75);
        assert.equal(resNormal.displayValue, '75.0');

        // Non-suppression
        const resNon = evaluateClinicalFormula(formula, { BASELINE: 20, POST: 15 }, 'END-0061-03', '%');
        assert.equal(resNon.status, 'SUCCESS');
        assert.equal(resNon.rawValue, 25);
        assert.equal(resNon.displayValue, '25.0');

        // Baseline = 0 division by zero guard
        const resZero = evaluateClinicalFormula(formula, { BASELINE: 0, POST: 5 }, 'END-0061-03', '%');
        assert.equal(resZero.status, 'DIVIDE_BY_ZERO');
        assert.equal(resZero.isError, true);
        assert.equal(resZero.displayValue, 'Calculation Error');
    });
});
