import assert from'node:assert/strict';
import test from'node:test';
import{handleGenerationRequest}from'../src/generation-endpoint.ts';

const secret='a'.repeat(48),request=(method='POST',value=secret)=>new Request('https://dashboard.bimalpathology.com.np/internal/generate',{method,headers:value===null?{}:{authorization:`Bearer ${value}`}});
test('missing Authorization returns 401',async()=>assert.equal((await handleGenerationRequest(request('POST',null),secret,async()=>({enabled:true}))).status,401));
test('malformed Bearer returns 401',async()=>assert.equal((await handleGenerationRequest(new Request('https://x/internal/generate',{method:'POST',headers:{authorization:`Token ${secret}`}}),secret,async()=>({enabled:true}))).status,401));
test('wrong secret returns 401',async()=>assert.equal((await handleGenerationRequest(request('POST','b'.repeat(48)),secret,async()=>({enabled:true}))).status,401));
test('correct secret invokes exactly one generation cycle',async()=>{let calls=0;const result=await handleGenerationRequest(request(),secret,async()=>{calls++;return{enabled:true,claimed:false}});assert.equal(result.status,200);assert.equal(calls,1)});
test('GET is rejected without invoking generation',async()=>{let calls=0;const result=await handleGenerationRequest(request('GET'),secret,async()=>{calls++;return{enabled:true}});assert.equal(result.status,405);assert.equal(calls,0)});
test('disabled generation is a safe no-op',async()=>assert.deepEqual((await handleGenerationRequest(request(),secret,async()=>({enabled:false}))).body,{attempted:false,claimed:false,generated:false,completed:false,status:'Disabled'}));
test('no claim is a safe no-op',async()=>assert.equal((await handleGenerationRequest(request(),secret,async()=>({enabled:true,claimed:false}))).body.status,'NoClaim'));
test('successful cycle reports Ready',async()=>assert.deepEqual((await handleGenerationRequest(request(),secret,async()=>({enabled:true,claimed:true,ready:true}))).body,{attempted:true,claimed:true,generated:true,completed:true,status:'Ready'}));
for(const code of['PDF_GENERATION_FAILED','R2_UPLOAD_FAILED'])test(code+' is safely returned',async()=>{const body=(await handleGenerationRequest(request(),secret,async()=>({enabled:true,claimed:true,ready:false,failureCode:code}))).body;assert.equal(body.safeErrorCode,code)});
test('completion failure is safely classified',async()=>{const result=await handleGenerationRequest(request(),secret,async()=>{throw new Error('RPC_complete_report_pdf_artifact_v2_409')});assert.equal(result.status,500);assert.equal(result.body.safeErrorCode,'COMPLETE_RPC_FAILED')});
test('repeated invocation does not duplicate a Ready artifact',async()=>{let pending=true,sends=0;const cycle=async()=>pending?(pending=false,sends++,{enabled:true,claimed:true,ready:true}):({enabled:true,claimed:false});await handleGenerationRequest(request(),secret,cycle);await handleGenerationRequest(request(),secret,cycle);assert.equal(sends,1)});
test('response contains no sensitive fields',async()=>{const body=(await handleGenerationRequest(request(),secret,async()=>({enabled:true,claimed:true,ready:true}))).body;for(const key of['patient','snapshot','token','objectKey','pdf','credential'])assert.equal(key in body,false)});
