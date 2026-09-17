import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const migration50 = read('supabase/migrations/00050_catalogue_management_architecture.sql');
const migration51 = read('supabase/migrations/00051_inactive_user_permission_enforcement.sql');
const migration52 = read('supabase/migrations/00052_admin_rbac_and_critical_amendment_safety.sql');
const permissions = read('src/types/permissions.ts');
const billing = read('src/features/billing/NewBillPage.tsx');
const catalogue = read('src/features/catalogue/CataloguePage.tsx') + read('src/features/catalogue/EasyTestEditorDialog.tsx');
const categoryPackages = read('src/features/catalogue/CategoryPackageManager.tsx');
const rangeCsv = read('src/features/catalogue/ReferenceRangeCsvModal.tsx');
const rangeBulk = read('src/features/catalogue/BulkReferenceRangeEditor.tsx');
const roles = read('src/features/admin/RolePermissionsPage.tsx');
const users = read('src/features/admin/UserManagementPage.tsx');
const personnel = read('src/features/personnel/ReportingPersonnelPage.tsx');
const doctors = read('src/features/personnel/ReferringDoctorsPage.tsx');
const patients = read('src/features/patients/PatientsPage.tsx');
const payments = read('src/features/billing/BillListPage.tsx');
const samples = read('src/features/samples/SampleAccessioningPage.tsx');
const results = read('src/features/worklist/ResultEntryPage.tsx');
const reports = read('src/features/reports/ReportsPage.tsx');
const liveFinalCore = read('scripts/verify-live-final-core.js');
const phase7Patient = read('scripts/verify-phase7-patient-uniqueness.js');
const packageJson = JSON.parse(read('package.json'));

let passed = 0;
const check = (condition, message) => {
  assert.ok(condition, message);
  passed += 1;
  console.log(`PASS: ${message}`);
};

const activeGate = migration51.indexOf('IF NOT public.is_active_user() THEN');
const superAdminGate = migration51.indexOf('IF public.is_super_admin() THEN', activeGate);
const directGrantLookup = migration51.indexOf('FROM public.user_direct_permissions udp', activeGate);
const roleLookup = migration51.indexOf('FROM public.user_roles ur', activeGate);
check(
  activeGate >= 0 && superAdminGate > activeGate && directGrantLookup > activeGate && roleLookup > activeGate,
  'inactive-profile denial precedes super-admin, direct-grant, and role permission evaluation',
);
check(
  /CREATE OR REPLACE FUNCTION public\.is_active_user\(\)[\s\S]*auth\.uid\(\) IS NOT NULL[\s\S]*up\.is_active = TRUE/.test(migration51),
  'common active-user gate requires an authenticated active application profile',
);
check(
  /REVOKE ALL ON FUNCTION public\.is_active_user\(\) FROM PUBLIC, anon/.test(migration51) &&
  /REVOKE ALL ON FUNCTION public\.has_permission\(VARCHAR\) FROM PUBLIC, anon/.test(migration51),
  'common authorization helpers deny PUBLIC and anon execution',
);

const permissionKeys = [...permissions.matchAll(/:\s*'(can_[a-z_]+)'/g)].map((match) => match[1]);
check(permissionKeys.length === 25 && new Set(permissionKeys).size === 25, 'all 25 application permission keys remain uniquely declared');
check(
  migration52.includes("'00000000-0000-0000-0000-000000000001'")
    && migration52.includes("'can_manage_outsource_tracking'")
    && migration52.includes('ON CONFLICT (role_id, permission_key) DO NOTHING'),
  'forward runtime closure gives the complete Administrator role its only missing permission idempotently',
);
check(
  /v_material_change[\s\S]*NEW\.numeric_value IS DISTINCT FROM OLD\.numeric_value[\s\S]*a\.timestamp >= v_not_before/.test(migration52)
    && /REVOKE ALL ON FUNCTION public\.enforce_critical_acknowledgement_authority\(\)[\s\S]*FROM PUBLIC, anon, authenticated/.test(migration52),
  'material critical-result amendments require a fresh same-actor server-audited acknowledgement',
);
check(
  results.includes('materialValueChanged') && results.includes('critical_acknowledged: false'),
  'Result Entry clears stale critical acknowledgement when an entered or calculated clinical value changes',
);

check(
  /REVOKE EXECUTE ON FUNCTION public\.create_patient_bill_and_order\(\s*JSONB,\s*JSONB,\s*JSONB\[\],\s*JSONB,\s*TEXT\s*\)[\s\S]*FROM PUBLIC, anon, authenticated/.test(migration51),
  'obsolete five-argument billing RPC remains revoked from browser roles',
);
check(
  billing.includes("rpc('search_billable_catalogue'") &&
  billing.includes("rpc('catalogue_expand_package'") &&
  billing.includes("rpc('create_patient_bill_order_with_packages'") &&
  !billing.includes("rpc('create_patient_bill_and_order'"),
  'New Bill uses guarded search, package expansion, and package-aware billing RPCs only',
);
check(
  !read('src/features/billing/NewBillPage.tsx').includes("rpc('create_patient_bill_and_order'") &&
  !read('src/features/billing/BillListPage.tsx').includes("rpc('create_patient_bill_and_order'"),
  'billing frontend has no dependency on either obsolete create_patient_bill_and_order signature',
);
check(
  /create_patient_bill_order_with_packages[\s\S]*has_permission\('can_create_bill'\)/.test(migration50),
  'package-aware billing wrapper enforces server-side billing permission',
);
for (const [source, label] of [
  [liveFinalCore, 'final-core mutation harness'],
  [phase7Patient, 'Phase 7 patient mutation harness'],
]) {
  check(
    source.includes("from './staging-target-guard.js'")
      && source.includes("EXPECTED_MIGRATION_HEAD = '00052'")
      && source.includes('assertSyntheticStagingTarget')
      && !source.includes('.env.local')
      && !source.includes("rpc('create_patient_bill_and_order'"),
    `${label} is isolated-staging-only at head 00052 and has no obsolete billing dependency`,
  );
}
check(
  liveFinalCore.includes("rpc('create_patient_bill_order_with_packages'")
    && phase7Patient.includes("import('./staging-final-patient-runtime.js')"),
  'legacy runtime entry points preserve useful coverage through maintained package-aware staging suites',
);
check(
  packageJson.scripts['test:phase7'] === 'npm run test:phase7:staging'
    && packageJson.scripts['test:phase7:staging'] === 'node scripts/verify-phase7-patient-uniqueness.js',
  'Phase 7 package entry point is explicitly labelled as staging-only',
);

const mutationPattern = (table) => new RegExp(`\\.from\\('${table}'\\)[\\s\\S]{0,300}?\\.(?:insert|update|upsert|delete)\\(`);
for (const [source, tables, label] of [
  [catalogue, ['tests', 'parameters', 'reference_ranges'], 'catalogue'],
  [categoryPackages, ['test_categories', 'health_packages', 'health_package_components'], 'category/package'],
  [roles, ['role_permissions'], 'role-permission'],
  [personnel, ['reporting_personnel'], 'reporting-personnel'],
  [doctors, ['referring_doctors'], 'referring-doctor'],
]) {
  check(tables.every((table) => !mutationPattern(table).test(source)), `${label} frontend has no revoked direct-table mutation dependency`);
}

for (const [name, pattern] of [
  ['catalogue_save_test', /rpc\('catalogue_save_test(_easy)?'/],
  ['catalogue_save_parameter', /rpc\('catalogue_save_parameter(_easy)?'/],
  ['catalogue_save_range', /rpc\('catalogue_save_range(_easy)?'/],
  ['catalogue_set_test_lifecycle', /rpc\('catalogue_set_test_lifecycle'/],
  ['catalogue_set_parameter_lifecycle', /rpc\('catalogue_set_parameter_lifecycle'/],
]) check(pattern.test(catalogue), `catalogue frontend uses ${name}`);
check(categoryPackages.includes("rpc('catalogue_save_category'") && categoryPackages.includes("rpc('catalogue_save_package'"), 'category/package frontend uses guarded save RPCs');
check(
  categoryPackages.includes("rpc('catalogue_set_category_lifecycle'") &&
  categoryPackages.includes("rpc('catalogue_delete_category'") &&
  categoryPackages.includes("rpc('catalogue_set_package_lifecycle'") &&
  categoryPackages.includes("rpc('catalogue_delete_package'") &&
  categoryPackages.includes('p_expected_version'),
  'category/package lifecycle and safe-delete calls use guarded optimistic-concurrency RPCs',
);
check(
  rangeCsv.includes("rpc('catalogue_replace_ranges'") && rangeBulk.includes("rpc('catalogue_replace_ranges'"),
  'both reference-range bulk editors use the atomic guarded replacement RPC',
);
check(!roles.includes("rpc('replace_role_permission_matrix'") && roles.includes('Laboratory Operator') && roles.includes('Super Admin responsibilities'), 'role-permission frontend presents the locked final owner/operator model without an editable matrix');
check(personnel.includes("rpc('save_reporting_personnel'"), 'reporting-personnel frontend uses guarded save RPC');
check(doctors.includes("rpc('save_referring_doctor'"), 'referring-doctor frontend uses guarded save RPC');

for (const [source, rpcNames, label] of [
  [patients, ['create_patient', 'update_patient_demographics', 'delete_unused_patient', 'set_patient_archived'], 'patient'],
  [payments, ['receive_bill_payment'], 'payment'],
  [samples, ['transition_sample_lifecycle'], 'sample lifecycle'],
  [results, ['check_report_group_readiness', 'record_critical_value_acknowledgement', 'save_test_results', 'sign_and_queue_report_group'], 'clinical result/sign-off'],
  [reports, ['get_report_secure_link_status', 'provision_historical_report_secure_link'], 'secure-report'],
  [users, ['update_user_access'], 'user-access'],
]) {
  check(
    rpcNames.every((rpcName) => new RegExp(`\\.rpc(?: as any)?\\)?\\(\\s*['"]${rpcName}['"]`).test(source)),
    `${label} frontend uses only its expected server-authoritative mutation/status RPCs`,
  );
}

for (const file of [
  'scripts/verify-phase2.js',
  'scripts/verify-phase3.js',
  'scripts/verify-phase4.js',
  'scripts/verify-phase5.js',
  'scripts/verify-phase13-dashboard-collections.js',
]) {
  const source = read(file);
  check(
    !source.includes("from '@supabase/supabase-js'") &&
    !source.includes('createClient(') &&
    !source.includes('anonClient.') &&
    !/\bfetch\s*\(/.test(source),
    `${file} is deterministic and cannot target production`,
  );
}

console.log(`Final release security contracts: ${passed} passed, 0 failed.`);
