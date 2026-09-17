import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export const BASELINE_HEAD = '00075';
export const CANDIDATE_HEAD = '00079';
export const DEFERRED_CLOUD_SMS = '00070_cloud_sms_dispatch_coordination.sql';
export const CANDIDATE_SET_SHA256 = '34e1f624cb1413f1ef7c6bfbdda45b79c25739129a7f93bb10f0956ad5f1550b';
export const CANDIDATE = Object.freeze({
  '00076_sms_gateway_v2_identity_and_heartbeat.sql': 'bc877a67213080c79b0570cbe0e388041ede9e535c48a00e35da0d1304f7f29f',
  '00077_two_role_permission_reconciliation.sql': 'd4ba407ba2c96b2d23007f5fca0c65532800f15e35b2369e840051597237be6f',
  '00078_two_role_authorization_and_catalogue_access.sql': '12d40657ffc47f90cb2c96aefdb557cd3377727c003a5c42dac3ef602cf09112',
  '00079_single_operator_report_authorization.sql': 'a6f57eabe02ed5ed75dc888e6c2a5158f9ced814ac394bf4ca5935190b34fb6f',
});

const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
const versionOf = name => name.slice(0,name.indexOf('_'));

export function verifyCandidate00079(root=process.cwd()) {
  const migrationDir=path.join(root,'supabase','migrations');
  const deferredDir=path.join(root,'supabase','deferred_migrations');
  const files=fs.readdirSync(migrationDir).filter(name=>/^\d{5,}_.+\.sql$/.test(name)).sort((a,b)=>versionOf(a).localeCompare(versionOf(b))||a.localeCompare(b));
  const pending=files.filter(name=>versionOf(name)>BASELINE_HEAD);
  if(JSON.stringify(pending)!==JSON.stringify(Object.keys(CANDIDATE))) throw new Error(`CANDIDATE_00079_PENDING_SET_MISMATCH: ${pending.join(',')}`);
  for(const[name,expected]of Object.entries(CANDIDATE)){const actual=sha256(fs.readFileSync(path.join(migrationDir,name)));if(actual!==expected)throw new Error(`CANDIDATE_00079_CHECKSUM_MISMATCH: ${name} ${actual}`)}
  if(!fs.existsSync(path.join(deferredDir,DEFERRED_CLOUD_SMS))) throw new Error('DEFERRED_00070_MISSING');
  if(files.some(name=>/cloud[_-]sms/i.test(name))) throw new Error('CLOUD_SMS_PRESENT_IN_DEPLOYABLE_MIGRATIONS');
  const setHash=crypto.createHash('sha256');
  for(const name of files.filter(name=>versionOf(name)<=CANDIDATE_HEAD)){setHash.update(name);setHash.update('\0');setHash.update(fs.readFileSync(path.join(migrationDir,name)));setHash.update('\0')}
  const migrationSetSha256=setHash.digest('hex');
  if(migrationSetSha256!==CANDIDATE_SET_SHA256) throw new Error(`CANDIDATE_00079_SET_HASH_MISMATCH: ${migrationSetSha256}`);
  return {baselineHead:BASELINE_HEAD,candidateHead:CANDIDATE_HEAD,pending,checksums:CANDIDATE,migrationSetSha256,deferredCloudSms:DEFERRED_CLOUD_SMS};
}
