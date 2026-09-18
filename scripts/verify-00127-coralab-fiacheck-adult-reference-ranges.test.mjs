import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

describe('Migration 00127: CORALAB ACE & FIAcheck Reference Ranges Audit', () => {
    const migrationPath = path.resolve('supabase/migrations/00127_coralab_fiacheck_adult_reference_ranges.sql');
    const sql = fs.readFileSync(migrationPath, 'utf8');

    it('should exist and be non-empty', () => {
        assert.ok(fs.existsSync(migrationPath), 'Migration 00127 file must exist');
        assert.ok(sql.length > 500, 'Migration file should have substantial content');
    });

    it('should be wrapped in a transaction block', () => {
        assert.ok(sql.includes('BEGIN;'), 'Must have BEGIN block');
        assert.ok(sql.includes('COMMIT;'), 'Must have COMMIT block');
    });

    describe('1. CORALAB ACE: Glucose & RFT Ranges', () => {
        it('configures Fasting Glucose (BIO-0001) as 70 - 100 mg/dL', () => {
            assert.ok(sql.includes("'BIO-0001'"), 'Must target BIO-0001');
            assert.ok(sql.includes('70.0, 100.0'), 'Must set 70 - 100');
            assert.ok(sql.includes("'70 - 100 mg/dL'"), 'Must set display text 70 - 100 mg/dL');
        });

        it('configures PPBS (BIO-0003) as < 140 mg/dL', () => {
            assert.ok(sql.includes("'BIO-0003'"), 'Must target BIO-0003');
            assert.ok(sql.includes('NULL, 140.0'), 'Must set upper limit 140 without lower bound');
            assert.ok(sql.includes("'< 140 mg/dL'"), 'Must set display text < 140 mg/dL');
        });

        it('configures Random Glucose (BIO-0002) as 70 - 140 mg/dL', () => {
            assert.ok(sql.includes("'BIO-0002'"), 'Must target BIO-0002');
            assert.ok(sql.includes('70.0, 140.0'), 'Must set 70 - 140');
            assert.ok(sql.includes("'70 - 140 mg/dL'"), 'Must set display text 70 - 140 mg/dL');
        });

        it('configures Urea (BIO-0008) as 15 - 45 mg/dL', () => {
            assert.ok(sql.includes("'BIO-0008'"), 'Must target BIO-0008');
            assert.ok(sql.includes('15.0, 45.0'), 'Must set 15 - 45');
        });

        it('configures BUN (BIO-0009) as 7 - 20 mg/dL', () => {
            assert.ok(sql.includes("'BIO-0009'"), 'Must target BIO-0009');
            assert.ok(sql.includes('7.0, 20.0'), 'Must set 7 - 20');
        });

        it('configures Creatinine (BIO-0010) as sex-specific: Male 0.7-1.3, Female 0.6-1.1 mg/dL', () => {
            assert.ok(sql.includes("'BIO-0010'"), 'Must target BIO-0010');
            assert.ok(sql.includes("'Male', 0, 43800, 0.7, 1.3"), 'Male range 0.7 - 1.3');
            assert.ok(sql.includes("'Female', 0, 43800, 0.6, 1.1"), 'Female range 0.6 - 1.1');
        });

        it('configures Uric Acid (BIO-0012) as sex-specific: Male 3.5-7.2, Female 2.6-6.0 mg/dL', () => {
            assert.ok(sql.includes("'BIO-0012'"), 'Must target BIO-0012');
            assert.ok(sql.includes("'Male', 0, 43800, 3.5, 7.2"), 'Male range 3.5 - 7.2');
            assert.ok(sql.includes("'Female', 0, 43800, 2.6, 6.0"), 'Female range 2.6 - 6.0');
        });
    });

    describe('2. CORALAB ACE: Liver Function Tests (LFT)', () => {
        it('configures Total Bilirubin (BIO-0017) as 0.2 - 1.2 mg/dL', () => {
            assert.ok(sql.includes("'BIO-0017'"), 'Must target BIO-0017');
            assert.ok(sql.includes('0.2, 1.2'), 'Must set 0.2 - 1.2');
        });

        it('configures Direct Bilirubin (BIO-0018) as 0.0 - 0.3 mg/dL', () => {
            assert.ok(sql.includes("'BIO-0018'"), 'Must target BIO-0018');
            assert.ok(sql.includes('0.0, 0.3'), 'Must set 0.0 - 0.3');
        });

        it('configures ALT/SGPT (BIO-0021) as sex-specific: Male < 45, Female < 35 U/L', () => {
            assert.ok(sql.includes("'BIO-0021'"), 'Must target BIO-0021');
            assert.ok(sql.includes("'Male', 0, 43800, NULL, 45.0"), 'Male ALT < 45');
            assert.ok(sql.includes("'Female', 0, 43800, NULL, 35.0"), 'Female ALT < 35');
        });

        it('configures AST/SGOT (BIO-0020) as sex-specific: Male < 40, Female < 35 U/L', () => {
            assert.ok(sql.includes("'BIO-0020'"), 'Must target BIO-0020');
            assert.ok(sql.includes("'Male', 0, 43800, NULL, 40.0"), 'Male AST < 40');
            assert.ok(sql.includes("'Female', 0, 43800, NULL, 35.0"), 'Female AST < 35');
        });

        it('configures ALP (BIO-0022) as 44 - 147 U/L', () => {
            assert.ok(sql.includes("'BIO-0022'"), 'Must target BIO-0022');
            assert.ok(sql.includes('44.0, 147.0'), 'Must set 44 - 147');
        });

        it('configures Total Protein (BIO-0013) as 6.4 - 8.3 g/dL', () => {
            assert.ok(sql.includes("'BIO-0013'"), 'Must target BIO-0013');
            assert.ok(sql.includes('6.4, 8.3'), 'Must set 6.4 - 8.3');
        });

        it('configures Albumin (BIO-0014) as 3.5 - 5.0 g/dL', () => {
            assert.ok(sql.includes("'BIO-0014'"), 'Must target BIO-0014');
            assert.ok(sql.includes('3.5, 5.0'), 'Must set 3.5 - 5.0');
        });

        it('configures Globulin (BIO-0015) as 2.0 - 3.5 g/dL', () => {
            assert.ok(sql.includes("'BIO-0015'"), 'Must target BIO-0015');
            assert.ok(sql.includes('2.0, 3.5'), 'Must set 2.0 - 3.5');
        });

        it('configures A/G Ratio (BIO-0016) as 1.2 - 2.2', () => {
            assert.ok(sql.includes("'BIO-0016'"), 'Must target BIO-0016');
            assert.ok(sql.includes('1.2, 2.2'), 'Must set 1.2 - 2.2');
        });
    });

    describe('3. CORALAB ACE: Lipid Profile & HbA1c', () => {
        it('configures Total Cholesterol (BIO-0027) as < 200 mg/dL with Desirable interpretation', () => {
            assert.ok(sql.includes("'BIO-0027'"), 'Must target BIO-0027');
            assert.ok(sql.includes("'< 200 mg/dL'"), 'Must set < 200 mg/dL');
            assert.ok(sql.includes('Desirable'), 'Must include Desirable interpretation');
        });

        it('configures Triglycerides (BIO-0028) as < 150 mg/dL with Normal interpretation', () => {
            assert.ok(sql.includes("'BIO-0028'"), 'Must target BIO-0028');
            assert.ok(sql.includes("'< 150 mg/dL'"), 'Must set < 150 mg/dL');
            assert.ok(sql.includes('Normal: < 150 mg/dL'), 'Must include Normal interpretation');
        });

        it('configures HDL Cholesterol (BIO-0029) as sex-specific: Male > 40, Female > 50 mg/dL', () => {
            assert.ok(sql.includes("'BIO-0029'"), 'Must target BIO-0029');
            assert.ok(sql.includes("'Male', 0, 43800, 40.0, NULL"), 'Male HDL > 40');
            assert.ok(sql.includes("'Female', 0, 43800, 50.0, NULL"), 'Female HDL > 50');
        });

        it('configures LDL Direct (BIO-0030) and LDL Calculated (BIO-0031) safely as < 100 mg/dL Optimal', () => {
            assert.ok(sql.includes("'BIO-0030'"), 'Must target BIO-0030');
            assert.ok(sql.includes("'BIO-0031'"), 'Must target BIO-0031');
            assert.ok(sql.includes("Optimal: < 100 mg/dL"), 'Must set Optimal band');
        });

        it('configures VLDL Cholesterol (BIO-0032) as 10 - 30 mg/dL', () => {
            assert.ok(sql.includes("'BIO-0032'"), 'Must target BIO-0032');
            assert.ok(sql.includes('10.0, 30.0'), 'Must set 10 - 30');
        });

        it('configures HbA1c (BIO-0006) as < 5.7 % with structured interpretation bands and CORALAB ACE identity', () => {
            assert.ok(sql.includes("'BIO-0006'"), 'Must target BIO-0006');
            assert.ok(sql.includes("'< 5.7 %'"), 'Must set < 5.7% normal text');
            assert.ok(sql.includes("Prediabetes: 5.7 - 6.4%"), 'Must include prediabetes band');
            assert.ok(sql.includes("Diabetes: >= 6.5%"), 'Must include diabetes band');
            assert.ok(sql.includes("CORALAB ACE"), 'Must preserve CORALAB ACE method/identity');
        });
    });

    describe('4. FIAcheck: Cardiac, Inflammatory & Coagulation Markers', () => {
        it('configures Troponin I (BIO-0063) as < 0.1 ng/mL with MI Suspected decision limit', () => {
            assert.ok(sql.includes("'BIO-0063'"), 'Must target BIO-0063');
            assert.ok(sql.includes("NULL, 0.1"), 'Normal reference < 0.1');
            assert.ok(sql.includes("> 0.5 ng/mL (MI Suspected)"), 'Must separate decision cutoff');
        });

        it('configures D-Dimer (COA-0006) strictly using µg/mL FEU with < 0.50 cutoff', () => {
            assert.ok(sql.includes("'COA-0006'"), 'Must target COA-0006');
            assert.ok(sql.includes("'µg/mL FEU'"), 'Must preserve µg/mL FEU unit');
            assert.ok(sql.includes("NULL, 0.5"), 'Normal max 0.5');
            assert.ok(sql.includes("Thrombosis/PE Suspected"), 'Must separate PE cutoff');
        });

        it('configures CK-MB Mass (BIO-0061) as < 5.0 ng/mL on FIAcheck without affecting CK-MB Activity', () => {
            assert.ok(sql.includes("'BIO-0061'"), 'Must target BIO-0061');
            assert.ok(sql.includes("NULL, 5.0"), 'Normal max 5.0');
            assert.ok(sql.includes("Cardiac Injury Indicator"), 'Must include interpretive remark');
            assert.ok(!sql.includes("'BIO-0062'"), 'Must NOT touch BIO-0062 (CK-MB Activity)');
        });

        it('configures Standard CRP (IMM-0001) as < 6.0 mg/L with Turbidimetry identity (no fake FIAcheck mapping)', () => {
            assert.ok(sql.includes("'IMM-0001'"), 'Must target IMM-0001');
            assert.ok(sql.includes("NULL, 6.0"), 'Normal max 6.0');
            assert.ok(sql.includes("Turbidimetry"), 'Must keep turbidimetry identity');
        });

        it('configures hs-CRP (BIO-0068) with 3 cardiovascular risk bands: <1.0, 1.0-3.0, >3.0 mg/L', () => {
            assert.ok(sql.includes("'BIO-0068'"), 'Must target BIO-0068');
            assert.ok(sql.includes("Low Risk: < 1.0"), 'Must include low risk');
            assert.ok(sql.includes("Avg Risk: 1.0 - 3.0"), 'Must include average risk');
            assert.ok(sql.includes("High Risk: > 3.0"), 'Must include high risk');
        });

        it('configures Procalcitonin (PCT_SEPSIS) as < 0.05 ng/mL isolated from CBC PCT', () => {
            assert.ok(sql.includes("'PCT_SEPSIS'"), 'Must target PCT_SEPSIS');
            assert.ok(sql.includes("NULL, 0.05"), 'Normal max 0.05');
            assert.ok(sql.includes("Systemic Infection"), 'Must include systemic infection cutoff');
        });
    });

    describe('5. FIAcheck: Thyroid Hormones & Ferritin', () => {
        it('configures TSH (END-0001) as 0.40 - 4.20 µIU/mL', () => {
            assert.ok(sql.includes("'END-0001'"), 'Must target END-0001');
            assert.ok(sql.includes("0.40, 4.20"), 'Must set 0.40 - 4.20');
        });

        it('configures Total T3 (END-0005) with unit-reconciled range 0.80 - 2.00 ng/mL', () => {
            assert.ok(sql.includes("'END-0005'"), 'Must target END-0005');
            assert.ok(sql.includes("0.80, 2.00"), 'Must set 0.80 - 2.00');
            assert.ok(sql.includes("'ng/mL'"), 'Must retain ng/mL canonical unit');
        });

        it('configures Total T4 (END-0004) as 5.0 - 12.0 µg/dL', () => {
            assert.ok(sql.includes("'END-0004'"), 'Must target END-0004');
            assert.ok(sql.includes("5.0, 12.0"), 'Must set 5.0 - 12.0');
        });

        it('configures Free T3 (END-0003) as 2.0 - 4.4 pg/mL', () => {
            assert.ok(sql.includes("'END-0003'"), 'Must target END-0003');
            assert.ok(sql.includes("2.0, 4.4"), 'Must set 2.0 - 4.4');
        });

        it('configures Free T4 (END-0002) as 0.9 - 1.7 ng/dL', () => {
            assert.ok(sql.includes("'END-0002'"), 'Must target END-0002');
            assert.ok(sql.includes("0.9, 1.7"), 'Must set 0.9 - 1.7');
        });

        it('configures Ferritin (BIO-0050) as sex-specific: Male 20-250, Female 10-120 ng/mL', () => {
            assert.ok(sql.includes("'BIO-0050'"), 'Must target BIO-0050');
            assert.ok(sql.includes("'Male', 0, 43800, 20.0, 250.0"), 'Male Ferritin 20 - 250');
            assert.ok(sql.includes("'Female', 0, 43800, 10.0, 120.0"), 'Female Ferritin 10 - 120');
        });
    });

    describe('6. Manual Tests: ESR Westergren & Stool Occult Blood', () => {
        it('configures ESR Westergren (HEM-0027) with approved sex + age bands (<=50 and >50)', () => {
            assert.ok(sql.includes("'HEM-0027'"), 'Must target HEM-0027');
            assert.ok(sql.includes("'Male', 0, 18262, 0.0, 15.0"), 'Male <= 50: 0 - 15');
            assert.ok(sql.includes("'Male', 18263, 43800, 0.0, 20.0"), 'Male > 50: 0 - 20');
            assert.ok(sql.includes("'Female', 0, 18262, 0.0, 20.0"), 'Female <= 50: 0 - 20');
            assert.ok(sql.includes("'Female', 18263, 43800, 0.0, 30.0"), 'Female > 50: 0 - 30');
            assert.ok(sql.includes("'mm/1st hr'"), 'Must use mm/1st hr unit');
            assert.ok(sql.includes("'Westergren'"), 'Must preserve Westergren method');
        });

        it('configures Stool Occult Blood (CLP-0025, CLP-0026) as Qualitative with Expected: Negative', () => {
            assert.ok(sql.includes("'CLP-0025'"), 'Must target CLP-0025');
            assert.ok(sql.includes("'CLP-0026'"), 'Must target CLP-0026');
            assert.ok(sql.includes("value_type = 'Select'"), 'Must set value_type to Select');
            assert.ok(sql.includes('["Negative", "Positive"]'), 'Must provide Negative/Positive options');
            assert.ok(sql.includes("'Negative'"), 'Must set expected normal_text Negative');
        });
    });

    describe('7. Production Invariant Safety', () => {
        it('does NOT modify catalogue rate versions or billing tables', () => {
            assert.ok(!sql.toLowerCase().includes('catalogue_rate_versions'), 'Must not touch catalogue_rate_versions');
            assert.ok(!sql.toLowerCase().includes('invoice'), 'Must not touch invoices');
            assert.ok(!sql.toLowerCase().includes('bill_items'), 'Must not touch bill_items');
        });

        it('does NOT mutate historical clinical test results or signed report snapshots', () => {
            assert.ok(!sql.toLowerCase().includes('diagnostic_reports'), 'Must not touch diagnostic_reports');
            assert.ok(!sql.toLowerCase().includes('report_snapshots'), 'Must not touch report_snapshots');
        });
    });
});
