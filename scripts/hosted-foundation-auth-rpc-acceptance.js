import { createClient } from '@supabase/supabase-js';
import { writeFile } from 'node:fs/promises';
import { assertSyntheticStagingTarget } from './staging-target-guard.js';
import { bootstrapAdminClient, provisionSyntheticActor } from './hosted-synthetic-actors.js';

const { STAGING_SUPABASE_URL: url, STAGING_ANON_KEY: anonKey, STAGING_SERVICE_KEY: serviceKey, STAGING_TEST_PASSWORD: password } = process.env;
if (!url || !anonKey || !serviceKey || !password) throw new Error('Hosted acceptance credentials are required.');
if (!['00058','00059','00060'].includes(process.env.STAGING_EXPECTED_MIGRATION_HEAD)) throw new Error('STAGING_EXPECTED_MIGRATION_HEAD must be accepted foundation 00058, RBAC head 00059, or Technician-convergence head 00060.');
assertSyntheticStagingTarget({ expectedHead: process.env.STAGING_EXPECTED_MIGRATION_HEAD });
const service = createClient(url, serviceKey, { auth: { persistSession: false } });
const db = await bootstrapAdminClient(url, anonKey);
const stamp = Date.now().toString(36);
const evidence = { personas: {}, contracts: [] };
const assert = (value, message, detail) => { if (!value) throw new Error(`${message}: ${JSON.stringify(detail)}`); };

async function actor(label, roleId, active = true) {
  if (label === 'admin') {
    const user = await db.auth.getUser();
    evidence.personas[label] = { user_id:user.data.user.id,active:true };
    return db;
  }
  const made = await provisionSyntheticActor({ url, anonKey, management:service, label:`auth-${label}-${stamp}`, password, roleId, active });
  evidence.personas[label] = { user_id: made.id, active };
  return made.client;
}

const admin = await actor('admin', '00000000-0000-0000-0000-000000000001');
const technician = await actor('technician', '00000000-0000-0000-0000-000000000004');
const verifier = await actor('verifier', '00000000-0000-0000-0000-000000000007');
const signatory = await actor('signatory', '00000000-0000-0000-0000-000000000008');
const inactive = await actor('inactive', '00000000-0000-0000-0000-000000000004', false);
const anonymous = createClient(url, anonKey, { auth: { persistSession: false } });
const missingItem = '00000000-0000-0000-0000-000000000000';
const sixArgs = { p_order_item_id: missingItem, p_results: [], p_target_status: 'Draft', p_amended_from_report_id: null, p_amendment_reason: null, p_expected_revision: 0 };
const fiveArgs = { ...sixArgs }; delete fiveArgs.p_expected_revision;

for (const [label, client] of Object.entries({ admin, technician, verifier, signatory })) {
  const result = await client.rpc('save_test_results', sixArgs);
  assert(result.error && result.error.code !== 'PGRST202', 'six-argument save_test_results is not exposed', { label, error: result.error });
  evidence.contracts.push({ label, contract: 'six-argument RPC exposed', pass: true, downstream_code: result.error.code });
}
const obsolete = await admin.rpc('save_test_results', fiveArgs);
assert(obsolete.error?.code === 'PGRST202' || /function.*schema cache|could not find/i.test(obsolete.error?.message || ''), 'obsolete five-argument RPC remains callable', obsolete.error);
evidence.contracts.push({ label: 'admin', contract: 'five-argument RPC unavailable', pass: true, error_code: obsolete.error.code });

for (const [label, client] of Object.entries({ inactive, anonymous })) {
  const result = await client.rpc('save_test_results', sixArgs);
  assert(result.error, 'unauthorized persona completed a result mutation probe', { label, result });
  evidence.contracts.push({ label, contract: 'result mutation denied', pass: true, error_code: result.error.code });
}

const protectedRow = await db.from('test_results').select('id,display_value').limit(1).maybeSingle();
if (protectedRow.error) throw protectedRow.error;
if (protectedRow.data) {
  for (const [label, client] of Object.entries({ admin, technician, verifier, signatory, inactive, anonymous })) {
    const attempt = await client.from('test_results').update({ display_value: `BYPASS-${stamp}` }).eq('id', protectedRow.data.id).select('id');
    assert(attempt.error || attempt.data?.length === 0, 'direct test_results mutation was permitted', { label, attempt });
    evidence.contracts.push({ label, contract: 'direct table mutation denied/no rows', pass: true, error_code: attempt.error?.code || null });
  }
  const after = await db.from('test_results').select('display_value').eq('id', protectedRow.data.id).single();
  assert(after.data?.display_value === protectedRow.data.display_value, 'direct-table probe changed clinical data', after);
}

evidence.summary = { pass: true, genuine_auth_users: Object.keys(evidence.personas).length, contracts: evidence.contracts.length, sparrow_send_attempted: false };
await writeFile('artifacts/hosted-foundation-auth-rpc.json', JSON.stringify(evidence, null, 2));
console.log(JSON.stringify(evidence.summary));
