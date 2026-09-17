import { createClient } from '@supabase/supabase-js'
import fs from 'node:fs/promises'

const { STAGING_SUPABASE_URL:url, STAGING_SERVICE_KEY:key, STAGING_PROJECT_REF:ref, STAGING_EXPECTED_MIGRATION_HEAD:head } = process.env
if (ref !== 'ilcnctiaumrjbnlmnise' || url !== 'https://ilcnctiaumrjbnlmnise.supabase.co' || head !== '00069' || !key) throw new Error('Isolated staging 00069 credentials/identity are required')
const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}})
const checks=[]; const check=(ok,name,details={})=>{checks.push({name,pass:Boolean(ok),...details});if(!ok)throw new Error(`${name} failed: ${JSON.stringify(details)}`)}
const all=async(table,select='*')=>{const out=[];for(let from=0;;from+=500){const {data,error}=await db.from(table).select(select).range(from,from+499);if(error)throw error;out.push(...data);if(data.length<500)return out}}

const [sourceRows,components,conflicts,summaryResult]=await Promise.all([
  all('catalogue_master_source_rows'),all('catalogue_profile_components'),all('catalogue_identity_conflicts'),db.rpc('catalogue_master_acceptance_summary'),
])
if(summaryResult.error)throw summaryResult.error;const summary=summaryResult.data
check(sourceRows.length===256,'all 256 source rows accounted',{count:sourceRows.length})
check(new Set(sourceRows.map(x=>x.source_number)).size===256,'source numbers unique')
const dispositions=Object.fromEntries(Object.entries(sourceRows.reduce((a,x)=>((a[x.disposition]=(a[x.disposition]||0)+1),a),{})).sort())
const models=summary.reporting_models
check(summary.unique_codes,'canonical codes unique',{tests:summary.tests})
check(summary.draft_operational===0,'Draft identities non-operational')
check(summary.reporting_without_structure===0,'no reporting without active structure')
check(summary.specialist_generic_reporting===0,'specialists excluded from generic reporting')
check(summary.invalid_profile_components===0,'profile components valid',{count:components.length})
check(summary.duplicate_profile_order===0&&new Set(components.map(x=>`${x.profile_test_id}:${x.display_order}`)).size===components.length,'profile expansion deterministic')
for(const [code,ok] of Object.entries(summary.alias_checks))check(ok,`${code} aliases resolve`)
for(const [code,ok] of Object.entries(summary.required_profiles))check(ok,`${code} profile exists`)
check(conflicts.length>=6,'explicit conflict registry populated',{count:conflicts.length})
const departments=summary.departments
const evidence={project_ref:ref,migration_head:head,source_rows:sourceRows.length,tests:summary.tests,profiles:summary.profiles,profile_components:components.length,conflicts:conflicts.length,dispositions,reporting_models:models,departments,checks}
await fs.mkdir('artifacts/catalogue',{recursive:true});await fs.writeFile('artifacts/catalogue/staging-master-256-acceptance.json',JSON.stringify(evidence,null,2))
console.log(JSON.stringify(evidence,null,2))
