import { createClient } from '@supabase/supabase-js'
import { writeFile } from 'node:fs/promises'
import { assertSyntheticStagingTarget } from './staging-target-guard.js'
import { bootstrapAdminClient, provisionSyntheticActor } from './hosted-synthetic-actors.js'

const { STAGING_SUPABASE_URL:url, STAGING_ANON_KEY:anonKey, STAGING_SERVICE_KEY:serviceKey, STAGING_TEST_PASSWORD:password, STAGING_EXPECTED_MIGRATION_HEAD:expectedHead } = process.env
if (!url || !anonKey || !serviceKey || !password || !expectedHead) throw new Error('Guarded staging browser fixture environment is incomplete')
const target = assertSyntheticStagingTarget({ expectedHead })
const management = createClient(url, serviceKey, { auth:{ persistSession:false, autoRefreshToken:false } })
const admin = await bootstrapAdminClient(url, anonKey)
const adminUser = await admin.auth.getUser()
if (adminUser.error) throw adminUser.error
const techA = await provisionSyntheticActor({ url,anonKey,management,label:'browser-tech-a',password,roleId:'00000000-0000-0000-0000-000000000004' })
const techB = await provisionSyntheticActor({ url,anonKey,management,label:'browser-tech-b',password,roleId:'00000000-0000-0000-0000-000000000004' })
const verifier = await provisionSyntheticActor({ url,anonKey,management,label:'browser-verifier',password,roleId:'00000000-0000-0000-0000-000000000007' })
const signatory = await provisionSyntheticActor({ url,anonKey,management,label:'browser-signatory',password,roleId:'00000000-0000-0000-0000-000000000008' })

const pending = await admin.from('clinical_order_items').select('id,order_id,sample_id,test_name,status,result_revision,clinical_orders!inner(patients!inner(full_name))')
  .eq('status','Pending').eq('result_revision',0).not('sample_id','is',null).order('created_at',{ascending:false}).limit(50)
if (pending.error) throw pending.error
const fixture = pending.data[0]
if (!fixture) throw new Error('No synthetic Pending browser result fixture is available')
for (const to of ['Collected','Received']) {
  const transition = await techA.client.rpc('transition_sample_lifecycle',{ p_sample_id:fixture.sample_id,p_to_status:to,p_reason:null })
  if (transition.error) throw transition.error
}
const ready = await admin.from('clinical_order_items').select('id,status,result_revision').eq('id',fixture.id).single()
if (ready.error || ready.data.status !== 'SampleReceived' || ready.data.result_revision !== 0) throw ready.error || new Error('Browser fixture did not reach SampleReceived revision 0')
const evidence = { target,admin_user_id:adminUser.data.user.id,admin_email:adminUser.data.user.email,technician_user_id:techA.id,technician_email:techA.email,technician_b_user_id:techB.id,technician_b_email:techB.email,verifier_user_id:verifier.id,verifier_email:verifier.email,signatory_user_id:signatory.id,signatory_email:signatory.email,result_item_id:fixture.id,synthetic_fixture_verified:true }
await writeFile('artifacts/staging-browser-fixtures.json',JSON.stringify(evidence,null,2))
console.log(JSON.stringify(evidence))
