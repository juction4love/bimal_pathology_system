import fs from 'node:fs'
import { createHash } from 'node:crypto'

const migration='supabase/migrations/00067_master_catalogue_256_identity_architecture.sql'
const convergence='supabase/migrations/00068_master_catalogue_service_role_read_convergence.sql'
const summary='supabase/migrations/00069_master_catalogue_acceptance_summary.sql'
const source='docs/audits/master-catalogue-reconciliation-256.csv'
const must=(ok,message)=>{if(!ok)throw new Error(message);console.log(`PASS ${message}`)}
const sql=fs.readFileSync(migration,'utf8')
const csv=fs.readFileSync(source,'utf8')
must(csv.trim().split(/\r?\n/).length===257,'reconciliation contains header plus 256 rows')
must((sql.match(/INSERT INTO public\.catalogue_master_source_rows/g)||[]).length===256,'migration accounts for every source row')
must(sql.includes("CHECK(source_row_count=256)")&&sql.includes('TM256_ACCOUNTING_FAILED'),'256-row invariant is fail closed')
must(sql.includes('catalogue_source_disposition_enum')&&sql.includes('catalogue_reporting_model_enum'),'disposition and reporting model are explicit')
must(sql.includes("false,'Draft','Requires Clinical Validation'")&&sql.includes('true,false,false,false'),'new identities are Draft and non-operational')
must(sql.includes('TM256_REPORTING_WITHOUT_STRUCTURE')&&sql.includes('TM256_SPECIALIST_GENERIC_REPORTING'),'clinical and specialist reporting gates are asserted')
must(sql.includes("code IN('AFP','BETA HCG','LIPID','RFT')")&&sql.includes('TM256 convergence: structurally incomplete legacy identity held non-operational')&&sql.includes('clinical_reporting_enabled=false'),'known legacy zero-parameter reporting identities are prospectively quarantined without ID deletion')
must((sql.match(/INSERT INTO public\.catalogue_profile_components/g)||[]).length>=50,'profile component architecture is seeded')
for(const code of ['TLC','PCV','CK_MB','LIPID_PROFILE','KFT','ABS_DLC','RBC_INDICES','PLATELET_INDICES','DENGUE_PANEL','HAV_PANEL'])must(sql.includes(`'${code}'`),`${code} canonical identity/alias is represented`)
for(const model of ['MicrobiologyWorkflow','CytologyWorkflow','MolecularWorkflow','StructuredNested'])must(sql.includes(`'${model}'`),`${model} boundary is represented`)
must(fs.existsSync('supabase/deferred_migrations/00070_cloud_sms_dispatch_coordination.sql'),'cloud SMS remains deferred at 00070')
must(!fs.readdirSync('supabase/migrations').some(x=>x.includes('cloud_sms')),'cloud SMS absent from deployable migrations')
must(fs.readFileSync(convergence,'utf8').includes('TO service_role')&&fs.readFileSync(convergence,'utf8').includes('TM256_ANON_METADATA_PRIVILEGE_LEAK'),'hosted privilege convergence is narrow and asserted')
must(fs.readFileSync(summary,'utf8').includes("auth.role() <> 'service_role'")&&fs.readFileSync(summary,'utf8').includes('REVOKE ALL'),'acceptance summary is service-role only')
console.log(JSON.stringify({migration_sha256:createHash('sha256').update(sql).digest('hex'),source_rows:256},null,2))
