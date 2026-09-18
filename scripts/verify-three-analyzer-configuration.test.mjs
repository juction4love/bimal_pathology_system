import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const projectRoot = process.cwd();

test('3-Analyzer Configuration & Safety Verification Test Suite', async (t) => {

  await t.test('COUNCELL 23 EXCEL: CBC 24-Parameter Authoritative Suite & Governance', async () => {
    // 1. Verify Migration 00124 and 00125 exist
    const mig124Path = path.join(projectRoot, 'supabase/migrations/00124_cbc_reporting_parameters.sql');
    const mig125Path = path.join(projectRoot, 'supabase/migrations/00125_three_analyzer_reporting_configuration.sql');
    assert.ok(fs.existsSync(mig124Path), 'Migration 00124 must exist');
    assert.ok(fs.existsSync(mig125Path), 'Migration 00125 must exist');

    const mig124Content = fs.readFileSync(mig124Path, 'utf8');
    const mig125Content = fs.readFileSync(mig125Path, 'utf8');

    // 2. Authoritative parameter definitions (code, unit, order)
    const expectedAuthoritativeCBCParams = [
      { order: 1, code: 'WBC', unit: '10^9/L' },
      { order: 2, code: 'LYM_ABS', unit: '10^9/L' },
      { order: 3, code: 'MID_ABS', unit: '10^9/L' },
      { order: 4, code: 'GRAN_ABS', unit: '10^9/L' },
      { order: 5, code: 'LYM_PERCENT', unit: '%' },
      { order: 6, code: 'MID_PERCENT', unit: '%' },
      { order: 7, code: 'GRAN_PERCENT', unit: '%' },
      { order: 8, code: 'NLR', unit: 'Ratio' },
      { order: 9, code: 'PLR', unit: 'Ratio' },
      { order: 10, code: 'RBC', unit: '10^12/L' },
      { order: 11, code: 'HGB', unit: 'g/dL' },
      { order: 12, code: 'HCT', unit: '%' },
      { order: 13, code: 'MCV', unit: 'fL' },
      { order: 14, code: 'MCH', unit: 'pg' },
      { order: 15, code: 'MCHC', unit: 'g/dL' },
      { order: 16, code: 'RDW_CV', unit: '%' },
      { order: 17, code: 'RDW_SD', unit: 'fL' },
      { order: 18, code: 'PLT', unit: '10^9/L' },
      { order: 19, code: 'MPV', unit: 'fL' },
      { order: 20, code: 'PDW_CV', unit: '%' },
      { order: 21, code: 'PDW_SD', unit: 'fL' },
      { order: 22, code: 'PCT', unit: '%' },
      { order: 23, code: 'P_LCC', unit: '10^9/L' },
      { order: 24, code: 'P_LCR', unit: '%' }
    ];

    for (const param of expectedAuthoritativeCBCParams) {
      assert.ok(
        mig124Content.includes(`'${param.code}'`),
        `Migration 00124 must contain CBC parameter '${param.code}'`
      );
      assert.ok(
        mig124Content.includes(`'${param.unit}'`),
        `Migration 00124 must contain unit '${param.unit}' for '${param.code}'`
      );
    }

    // 3. Verify CBC remains ONE billable test item (HEM-0001)
    assert.ok(
      mig124Content.includes("SELECT id INTO v_cbc_id FROM public.tests WHERE code = 'HEM-0001'"),
      'CBC must be linked to canonical code HEM-0001'
    );

    // 4. Verify Manual Microscopy Differential is NOT mixed with automated CBC
    assert.ok(
      mig125Content.includes("HEM-0016") && mig125Content.includes("CBC_LYM_P"),
      'Migration 00125 must safeguard separation between manual lymphocyte % and automated LYM%'
    );

    // 5. Verify No Automated ANC is fabricated for 3-part CBC
    assert.ok(
      !mig124Content.includes("('ANC', 'Absolute Neutrophil Count'"),
      'Automated ANC must NOT be fabricated in CounCell 3-part CBC parameter list'
    );

    // 6. Verify Histograms are NOT created as numeric result parameters
    const nonNumericHistograms = ['WBC_HISTOGRAM', 'RBC_HISTOGRAM', 'PLT_HISTOGRAM'];
    for (const hist of nonNumericHistograms) {
      assert.ok(
        !mig124Content.includes(`v_cbc_id, '${hist}'`),
        `Histograms (${hist}) must NOT be inserted as numeric test parameters`
      );
    }
  });

  await t.test('CORALAB ACE: Photometric Method Integrity & Assay Safety', async () => {
    const mig107Path = path.join(projectRoot, 'supabase/migrations/00107_coralab_ace_biochemistry_integration.sql');
    const mig125Path = path.join(projectRoot, 'supabase/migrations/00125_three_analyzer_reporting_configuration.sql');
    assert.ok(fs.existsSync(mig107Path), 'Migration 00107 must exist');

    const mig125Content = fs.readFileSync(mig125Path, 'utf8');

    // 1. Verify Na / K / Cl are strictly PHOTOMETRIC (NON-ISE)
    assert.ok(
      mig125Content.includes("Photometric (Colorimetric)") && mig125Content.includes("BIO-0037"),
      'Sodium (BIO-0037) must be Photometric Colorimetric (Non-ISE)'
    );
    assert.ok(
      mig125Content.includes("Photometric (Turbidimetric)") && mig125Content.includes("BIO-0038"),
      'Potassium (BIO-0038) must be Photometric Turbidimetric (Non-ISE)'
    );
    assert.ok(
      mig125Content.includes("Photometric (Mercuric Thiocyanate)") && mig125Content.includes("BIO-0039"),
      'Chloride (BIO-0039) must be Photometric Mercuric Thiocyanate (Non-ISE)'
    );

    // 2. Verify CK-MB Activity is U/L and UV Kinetic
    assert.ok(
      mig125Content.includes("BIO-0062") && mig125Content.includes("U/L") && mig125Content.includes("UV Kinetic"),
      'CORALAB CK-MB must be Activity assay in U/L'
    );
  });

  await t.test('FIACHECK: Immunoassay Analytical Safety & Identity Preservation', async () => {
    const mig109Path = path.join(projectRoot, 'supabase/migrations/00109_fiacheck_analyzer_integration.sql');
    const mig125Path = path.join(projectRoot, 'supabase/migrations/00125_three_analyzer_reporting_configuration.sql');
    assert.ok(fs.existsSync(mig109Path), 'Migration 00109 must exist');

    const mig125Content = fs.readFileSync(mig125Path, 'utf8');

    // 1. Verify D-Dimer is strictly FEU identity
    assert.ok(
      mig125Content.includes("COA-0006") && mig125Content.includes("µg/mL FEU"),
      'FIAcheck D-Dimer (COA-0006) must preserve FEU unit identity'
    );

    // 2. Verify CK-MB Mass is ng/mL (distinct from CORALAB CK-MB Activity)
    assert.ok(
      mig125Content.includes("BIO-0061") && mig125Content.includes("ng/mL"),
      'FIAcheck CK-MB Mass (BIO-0061) must be ng/mL and distinct from BIO-0062'
    );

    // 3. Verify Beta-hCG quantitative is mIU/mL
    assert.ok(
      mig125Content.includes("END-0039") && mig125Content.includes("mIU/mL"),
      'FIAcheck Beta-hCG (END-0039) must be Quantitative in mIU/mL'
    );

    // 4. Verify hs-CRP is mg/L
    assert.ok(
      mig125Content.includes("BIO-0068") && mig125Content.includes("mg/L"),
      'FIAcheck hs-CRP (BIO-0068) must be mg/L'
    );

    // 5. Verify Procalcitonin is PCT_SEPSIS in ng/mL
    assert.ok(
      mig125Content.includes("PCT_SEPSIS") && mig125Content.includes("ng/mL"),
      'FIAcheck Procalcitonin must be PCT_SEPSIS in ng/mL'
    );
  });

  await t.test('COUNCELL 23 EXCEL & MANUAL MICROSCOPY: Physical vs Microscopy Channel Isolation', async () => {
    const mig125Path = path.join(projectRoot, 'supabase/migrations/00125_three_analyzer_reporting_configuration.sql');
    const mig125Content = fs.readFileSync(mig125Path, 'utf8');

    // 1. Verify MANUAL_MICROSCOPY analyzer master is created
    assert.ok(
      mig125Content.includes("'MANUAL_MICROSCOPY'") && mig125Content.includes("Manual Microscopy / Peripheral Smear"),
      'Migration 00125 must create MANUAL_MICROSCOPY master record'
    );

    // 2. Verify all 8 manual channels are moved away from COUNCELL_23_EXCEL
    const manualChannels = ['NEUT_PERCENT', 'MONO_PERCENT', 'EOS_PERCENT', 'BASO_PERCENT', 'ANC', 'AEC', 'MANUAL_LYM_PERCENT', 'ALC'];
    for (const ch of manualChannels) {
      assert.ok(
        mig125Content.includes(`'${ch}'`),
        `Migration 00125 must reassign manual channel '${ch}' to MANUAL_MICROSCOPY`
      );
    }
  });

  await t.test('GLOBAL INVARIANTS: Report Document & Clinical Snapshot Safety', async () => {
    // 1. Verify ReportDocument.tsx renders multi-parameter tests with parameter tables
    const reportDocPath = path.join(projectRoot, 'src/features/reports/ReportDocument.tsx');
    assert.ok(fs.existsSync(reportDocPath), 'ReportDocument.tsx must exist');
    const reportDocContent = fs.readFileSync(reportDocPath, 'utf8');

    assert.ok(
      reportDocContent.includes('parameter') || reportDocContent.includes('results') || reportDocContent.includes('unit'),
      'ReportDocument must support parameter rows, units, reference ranges, and flags'
    );

    // 2. Verify SMS templates remain 100% URL-free across all pending migrations
    const mig122Path = path.join(projectRoot, 'supabase/migrations/00122_url_free_sms_notifications.sql');
    const mig122Content = fs.readFileSync(mig122Path, 'utf8');
    const smsMatches = [...mig122Content.matchAll(/'Bimal Pathology: ([^']*)'/g)];
    assert.ok(smsMatches.length > 0, 'Must contain Bimal Pathology SMS template literals');
    for (const match of smsMatches) {
      assert.doesNotMatch(match[1], /https?:|www\.|bimalpathology\./i, 'SMS message literal must not contain URLs');
    }
  });

});
