import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const root=path.resolve(import.meta.dirname,'..');
const migrationDir=path.join(root,'supabase','migrations');
const deferredDir=path.join(root,'supabase','deferred_migrations');
const output=path.join(root,'qa-artifacts','migration-replay-00085','migration-order.json');
const key=name=>{const version=name.match(/^(\d+)_/)?.[1];if(!version)throw new Error(`Invalid migration filename: ${name}`);return version==='000565'?56.5:Number(version)};
const files=fs.readdirSync(migrationDir).filter(name=>name.endsWith('.sql')).sort((a,b)=>key(a)-key(b)||a.localeCompare(b));
if(files[0]!=='00000_supabase_extension_compatibility.sql'||!files.at(-1)?.startsWith('00085_'))throw new Error('Unexpected migration boundaries');
const special=files.indexOf('000565_legacy_hosted_privilege_preconvergence.sql');
if(files[special-1]!=='00056_foundation_result_readiness_and_revision.sql'||files[special+1]!=='00057_hosted_privilege_convergence.sql')throw new Error('000565 ordering contract failed');
const deferred=fs.readdirSync(deferredDir).filter(name=>name.endsWith('.sql')).sort();
const manifest={generatedAt:new Date().toISOString(),first:files[0],final:files.at(-1),count:files.length,files:files.map((name,index)=>({order:index+1,name,sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(migrationDir,name))).digest('hex')})),excluded:deferred.map(name=>({name,reason:'Repository policy keeps cloud SMS coordination outside the deployable migration chain'}))};
fs.mkdirSync(path.dirname(output),{recursive:true});
fs.writeFileSync(output,JSON.stringify(manifest,null,2)+'\n');
console.log(JSON.stringify({output:path.relative(root,output),count:files.length,first:manifest.first,final:manifest.final,excluded:deferred}));
