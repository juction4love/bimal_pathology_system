import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration118 = fs.readFileSync('supabase/migrations_legacy_archive/00118_lab_technician_operational_rbac.sql', 'utf8');
const permissionsFile = fs.readFileSync('src/types/permissions.ts', 'utf8');
const routesFile = fs.readFileSync('src/app/routes.tsx', 'utf8');
const appLayoutFile = fs.readFileSync('src/app/AppLayout.tsx', 'utf8');
const rolePermissionsPage = fs.readFileSync('src/features/admin/RolePermissionsPage.tsx', 'utf8');
const reportingPersonnelPage = fs.readFileSync('src/features/personnel/ReportingPersonnelPage.tsx', 'utf8');
const referringDoctorsPage = fs.readFileSync('src/features/personnel/ReferringDoctorsPage.tsx', 'utf8');

const OPERATIONAL_PERMISSIONS = [
  'can_view_dashboard',
  'can_create_bill',
  'can_edit_patient',
  'can_collect_sample',
  'can_receive_sample',
  'can_reject_sample',
  'can_enter_results',
  'can_verify_results',
  'can_acknowledge_critical',
  'can_sign_reports',
  'can_amend_reports',
  'can_print_reports',
  'can_manage_outsource_tracking',
];

const ADMIN_ONLY_PERMISSIONS = [
  'can_manage_catalogue',
  'can_configure_catalogue_technical',
  'can_manage_ast_breakpoints',
  'can_manage_referring_doctors',
  'can_manage_personnel',
  'can_view_financials',
  'can_manage_users',
  'can_manage_roles',
  'can_view_audit_logs',
  'can_view_hmis_reports',
  'can_edit_hmis_reports',
  'can_finalize_hmis_reports',
];

test('1. Migration 00118 restricts Lab Technician to exactly 13 operational permissions', () => {
  const match = migration118.match(/technician_allowed CONSTANT TEXT\[\]\s*:=\s*ARRAY\[([\s\S]*?)\];/);
  assert.ok(match, 'technician_allowed constant array must be defined in 00118');

  for (const perm of OPERATIONAL_PERMISSIONS) {
    assert.ok(match[1].includes(`'${perm}'`), `technician_allowed must contain operational permission ${perm}`);
  }

  for (const perm of ADMIN_ONLY_PERMISSIONS) {
    assert.ok(!match[1].includes(`'${perm}'`), `technician_allowed must NOT contain admin permission ${perm}`);
  }
});

test('2. Migration 00118 cleans up database role_permissions for lab_technician', () => {
  assert.match(migration118, /DELETE FROM public\.role_permissions\s+WHERE role_id IN \(SELECT id FROM public\.roles WHERE code = 'lab_technician'\)/);
  assert.match(migration118, /INSERT INTO public\.role_permissions \(role_id, permission_key\)\s+SELECT r\.id, p\.perm\s+FROM public\.roles r/);
  assert.match(migration118, /INSERT INTO public\.audit_logs/);
});

test('3. Migration 00118 enforces server-side 42501 denial in catalogue_require_manager and catalogue_require_technical', () => {
  assert.match(migration118, /CREATE OR REPLACE FUNCTION public\.catalogue_require_manager\(\)/);
  assert.match(migration118, /RAISE EXCEPTION 'Catalogue management requires administrative authorization\.' USING ERRCODE='42501';/);
  assert.match(migration118, /CREATE OR REPLACE FUNCTION public\.catalogue_require_technical\(\)/);
  assert.match(migration118, /RAISE EXCEPTION 'Catalogue technical configuration requires administrative authorization\.' USING ERRCODE='42501';/);
});

test('4. Migration 00118 secures replace_role_permission_matrix with strict validation and 42501 denial', () => {
  assert.match(migration118, /CREATE OR REPLACE FUNCTION public\.replace_role_permission_matrix\(/);
  assert.match(migration118, /IF auth\.uid\(\) IS NULL OR NOT \(public\.has_permission\('can_manage_roles'\) OR public\.is_super_admin\(\)\) THEN/);
  assert.match(migration118, /RAISE EXCEPTION 'Permission denied\.' USING ERRCODE='42501';/);
  assert.match(migration118, /RAISE EXCEPTION 'Lab Technician must retain the complete operational pathology permission set \(13 operational permissions\)\.' USING ERRCODE='23514';/);
});

test('5. Frontend permissions.ts LAB_TECHNICIAN_PERMISSION_ALLOWLIST contains only the 13 operational permissions', () => {
  const allowlistMatch = permissionsFile.match(/export const LAB_TECHNICIAN_PERMISSION_ALLOWLIST: PermissionKey\[\] = \[([\s\S]*?)\];/);
  assert.ok(allowlistMatch, 'LAB_TECHNICIAN_PERMISSION_ALLOWLIST must be exported');

  for (const perm of OPERATIONAL_PERMISSIONS) {
    const enumKey = perm.toUpperCase();
    assert.ok(allowlistMatch[1].includes(enumKey), `allowlist must include PERMISSION_KEYS.${enumKey}`);
  }

  for (const perm of ADMIN_ONLY_PERMISSIONS) {
    const enumKey = perm.toUpperCase();
    assert.ok(!allowlistMatch[1].includes(enumKey), `allowlist must NOT include PERMISSION_KEYS.${enumKey}`);
  }
});

test('6. Route guards protect /catalogue, /personnel/doctors, /personnel/reporting from Lab Technician', () => {
  assert.match(routesFile, /path:\s*'catalogue'[\s\S]*?permission=\{PERMISSION_KEYS\.CAN_MANAGE_CATALOGUE\}/);
  assert.match(routesFile, /path:\s*'personnel\/doctors'[\s\S]*?permission=\{PERMISSION_KEYS\.CAN_MANAGE_REFERRING_DOCTORS\}/);
  assert.match(routesFile, /path:\s*'personnel\/reporting'[\s\S]*?permission=\{PERMISSION_KEYS\.CAN_MANAGE_PERSONNEL\}/);
  assert.match(routesFile, /path:\s*'admin\/users'[\s\S]*?permission=\{PERMISSION_KEYS\.CAN_MANAGE_USERS\}/);
  assert.match(routesFile, /path:\s*'admin\/roles'[\s\S]*?permission=\{PERMISSION_KEYS\.CAN_MANAGE_ROLES\}/);
});

test('7. AppLayout hides Catalogue & Personnel and Administration sections from Lab Technician', () => {
  assert.match(appLayoutFile, /label:\s*'Test Catalogue'[\s\S]*?permission:\s*PERMISSION_KEYS\.CAN_MANAGE_CATALOGUE/);
  assert.match(appLayoutFile, /label:\s*'Referring Doctors'[\s\S]*?permission:\s*PERMISSION_KEYS\.CAN_MANAGE_REFERRING_DOCTORS/);
  assert.match(appLayoutFile, /label:\s*'Reporting Personnel'[\s\S]*?permission:\s*PERMISSION_KEYS\.CAN_MANAGE_PERSONNEL/);
  assert.match(appLayoutFile, /if \(visibleItems\.length === 0\) return null;/);
});

test('8. Clinical Operations routes remain fully available to Lab Technician', () => {
  assert.match(routesFile, /path:\s*'billing\/new'[\s\S]*?permission=\{PERMISSION_KEYS\.CAN_CREATE_BILL\}/);
  assert.match(routesFile, /path:\s*'billing'[\s\S]*?anyPermissions=\{\[PERMISSION_KEYS\.CAN_CREATE_BILL,\s*PERMISSION_KEYS\.CAN_VIEW_FINANCIALS\]\}/);
  assert.match(routesFile, /path:\s*'patients'[\s\S]*?permission=\{PERMISSION_KEYS\.CAN_EDIT_PATIENT\}/);
  assert.match(routesFile, /path:\s*'samples'[\s\S]*?anyPermissions=\{\[PERMISSION_KEYS\.CAN_COLLECT_SAMPLE/);
  assert.match(routesFile, /path:\s*'worklist'[\s\S]*?anyPermissions=\{\[PERMISSION_KEYS\.CAN_ENTER_RESULTS/);
  assert.match(routesFile, /path:\s*'reports'[\s\S]*?permission=\{PERMISSION_KEYS\.CAN_PRINT_REPORTS\}/);
  assert.match(routesFile, /path:\s*'outsource'[\s\S]*?permission=\{PERMISSION_KEYS\.CAN_MANAGE_OUTSOURCE_TRACKING\}/);
});

test('9. Reporting Personnel and Referring Doctors screens enforce edit/add controls server and UI side', () => {
  assert.match(reportingPersonnelPage, /can\(PERMISSION_KEYS\.CAN_MANAGE_PERSONNEL\)/);
  assert.match(referringDoctorsPage, /can\(PERMISSION_KEYS\.CAN_MANAGE_REFERRING_DOCTORS\)/);
});

test('10. RolePermissionsPage reflects the clear two-level model', () => {
  assert.match(rolePermissionsPage, /Super Admin/);
  assert.match(rolePermissionsPage, /Lab Technician/);
  assert.match(rolePermissionsPage, /Outsource tracking/);
});
