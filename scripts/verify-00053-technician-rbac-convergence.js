import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/00053_technician_rbac_convergence.sql', 'utf8');
const permissions = fs.readFileSync('src/types/permissions.ts', 'utf8');
const technician19 = fs.readFileSync('supabase/migrations/00019_technician_clinical_only_permissions.sql', 'utf8');
const separation26 = fs.readFileSync('supabase/migrations/00026_separate_technician_from_verifier.sql', 'utf8');

const canonical = [
  'can_view_dashboard',
  'can_collect_sample',
  'can_receive_sample',
  'can_reject_sample',
  'can_enter_results',
  'can_acknowledge_critical',
  'can_print_reports',
  'can_manage_outsource_tracking',
];
const forbidden = [
  'can_create_bill', 'can_edit_patient', 'can_verify_results', 'can_sign_reports',
  'can_amend_reports', 'can_manage_catalogue', 'can_manage_referring_doctors',
  'can_manage_personnel', 'can_view_financials', 'can_manage_users',
  'can_manage_roles', 'can_view_audit_logs',
];

for (const key of canonical) {
  assert.match(permissions, new RegExp(`PERMISSION_KEYS\\.[A-Z_]+,?`));
  assert.ok(migration.includes(`'${key}'`), `00053 must preserve ${key}`);
  assert.ok(technician19.includes(`'${key}'`), `00019 must support canonical ${key}`);
}
for (const key of forbidden) {
  assert.ok(!new RegExp(`v_expected_permissions[\\s\\S]*?'${key}'`).test(
    migration.slice(migration.indexOf('v_expected_permissions'), migration.indexOf('v_old_permissions')),
  ), `00053 canonical set must exclude ${key}`);
}
assert.ok(separation26.includes("'can_verify_results', 'can_sign_reports', 'can_amend_reports'"));
assert.match(migration, /WHERE code = 'lab_technician'/);
assert.match(migration, /v_role\.id <> '00000000-0000-0000-0000-000000000004'/);
assert.match(migration, /NOT \(permission_key = ANY\(v_expected_permissions\)\)/);
assert.match(migration, /ON CONFLICT\(role_id, permission_key\) DO NOTHING/);
assert.match(migration, /TECHNICIAN_RBAC_CONVERGED/);
assert.doesNotMatch(migration, /DELETE FROM public\.(?:users|user_profiles|user_roles|user_direct_permissions)/);
assert.doesNotMatch(migration, /(?:patients|bills|payment_transactions|test_results|diagnostic_reports|sms_queue_items)/);

console.log('00053 Technician RBAC convergence contract: PASS');
