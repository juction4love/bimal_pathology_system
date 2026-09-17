import crypto from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { createClient } from '@supabase/supabase-js';
import { assertSyntheticStagingTarget } from './staging-target-guard.js';
import { PERMISSION_KEYS } from '../src/types/permissions.ts';

const { STAGING_SUPABASE_URL:url, STAGING_ANON_KEY:anonKey, STAGING_SERVICE_KEY:serviceKey } = process.env;
if (!url || !anonKey || !serviceKey) throw new Error('Staging URL and API keys are required in process memory.');
if (!['00059','00060'].includes(process.env.STAGING_EXPECTED_MIGRATION_HEAD)) throw new Error('Canonical-role acceptance requires staging head 00059 or 00060.');
assertSyntheticStagingTarget({ expectedHead:process.env.STAGING_EXPECTED_MIGRATION_HEAD });

const service = createClient(url, serviceKey, { auth:{persistSession:false,autoRefreshToken:false} });
const anon = createClient(url, anonKey, { auth:{persistSession:false,autoRefreshToken:false} });
const adminRole='00000000-0000-0000-0000-000000000001';
const technicianRole='00000000-0000-0000-0000-000000000004';
const verifierRole='00000000-0000-0000-0000-000000000007';
const signatoryRole='00000000-0000-0000-0000-000000000008';
const allPermissions=Object.values(PERMISSION_KEYS);
const expected={
  admin:new Set(allPermissions),
  technician:new Set(['can_view_dashboard','can_collect_sample','can_receive_sample','can_reject_sample','can_enter_results','can_acknowledge_critical','can_print_reports','can_manage_outsource_tracking']),
  verifier:new Set(['can_view_dashboard','can_verify_results','can_acknowledge_critical','can_print_reports']),
  signatory:new Set(['can_view_dashboard','can_sign_reports','can_amend_reports','can_print_reports']),
};
const evidence={target:'ilcnctiaumrjbnlmnise',head:process.env.STAGING_EXPECTED_MIGRATION_HEAD,personas:{},checks:[],sparrow_send_attempted:false};
const check=(pass,name,detail={})=>{ if(!pass) throw new Error(`${name}: ${JSON.stringify(detail)}`); evidence.checks.push({name,pass:true,...detail}); };
const password=()=>`${crypto.randomBytes(24).toString('base64url')}!aA7`;

const listed=await service.auth.admin.listUsers({page:1,perPage:1000});
if(listed.error) throw listed.error;
const candidates=listed.data.users.filter(user=>
  user.email?.endsWith('@example.invalid')
  && /(?:foundation|phase\s*2).*(?:bootstrap|admin)|qa administrator/i.test(user.user_metadata?.full_name??''));
let bootstrapClient=null;
for(const candidate of candidates){
  const bootstrapPassword=password();
  const reset=await service.auth.admin.updateUserById(candidate.id,{password:bootstrapPassword,email_confirm:true});
  if(reset.error) continue;
  const client=createClient(url,anonKey,{auth:{persistSession:false,autoRefreshToken:false}});
  const login=await client.auth.signInWithPassword({email:candidate.email,password:bootstrapPassword});
  if(login.error) continue;
  const authority=await client.rpc('has_permission',{p_permission_key:'can_manage_users'});
  if(!authority.error&&authority.data===true){bootstrapClient=client;break;}
}
if(!bootstrapClient) throw new Error('No active synthetic staging Administrator is available for authoritative update_user_access calls.');

const stamp=`${Date.now().toString(36)}-${crypto.randomBytes(3).toString('hex')}`;
async function createActor(label,roleId,active=true){
  const email=`qa-${label}-${stamp}@example.invalid`;
  const actorPassword=password();
  const made=await service.auth.admin.createUser({email,password:actorPassword,email_confirm:true,user_metadata:{full_name:`QA ${label[0].toUpperCase()+label.slice(1)}`,qa_marker:'BIMAL-RBAC-00059'}});
  if(made.error) throw made.error;
  const access=await bootstrapClient.rpc('update_user_access',{p_user_id:made.data.user.id,p_is_active:active,p_is_super_admin:false,p_role_ids:active&&roleId?[roleId]:[]});
  if(access.error) throw access.error;
  const client=createClient(url,anonKey,{auth:{persistSession:false,autoRefreshToken:false}});
  if(active){const login=await client.auth.signInWithPassword({email,password:actorPassword});if(login.error)throw login.error;}
  evidence.personas[label]={user_id:made.data.user.id,email,active};
  return client;
}
const clients={
  admin:await createActor('administrator',adminRole),
  technician:await createActor('technician',technicianRole),
  verifier:await createActor('verifier',verifierRole),
  signatory:await createActor('signatory',signatoryRole),
};
const inactive=await createActor('inactive',technicianRole,false);

for(const [label,client] of Object.entries(clients)){
  for(const permission of allPermissions){
    const result=await client.rpc('has_permission',{p_permission_key:permission});
    if(result.error) throw result.error;
    check(result.data===expected[label].has(permission),`${label}:${permission}`);
  }
  const direct=await client.from('test_results').update({comments:'QA-DIRECT-DML-MUST-FAIL'}).eq('id',crypto.randomUUID()).select('id');
  check(Boolean(direct.error)||direct.data?.length===0,`${label}:direct-clinical-DML-denied`,{code:direct.error?.code??null});
}
for(const [label,client] of [['inactive',inactive],['anonymous',anon]]){
  const result=await client.rpc('has_permission',{p_permission_key:'can_view_dashboard'});
  check(Boolean(result.error)||result.data===false,`${label}:permission-denied`,{code:result.error?.code??null});
}
check(!expected.technician.has('can_verify_results')&&!expected.technician.has('can_sign_reports'),'technician-separation');
check(expected.verifier.has('can_verify_results')&&!expected.verifier.has('can_sign_reports')&&!expected.verifier.has('can_amend_reports'),'verifier-separation');
check(expected.signatory.has('can_sign_reports')&&expected.signatory.has('can_amend_reports')&&!expected.signatory.has('can_verify_results'),'signatory-separation');
check(!expected.signatory.has('can_manage_users')&&!expected.verifier.has('can_manage_catalogue'),'administrative-separation');

await mkdir('artifacts',{recursive:true});
await writeFile('artifacts/staging-canonical-role-auth-acceptance.json',JSON.stringify(evidence,null,2));
console.log(JSON.stringify({pass:true,personas:Object.keys(evidence.personas).length,checks:evidence.checks.length,secrets_logged:false}));
