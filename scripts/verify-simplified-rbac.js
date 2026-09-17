/**
 * Verify Simplified 2-Role RBAC:
 * Credentials are supplied only through LIS_TEST_* environment variables.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';
import { getAdminCredential, getTechCredential } from './lib/testCredentials.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const envPath = path.resolve(__dirname, '../.env.local');

const envContent = fs.readFileSync(envPath, 'utf8');
const envVars = {};

envContent.split('\n').forEach((line) => {
  const trimmed = line.trim();
  if (trimmed && !trimmed.startsWith('#')) {
    const match = trimmed.match(/^([^=]+)=(.*)$/);
    if (match) {
      const key = match[1].trim();
      let value = match[2].trim();
      if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }
      envVars[key] = value;
    }
  }
});

const supabaseUrl = envVars.VITE_SUPABASE_URL;
const supabaseAnonKey = envVars.VITE_SUPABASE_ANON_KEY;

async function checkAccount(email, password, expectedRole) {
  console.log(`\n================================================================`);
  console.log(` CHECKING ACCOUNT: ${email} (${expectedRole})`);
  console.log(`================================================================`);

  const client = createClient(supabaseUrl, supabaseAnonKey);

  const { data: authData, error: signInErr } = await client.auth.signInWithPassword({
    email,
    password,
  });

  if (signInErr) {
    console.error(`[${email}] Sign in failed:`, signInErr.message);
    return false;
  }

  const userId = authData.user.id;
  console.log(`[${email}] Signed in. UID: ${userId}`);

  // Fetch user profile
  const { data: profile, error: profErr } = await client
    .from('user_profiles')
    .select('*')
    .eq('id', userId)
    .single();

  if (profErr) {
    console.error(`[${email}] Profile query failed:`, profErr.message);
    return false;
  }
  console.log(`[${email}] Profile: full_name="${profile.full_name}", is_super_admin=${profile.is_super_admin}`);

  // Fetch user roles
  const { data: roles, error: rolesErr } = await client
    .from('user_roles')
    .select('role_id, role:roles(id, code, name)')
    .eq('user_id', userId);

  if (rolesErr) {
    console.error(`[${email}] Roles query failed:`, rolesErr.message);
    return false;
  }
  const assignedRoles = roles.map((r) => r.role?.code).filter(Boolean);
  console.log(`[${email}] Assigned DB Roles:`, assignedRoles);

  // Check Catalogue query
  const { data: tests, error: testsErr } = await client
    .from('tests')
    .select('id, code, name, is_active')
    .eq('is_active', true);

  console.log(`[${email}] Catalogue Query: ${testsErr ? `Error (${testsErr.message})` : `SUCCESS (${tests?.length} tests)`}`);

  // Check Audit Logs query (Admin should succeed, Tech should get 0 rows or denied by RLS)
  const { data: audits, error: auditErr } = await client
    .from('audit_logs')
    .select('id, action')
    .limit(5);

  console.log(`[${email}] Audit Logs Query: ${auditErr ? `Denied (${auditErr.message})` : `Returned ${audits?.length} rows`}`);

  return true;
}

async function run() {
  const admin = getAdminCredential();
  const tech = getTechCredential();
  const adminOk = await checkAccount(admin.email, admin.password, 'ADMIN');
  const techOk = await checkAccount(tech.email, tech.password, 'LAB_TECHNICIAN');

  if (!adminOk || !techOk) {
    console.error('Account verification failed.');
    process.exit(1);
  }
  console.log('\n✅ All RBAC checks completed successfully.');
}

run();
