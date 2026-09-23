import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

// Helper functions representing clinicalReferenceRange logic
function resolvePatientReferenceRange(ranges, patientAgeDays, patientGender) {
  if (!ranges || ranges.length === 0) return null;
  const approvedRanges = ranges.filter((r) => r.is_active !== false && r.is_approved !== false);
  if (approvedRanges.length === 0) return null;
  const normalizedGender = (patientGender || 'All').trim();
  const matchingAge = approvedRanges.filter((r) => r.age_min_days <= patientAgeDays && r.age_max_days >= patientAgeDays);
  if (matchingAge.length === 0) return null;
  const exactGender = matchingAge.filter((r) => r.gender.toLowerCase() === normalizedGender.toLowerCase());
  const candidatePool = exactGender.length > 0 ? exactGender : matchingAge.filter((r) => r.gender === 'All');
  if (candidatePool.length === 0) return null;
  let best = candidatePool[0];
  let narrowestInterval = best.age_max_days - best.age_min_days;
  for (let i = 1; i < candidatePool.length; i++) {
    const interval = candidatePool[i].age_max_days - candidatePool[i].age_min_days;
    if (interval < narrowestInterval) {
      narrowestInterval = interval;
      best = candidatePool[i];
    }
  }
  return best;
}

function evaluateResultFlag(valueStr, valueType, range) {
  if (!valueStr || valueStr.trim() === '' || !range) return { flag: 'Normal', isCritical: false };
  if (valueType === 'Numeric' || valueType === 'Calculated') {
    const num = parseFloat(valueStr);
    if (isNaN(num)) return { flag: 'Normal', isCritical: false };
    const { critical_low, critical_high, normal_min, normal_max } = range;
    if (critical_low != null && num <= critical_low) return { flag: 'CriticalLow', isCritical: true };
    if (critical_high != null && num >= critical_high) return { flag: 'CriticalHigh', isCritical: true };
    if (normal_min != null && num < normal_min) return { flag: 'L', isCritical: false };
    if (normal_max != null && num > normal_max) return { flag: 'H', isCritical: false };
    return { flag: 'Normal', isCritical: false };
  }
  return { flag: 'Normal', isCritical: false };
}

function formatReferenceRangeText(range) {
  if (!range) return 'Not configured';
  if (range.reference_text && range.reference_text.trim().length > 0) return range.reference_text.trim();
  if (range.normal_text && range.normal_text.trim().length > 0) return range.normal_text.trim();
  const hasMin = range.normal_min !== null && range.normal_min !== undefined;
  const hasMax = range.normal_max !== null && range.normal_max !== undefined;
  if (hasMin && hasMax) return `${range.normal_min} - ${range.normal_max}`;
  if (!hasMin && hasMax) return `< ${range.normal_max}`;
  if (hasMin && !hasMax) return `> ${range.normal_min}`;
  return 'Not configured';
}

const projectRoot = process.cwd();

test('Bimal Pathology LIS: Migration 00126 CounCell Adult CBC Reference Ranges Verification', async (t) => {
  const mig126Path = path.join(projectRoot, 'supabase/migrations_legacy_archive/00126_councell_cbc_adult_reference_ranges.sql');

  await t.test('1. Migration 00126 File Structure & Invariants', () => {
    assert.ok(fs.existsSync(mig126Path), 'Migration 00126 file must exist');
    const content = fs.readFileSync(mig126Path, 'utf8');

    // Verify HEM-0001 linkage
    assert.ok(content.includes("code = 'HEM-0001'"), 'Must reference canonical CBC code HEM-0001');

    // Verify all 24 CBC parameter codes are present in 00126
    const expectedParams = [
      'WBC', 'LYM_ABS', 'MID_ABS', 'GRAN_ABS',
      'LYM_PERCENT', 'MID_PERCENT', 'GRAN_PERCENT',
      'NLR', 'PLR', 'RBC', 'HGB', 'HCT',
      'MCV', 'MCH', 'MCHC', 'RDW_CV', 'RDW_SD',
      'PLT', 'MPV', 'PDW_CV', 'PDW_SD',
      'PCT', 'P_LCC', 'P_LCR'
    ];

    for (const code of expectedParams) {
      assert.ok(content.includes(`code = '${code}'`), `Migration 00126 must configure reference range for parameter '${code}'`);
    }
  });

  await t.test('2. Exact Approved Reference Range Values & Sex-Specific Definitions', () => {
    const content = fs.readFileSync(mig126Path, 'utf8');

    // Sex-Specific Parameters (3)
    // RBC: Male 4.5 - 5.9, Female 4.0 - 5.2 (10^12/L)
    assert.ok(content.includes("'Male'") && content.includes('4.5, 5.9') && content.includes("'10^12/L'"), 'RBC Male range must be 4.5-5.9 10^12/L');
    assert.ok(content.includes("'Female'") && content.includes('4.0, 5.2') && content.includes("'10^12/L'"), 'RBC Female range must be 4.0-5.2 10^12/L');

    // HGB: Male 13.0 - 17.0, Female 12.0 - 15.5 (g/dL)
    assert.ok(content.includes("'Male'") && content.includes('13.0, 17.0') && content.includes("'g/dL'"), 'HGB Male range must be 13.0-17.0 g/dL');
    assert.ok(content.includes("'Female'") && content.includes('12.0, 15.5') && content.includes("'g/dL'"), 'HGB Female range must be 12.0-15.5 g/dL');

    // HCT: Male 40.0 - 50.0, Female 36.0 - 46.0 (%)
    assert.ok(content.includes("'Male'") && content.includes('40.0, 50.0') && content.includes("'%'"), 'HCT Male range must be 40.0-50.0 %');
    assert.ok(content.includes("'Female'") && content.includes('36.0, 46.0') && content.includes("'%'"), 'HCT Female range must be 36.0-46.0 %');

    // Adult Generic Parameters (21)
    const genericExpected = [
      { code: 'WBC', min: '4.0', max: '11.0', unit: '10^9/L' },
      { code: 'LYM_ABS', min: '1.0', max: '3.0', unit: '10^9/L' },
      { code: 'MID_ABS', min: '0.2', max: '0.8', unit: '10^9/L' },
      { code: 'GRAN_ABS', min: '2.0', max: '7.0', unit: '10^9/L' },
      { code: 'LYM_PERCENT', min: '20.0', max: '40.0', unit: '%' },
      { code: 'MID_PERCENT', min: '2.0', max: '10.0', unit: '%' },
      { code: 'GRAN_PERCENT', min: '40.0', max: '70.0', unit: '%' },
      { code: 'NLR', min: '1.0', max: '3.0', unit: 'Ratio' },
      { code: 'PLR', min: '100.0', max: '200.0', unit: 'Ratio' },
      { code: 'MCV', min: '80.0', max: '100.0', unit: 'fL' },
      { code: 'MCH', min: '27.0', max: '32.0', unit: 'pg' },
      { code: 'MCHC', min: '31.5', max: '35.0', unit: 'g/dL' },
      { code: 'RDW_CV', min: '11.5', max: '14.5', unit: '%' },
      { code: 'RDW_SD', min: '39.0', max: '46.0', unit: 'fL' },
      { code: 'PLT', min: '150.0', max: '450.0', unit: '10^9/L' },
      { code: 'MPV', min: '6.5', max: '12.0', unit: 'fL' },
      { code: 'PDW_CV', min: '9.0', max: '17.0', unit: '%' },
      { code: 'PDW_SD', min: '9.0', max: '17.0', unit: 'fL' },
      { code: 'PCT', min: '0.100', max: '0.500', unit: '%' },
      { code: 'P_LCC', min: '30.0', max: '90.0', unit: '10^9/L' },
      { code: 'P_LCR', min: '19.7', max: '42.4', unit: '%' }
    ];

    for (const exp of genericExpected) {
      assert.ok(
        content.includes(exp.code) && content.includes(exp.min) && content.includes(exp.max),
        `Generic parameter ${exp.code} must have range ${exp.min} - ${exp.max}`
      );
    }
  });

  await t.test('3. Reference Range Resolution & Patient Sex Selection Engine', () => {
    // Simulated DB reference ranges for RBC, HGB, and WBC
    const simulatedRanges = [
      {
        id: 'rr-rbc-m',
        parameter_id: 'param-rbc',
        gender: 'Male',
        age_min_days: 0,
        age_max_days: 43800,
        normal_min: 4.5,
        normal_max: 5.9,
        normal_text: '4.5 - 5.9 10^12/L',
        unit: '10^12/L',
        is_active: true,
        is_approved: true
      },
      {
        id: 'rr-rbc-f',
        parameter_id: 'param-rbc',
        gender: 'Female',
        age_min_days: 0,
        age_max_days: 43800,
        normal_min: 4.0,
        normal_max: 5.2,
        normal_text: '4.0 - 5.2 10^12/L',
        unit: '10^12/L',
        is_active: true,
        is_approved: true
      },
      {
        id: 'rr-wbc-all',
        parameter_id: 'param-wbc',
        gender: 'All',
        age_min_days: 0,
        age_max_days: 43800,
        normal_min: 4.0,
        normal_max: 11.0,
        normal_text: '4.0 - 11.0 10^9/L',
        unit: '10^9/L',
        is_active: true,
        is_approved: true
      }
    ];

    // Male adult (30 years = 10950 days)
    const maleRbc = resolvePatientReferenceRange(
      simulatedRanges.filter((r) => r.parameter_id === 'param-rbc'),
      10950,
      'Male'
    );
    assert.equal(maleRbc?.gender, 'Male');
    assert.equal(maleRbc?.normal_min, 4.5);
    assert.equal(maleRbc?.normal_max, 5.9);
    assert.equal(formatReferenceRangeText(maleRbc), '4.5 - 5.9 10^12/L');

    // Female adult (30 years = 10950 days)
    const femaleRbc = resolvePatientReferenceRange(
      simulatedRanges.filter((r) => r.parameter_id === 'param-rbc'),
      10950,
      'Female'
    );
    assert.equal(femaleRbc?.gender, 'Female');
    assert.equal(femaleRbc?.normal_min, 4.0);
    assert.equal(femaleRbc?.normal_max, 5.2);
    assert.equal(formatReferenceRangeText(femaleRbc), '4.0 - 5.2 10^12/L');

    // Generic parameter WBC (Male and Female resolve to same 'All' range)
    const maleWbc = resolvePatientReferenceRange(
      simulatedRanges.filter((r) => r.parameter_id === 'param-wbc'),
      10950,
      'Male'
    );
    const femaleWbc = resolvePatientReferenceRange(
      simulatedRanges.filter((r) => r.parameter_id === 'param-wbc'),
      10950,
      'Female'
    );
    assert.equal(maleWbc?.normal_min, 4.0);
    assert.equal(maleWbc?.normal_max, 11.0);
    assert.equal(femaleWbc?.normal_min, 4.0);
    assert.equal(femaleWbc?.normal_max, 11.0);
  });

  await t.test('4. Abnormal Flagging with Approved Adult CBC Ranges', () => {
    const hgbFemaleRange = {
      parameter_id: 'param-hgb',
      gender: 'Female',
      age_min_days: 0,
      age_max_days: 43800,
      normal_min: 12.0,
      normal_max: 15.5,
      is_active: true,
      is_approved: true
    };

    // Normal: 13.5
    assert.deepEqual(evaluateResultFlag('13.5', 'Numeric', hgbFemaleRange), { flag: 'Normal', isCritical: false });
    // Low: 10.5
    assert.deepEqual(evaluateResultFlag('10.5', 'Numeric', hgbFemaleRange), { flag: 'L', isCritical: false });
    // High: 16.2
    assert.deepEqual(evaluateResultFlag('16.2', 'Numeric', hgbFemaleRange), { flag: 'H', isCritical: false });
  });

  await t.test('5. Critical Identity Isolation (Plateletcrit vs Procalcitonin, Manual vs Auto Diff)', () => {
    const content = fs.readFileSync(mig126Path, 'utf8');

    // Verify CBC Plateletcrit uses code 'PCT' and unit '%'
    assert.ok(content.includes("code = 'PCT'") && content.includes("'0.100 - 0.500 %'"));

    // Verify no mention of PCT_SEPSIS or ng/mL under CBC PCT
    assert.ok(!content.includes("code = 'PCT_SEPSIS'"), '00126 must not alter PCT_SEPSIS');

    // Verify manual differential codes are NOT present in 00126
    const manualCodes = ['HEM-0015', 'HEM-0016', 'HEM-0017', 'HEM-0018', 'HEM-0019', 'HEM-0020', 'HEM-0021', 'HEM-0022'];
    for (const mc of manualCodes) {
      assert.ok(!content.includes(`'${mc}'`), `00126 must not contain manual microscopy code ${mc}`);
    }
  });

  await t.test('6. Non-Destructive Invariant on Billing & Historical Data', () => {
    const content = fs.readFileSync(mig126Path, 'utf8');

    // Must NOT alter rates or bills
    assert.ok(!content.includes('catalogue_rate_versions'), '00126 must not mutate catalogue_rate_versions');
    assert.ok(!content.includes('public.bills'), '00126 must not mutate bills');
    assert.ok(!content.includes('public.diagnostic_reports'), '00126 must not mutate diagnostic_reports');
  });

});
