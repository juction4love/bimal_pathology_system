import { createClient } from '@supabase/supabase-js';
import { writeFile } from 'node:fs/promises';
import { assertSyntheticStagingTarget } from './staging-target-guard.js';

const { STAGING_SUPABASE_URL: url, STAGING_ANON_KEY: anonKey, STAGING_SERVICE_KEY: serviceKey, STAGING_TEST_PASSWORD: password } = process.env;
if (!url || !anonKey || !serviceKey || !password) throw new Error('Staging environment variables are required');
if (process.env.STAGING_EXPECTED_MIGRATION_HEAD !== '00053') throw new Error('STAGING_EXPECTED_MIGRATION_HEAD must equal 00053');
const target = assertSyntheticStagingTarget({ expectedHead: process.env.STAGING_EXPECTED_MIGRATION_HEAD });
const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const stamp = Date.now().toString(36);
const ADMIN_ROLE = '00000000-0000-0000-0000-000000000001';
const TECH_ROLE = '00000000-0000-0000-0000-000000000004';
const ALL = [
  'can_view_dashboard', 'can_create_bill', 'can_edit_patient', 'can_collect_sample',
  'can_receive_sample', 'can_reject_sample', 'can_enter_results', 'can_verify_results',
  'can_acknowledge_critical', 'can_sign_reports', 'can_amend_reports', 'can_print_reports',
  'can_manage_catalogue', 'can_manage_referring_doctors', 'can_manage_personnel',
  'can_view_financials', 'can_manage_users', 'can_manage_roles', 'can_view_audit_logs',
  'can_manage_outsource_tracking', 'can_view_hmis_reports', 'can_edit_hmis_reports',
  'can_finalize_hmis_reports',
];
const TECH = [
  'can_view_dashboard', 'can_collect_sample', 'can_receive_sample', 'can_reject_sample',
  'can_enter_results', 'can_acknowledge_critical', 'can_print_reports',
  'can_manage_outsource_tracking',
];
const created = [];
const results = [];
const record = (name, pass, details = {}) => results.push({ name, pass, ...details });

async function identity(label, { roleId, direct = [], active = true, displayName = label }) {
  const email = `rbac-00053-${label}-${stamp}@example.invalid`;
  const made = await service.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name: displayName } });
  if (made.error) throw made.error;
  const id = made.data.user.id;
  created.push(id);
  await service.from('user_profiles').update({ is_active: active, is_super_admin: false }).eq('id', id).throwOnError();
  if (roleId) {
    await service.from('user_roles').delete().eq('user_id', id).throwOnError();
    await service.from('user_roles').insert({ user_id: id, role_id: roleId }).throwOnError();
  }
  if (direct.length) await service.from('user_direct_permissions').insert(direct.map((permission_key) => ({ user_id: id, permission_key, is_granted: true }))).throwOnError();
  const client = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const login = await client.auth.signInWithPassword({ email, password });
  if (login.error || !login.data.session?.access_token) throw login.error || new Error(`${label} JWT missing`);
  return { client, id };
}

async function matrix(label, subject, expected) {
  const checks = await Promise.all(ALL.map((key) => subject.client.rpc('has_permission', { p_permission_key: key })));
  const granted = ALL.filter((_, index) => !checks[index].error && checks[index].data === true).sort();
  const wanted = [...expected].sort();
  record(`${label} exact permission matrix`, JSON.stringify(granted) === JSON.stringify(wanted), { granted, expected: wanted, errors: checks.filter((x) => x.error).map((x) => x.error.message) });
}

async function denied(label, promise) {
  const response = await promise;
  record(label, Boolean(response.error) && response.error.code === '42501', { code: response.error?.code, message: response.error?.message });
}

try {
  const admin = await identity('admin', { roleId: ADMIN_ROLE });
  const technician = await identity('technician', { roleId: TECH_ROLE, displayName: 'Synthetic Lab Technician' });
  const senior = await identity('senior-technician', { roleId: TECH_ROLE, displayName: 'Synthetic Senior Lab Technician' });
  const billing = await identity('billing', { direct: ['can_view_dashboard', 'can_create_bill', 'can_edit_patient'] });
  const catalogue = await identity('catalogue', { direct: ['can_view_dashboard', 'can_manage_catalogue'] });
  const roleManager = await identity('role-manager', { direct: ['can_view_dashboard', 'can_manage_roles', 'can_manage_users'] });
  const inactive = await identity('inactive-technician', { roleId: TECH_ROLE, active: false });

  await matrix('Admin', admin, ALL);
  await matrix('Lab Technician', technician, TECH);
  await matrix('Senior Lab Technician profile using canonical role', senior, TECH);
  await matrix('billing-capable subject', billing, ['can_view_dashboard', 'can_create_bill', 'can_edit_patient']);
  await matrix('catalogue manager subject', catalogue, ['can_view_dashboard', 'can_manage_catalogue']);
  await matrix('role manager subject', roleManager, ['can_view_dashboard', 'can_manage_roles', 'can_manage_users']);
  await matrix('inactive Technician', inactive, []);

  await denied('Technician billing RPC denied server-side', technician.client.rpc('create_patient_bill_order_with_packages', {
    p_patient_data: {}, p_bill_data: {}, p_items_data: [], p_payment_data: null,
    p_idempotency_key: `denied-${stamp}`, p_packages: [],
  }));
  await denied('Technician catalogue mutation RPC denied server-side', technician.client.rpc('catalogue_save_category', { p_category: {}, p_expected_version: null }));
  await denied('Technician role-management RPC denied server-side', technician.client.rpc('replace_role_permission_matrix', { p_matrix: [] }));
  await denied('Technician financial dashboard RPC denied server-side', technician.client.rpc('get_dashboard_collection_summary'));
  await denied('Technician sign-off RPC denied server-side', technician.client.rpc('sign_and_queue_diagnostic_report', {
    p_order_id: crypto.randomUUID(), p_performed_by_id: crypto.randomUUID(), p_signed_by_id: null,
    p_amendment_reason: null, p_amended_from_report_id: null,
    p_token_hash: '0'.repeat(64), p_public_report_url: 'https://lis.bimalpathology.com.np/r/denied',
  }));

  const roleMatrix = await service.from('role_permissions').select('permission_key').eq('role_id', TECH_ROLE).order('permission_key');
  record('persisted Technician role equals canonical matrix', !roleMatrix.error && JSON.stringify(roleMatrix.data.map((x) => x.permission_key)) === JSON.stringify([...TECH].sort()));
  const audit = await service.from('audit_logs').select('user_id,user_name,action,entity_id,new_data').eq('action', 'TECHNICIAN_RBAC_CONVERGED').eq('entity_id', TECH_ROLE).order('timestamp', { ascending: false }).limit(1);
  const auditIsAbsentForNoop = !audit.error && audit.data.length === 0;
  const auditIsMigrationAuthored = !audit.error && audit.data.length === 1
    && audit.data[0].user_id === null
    && audit.data[0].user_name === 'Database migration 00053';
  record('00053 audit evidence is absent for an idempotent no-op or migration-authored for a change', auditIsAbsentForNoop || auditIsMigrationAuthored, { audit_rows: audit.data?.length });
} finally {
  const cleanup = [];
  for (const id of created.reverse()) {
    const removed = await service.auth.admin.deleteUser(id);
    cleanup.push({ id, pass: !removed.error, error: removed.error?.message });
  }
  const safe = results.every((x) => x.pass) && cleanup.every((x) => x.pass);
  const evidence = { target, summary: { pass: results.filter((x) => x.pass).length, fail: results.filter((x) => !x.pass).length, cleanup_fail: cleanup.filter((x) => !x.pass).length, safe, production_touched: false, sms_sent: false }, results, cleanup: cleanup.map(({ pass, error }) => ({ pass, error })) };
  await writeFile('artifacts/staging-00053-rbac-runtime.json', JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify(evidence.summary));
  if (!safe) process.exitCode = 1;
}
