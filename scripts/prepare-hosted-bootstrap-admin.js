import { createClient } from '@supabase/supabase-js';
import { assertSyntheticStagingTarget } from './staging-target-guard.js';

const { STAGING_SUPABASE_URL:url, STAGING_SERVICE_KEY:serviceKey, STAGING_TEST_PASSWORD:password } = process.env;
if (!url || !serviceKey || !password || process.env.STAGING_EXPECTED_MIGRATION_HEAD !== '00058') throw new Error('Guarded staging bootstrap environment is incomplete.');
assertSyntheticStagingTarget({ expectedHead:process.env.STAGING_EXPECTED_MIGRATION_HEAD });
const management = createClient(url, serviceKey, { auth:{ persistSession:false } });
const listed = await management.auth.admin.listUsers({ page:1, perPage:1000 });
if (listed.error) throw listed.error;
if (listed.data.users.some(user => !user.email?.endsWith('@example.invalid'))) throw new Error('NON_SYNTHETIC_AUTH_IDENTITY_PRESENT');
let user = [...listed.data.users].sort((a,b) => new Date(a.created_at)-new Date(b.created_at))[0];
if (!user) {
  const email = `foundation-bootstrap-${Date.now().toString(36)}@example.invalid`;
  const made = await management.auth.admin.createUser({ email,password,email_confirm:true,user_metadata:{full_name:'Foundation Bootstrap Administrator'} });
  if (made.error) throw made.error;
  user = made.data.user;
} else {
  const updated = await management.auth.admin.updateUserById(user.id, { password, email_confirm:true });
  if (updated.error) throw updated.error;
}
console.log(JSON.stringify({ email:user.email, user_id:user.id, synthetic_only:true }));
