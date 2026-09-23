/** Deterministic Phase 9 SHA-256 and sign-off authorization regression suite. */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const migration01 = read('supabase/migrations_legacy_archive/00001_initial_schema.sql');
const migration02 = read('supabase/migrations_legacy_archive/00002_rls_and_permissions.sql');
const migration14Path = path.join(root, 'supabase/migrations_legacy_archive/00014_fix_report_sha256_digest.sql');
const migration14 = read('supabase/migrations_legacy_archive/00014_fix_report_sha256_digest.sql');
const migration15 = read('supabase/migrations_legacy_archive/00015_laboratory_calculation_engine.sql');
let passedCount = 0;
let failedCount = 0;

function assert(condition, code, description) {
  if (condition) { console.log(`  ✅ [PASS] ${code}: ${description}`); passedCount++; }
  else { console.error(`  ❌ [FAIL] ${code}: ${description}`); failedCount++; }
}

async function runSignoffSuite() {
  console.log('================================================================');
  console.log(' BIMAL PATHOLOGY - PHASE 9 SHA-256 & SIGN-OFF REGRESSION SUITE');
  console.log('================================================================\n');

  console.log('--- TEST GROUP 1: MIGRATION & CODE INTEGRITY INSPECTION ---');
  assert(fs.existsSync(migration14Path), '1. ReportSignoff_MigrationFileCreated', 'Forward-only migration 00014_fix_report_sha256_digest.sql exists');

  const qualifiedDigest14 = /extensions\.digest\s*\(\s*convert_to\(v_hash_input,\s*'UTF8'\),\s*'sha256'\s*\)/i.test(migration14);
  const qualifiedDigest15 = /extensions\.digest\s*\(\s*convert_to\(v_hash_input,\s*'UTF8'\),\s*'sha256'\s*\)/i.test(migration15);
  assert(qualifiedDigest14 && qualifiedDigest15, '2. ReportSignoff_UsesSchemaQualifiedPgcrypto', 'Migrations 00014 and 00015 use schema-qualified extensions.digest with UTF8 input');

  const { calculateSnapshotSha256 } = await import('../src/lib/reportRenderer.ts');
  const hash = await calculateSnapshotSha256({
    organization: { name_en: 'Bimal Pathology' },
    patient: { full_name: 'Test Patient', uhid: 'BP-2026-0001' },
    order: { order_number: 'LAB-2026-00011' }, signatories: {}, investigations: [],
  });
  assert(/^[0-9a-f]{64}$/i.test(hash), '3. ReportSignoff_Sha256Is64HexCharacters', `SHA-256 generator produces 64 hex characters: ${hash.substring(0, 16)}...`);

  console.log('\n--- TEST GROUP 2: ROLE-BASED ACCESS CONTROL & SIGN-OFF GATE ---');
  const explicitAuthGate = /IF auth\.uid\(\) IS NULL THEN\s*RAISE EXCEPTION 'Authentication required\.'/i.test(migration15);
  const anonRevoked = /REVOKE ALL ON FUNCTION public\.sign_and_freeze_diagnostic_report\(UUID, UUID, UUID, TEXT, UUID\) FROM PUBLIC, anon/i.test(migration15);
  const authenticatedGrant = /GRANT EXECUTE ON FUNCTION public\.sign_and_freeze_diagnostic_report\(UUID, UUID, UUID, TEXT, UUID\) TO authenticated/i.test(migration15);
  assert(explicitAuthGate && anonRevoked && authenticatedGrant, '4. UnauthorizedUser_CannotSign', 'Final sign-off RPC rejects anonymous callers and grants execution only to authenticated users');

  const { ACTIVE_ROLE_CODES, SYSTEM_ROLES, PERMISSION_KEYS } = await import('../src/types/permissions.ts');
  const techCanSign = SYSTEM_ROLES.LAB_TECHNICIAN.defaultPermissions.includes(PERMISSION_KEYS.CAN_SIGN_REPORTS);
  const callerPermissionGate = /IF NOT public\.has_permission\('can_sign_reports'\) THEN\s*RAISE EXCEPTION 'Access Denied:/i.test(migration15);
  assert(techCanSign && callerPermissionGate, '5. AuthorizedLabTechnician_CanSign', 'Lab Technician has can_sign_reports and the final RPC still enforces caller permission');

  const adminIsCompatibilityOnly = !ACTIVE_ROLE_CODES.includes(SYSTEM_ROLES.ADMIN.code);
  assert(adminIsCompatibilityOnly, '6. Administrator_IsCompatibilityOnly', 'Administrator is retained only for historical compatibility and is not normally assignable');

  console.log('\n--- TEST GROUP 3: SIGNATORY CONFIGURATION INSPECTION ---');
  const personnelSchema = /CREATE TABLE reporting_personnel\s*\([\s\S]*?can_sign_reports BOOLEAN NOT NULL DEFAULT FALSE[\s\S]*?is_active BOOLEAN NOT NULL DEFAULT TRUE/i.test(migration01);
  const personnelPolicy = /CREATE POLICY "reporting_personnel_select"[\s\S]*?FOR SELECT TO authenticated/i.test(migration02);
  const signatoryLookup = /FROM public\.reporting_personnel\s+WHERE id = p_signed_by_id/i.test(migration15);
  const activeGate = /IF v_signed_by\.is_active IS NOT TRUE THEN/i.test(migration15);
  const authorityGate = /IF v_signed_by\.can_sign_reports IS NOT TRUE THEN/i.test(migration15);
  assert(personnelSchema && personnelPolicy && signatoryLookup && activeGate && authorityGate, '7. Signatory_ActiveAuthorizedPersonnelRequired', 'Schema and final RPC require an existing, active reporting person with sign authority');

  console.log('\n================================================================');
  console.log(` SUMMARY: ${passedCount} PASSED, ${failedCount} FAILED`);
  console.log('================================================================\n');
  if (failedCount > 0) process.exit(1);
}

runSignoffSuite().catch((error) => { console.error(error); process.exit(1); });
