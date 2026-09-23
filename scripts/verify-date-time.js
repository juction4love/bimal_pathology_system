import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import {
  BS_MONTH_NAMES, NEPAL_TIME_ZONE, adToBs, formatAdDate, formatAdDateTime,
  formatBsDate, formatDualDate, formatDualDateTime, formatNepalIso,
  getNepalDayBounds, getNepalMonthBounds, getNepalTodayAd, toNepaliDigits,
} from '../src/lib/dateTime.ts';

let passed = 0;
let failed = 0;
function check(condition, name, detail) {
  if (condition) { passed += 1; console.log(`PASS ${name}: ${detail}`); }
  else { failed += 1; console.error(`FAIL ${name}: ${detail}`); }
}
const sameBs = (actual, expected) => actual?.year === expected.year && actual?.month === expected.month && actual?.day === expected.day;
const read = (path) => fs.readFileSync(path, 'utf8');

check(NEPAL_TIME_ZONE === 'Asia/Kathmandu', 'CanonicalZone', NEPAL_TIME_ZONE);
check(toNepaliDigits('0123456789') === '०१२३४५६७८९', 'NepaliDigits', 'all ten digits map exactly');
check(BS_MONTH_NAMES.join('|') === 'बैशाख|जेठ|असार|साउन|भदौ|असोज|कात्तिक|मंसिर|पुस|माघ|फागुन|चैत', 'BsMonths', 'all 12 required month names are canonical');
check(sameBs(adToBs('2023-04-14'), { year: 2080, month: 1, day: 1 }), 'KnownPair2080', '14 Apr 2023 = 2080 Baisakh 1');
check(sameBs(adToBs('2024-04-13'), { year: 2081, month: 1, day: 1 }), 'KnownPair2081', '13 Apr 2024 = 2081 Baisakh 1');
check(sameBs(adToBs('2026-08-21'), { year: 2083, month: 5, day: 5 }), 'KnownPair2083', '21 Aug 2026 = 2083 Bhadau 5');
check(sameBs(adToBs('2024-02-29'), { year: 2080, month: 11, day: 17 }), 'LeapDay', 'Gregorian leap day converts through library dataset');
check(formatBsDate('2026-08-21') === '२०८३ भदौ ५', 'ActualBsFormat', 'not an AD digit substitution');
check(formatBsDate('2083-05-03 BS') === '२०८३ भदौ ३', 'StoredBsFormat', 'explicit BS field formats without reconversion');
check(formatBsDate('2026-08-21') !== toNepaliDigits('2026-08-21'), 'NoFakeBs', 'digit-only AD output cannot pass as BS');
check(formatAdDate('2026-08-21T02:45:00Z') === '21 Aug 2026', 'AdDate', 'canonical AD date');
check(formatAdDateTime('2026-08-21T02:45:00Z') === '21 Aug 2026, 08:30 AM', 'NepalTime', 'UTC instant converts to UTC+05:45');
check(formatDualDate('2026-08-21') === '21 Aug 2026 / २०८३ भदौ ५', 'DualDate', 'AD and actual BS');
check(formatDualDate('2026-08-21', '2083-05-04 BS') === '21 Aug 2026 / २०८३ भदौ ५', 'AuthoritativeAdConversion', 'stale historical BS presentation never overrides the AD timestamp');
check(formatDualDateTime('2026-08-21T02:45:00Z') === '21 Aug 2026, 08:30 AM / २०८३ भदौ ५', 'DualDateTime', 'time remains Nepal local and BS is not repeated with time');

const beforeMidnight = getNepalDayBounds('2026-08-20T18:14:59Z');
const atMidnight = getNepalDayBounds('2026-08-20T18:15:00Z');
check(beforeMidnight.dateAd === '2026-08-20' && atMidnight.dateAd === '2026-08-21', 'NepalMidnight', 'day changes exactly at UTC 18:15');
check(atMidnight.startIso === '2026-08-20T18:15:00.000Z' && atMidnight.endExclusiveIso === '2026-08-21T18:15:00.000Z', 'FilterUtcBounds', 'selected Nepal day maps to half-open UTC bounds');
const month = getNepalMonthBounds('2026-12-15');
check(month.startIso === '2026-11-30T18:15:00.000Z' && month.endExclusiveIso === '2026-12-31T18:15:00.000Z', 'MonthBoundary', 'December bounds cross UTC dates correctly');
check(getNepalTodayAd('2025-12-31T18:14:59Z') === '2025-12-31' && getNepalTodayAd('2025-12-31T18:15:00Z') === '2026-01-01', 'YearBoundary', 'Nepal new year day boundary is deterministic');
check(formatNepalIso('2026-08-21T02:45:00Z') === '2026-08-21T08:30:00+05:45', 'CsvIsoOffset', 'machine export includes explicit Nepal offset');

const timezoneProbe = `import('./src/lib/dateTime.ts').then(d=>console.log(JSON.stringify([d.formatAdDateTime('2026-08-21T02:45:00Z'),d.formatBsDate('2026-08-21T02:45:00Z'),d.getNepalDayBounds('2026-08-21T02:45:00Z')])))`;
const outputs = ['UTC', 'America/New_York', 'Pacific/Auckland'].map((TZ) => spawnSync(process.execPath, ['-e', timezoneProbe], { cwd: process.cwd(), env: { ...process.env, TZ }, encoding: 'utf8' }).stdout.trim());
check(outputs.every((value) => value === outputs[0] && value.length > 0), 'DeviceTimezoneIndependence', 'UTC, New York and Auckland processes produce identical output');

const technician = read('src/features/dashboard/TechnicianDashboard.tsx');
const worklist = read('src/features/dashboard/PatientOrderWorklist.tsx');
const registrySearch = read('supabase/migrations_legacy_archive/00073_server_search_pagination_convergence.sql');
const billing = read('src/features/billing/BillListPage.tsx');
const samples = read('src/features/samples/SampleAccessioningPage.tsx');
const results = read('src/features/worklist/ResultEntryPage.tsx');
const report = read('src/features/reports/ReportDocument.tsx');
const audit = read('src/features/admin/AuditLogPage.tsx');
const outsource = read('src/features/outsource/OutsourceTrackingPage.tsx');
const settings = read('src/features/settings/SettingsPage.tsx');
const catalogue75 = read('supabase/migrations_legacy_archive/00075_catalogue_readiness_approval_workflow.sql');
check(technician.includes("rpc('get_technician_operational_summary'") && catalogue75.includes("now() AT TIME ZONE 'Asia/Kathmandu'"), 'DashboardToday', 'dashboard summary derives the Nepal day server-side');
check(worklist.includes("rpc('search_dashboard_orders'") && registrySearch.includes("AT TIME ZONE 'Asia/Kathmandu'"), 'WorklistToday', 'Today filter is server-authoritative in the Nepal calendar day');
check(billing.includes('formatDualDate(bill.created_at)') && billing.includes('formatAdDateTime(pt.created_at)'), 'BillingDates', 'invoice and payment history use central utility');
check(samples.includes('formatAdDateTime(sample.collected_at)') && samples.includes('formatAdDateTime(sample.rejected_at)'), 'SampleDates', 'sample lifecycle dates use central utility');
check(results.includes('formatAdDateTime(verifiedMeta.verifiedAt)') && results.includes('formatAdDateTime(existingReport.signed_at)'), 'ResultDates', 'verification and report times use central utility');
check(report.includes('formatDualDate(order.registered_date_ad, order.registered_date_bs)') && report.includes('formatAdDateTime(order.collected_at)') && report.includes('formatAdDateTime(order.reported_at)'), 'PdfDates', 'registered is dual; lifecycle timestamps are Nepal AD');
check(audit.includes('formatAdDateTime(log.timestamp)'), 'AuditDates', 'audit timestamps use central utility');
check(outsource.includes('formatAdDateTime(ev.created_at)') && outsource.includes('getNepalDayBounds'), 'OutsourceDates', 'event timeline and Today totals are Nepal-correct');
check(settings.includes('formatNepalIso(raw)') && settings.includes('(Nepal ISO +05:45)'), 'CsvDates', 'timestamp values and headers are deterministic and explicit');

const sourceFiles = fs.readdirSync('src/features', { recursive: true }).filter((file) => typeof file === 'string' && file.endsWith('.tsx'));
const unsafe = sourceFiles.flatMap((relative) => {
  const path = `src/features/${relative.replaceAll('\\', '/')}`;
  const text = read(path);
  return /toLocaleDateString|toLocaleTimeString|Intl\.DateTimeFormat|setHours\(0\s*,\s*0\s*,\s*0\s*,\s*0\)|toISOString\(\)\.split\(['"]T['"]\)\[0\]/.test(text) ? [path] : [];
});
check(unsafe.length === 0, 'NoUnsafePresentation', unsafe.length ? unsafe.join(', ') : 'no feature performs device-local date presentation or midnight derivation');
check(!read('src/lib/dateTime.ts').includes('roughly 56 years') && read('src/lib/dateTime.ts').includes("from 'nepali-date-converter'"), 'AuthoritativeConverter', 'approximation removed; maintained converter is centralized');

console.log(`\nDATE/TIME REGRESSION: ${passed} passed, ${failed} failed`);
if (failed) process.exit(1);
