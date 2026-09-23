/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Automated Verification Suite for Reference Range Setup, Validation, Approval & Flag Engine
 */

const RESULT_FLAGS = {
  NORMAL: 'Normal',
  LOW: 'Low',
  HIGH: 'High',
  CRITICAL_LOW: 'CriticalLow',
  CRITICAL_HIGH: 'CriticalHigh',
  ABNORMAL: 'Abnormal',
  NO_RANGE: 'NoRange',
};

function validateReferenceRange(range) {
  if (range.age_min_days !== undefined && range.age_max_days !== undefined) {
    if (range.age_min_days > range.age_max_days) {
      return { isValid: false, error: `Age Min (${range.age_min_days} days) cannot exceed Age Max (${range.age_max_days} days).` };
    }
  }

  const hasMin = range.normal_min !== null && range.normal_min !== undefined;
  const hasMax = range.normal_max !== null && range.normal_max !== undefined;

  if (hasMin && hasMax && Number(range.normal_min) > Number(range.normal_max)) {
    return { isValid: false, error: `Normal Min (${range.normal_min}) cannot be greater than Normal Max (${range.normal_max}).` };
  }

  if (hasMin && range.critical_low !== null && range.critical_low !== undefined) {
    if (Number(range.critical_low) > Number(range.normal_min)) {
      return { isValid: false, error: `Critical Low (${range.critical_low}) cannot be higher than Normal Min (${range.normal_min}).` };
    }
  }

  if (hasMax && range.critical_high !== null && range.critical_high !== undefined) {
    if (Number(range.critical_high) < Number(range.normal_max)) {
      return { isValid: false, error: `Critical High (${range.critical_high}) cannot be lower than Normal Max (${range.normal_max}).` };
    }
  }

  return { isValid: true };
}

function checkRangeOverlap(existingRanges, target, currentId) {
  const targetGender = target.gender || 'All';
  const targetMin = target.age_min_days ?? 0;
  const targetMax = target.age_max_days ?? 43800;

  for (const ex of existingRanges) {
    if (currentId && ex.id === currentId) continue;
    if (ex.is_active === false) continue;

    const genderMatch = ex.gender === targetGender || ex.gender === 'All' || targetGender === 'All';
    if (genderMatch && ex.gender === targetGender) {
      const overlap = Math.max(targetMin, ex.age_min_days) <= Math.min(targetMax, ex.age_max_days);
      if (overlap) {
        return { hasOverlap: true, overlappingWith: ex };
      }
    }
  }
  return { hasOverlap: false };
}

function resolvePatientReferenceRange(ranges, patientAgeDays, patientGender) {
  if (!ranges || ranges.length === 0) return null;

  // Filter ONLY active and approved ranges
  const approvedRanges = ranges.filter(
    (r) => r.is_active !== false && r.is_approved !== false
  );
  if (approvedRanges.length === 0) return null;

  const normalizedGender = (patientGender || 'All').trim();
  const matchingAge = approvedRanges.filter(
    (r) => r.age_min_days <= patientAgeDays && r.age_max_days >= patientAgeDays
  );

  if (matchingAge.length === 0) return null;

  const exactGender = matchingAge.filter(
    (r) => r.gender.toLowerCase() === normalizedGender.toLowerCase()
  );

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

function formatReferenceRangeText(range) {
  if (!range) return '—';

  if (range.reference_text && range.reference_text.trim().length > 0) {
    return range.reference_text.trim();
  }

  const hasMin = range.normal_min !== null && range.normal_min !== undefined;
  const hasMax = range.normal_max !== null && range.normal_max !== undefined;

  if (hasMin && hasMax) {
    return `${range.normal_min} - ${range.normal_max}`;
  }

  if (!hasMin && hasMax) {
    return `< ${range.normal_max}`;
  }
  if (hasMin && !hasMax) {
    return `> ${range.normal_min}`;
  }

  if (range.normal_text && range.normal_text.trim().length > 0) {
    return range.normal_text.trim();
  }

  return '—';
}

function evaluateResultFlag(valueStr, valueType, range) {
  if (!valueStr || valueStr.trim() === '' || !range) {
    return { flag: RESULT_FLAGS.NORMAL, isCritical: false };
  }

  if (valueType === 'Numeric' || valueType === 'Calculated') {
    const num = parseFloat(valueStr);
    if (isNaN(num)) {
      return { flag: RESULT_FLAGS.NORMAL, isCritical: false };
    }

    const { critical_low, critical_high, normal_min, normal_max } = range;

    if (critical_low !== null && critical_low !== undefined && num <= critical_low) {
      return { flag: RESULT_FLAGS.CRITICAL_LOW, isCritical: true };
    }
    if (critical_high !== null && critical_high !== undefined && num >= critical_high) {
      return { flag: RESULT_FLAGS.CRITICAL_HIGH, isCritical: true };
    }
    if (normal_min !== null && normal_min !== undefined && num < normal_min) {
      return { flag: RESULT_FLAGS.LOW, isCritical: false };
    }
    if (normal_max !== null && normal_max !== undefined && num > normal_max) {
      return { flag: RESULT_FLAGS.HIGH, isCritical: false };
    }
    return { flag: RESULT_FLAGS.NORMAL, isCritical: false };
  }

  if (range.normal_text && range.normal_text.trim().length > 0) {
    if (valueStr.trim().toLowerCase() !== range.normal_text.trim().toLowerCase()) {
      return { flag: RESULT_FLAGS.ABNORMAL, isCritical: false };
    }
  }

  return { flag: RESULT_FLAGS.NORMAL, isCritical: false };
}

function formatResultFlag(flag) {
  switch (flag) {
    case 'CriticalLow':
      return { label: 'LL', isAbnormal: true, isCritical: true };
    case 'CriticalHigh':
      return { label: 'HH', isAbnormal: true, isCritical: true };
    case 'Low':
      return { label: 'L', isAbnormal: true, isCritical: false };
    case 'High':
      return { label: 'H', isAbnormal: true, isCritical: false };
    case 'Abnormal':
      return { label: 'A', isAbnormal: true, isCritical: false };
    case 'NoRange':
    case 'Normal':
    default:
      return { label: '', isAbnormal: false, isCritical: false };
  }
}

let passed = 0;
let failed = 0;

function assert(condition, code, desc) {
  if (condition) {
    console.log(`  ✅ [PASS] ${code}: ${desc}`);
    passed++;
  } else {
    console.error(`  ❌ [FAIL] ${code}: ${desc}`);
    failed++;
  }
}

console.log('================================================================');
console.log(' REFERENCE RANGE SETUP, VALIDATION & APPROVAL SUITE');
console.log('================================================================\n');

// 1. Parameter without range -> "—"
const unconfiguredText = formatReferenceRangeText(null);
assert(unconfiguredText === '—', '1. UnconfiguredRange', 'Parameter without range resolves to "—"');

// 2. Configured numeric min-max range
const numericRange = {
  parameter_id: 'p1',
  gender: 'All',
  age_min_days: 0,
  age_max_days: 43800,
  normal_min: 12.0,
  normal_max: 16.0,
  is_active: true,
  is_approved: true,
};
const numericText = formatReferenceRangeText(numericRange);
assert(numericText === '12 - 16' || numericText === '12.0 - 16.0', '2. NumericRange', `Numeric min-max formats properly: "${numericText}"`);

// 3. One-sided ranges (< 200, > 40)
const maxOnlyRange = { parameter_id: 'p2', gender: 'All', age_min_days: 0, age_max_days: 43800, normal_max: 200, is_active: true, is_approved: true };
assert(formatReferenceRangeText(maxOnlyRange) === '< 200', '3. OneSidedMax', 'One-sided upper limit formats as "< 200"');

const minOnlyRange = { parameter_id: 'p3', gender: 'All', age_min_days: 0, age_max_days: 43800, normal_min: 40, is_active: true, is_approved: true };
assert(formatReferenceRangeText(minOnlyRange) === '> 40', '4. OneSidedMin', 'One-sided lower limit formats as "> 40"');

// 4. Qualitative normal range (e.g. "Negative")
const qualitativeRange = { parameter_id: 'p4', gender: 'All', age_min_days: 0, age_max_days: 43800, normal_text: 'Negative', is_active: true, is_approved: true };
assert(formatReferenceRangeText(qualitativeRange) === 'Negative', '5. QualitativeText', 'Qualitative range formats as "Negative"');

// 5. Explicit reference_text override
const explicitRange = { parameter_id: 'p5', gender: 'All', age_min_days: 0, age_max_days: 43800, reference_text: 'Desirable: < 200, Borderline: 200-239', is_active: true, is_approved: true };
assert(formatReferenceRangeText(explicitRange) === 'Desirable: < 200, Borderline: 200-239', '6. ExplicitText', 'Explicit reference_text takes top priority');

// 6. Age & Sex resolution (narrowest applicable range, exact gender before All)
const multiRanges = [
  { parameter_id: 'hb', gender: 'All', age_min_days: 0, age_max_days: 43800, normal_min: 11.5, normal_max: 17.5, is_active: true, is_approved: true },
  { parameter_id: 'hb', gender: 'Male', age_min_days: 5475, age_max_days: 43800, normal_min: 13.0, normal_max: 17.0, is_active: true, is_approved: true },
  { parameter_id: 'hb', gender: 'Female', age_min_days: 5475, age_max_days: 43800, normal_min: 12.0, normal_max: 15.0, is_active: true, is_approved: true },
  { parameter_id: 'hb', gender: 'All', age_min_days: 0, age_max_days: 30, normal_min: 14.0, normal_max: 24.0, is_active: true, is_approved: true },
];

const adultMale = resolvePatientReferenceRange(multiRanges, 30 * 365, 'Male');
assert(adultMale?.normal_min === 13.0 && adultMale?.normal_max === 17.0, '7. AdultMaleResolution', 'Adult male resolves exact gender & age range: 13.0 - 17.0');

const adultFemale = resolvePatientReferenceRange(multiRanges, 30 * 365, 'Female');
assert(adultFemale?.normal_min === 12.0 && adultFemale?.normal_max === 15.0, '8. AdultFemaleResolution', 'Adult female resolves exact gender & age range: 12.0 - 15.0');

const newborn = resolvePatientReferenceRange(multiRanges, 5, 'Male');
assert(newborn?.normal_min === 14.0 && newborn?.normal_max === 24.0, '9. NewbornResolution', 'Newborn resolves narrowest neonatal range: 14.0 - 24.0');

// 7. Flag evaluation & Badge formatting (NO badge for Normal)
const cbcRange = {
  parameter_id: 'hb',
  gender: 'All',
  age_min_days: 0,
  age_max_days: 43800,
  normal_min: 12.0,
  normal_max: 16.0,
  critical_low: 7.0,
  critical_high: 20.0,
  is_active: true,
  is_approved: true,
};

const normalRes = evaluateResultFlag('14.0', 'Numeric', cbcRange);
assert(normalRes.flag === RESULT_FLAGS.NORMAL && formatResultFlag(normalRes.flag).label === '', '10. NormalNoBadge', 'Normal result has NO Normal badge rendered');

const lowRes = evaluateResultFlag('10.5', 'Numeric', cbcRange);
assert(lowRes.flag === RESULT_FLAGS.LOW && formatResultFlag(lowRes.flag).label === 'L', '11. LowFlag', 'Low result generates flag "L"');

const highRes = evaluateResultFlag('17.5', 'Numeric', cbcRange);
assert(highRes.flag === RESULT_FLAGS.HIGH && formatResultFlag(highRes.flag).label === 'H', '12. HighFlag', 'High result generates flag "H"');

const critLowRes = evaluateResultFlag('5.5', 'Numeric', cbcRange);
assert(critLowRes.flag === RESULT_FLAGS.CRITICAL_LOW && formatResultFlag(critLowRes.flag).label === 'LL', '13. CriticalLowFlag', 'Critical low result generates flag "LL"');

const critHighRes = evaluateResultFlag('22.0', 'Numeric', cbcRange);
assert(critHighRes.flag === RESULT_FLAGS.CRITICAL_HIGH && formatResultFlag(critHighRes.flag).label === 'HH', '14. CriticalHighFlag', 'Critical high result generates flag "HH"');

const serologyRange = { parameter_id: 'hiv', gender: 'All', age_min_days: 0, age_max_days: 43800, normal_text: 'Non-Reactive', is_active: true, is_approved: true };
const abnQualRes = evaluateResultFlag('Reactive', 'Text', serologyRange);
assert(abnQualRes.flag === RESULT_FLAGS.ABNORMAL && formatResultFlag(abnQualRes.flag).label === 'A', '15. AbnormalQualFlag', 'Qualitative mismatch generates flag "A"');

// 8. Approval Enforcement: Unapproved / Inactive ranges are rejected from production
const unapprovedRanges = [
  { parameter_id: 'glu', gender: 'All', age_min_days: 0, age_max_days: 43800, normal_min: 70, normal_max: 100, is_active: true, is_approved: false },
  { parameter_id: 'glu', gender: 'All', age_min_days: 0, age_max_days: 43800, normal_min: 60, normal_max: 90, is_active: false, is_approved: true },
];
const unapprovedResolved = resolvePatientReferenceRange(unapprovedRanges, 25 * 365, 'Male');
assert(unapprovedResolved === null, '16. ApprovalEnforcement', 'Unapproved or inactive reference ranges are strictly excluded from patient resolution');

// 9. Range Validation Tests (min <= max, critical bounds, age bounds)
const invalidMinMax = validateReferenceRange({ normal_min: 15, normal_max: 10 });
assert(invalidMinMax.isValid === false, '17. ValidateMinMax', 'Validation rejects normal_min > normal_max');

const invalidCritLow = validateReferenceRange({ normal_min: 10, normal_max: 20, critical_low: 12 });
assert(invalidCritLow.isValid === false, '18. ValidateCriticalLow', 'Validation rejects critical_low > normal_min');

const invalidCritHigh = validateReferenceRange({ normal_min: 10, normal_max: 20, critical_high: 18 });
assert(invalidCritHigh.isValid === false, '19. ValidateCriticalHigh', 'Validation rejects critical_high < normal_max');

const invalidAge = validateReferenceRange({ age_min_days: 500, age_max_days: 100 });
assert(invalidAge.isValid === false, '20. ValidateAgeMinMax', 'Validation rejects age_min_days > age_max_days');

const validRange = validateReferenceRange({ age_min_days: 0, age_max_days: 43800, normal_min: 12, normal_max: 16, critical_low: 7, critical_high: 20 });
assert(validRange.isValid === true, '21. ValidateValidRange', 'Validation accepts structurally sound reference interval');

// 10. Range Overlap Detection
const existing = [
  { id: '1', parameter_id: 'p1', gender: 'Male', age_min_days: 0, age_max_days: 6570, is_active: true },
];
const overlappingRange = checkRangeOverlap(existing, { gender: 'Male', age_min_days: 3650, age_max_days: 10000 });
assert(overlappingRange.hasOverlap === true, '22. DetectOverlap', 'Overlap detector catches intersecting age ranges for same gender');

const nonOverlappingRange = checkRangeOverlap(existing, { gender: 'Male', age_min_days: 6571, age_max_days: 43800 });
assert(nonOverlappingRange.hasOverlap === false, '23. AllowNonOverlap', 'Overlap detector allows contiguous non-overlapping age ranges');

console.log('\n================================================================');
console.log(` SUMMARY: ${passed} PASSED, ${failed} FAILED`);
console.log('================================================================');

if (failed > 0) {
  process.exit(1);
}
