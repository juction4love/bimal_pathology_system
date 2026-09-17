export const MIN_SEC_PATTERN = /^\d{1,3}:[0-5]\d$/;

export function validateMinSec(value: string): string | null {
  const normalized = value.trim();
  if (!normalized) return null;
  return MIN_SEC_PATTERN.test(normalized) ? null : 'Use Min:Sec format, for example 4:30. Seconds must be 00–59.';
}
