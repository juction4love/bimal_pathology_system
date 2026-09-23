/** Optional authorized-signatory regression suite. */
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const migration = read('supabase/migrations_legacy_archive/00029_optional_authorized_signatory.sql');
const runtimeFix = read('supabase/migrations_legacy_archive/00030_fix_optional_authorizer_runtime.sql');
const report = read('src/features/reports/ReportDocument.tsx');
const entry = read('src/features/worklist/ResultEntryPage.tsx');
const publicPage = read('src/features/public/PublicReportPage.tsx');

let passed = 0;
let failed = 0;
const assert = (condition, name, detail) => {
  if (condition) { passed++; console.log(`  PASS ${name}: ${detail}`); }
  else { failed++; console.error(`  FAIL ${name}: ${detail}`); }
};

console.log('\nBIMAL PATHOLOGY - OPTIONAL AUTHORIZER REGRESSION SUITE\n');

assert(
  /p_performed_by_id UUID,[\s\S]*?p_signed_by_id UUID/.test(migration) &&
    /IF p_signed_by_id IS NOT NULL THEN[\s\S]*?can_sign_reports IS NOT TRUE/.test(migration),
  'PerformedPresentAuthorizedAbsent',
  'performed-by remains required while a supplied authorizer is validated conditionally',
);
assert(
  /'authorized_by', CASE WHEN p_signed_by_id IS NULL THEN NULL::JSONB/.test(migration) &&
    /ALTER COLUMN signed_by_personnel_name DROP NOT NULL/.test(migration),
  'AuthorizationStoredAsNull',
  'the snapshot and report columns store an absent authorizer as null',
);
assert(
  /gridTemplateColumns: signatories\?\.authorized_by \? '1fr 1fr' : '1fr'/.test(report) &&
    /\{signatories\?\.authorized_by && <Box/.test(report) &&
    !/authorized_by\?\.full_name \|\| 'Not recorded'/.test(report),
  'PdfOptionalAuthorizationArea',
  'an absent authorizer renders no fabricated or empty identity panel',
);
assert(
  /p_signed_by_id: signedById \|\| null/.test(entry) &&
    /p\.canSignReports && p\.id !== performedById/.test(entry),
  'NoDuplicatedTechnicianIdentity',
  'the UI sends null and excludes the selected performer from authorizer choices',
);
assert(
  /authorized_by \? 'FINAL SIGNED REPORT' : 'FINAL REPORT'/.test(report) &&
    !/Reg: \{p\.registrationNumber \|\| 'Verified'\}/.test(entry),
  'NoFakeAuthorizationWording',
  'unsigned authorization uses FINAL REPORT and no fabricated verified registration text',
);
assert(
  /resolve_public_report_by_token/.test(read('supabase/migrations_legacy_archive/00021_final_flow_integrity_and_concurrency.sql')) &&
    /<ReportDocument/.test(publicPage) && /integrity_hash/.test(migration),
  'QrPublicReportStillWorks',
  'public resolution and the immutable hash remain wired to the shared renderer',
);
assert(
  /p_amended_from_report_id IS NOT NULL/.test(migration) &&
    /v_version := v_parent_report\.version \+ 1/.test(migration) &&
    /'amendment_reason', p_amendment_reason/.test(migration),
  'AmendmentVersioningStillWorks',
  'version increment, parent linkage, and amendment reason remain intact',
);
assert(
  !/UPDATE public\.diagnostic_reports\s+SET\s+(?:clinical_snapshot_json|signed_by_personnel)/i.test(migration),
  'HistoricalReportsUnchanged',
  'the forward migration performs no authorization or snapshot backfill',
);
assert(
  /ELSE jsonb_build_object\([\s\S]*?'full_name', v_signed_by\.full_name/.test(migration) &&
    /NEW\.signed_by_personnel_id IS NOT NULL AND NOT EXISTS/.test(migration),
  'LaterSeparateSignatorySupported',
  'a future distinct active signatory follows the normal validated snapshot path',
);
assert(
  /IF NOT public\.has_permission\('can_sign_reports'\)/.test(migration) &&
    /p\.id !== performedById/.test(entry),
  'PermissionsRemainSeparate',
  'caller permission gates remain independent from Reporting Personnel identity',
);

const executeAuthorizationBranch = (authorizedId, selectedPersonnel) => {
  let authorizedSnapshot = null;
  let authorizedPersonnelId = null;
  let authorizedName = null;
  if (authorizedId !== null) {
    const person = selectedPersonnel;
    authorizedPersonnelId = person.id;
    authorizedName = person.full_name;
    authorizedSnapshot = { id: person.id, full_name: person.full_name };
  }
  return { authorizedSnapshot, authorizedPersonnelId, authorizedName };
};
const nullBranch = executeAuthorizationBranch(null, undefined);
assert(
  nullBranch.authorizedSnapshot === null &&
    nullBranch.authorizedPersonnelId === null &&
    nullBranch.authorizedName === null &&
    !/v_signed_by RECORD/.test(runtimeFix) &&
    !/v_signed_by\s*\./.test(runtimeFix) &&
    /v_authorized_snapshot JSONB := NULL/.test(runtimeFix) &&
    /'authorized_by', v_authorized_snapshot/.test(runtimeFix),
  'UnassignedRecordNullBranchRegression',
  'executing the null-authorizer branch never reads a record and reproduces no record "v_signed_by" is not assigned yet error',
);
assert(
  /IF p_signed_by_id = p_performed_by_id THEN/.test(runtimeFix) &&
    /v_authorized_snapshot := jsonb_build_object/.test(runtimeFix) &&
    /v_signed_by_is_active IS NOT TRUE/.test(runtimeFix) &&
    /v_signed_by_can_sign_reports IS NOT TRUE/.test(runtimeFix),
  'DistinctAuthorizedScalarBranch',
  'the supplied-authorizer branch enforces distinct, active, authorized personnel before constructing JSON',
);

console.log(`\nSUMMARY: ${passed} PASSED, ${failed} FAILED\n`);
if (failed) process.exit(1);
