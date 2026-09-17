import assert from'node:assert/strict';
import test from'node:test';
import{runScheduled}from'../src/scheduled.ts';

const env={};
const run=async(resultOrError)=>{const logs=[];const generate=async()=>{if(resultOrError instanceof Error)throw resultOrError;return resultOrError};await assert.doesNotReject(()=>runScheduled(env,generate,async()=>({available:false}),value=>logs.push(JSON.parse(value))));return logs};

test('enabled pending claim completes during scheduled invocation',async()=>{const logs=await run({enabled:true,claimed:true,ready:true});assert.deepEqual(logs.map(x=>x.event),['artifact.schedule.started','artifact.complete.succeeded','report_pdf_delivery_acceptance'])});
test('disabled generation makes no claim',async()=>{const logs=await run({enabled:false});assert.deepEqual(logs.map(x=>x.event),['artifact.schedule.started','artifact.generation.disabled'])});
test('no available claim exits cleanly',async()=>{const logs=await run({enabled:true,claimed:false});assert.equal(logs[1].event,'artifact.claim.none')});
for(const [name,error,code]of[
  ['Auth failure',new Error('WORKER_AUTH_401'),'WORKER_AUTH_FAILED'],
  ['claim failure',new Error('RPC_claim_report_pdf_artifact_v2_403'),'CLAIM_RPC_FAILED'],
  ['completion failure',new Error('RPC_complete_report_pdf_artifact_v2_409'),'COMPLETE_RPC_FAILED'],
])test(name+' is safely classified',async()=>{const logs=[];await assert.rejects(()=>runScheduled(env,async()=>{throw error},async()=>({}),value=>logs.push(JSON.parse(value))));assert.equal(logs.at(-1).code,code)});
for(const code of['PDF_GENERATION_FAILED','R2_UPLOAD_FAILED'])test(code+' is safely reported',async()=>{const logs=await run({enabled:true,claimed:true,ready:false,failureCode:code});assert.equal(logs[1].code,code)});
test('repeated scheduled invocation does not duplicate an already Ready artifact',async()=>{let claims=1,completions=0;const generate=async()=>claims--?{enabled:true,claimed:true,ready:true}:{enabled:true,claimed:false};await runScheduled(env,generate,async()=>({}),()=>{});completions++;await runScheduled(env,generate,async()=>({}),()=>{});assert.equal(completions,1)});
