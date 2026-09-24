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

/**
 * Maps standard patient titles to corresponding gender.
 * Mr. -> Male
 * Miss -> Female
 * Mrs. -> Female
 * Ms. -> Female
 * Master -> Male
 * Neutral/unmapped titles (Dr., Prof., Baby, etc.) return null (no forced gender).
 * Does NOT infer title from patient name.
 */
export function getGenderForTitle(title?: string | null): 'Male' | 'Female' | null {
  if (!title) return null;
  const lower = title.trim().toLowerCase().replace(/\.+$/, '');
  if (lower === 'mr' || lower === 'master' || lower === 'shree' || lower === 'kumar') {
    return 'Male';
  }
  if (lower === 'miss' || lower === 'mrs' || lower === 'ms' || lower === 'smt' || lower === 'shrimati' || lower === 'kumari') {
    return 'Female';
  }
  return null;
}

/**
 * Validates that title and gender are not contradictory.
 * Returns an error message if contradictory, or null if valid.
 * - Mr. + Female => invalid
 * - Miss + Male => invalid
 * - Mrs. + Male => invalid
 */
export function validatePatientTitleAndGender(
  title?: string | null,
  gender?: string | null
): string | null {
  if (!title || !gender) return null;
  const lowerTitle = title.trim().toLowerCase().replace(/\.+$/, '');
  const normGender = gender.trim().toLowerCase();

  const maleTitles = ['mr', 'master', 'shree', 'kumar'];
  const femaleTitles = ['mrs', 'ms', 'miss', 'smt', 'shrimati', 'kumari'];

  if ((normGender === 'female' || normGender === 'f') && maleTitles.includes(lowerTitle)) {
    return `Patient title "${title.trim()}" contradicts selected gender (Female).`;
  }
  if ((normGender === 'male' || normGender === 'm') && femaleTitles.includes(lowerTitle)) {
    return `Patient title "${title.trim()}" contradicts selected gender (Male).`;
  }

  return null;
}

/**
 * Formats patient display identity safely without guessed or conflicting honorifics.
 * If title conflicts with sex (e.g., 'Mr.' with Female or 'Mrs.'/'Ms.' with Male),
 * the conflicting title is omitted, returning the clean validated full name.
 * Never guesses or forces honorifics.
 */
export function formatPatientDisplayName(
  fullName?: string | null,
  title?: string | null,
  gender?: string | null
): string {
  const cleanName = (fullName || '').trim();
  if (!cleanName) return '—';
  if (!title) return cleanName;

  const rawTitle = title.trim();
  const lowerTitle = rawTitle.toLowerCase().replace(/\.+$/, '');
  const normGender = (gender || '').trim().toLowerCase();

  const maleTitles = ['mr', 'master', 'shree', 'kumar'];
  const femaleTitles = ['mrs', 'ms', 'miss', 'smt', 'shrimati', 'kumari'];

  if (normGender === 'female' || normGender === 'f') {
    if (maleTitles.includes(lowerTitle)) {
      return cleanName;
    }
  } else if (normGender === 'male' || normGender === 'm') {
    if (femaleTitles.includes(lowerTitle)) {
      return cleanName;
    }
  }

  // If the full name already starts with the title, do not repeat it
  if (cleanName.toLowerCase().startsWith(rawTitle.toLowerCase())) {
    return cleanName;
  }

  return `${rawTitle} ${cleanName}`;
}


