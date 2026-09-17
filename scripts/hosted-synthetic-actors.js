import { createClient } from '@supabase/supabase-js';
import { assertSyntheticStagingTarget } from './staging-target-guard.js';

function assertGuardedTarget(url) {
  if (!process.env.STAGING_SUPABASE_URL || url !== process.env.STAGING_SUPABASE_URL) throw new Error('STAGING_SUPABASE_URL_MISMATCH');
  return assertSyntheticStagingTarget({ expectedHead: process.env.STAGING_EXPECTED_MIGRATION_HEAD });
}

export async function bootstrapAdminClient(url, anonKey) {
  assertGuardedTarget(url);
  const email = process.env.STAGING_BOOTSTRAP_ADMIN_EMAIL;
  const password = process.env.STAGING_BOOTSTRAP_ADMIN_PASSWORD;
  if (!email || !password || !email.endsWith('@example.invalid')) throw new Error('Synthetic bootstrap Admin credentials are required.');
  const client = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const login = await client.auth.signInWithPassword({ email, password });
  if (login.error) throw login.error;
  return client;
}

export async function provisionSyntheticActor({ url, anonKey, management, label, password, roleId, active = true }) {
  assertGuardedTarget(url);
  const email = `foundation-${label}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}@example.invalid`;
  const made = await management.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name: `Foundation ${label}` } });
  if (made.error) throw made.error;
  const admin = await bootstrapAdminClient(url, anonKey);
  const access = await admin.rpc('update_user_access', {
    p_user_id: made.data.user.id,
    p_is_active: active,
    p_is_super_admin: false,
    p_role_ids: active && roleId ? [roleId] : [],
  });
  if (access.error) throw access.error;
  const client = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const login = await client.auth.signInWithPassword({ email, password });
  if (login.error) throw login.error;
  return { client, id: made.data.user.id, email };
}
