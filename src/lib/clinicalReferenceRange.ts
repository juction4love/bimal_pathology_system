/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Clinical Reference Range Resolver & Abnormal Flag Engine
 * Shared across Result Entry, Verification, Report Snapshots, and PDF rendering.
 */

import { RESULT_FLAGS, ResultFlag } from '../config/constants';

export interface DbReferenceRange {
  id?: string;
  parameter_id: string;
  gender: string; // 'All' | 'Male' | 'Female'
  age_min_days: number;
  age_max_days: number;
  normal_min?: number | null;
  normal_max?: number | null;
  critical_low?: number | null;
  critical_high?: number | null;
  normal_text?: string | null;
  reference_text?: string | null;
  unit?: string | null;
  method?: string | null;
  effective_from?: string | null;
  effective_to?: string | null;
  is_active?: boolean;
  is_approved?: boolean;
  approved_by?: string | null;
  approved_at?: string | null;
}

/**
 * Validate a reference range record:
 * - min <= max
 * - critical_low <= normal_min when both exist
 * - critical_high >= normal_max when both exist
 * - age_min_days <= age_max_days
 */
export function validateReferenceRange(range: Partial<DbReferenceRange>): { isValid: boolean; error?: string } {
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

/**
 * Check if a new/edited range overlaps with existing active ranges for the same parameter and gender
 */
export function checkRangeOverlap(
  existingRanges: DbReferenceRange[],
  target: Partial<DbReferenceRange>,
  currentId?: string
): { hasOverlap: boolean; overlappingWith?: DbReferenceRange } {
  const targetGender = target.gender || 'All';
  const targetMin = target.age_min_days ?? 0;
  const targetMax = target.age_max_days ?? 43800;

  for (const ex of existingRanges) {
    if (currentId && ex.id === currentId) continue;
    if (ex.is_active === false) continue;

    // Check same or intersecting gender
    const genderMatch = ex.gender === targetGender || ex.gender === 'All' || targetGender === 'All';
    if (genderMatch && ex.gender === targetGender) {
      // Direct age interval overlap: max(min1, min2) <= min(max1, max2)
      const overlap = Math.max(targetMin, ex.age_min_days) <= Math.min(targetMax, ex.age_max_days);
      if (overlap) {
        return { hasOverlap: true, overlappingWith: ex };
      }
    }
  }
  return { hasOverlap: false };
}

/**
 * Resolve the narrowest applicable reference range for a patient:
 * - Must be active and approved (is_active !== false, is_approved !== false)
 * - Age-specific (days)
 * - Sex-specific (Exact gender prioritized over 'All')
 * - Narrowest age interval
 */
export function resolvePatientReferenceRange(
  ranges: DbReferenceRange[],
  patientAgeDays: number,
  patientGender: string
): DbReferenceRange | null {
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

  // 1. Try exact gender match
  const exactGender = matchingAge.filter(
    (r) => r.gender.toLowerCase() === normalizedGender.toLowerCase()
  );

  const candidatePool = exactGender.length > 0 ? exactGender : matchingAge.filter((r) => r.gender === 'All');
  if (candidatePool.length === 0) return null;

  // 2. Select narrowest age interval (age_max_days - age_min_days)
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

/**
 * Format reference range string strictly following priority rules:
 * a. reference_text if explicitly configured
 * b. numeric min-max: "12.0 - 16.0"
 * c. one-sided ranges: "< 200" or "> 40"
 * d. qualitative normal: "Negative" / normal_text
 * e. no configured range: "Not configured"
 */
export function formatReferenceRangeText(range?: DbReferenceRange | {
  reference_text?: string | null;
  normal_text?: string | null;
  normal_min?: number | null;
  normal_max?: number | null;
} | null): string {
  if (!range) return 'Not configured';

  // a. reference_text if explicitly configured
  if (range.reference_text && range.reference_text.trim().length > 0) {
    return range.reference_text.trim();
  }

  const hasMin = range.normal_min !== null && range.normal_min !== undefined;
  const hasMax = range.normal_max !== null && range.normal_max !== undefined;

  // b. numeric min-max: "12.0 - 16.0"
  if (hasMin && hasMax) {
    return `${range.normal_min} - ${range.normal_max}`;
  }

  // c. one-sided ranges: "< 200" or "> 40"
  if (!hasMin && hasMax) {
    return `< ${range.normal_max}`;
  }
  if (hasMin && !hasMax) {
    return `> ${range.normal_min}`;
  }

  // d. qualitative normal: "Negative"
  if (range.normal_text && range.normal_text.trim().length > 0) {
    return range.normal_text.trim();
  }

  // e. no configured range
  return 'Not configured';
}

/**
 * Evaluate abnormal / critical flag based on resolved range:
 * - Numeric / Calculated values checked against critical_low/high, normal_min/max
 * - Qualitative values checked against normal_text
 * - If no range exists or normal: flag is 'Normal'
 */
export function evaluateResultFlag(
  valueStr: string,
  valueType: string,
  range?: DbReferenceRange | null
): { flag: ResultFlag; isCritical: boolean } {
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

  // Qualitative comparison
  if (range.normal_text && range.normal_text.trim().length > 0) {
    if (valueStr.trim().toLowerCase() !== range.normal_text.trim().toLowerCase()) {
      return { flag: RESULT_FLAGS.ABNORMAL, isCritical: false };
    }
  }

  return { flag: RESULT_FLAGS.NORMAL, isCritical: false };
}
