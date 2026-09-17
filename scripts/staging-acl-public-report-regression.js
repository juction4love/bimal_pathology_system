import { readFile } from 'node:fs/promises';
import { createClient } from '@supabase/supabase-js';
import { assertSyntheticStagingTarget } from './staging-target-guard.js';
import { bootstrapAdminClient } from './hosted-synthetic-actors.js';

const { STAGING_SUPABASE_URL:url, STAGING_ANON_KEY:anonKey } = process.env;
if (!url || !anonKey) throw new Error('Guarded staging URL and anon key are required.');
assertSyntheticStagingTarget({ expectedHead:process.env.STAGING_EXPECTED_MIGRATION_HEAD });
const admin = await bootstrapAdminClient(url, anonKey);
const anon = createClient(url, anonKey, { auth:{ persistSession:false, autoRefreshToken:false } });
const lifecycle = JSON.parse(await readFile('artifacts/phase2-clinical-lifecycle.json','utf8'));
const { report_id:reportId, report_number:reportNumber, integrity_hash:integrityHash,
  report_token_id:tokenId, report_token_hash:tokenHash } = lifecycle.ids || {};
if (![reportId,reportNumber,integrityHash,tokenId,tokenHash].every(Boolean)) {
  throw new Error('Fresh synthetic lifecycle token evidence is required.');
}

const active = await anon.rpc('resolve_public_report_by_token',{ p_token_hash:tokenHash });
if (active.error || !active.data?.valid) throw active.error || new Error('Active token did not resolve.');
if (active.data.report_number !== reportNumber || active.data.integrity_hash !== integrityHash || active.data.version !== 1) {
  throw new Error('PUBLIC_REPORT_VERSION_BINDING_MISMATCH');
}
for (const table of ['test_categories','test_results','public_report_tokens','sms_queue_items']) {
  const probe = await anon.from(table).select('*',{ count:'exact',head:true });
  if (!probe.error) throw new Error(`ANON_PROTECTED_TABLE_ACCESS_PRESENT:${table}`);
}

const revoked = await admin.rpc('revoke_public_report_token',{ p_token_id:tokenId,p_reason:'Synthetic ACL acceptance' });
if (revoked.error) throw revoked.error;
const revokedResolve = await anon.rpc('resolve_public_report_by_token',{ p_token_hash:tokenHash });
if (revokedResolve.error || revokedResolve.data?.valid !== false) throw revokedResolve.error || new Error('Revoked token resolved.');
const invalid = await anon.rpc('resolve_public_report_by_token',{ p_token_hash:'0'.repeat(64) });
if (invalid.error || invalid.data?.valid !== false) throw invalid.error || new Error('Invalid token was not denied.');
const frozen = await admin.from('diagnostic_reports').select('integrity_hash,version').eq('id',reportId).single();
if (frozen.error || frozen.data.integrity_hash !== integrityHash || frozen.data.version !== 1) {
  throw frozen.error || new Error('Frozen report changed during token revocation.');
}

console.log(JSON.stringify({ pass:true,active_resolved:true,revoked_denied:true,
  invalid_token_denied:true,exact_report_version_binding:true,qr_route_shape:'/r/{opaque-token}',
  anon_protected_tables_denied:true,frozen_report_unchanged:true,sparrow_send_attempted:false }));
