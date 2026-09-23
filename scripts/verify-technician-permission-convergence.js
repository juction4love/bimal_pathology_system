import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration118 = fs.readFileSync('supabase/migrations_legacy_archive/00118_lab_technician_operational_rbac.sql', 'utf8');
const permissions = fs.readFileSync('src/types/permissions.ts', 'utf8');
const operationalRequired = [
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
const adminOnlyRestricted = [
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

const target = migration118.match(/technician_allowed CONSTANT TEXT\[\]\s*:=\s*ARRAY\[[\s\S]*?\];/)?.[0] ?? '';
assert.ok(target, 'Migration 00118 must define technician_allowed array');

for (const key of operationalRequired) {
  assert.ok(target.includes(`'${key}'`), `Migration 00118 technician_allowed missing operational permission ${key}`);
  assert.ok(permissions.includes(key), `frontend permissions.ts missing operational permission ${key}`);
}

const allowlistMatch = permissions.match(/export const LAB_TECHNICIAN_PERMISSION_ALLOWLIST: PermissionKey\[\] = \[([\s\S]*?)\];/)?.[1] ?? '';
assert.ok(allowlistMatch, 'permissions.ts must define LAB_TECHNICIAN_PERMISSION_ALLOWLIST');

for (const key of adminOnlyRestricted) {
  assert.ok(!target.includes(`'${key}'`), `Migration 00118 technician_allowed must NOT contain admin-only permission ${key}`);
  assert.ok(!allowlistMatch.includes(key), `frontend LAB_TECHNICIAN_PERMISSION_ALLOWLIST must NOT contain admin-only permission ${key}`);
}

assert.match(migration118, /CREATE OR REPLACE FUNCTION public\.catalogue_require_manager\(\)/);
assert.match(migration118, /CREATE OR REPLACE FUNCTION public\.catalogue_require_technical\(\)/);
assert.match(migration118, /public\.has_permission\('can_manage_catalogue'\) OR public\.is_super_admin\(\)/);
assert.match(permissions, /LAB_TECHNICIAN_PERMISSION_ALLOWLIST/);
console.log('Final Lab Technician operational permission convergence: PASS');

