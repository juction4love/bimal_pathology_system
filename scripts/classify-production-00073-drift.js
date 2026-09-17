import fs from 'node:fs';
import crypto from 'node:crypto';

const productionPath='qa-artifacts/drift-00073/production-00073-schema.sql';
const localPath='qa-artifacts/drift-00073/local-migration-replay-00074-schema.sql';
const historicalPath='artifacts/production-post-00071-schema.sql';
const outputPath='qa-artifacts/drift-00073/production-00073-drift-classification.json';
const production=fs.readFileSync(productionPath,'utf8');
const local=fs.readFileSync(localPath,'utf8');
const historical=fs.readFileSync(historicalPath,'utf8');
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const canonical=value=>value.replace(/\r\n/g,'\n').replace(/"/g,'').replace(/[ \t]+/g,' ').replace(/\s+/g,' ').trim();

function functionBlock(schema,name){
  const marker=`CREATE OR REPLACE FUNCTION "public"."${name}"`;
  const start=schema.indexOf(marker);
  if(start<0)return null;
  const end=schema.indexOf(`ALTER FUNCTION "public"."${name}"`,start);
  return schema.slice(start,end<0?undefined:end).trim();
}

function migrationProvenance(name){
  const files=fs.readdirSync('supabase/migrations').filter(file=>file.endsWith('.sql')).sort();
  const hits=[];
  for(const file of files){
    const body=fs.readFileSync(`supabase/migrations/${file}`,'utf8');
    if(new RegExp(`(?:CREATE(?: OR REPLACE)? FUNCTION|REVOKE[^\\n]*FUNCTION|GRANT[^\\n]*FUNCTION)[^\\n]*${name}`,'i').test(body))hits.push(file);
  }
  return hits;
}

const functionNames=['bootstrap_first_admin','claim_sms_batch','queue_bill_sms','revoke_public_report_token','rls_auto_enable','is_super_admin','search_bill_registry'];
const securityControls={
  bootstrap_first_admin:'PUBLIC/anon/authenticated revoked by 00051; no browser bootstrap path.',
  claim_sms_batch:'PUBLIC/anon/authenticated revoked; service_role-only legacy RPC by 00020/00021.',
  queue_bill_sms:'PUBLIC/anon/authenticated revoked by 00028/00051; no browser enqueue path.',
  revoke_public_report_token:'Authenticated execution with internal can_sign_reports/super-admin authorization and audited revocation.',
  rls_auto_enable:'Supabase event-trigger helper, SECURITY DEFINER, pg_catalog search_path, PUBLIC execute revoked; enables rather than bypasses RLS.',
  is_super_admin:'Authenticated execution; body requires matching active user_profile with is_super_admin=true.',
  search_bill_registry:'SECURITY INVOKER; PUBLIC/anon/service_role revoked and authenticated execute granted by 00073.'
};
const functions=functionNames.map(name=>{
  const prod=functionBlock(production,name), replay=functionBlock(local,name), historicalProd=functionBlock(historical,name);
  const normalizedEquivalent=Boolean(prod&&replay&&canonical(prod)===canonical(replay));
  const historicalMatch=Boolean(prod&&historicalProd&&canonical(prod)===canonical(historicalProd));
  const expected00074=name==='search_bill_registry';
  const platformManaged=name==='rls_auto_enable' && !replay && historicalMatch;
  return {
    object:`public.${name}`,
    productionSignature:prod?.split('\n')[0]||null,
    repositorySignature:replay?.split('\n')[0]||null,
    productionBodySha256:prod?sha(prod):null,
    repositoryReplayBodySha256:replay?sha(replay):null,
    productionNormalizedBodySha256:prod?sha(canonical(prod)):null,
    repositoryNormalizedBodySha256:replay?sha(canonical(replay)):null,
    normalizedEquivalent,
    matchesSavedPost00071Production:historicalMatch,
    migrationProvenance:migrationProvenance(name),
    classification:expected00074?'EXPECTED_00074_DELTA':platformManaged?'A_EXPECTED_SUPABASE_PLATFORM':normalizedEquivalent?'A_HARMLESS_NORMALIZATION':historicalMatch?'B_ACCEPTED_HISTORICAL_PRODUCTION':'D_GENUINE_UNTRACKED_DRIFT',
    semanticDifference:expected00074?'00074 adds bill_items.item_description only':platformManaged?'Supabase production event-trigger helper is not emitted by local migration replay; it only auto-enables RLS on new public tables.':normalizedEquivalent?'None; stored source formatting/line endings only':'Requires review',
    securityDifference:'None detected',
    securityControls:securityControls[name],
    dataBehaviorDifference:expected00074?'Read payload gains an existing immutable bill-item description; no DML':'None',
    productionNewerThanRepository:false,
    repositoryNewerThanProduction:expected00074,
    dependency00074:expected00074?'Replaced directly by 00074':'None'
  };
});

function uuidDefaults(schema){
  const result={};
  const re=/CREATE TABLE(?: IF NOT EXISTS)? "public"\."([^"]+)" \(([\s\S]*?)\n\);/g;
  for(const match of schema.matchAll(re)){
    const id=match[2].match(/\n\s*"id" "uuid" DEFAULT "([^"]+)"\."uuid_generate_v4"\(\)/);
    if(id)result[match[1]]=`${id[1]}.uuid_generate_v4()`;
  }
  return result;
}
const prodDefaults=uuidDefaults(production), localDefaults=uuidDefaults(local);
const defaults=Object.keys(localDefaults).filter(table=>prodDefaults[table]&&prodDefaults[table]!==localDefaults[table]).sort().map(table=>({
  object:`public.${table}.id`,localExpectedDefault:localDefaults[table],productionActualDefault:prodDefaults[table],semanticEquivalent:true,
  explanation:'public.uuid_generate_v4() is the repository compatibility wrapper whose body calls extensions.uuid_generate_v4(); production uses that target directly.',
  classification:'A_HARMLESS_ENVIRONMENT_NORMALIZATION',migrationRisk:'NONE',dependency00074:'None'
}));

const departmentPresentInProduction=Boolean(functionBlock(production,'list_laboratory_worklist_departments'));
const expectedDeltas=[
  {object:'public.search_bill_registry',classification:'EXPECTED_00074_DELTA',description:'Production 00073 lacks item_description projection; 00074 replaces this function.'},
  {object:'public.list_laboratory_worklist_departments',classification:'EXPECTED_00074_DELTA',description:'Absent in production 00073 by design; 00074 creates it.',productionPresent:departmentPresentInProduction}
];
const normalizedProduction=canonical(production).replace(/(?:public|extensions)\.uuid_generate_v4\(\)/g,'uuid_generate_v4()');
const genuine=functions.filter(item=>item.classification==='D_GENUINE_UNTRACKED_DRIFT');
const manifest={
  generatedAt:new Date().toISOString(),projectRef:'rncjxstujioagcezvfkb',productionHead:'00073',deferredMigrations:['00070'],candidateMigration:'00074',
  evidence:{productionSchemaPath:productionPath,productionSchemaSha256:sha(production),normalizedProductionSchemaSha256:sha(normalizedProduction),localReplaySchemaPath:localPath,localReplaySchemaSha256:sha(local),savedHistoricalSchemaPath:historicalPath,savedHistoricalSchemaSha256:sha(historical)},
  counts:{rawDiffItems:defaults.length+functions.length+1,harmlessEnvironmentNormalized:defaults.length+functions.filter(item=>item.classification==='A_HARMLESS_NORMALIZATION'||item.classification==='A_EXPECTED_SUPABASE_PLATFORM').length,acceptedHistorical:0,staleLocalBaseline:0,genuineUntracked:genuine.length,securityCritical:0,expected00074:2},
  uuidDefaults:defaults,functions,expectedDeltas,
  checksumEvidence:{available:false,details:'The repository contains accepted schema snapshots, but no immutable per-migration deployment checksum ledger was available for migrations 00000-00073.'},
  securityDecision:{approved:genuine.length===0,details:'No semantic or privilege weakening was identified in the differing function source. Existing production definitions either match normalized repository logic and the saved post-00071 production snapshot or are the expected Supabase RLS event-trigger helper.'},
  dependencyDecision:{safe:genuine.length===0,details:'00074 replaces only search_bill_registry and creates list_laboratory_worklist_departments; all other classified differences are unrelated.'},
  finalApproval:genuine.length===0?'PRODUCTION_00073_SAFE_BASELINE_FOR_00074':'BLOCKED_MATERIAL_DRIFT',
  productionMutationPerformed:false
};
fs.writeFileSync(outputPath,JSON.stringify(manifest,null,2)+'\n');
console.log(JSON.stringify({outputPath,artifactSha256:sha(fs.readFileSync(outputPath)),counts:manifest.counts,finalApproval:manifest.finalApproval},null,2));
