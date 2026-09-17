import NepaliDatePackage from 'nepali-date-converter';

// The package publishes CommonJS plus declarations; normalize its ESM interop shape.
const NepaliDate = ((NepaliDatePackage as unknown as { default?: typeof NepaliDatePackage }).default ?? NepaliDatePackage);

export const NEPAL_TIME_ZONE = 'Asia/Kathmandu';
export const NEPAL_UTC_OFFSET = '+05:45';
const NEPAL_OFFSET_MS = (5 * 60 + 45) * 60 * 1000;

export const BS_MONTH_NAMES = [
  'बैशाख', 'जेठ', 'असार', 'साउन', 'भदौ', 'असोज',
  'कात्तिक', 'मंसिर', 'पुस', 'माघ', 'फागुन', 'चैत',
] as const;
const AD_MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as const;
const AD_MONTH_LONG_NAMES = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'] as const;

type DateInput = string | number | Date | null | undefined;
type CalendarParts = { year: number; month: number; day: number };
const nepalPartsFormatter = new Intl.DateTimeFormat('en-CA-u-nu-latn', {
  timeZone: NEPAL_TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
});

function parseDateOnly(value: string): CalendarParts | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
  if (!match) return null;
  const parts = { year: Number(match[1]), month: Number(match[2]), day: Number(match[3]) };
  const check = new Date(Date.UTC(parts.year, parts.month - 1, parts.day));
  return check.getUTCFullYear() === parts.year && check.getUTCMonth() === parts.month - 1 && check.getUTCDate() === parts.day ? parts : null;
}

function getZonedParts(value: DateInput = new Date()): (CalendarParts & { hour: number; minute: number; second: number }) | null {
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value.trim())) {
    const date = parseDateOnly(value);
    return date ? { ...date, hour: 0, minute: 0, second: 0 } : null;
  }
  if (value == null) return null;
  const instant = value instanceof Date ? new Date(value.getTime()) : new Date(value);
  if (Number.isNaN(instant.getTime())) return null;
  const values: Record<string, number> = {};
  for (const part of nepalPartsFormatter.formatToParts(instant)) if (part.type !== 'literal') values[part.type] = Number(part.value);
  return { year: values.year, month: values.month, day: values.day, hour: values.hour, minute: values.minute, second: values.second };
}

function formatAdParts(parts: CalendarParts): string {
  return `${parts.day} ${AD_MONTH_NAMES[parts.month - 1]} ${parts.year}`;
}

function formatClock(hour: number, minute: number): string {
  return `${String(hour % 12 || 12).padStart(2, '0')}:${String(minute).padStart(2, '0')} ${hour >= 12 ? 'PM' : 'AM'}`;
}

export function toNepaliDigits(input: string | number): string {
  return String(input).replace(/[0-9]/g, (digit) => '०१२३४५६७८९'[Number(digit)]);
}

function parseStoredBsDate(value: string): CalendarParts | null {
  if (!/\sBS\s*$/i.test(value) && !/[०-९]/.test(value)) return null;
  const normalized = value.replace(/[०-९]/g, (digit) => String('०१२३४५६७८९'.indexOf(digit))).replace(/\s*BS\s*$/i, '').trim();
  const match = /^(20\d{2})[-/]([01]?\d)[-/]([0-3]?\d)$/.exec(normalized);
  return match ? { year: Number(match[1]), month: Number(match[2]), day: Number(match[3]) } : null;
}

export function adToBs(value: DateInput): CalendarParts | null {
  const ad = getZonedParts(value);
  if (!ad) return null;
  try {
    // The converter reads local calendar fields. Feeding the extracted Nepal Y/M/D as
    // local fields keeps the conversion identical on every device timezone.
    const converted = NepaliDate.fromAD(new Date(ad.year, ad.month - 1, ad.day)).getBS();
    return { year: converted.year, month: converted.month + 1, day: converted.date };
  } catch { return null; }
}

export function formatAdDate(value: DateInput): string {
  const parts = getZonedParts(value);
  return parts ? formatAdParts(parts) : '-';
}
export function formatAdDateTime(value: DateInput): string {
  const parts = getZonedParts(value);
  return parts ? `${formatAdParts(parts)}, ${formatClock(parts.hour, parts.minute)}` : '-';
}
export function formatBsDate(value: DateInput): string {
  const bs = typeof value === 'string' ? parseStoredBsDate(value) ?? adToBs(value) : adToBs(value);
  return bs && bs.month >= 1 && bs.month <= 12 ? `${toNepaliDigits(bs.year)} ${BS_MONTH_NAMES[bs.month - 1]} ${toNepaliDigits(bs.day)}` : '-';
}
export function formatBsDateIso(value: DateInput = new Date()): string {
  const bs = adToBs(value);
  return bs ? `${bs.year}-${String(bs.month).padStart(2, '0')}-${String(bs.day).padStart(2, '0')} BS` : '';
}
export function formatBsDateTime(value: DateInput): string {
  const bs = formatBsDate(value); const parts = getZonedParts(value);
  return bs === '-' || !parts ? bs : `${bs}, ${formatClock(parts.hour, parts.minute)}`;
}
export function formatDualDate(value: DateInput, storedBsDate?: string | null): string {
  const ad = formatAdDate(value);
  const convertedBs = formatBsDate(value);
  const bs = convertedBs === '-' && storedBsDate ? formatBsDate(storedBsDate) : convertedBs;
  return ad === '-' || bs === '-' ? ad : `${ad} / ${bs}`;
}
export function formatDualDateTime(value: DateInput, storedBsDate?: string | null): string {
  const ad = formatAdDateTime(value);
  const convertedBs = formatBsDate(value);
  const bs = convertedBs === '-' && storedBsDate ? formatBsDate(storedBsDate) : convertedBs;
  return ad === '-' || bs === '-' ? ad : `${ad} / ${bs}`;
}

export function getNepalDayBounds(value: DateInput = new Date()): { startIso: string; endExclusiveIso: string; dateAd: string } {
  const parts = getZonedParts(value); if (!parts) throw new Error('Invalid date for Nepal day bounds');
  const startMs = Date.UTC(parts.year, parts.month - 1, parts.day) - NEPAL_OFFSET_MS;
  return { startIso: new Date(startMs).toISOString(), endExclusiveIso: new Date(startMs + 86400000).toISOString(), dateAd: `${parts.year}-${String(parts.month).padStart(2, '0')}-${String(parts.day).padStart(2, '0')}` };
}
export function getNepalMonthBounds(value: DateInput = new Date()): { startIso: string; endExclusiveIso: string; label: string } {
  const parts = getZonedParts(value); if (!parts) throw new Error('Invalid date for Nepal month bounds');
  return { startIso: new Date(Date.UTC(parts.year, parts.month - 1, 1) - NEPAL_OFFSET_MS).toISOString(), endExclusiveIso: new Date(Date.UTC(parts.year, parts.month, 1) - NEPAL_OFFSET_MS).toISOString(), label: `${AD_MONTH_LONG_NAMES[parts.month - 1]} ${parts.year}` };
}
export function getNepalMonthBoundsFromKey(monthKey: string): { startIso: string; endExclusiveIso: string; label: string } {
  const match = /^(\d{4})-(\d{2})$/.exec(monthKey);
  if (!match) throw new Error('Month must use YYYY-MM format');
  const year = Number(match[1]); const month = Number(match[2]);
  if (month < 1 || month > 12) throw new Error('Month must use YYYY-MM format');
  return {
    startIso: new Date(Date.UTC(year, month - 1, 1) - NEPAL_OFFSET_MS).toISOString(),
    endExclusiveIso: new Date(Date.UTC(year, month, 1) - NEPAL_OFFSET_MS).toISOString(),
    label: `${AD_MONTH_LONG_NAMES[month - 1]} ${year}`,
  };
}
export function getNepalCurrentMonthKey(value: DateInput = new Date()): string {
  const parts = getZonedParts(value); if (!parts) throw new Error('Invalid date');
  return `${parts.year}-${String(parts.month).padStart(2, '0')}`;
}
export function getNepalDateBoundaries(value: DateInput = new Date()) {
  const day = getNepalDayBounds(value); const month = getNepalMonthBounds(value);
  return { todayStartIso: day.startIso, todayEndExclusiveIso: day.endExclusiveIso, monthStartIso: month.startIso, monthEndExclusiveIso: month.endExclusiveIso, currentMonthLabel: month.label };
}
export function getNepalTodayAd(value: DateInput = new Date()): string { return getNepalDayBounds(value).dateAd; }
export function formatNepalIso(value: DateInput): string {
  const p = getZonedParts(value); if (!p) return '';
  return `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}T${String(p.hour).padStart(2, '0')}:${String(p.minute).padStart(2, '0')}:${String(p.second).padStart(2, '0')}${NEPAL_UTC_OFFSET}`;
}

export function calculateAgeFromDob(dob: string | Date, asOf: DateInput = new Date()) {
  const birth = getZonedParts(dob); const current = getZonedParts(asOf);
  if (!birth || !current) return { years: 0, months: 0, days: 0 };
  let years = current.year - birth.year; let months = current.month - birth.month; let days = current.day - birth.day;
  if (days < 0) { months -= 1; days += new Date(Date.UTC(current.year, current.month - 1, 0)).getUTCDate(); }
  if (months < 0) { years -= 1; months += 12; }
  return { years: Math.max(0, years), months: Math.max(0, months), days: Math.max(0, days) };
}
export function formatAge(years?: number | null, months?: number | null, days?: number | null): string {
  if (years != null && years > 0) return `${years} Y`;
  if (months != null && months > 0) return `${months} M`;
  if (days != null && days > 0) return `${days} D`;
  if (years === 0 || months === 0 || days === 0) return '0 Y';
  return '-';
}

export const formatNepaliBsDate = formatBsDate;
export const formatAdDateTimeReport = formatAdDateTime;
export function getApproximateBsDate(value: Date = new Date()): string {
  return formatBsDateIso(value) || '-';
}
