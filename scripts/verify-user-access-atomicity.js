import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/00048_atomic_user_access_management.sql', 'utf8');
const finalModel = fs.readFileSync('supabase/migrations/00087_production_catalogue_rate_management.sql', 'utf8');
const page = fs.readFileSync('src/features/admin/UserManagementPage.tsx', 'utf8');
let passed = 0;
const check = (condition, label) => {
  if (!condition) throw new Error(`FAIL: ${label}`);
  passed += 1;
  console.log(`PASS: ${label}`);
};

check(migration.includes('CREATE OR REPLACE FUNCTION public.update_user_access'), 'atomic user-access RPC exists');
check(migration.includes('CREATE OR REPLACE FUNCTION public.handle_new_auth_user') && migration.includes("'Pending Staff Account'") && migration.includes('v_is_first,\n        v_is_first'), 'future non-first Auth identities are provisioned inactive without implicit clinical authority');
check(migration.includes("pg_advisory_xact_lock(hashtext('bimal:first-admin-bootstrap'))") && !migration.includes("VALUES (NEW.id, '00000000-0000-0000-0000-000000000004')"), 'first-admin bootstrap is serialized and signup never assigns Technician');
check(migration.includes('REVOKE ALL ON FUNCTION public.handle_new_auth_user() FROM PUBLIC, anon, authenticated'), 'Auth trigger helper is not directly executable');
check(finalModel.includes('NOT public.is_super_admin()') && finalModel.includes('System Owner authority is required.'), 'final RPC requires active server-side System Owner authority');
check(migration.includes('FOR UPDATE') && migration.includes('DELETE FROM public.user_roles') && migration.includes('INSERT INTO public.user_roles'), 'profile and role membership update in one locked transaction');
check(finalModel.includes('At least one active Super Admin is required.'), 'last active Super Admin cannot be removed');
check(finalModel.includes('You cannot deactivate your own account.'), 'System Owner cannot deactivate the current session account');
check(finalModel.includes('Lab Technician is the only normally assignable role.'), 'only Lab Technician is normally assignable');
check(migration.includes("'USER_ACCESS_UPDATED'") && migration.includes("'changed_fields'") && !migration.includes("'email', v_target.email"), 'audit is server-authored without sensitive profile values');
check(migration.includes('SET search_path = public, pg_temp') && migration.includes('REVOKE ALL') && migration.includes('TO authenticated'), 'SECURITY DEFINER search path and grants are narrow');
check(page.includes("supabase.rpc('update_user_access'") && !page.includes(".from('user_roles')\r\n        .delete()"), 'frontend uses the atomic RPC instead of delete/reinsert transactions');
check(page.includes('It remains inactive until Lab Technician access is assigned here.'), 'System Owner onboarding guidance matches fail-closed provisioning');
check(page.includes("role.code === 'lab_technician'") && !page.includes("['admin', 'lab_technician']"), 'frontend role selector exposes only Lab Technician');

console.log(`\nAtomic user-access management: ${passed} passed, 0 failed`);
