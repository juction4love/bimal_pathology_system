export interface PatientAgeInput {
  years: number | '' | null;
  months?: number | '' | null;
  days?: number | '' | null;
}

export const BLANK_PATIENT_AGE = Object.freeze({
  years: '' as const,
  months: '' as const,
  days: '' as const,
});

/**
 * Normalizes a person's name without rewriting intentional capitalization.
 * Wholly lowercase ASCII words get an initial capital; mixed-case, uppercase,
 * initials, and Unicode text are preserved apart from whitespace cleanup.
 */
export function normalizePatientName(input?: string | null): string {
  if (!input) return '';

  return input
    .trim()
    .split(/\s+/u)
    .filter(Boolean)
    .map((word) => /^[a-z][a-z'’.-]*$/.test(word)
      ? word.charAt(0).toUpperCase() + word.slice(1)
      : word)
    .join(' ');
}

/** Collapse whitespace without changing Unicode text or intentional casing. */
export function normalizePatientText(input?: string | null): string {
  return input?.trim().replace(/\s+/gu, ' ') || '';
}

/** Normalize the accepted Nepal dialing forms to the stored 10-digit form. */
export function normalizeNepalMobile(input?: string | null): string {
  let mobile = (input || '').replace(/[^0-9]/g, '');
  if (mobile.startsWith('977') && mobile.length === 13) mobile = mobile.slice(3);
  if (mobile.startsWith('0') && mobile.length === 11) mobile = mobile.slice(1);
  return mobile;
}

export function validateNepalMobile(input?: string | null): string | null {
  return /^(97|98)[0-9]{8}$/.test(normalizeNepalMobile(input))
    ? null
    : 'Please enter a valid 10-digit Nepal mobile number starting with 98 or 97.';
}

export function validatePatientAge(age: PatientAgeInput, yearsRequired: boolean): string | null {
  if (age.years == null || age.years === '') {
    return yearsRequired ? 'Please enter a valid patient age in years from 0 to 120.' : null;
  }
  if (!Number.isInteger(age.years) || age.years < 0 || age.years > 120) {
    return 'Please enter a valid patient age in years from 0 to 120.';
  }
  if (age.months != null && age.months !== '' &&
      (!Number.isInteger(age.months) || age.months < 0 || age.months > 11)) {
    return 'Patient age months must be from 0 to 11.';
  }
  if (age.days != null && age.days !== '' &&
      (!Number.isInteger(age.days) || age.days < 0 || age.days > 31)) {
    return 'Patient age days must be from 0 to 31.';
  }
  return null;
}
