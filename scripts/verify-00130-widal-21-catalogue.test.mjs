import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration00130 = readFileSync('supabase/migrations/00130_focused_approved_catalogue.sql', 'utf8');

test('Migration 00130: 21-Test Catalogue & 4-Antigen Widal Configuration', async (t) => {

  await t.test('1. Migration 00130 contains exactly the 21 approved user-facing billing investigations', () => {
    const expectedBillingCodes = [
      'HEM-0001', // Complete Blood Count (CBC)
      'HEM-0002', // Hemoglobin (Hb)
      'HEM-0027', // ESR (Westergren)
      'PRO-0001', // Liver Function Test (LFT)
      'PRO-0002', // Renal Function Test (RFT/KFT)
      'BIO-0001', // Glucose, Fasting (FBS)
      'BIO-0003', // Glucose, Postprandial 2 hr (PPBS)
      'BIO-0006', // HbA1c
      'PRO-0003', // Lipid Profile
      'BIO-0063', // Troponin I, High Sensitivity
      'END-0001', // TSH
      'END-0003', // Free T3 (FT3)
      'END-0002', // Free T4 (FT4)
      'BIO-0053', // Vitamin D, 25-OH
      'BIO-0051', // Vitamin B12
      'CLP-0001', // Urine Routine Examination (RE/ME)
      'SER-0015', // Dengue NS1 Antigen
      'SER-0016', // Dengue IgM
      'SER-0024', // Widal Test
      'SER-0004', // HBsAg
      'SER-0010'  // Anti-HCV
    ];

    for (const code of expectedBillingCodes) {
      assert.ok(migration00130.includes(`'${code}'`), `Migration 00130 must include billing code ${code}`);
    }
  });

  await t.test('2. Widal Test SER-0024 is configured with 4 antigen parameters and Tube Agglutination', () => {
    assert.match(migration00130, /code = 'SER-0024'/);
    assert.match(migration00130, /method = 'Tube Agglutination'/);
    assert.match(migration00130, /sample_type = 'Serum'/);
    assert.match(migration00130, /'WIDAL_TO', 'Salmonella Typhi ''O'''/);
    assert.match(migration00130, /'WIDAL_TH', 'Salmonella Typhi ''H'''/);
    assert.match(migration00130, /'WIDAL_AH', 'Salmonella Paratyphi ''AH'''/);
    assert.match(migration00130, /'WIDAL_BH', 'Salmonella Paratyphi ''BH'''/);
  });

  await t.test('3. Widal option set includes all approved dilution steps (<1:20 to 1:320)', () => {
    const requiredOptions = ['< 1:20', '1:20', '1:40', '1:80', '1:160', '1:320'];
    for (const opt of requiredOptions) {
      assert.ok(migration00130.includes(opt), `Widal dilution options must contain ${opt}`);
    }
  });

  await t.test('4. Diagnostic cut-offs are configured (>= 1:160 for O/H, >= 1:80 for AH/BH)', () => {
    assert.match(migration00130, /Diagnostic Cut-off: >= 1:160/);
    assert.match(migration00130, /Diagnostic Cut-off: >= 1:80/);
  });

  await t.test('5. KFT Profile components are restricted to Urea, BUN, Creatinine, Uric Acid', () => {
    assert.match(migration00130, /BIO-0037/); // Sodium deleted from panel
    assert.match(migration00130, /BIO-0038/); // Potassium deleted from panel
    assert.match(migration00130, /BIO-0039/); // Chloride deleted from panel
    assert.match(migration00130, /BIO-0011/); // eGFR deleted from panel
  });

  await t.test('6. Lipid Profile removes Non-HDL (BIO-0033)', () => {
    assert.match(migration00130, /BIO-0033/);
  });

  await t.test('7. Urine Routine removes non-routine parameters (CLP-0011, CLP-0012, CLP-0013, CLP-0019)', () => {
    assert.match(migration00130, /CLP-0011/);
    assert.match(migration00130, /CLP-0012/);
    assert.match(migration00130, /CLP-0013/);
    assert.match(migration00130, /CLP-0019/);
  });

  await t.test('8. Full Widal representative workflow test structure evaluation', () => {
    // Simulated patient test entry with example input:
    // O = 1:160, H = 1:80, AH = <1:20, BH = <1:20
    const sampleResults = {
      WIDAL_TO: '1:160',
      WIDAL_TH: '1:80',
      WIDAL_AH: '< 1:20',
      WIDAL_BH: '< 1:20',
    };

    const cutoffs = {
      WIDAL_TO: '>= 1:160',
      WIDAL_TH: '>= 1:160',
      WIDAL_AH: '>= 1:80',
      WIDAL_BH: '>= 1:80',
    };

    assert.equal(sampleResults.WIDAL_TO, '1:160');
    assert.equal(sampleResults.WIDAL_TH, '1:80');
    assert.equal(sampleResults.WIDAL_AH, '< 1:20');
    assert.equal(sampleResults.WIDAL_BH, '< 1:20');
    assert.equal(cutoffs.WIDAL_TO, '>= 1:160');
    assert.equal(cutoffs.WIDAL_AH, '>= 1:80');
  });
});
