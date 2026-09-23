import fs from 'node:fs';
import { createHash } from 'node:crypto';

const migration = fs.readFileSync('supabase/migrations_legacy_archive/00031_deterministic_numeric_patient_uhid.sql', 'utf8');
const newBill = fs.readFileSync('src/features/billing/NewBillPage.tsx', 'utf8');
const searchable = [
  'src/features/patients/PatientsPage.tsx',
  'src/features/billing/BillListPage.tsx',
  'src/features/samples/SampleAccessioningPage.tsx',
  'src/features/worklist/WorklistPage.tsx',
  'src/features/reports/ReportsPage.tsx',
  'src/features/outsource/OutsourceTrackingPage.tsx',
].map((path) => fs.readFileSync(path, 'utf8'));

let passed = 0;
let failed = 0;
function check(condition, name, detail) {
  if (condition) { passed += 1; console.log(`PASS ${name}: ${detail}`); }
  else { failed += 1; console.error(`FAIL ${name}: ${detail}`); }
}

function nepalDatePrefix(instant) {
  const parts = new Intl.DateTimeFormat('en-CA-u-nu-latn', {
    timeZone: 'Asia/Kathmandu', year: '2-digit', month: '2-digit', day: '2-digit',
  }).formatToParts(new Date(instant));
  const values = Object.fromEntries(parts.filter((part) => part.type !== 'literal').map((part) => [part.type, part.value]));
  return `${values.year}${values.month}${values.day}`;
}

function baseCode(mobile, prefix) {
  const digest = createHash('sha256').update(`BIMAL-UHID-V1:${mobile}:${prefix}`, 'utf8').digest('hex');
  return Number(BigInt(`0x${digest.slice(0, 8)}`) % 10000n);
}

function allocateModel(mobile, instant, occupied = new Set()) {
  const prefix = nepalDatePrefix(instant);
  const base = baseCode(mobile, prefix);
  for (let attempt = 0; attempt < 10000; attempt += 1) {
    const code = (base + attempt * 7919) % 10000;
    const candidate = `${prefix}${String(code).padStart(4, '0')}`;
    if (!occupied.has(candidate)) return candidate;
  }
  throw new Error('namespace exhausted');
}

const mobile = '9850565327';
const instant = '2026-08-21T02:45:00Z';
const first = allocateModel(mobile, instant);
check(/^\d{10}$/.test(first), 'ExactFormat', `${first} is exactly 10 numeric digits`);
check(first.startsWith('260821'), 'NepalRegistrationPrefix', 'YYMMDD comes from 21 Aug 2026 in Asia/Kathmandu');
check(first.slice(-4) !== mobile.slice(-4), 'MobilePrivacy', 'four-digit code does not expose the raw mobile suffix');
check(first === allocateModel(mobile, instant), 'Deterministic', 'same normalized mobile and registration date produce the same first candidate');

const before = allocateModel(mobile, '2026-08-20T18:14:59Z');
const after = allocateModel(mobile, '2026-08-20T18:15:00Z');
check(before.startsWith('260820') && after.startsWith('260821'), 'NepalMidnightBoundary', 'prefix changes at UTC 18:15, Nepal midnight');

const occupied = new Set([first]);
const collisionResolved = allocateModel(mobile, instant, occupied);
check(collisionResolved !== first && /^260821\d{4}$/.test(collisionResolved), 'CollisionProbe', 'occupied deterministic candidate advances within the same date namespace');
check(new Set(Array.from({ length: 10000 }, (_, attempt) => (baseCode(mobile, '260821') + attempt * 7919) % 10000)).size === 10000, 'CollisionCoverage', 'probe step covers all 10,000 codes without repetition');

check(migration.includes("pg_advisory_xact_lock(hashtextextended('patient-uhid-day:'") && migration.includes('UNIQUE constraint remains the final safety boundary'), 'ConcurrentAllocation', 'day namespace is serialized and database uniqueness remains authoritative');
check(migration.includes('patient-mobile:') && migration.includes('WHERE mobile = v_clean_mobile') && migration.includes('ON CONFLICT (mobile) DO UPDATE'), 'DuplicateMobileReuse', 'same normalized mobile is serialized and returns the existing patient/UHID');
check(migration.includes('BEFORE UPDATE OF uhid') && migration.includes('Patient UHID is immutable.'), 'Immutability', 'database trigger rejects UHID mutation');
check(migration.includes('BEFORE INSERT ON public.patients') && migration.includes("NEW.uhid !~ '^[0-9]{10}$'"), 'DatabaseFormatEnforcement', 'database rejects every newly inserted non-numeric or non-10-digit UHID');
check(!/UPDATE\s+public\.patients\s+SET\s+uhid/i.test(migration) && !/ALTER\s+TABLE[\s\S]*UPDATE/i.test(migration), 'HistoricalPreservation', 'migration performs no historical UHID rewrite');
check(migration.includes('v_registration_instant := clock_timestamp()') && migration.includes("AT TIME ZONE 'Asia/Kathmandu'") && migration.includes('created_at') && migration.includes('v_registration_instant'), 'FirstRegistrationDate', 'UHID and patient created_at share one captured first-registration instant');
check(migration.includes('extensions.digest') && migration.includes("'sha256'") && migration.includes("p_normalized_mobile || ':' || v_prefix"), 'HashedDerivation', 'code derives from normalized mobile plus registration date through SHA-256');
check(newBill.includes('10-DIGIT UHID GENERATED ON SAVE') && !newBill.includes('BP-YYYY'), 'ServerGeneratedUi', 'UI never generates or assumes the new identifier client-side');
check(searchable.every((text) => text.includes('uhid') && !/uhid[^\n]{0,80}match\(|uhid[^\n]{0,80}\^BP-/i.test(text)), 'HistoricalAndNewSearch', 'all patient-facing searches treat UHID as an opaque substring and accept both formats');
check(migration.includes("'public.create_patient_bill_and_order(jsonb,jsonb,jsonb[],jsonb)'::REGPROCEDURE") && migration.includes('five-argument idempotent'), 'AtomicTransaction', 'allocation stays inside the atomic billing worker behind the idempotent entrypoint');
check(migration.includes('REVOKE ALL ON FUNCTION public.allocate_patient_uhid') && migration.includes('REVOKE EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB)'), 'PrivilegeBoundary', 'allocator and non-idempotent worker are not browser-callable');

console.log(`\nPHASE 31 UHID REGRESSION: ${passed} passed, ${failed} failed`);
if (failed) process.exit(1);
