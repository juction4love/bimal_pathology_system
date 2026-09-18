import { readFileSync } from 'node:fs';
import test from 'node:test';import assert from 'node:assert/strict';import {SparrowProvider} from '../src/providers/sparrow/SparrowProvider.js';
const message={queueId:'q',recipient:'9800000000',body:'hello'};
test('accepted Sparrow response requires code and message ID',async()=>{const p=new SparrowProvider('t','s',(async()=>new Response(JSON.stringify({response_code:200,message_id:'id',count:1}),{status:200,headers:{'content-type':'application/json'}})) as typeof fetch);assert.equal((await p.send(message,AbortSignal.timeout(1000))).outcome,'accepted');});
test('Sparrow form fields are exact and ordered',async()=>{let body='';const p=new SparrowProvider('t','s',(async(_u:unknown,i?:RequestInit)=>{body=String(i?.body);return new Response(JSON.stringify({response_code:200,message_id:'id'}),{status:200,headers:{'content-type':'application/json'}});}) as typeof fetch);await p.send(message,AbortSignal.timeout(1000));assert.equal(body,'token=t&from=s&to=9800000000&text=hello');});
test('HTTP 429 is retryable',async()=>{const p=new SparrowProvider('t','s',(async()=>new Response(JSON.stringify({response_code:429}),{status:429,headers:{'content-type':'application/json'}})) as typeof fetch);assert.equal((await p.send(message,AbortSignal.timeout(1000))).outcome,'retryable_failure');});
test('HTTP 403 is provider unavailable',async()=>{const p=new SparrowProvider('t','s',(async()=>new Response('{}',{status:403,headers:{'content-type':'application/json'}})) as typeof fetch);assert.equal((await p.send(message,AbortSignal.timeout(1000))).outcome,'provider_unavailable');});
test('permanent Sparrow code is not retried',async()=>{const p=new SparrowProvider('t','s',(async()=>new Response(JSON.stringify({response_code:1002}),{status:400,headers:{'content-type':'application/json'}})) as typeof fetch);assert.equal((await p.send(message,AbortSignal.timeout(1000))).outcome,'permanent_failure');});
test('malformed response is unknown outcome',async()=>{const p=new SparrowProvider('t','s',(async()=>new Response('bad',{status:200})) as typeof fetch);assert.equal((await p.send(message,AbortSignal.timeout(1000))).outcome,'unknown_outcome');});
test('missing provider configuration fails without transport',()=>assert.throws(()=>new SparrowProvider('','s').validateConfiguration(),/CONFIGURATION/));

for (const body of ['http://example.com', 'HTTPS://example.com', 'www.example.com', 'lis.bimalpathology.com.np', 'dashboard.bimalpathology.com.np/o/secret', 'bit.ly/secret', '/r/secret', '/o/secret', 'https://192.168.1.1', 'example.org', 'https:\u200B//example.com', 'ｗｗｗ.example.com', 'ftp://example.com', 'mailto:a@example.com']) {
  test('blocks URL content before transport: ' + body, async () => {
    let calls = 0;
    const provider = new SparrowProvider('t', 's', (async () => { calls++; throw new Error('must not send'); }) as typeof fetch);
    assert.deepEqual(await provider.send({...message, body}, AbortSignal.timeout(1000)), {outcome:'permanent_failure', safeErrorCode:'SMS_URL_BLOCKED'});
    assert.equal(calls, 0);
  });
}
for (const body of ['Bimal Pathology: Your laboratory report is ready. Please collect it from the lab or contact 056-593288. Thank you.', 'Bimal Pathology: तपाईंको ल्याब रिपोर्ट तयार भएको छ। रिपोर्टका लागि ल्याबमा सम्पर्क गर्नुहोस्: 056-593288 धन्यवाद।', 'Bimal Pathology: Payment of NPR 1200.00 received for Lab No: BP-123. Thank you.']) {
  test('normal notification reaches Sparrow unchanged: ' + body, async () => {
    let sent = '';
    const provider = new SparrowProvider('t','s',(async (_url: unknown, init?: RequestInit) => { sent = new URLSearchParams(String(init?.body)).get('text')!; return new Response(JSON.stringify({response_code:200,message_id:'id'})); }) as typeof fetch);
    assert.equal((await provider.send({...message,body},AbortSignal.timeout(1000))).outcome,'accepted');
    assert.equal(sent,body);
  });
}

test('each report-ready SQL construction produces URL-free outbound text', async () => {
 const sql = readFileSync(new URL('../../../../supabase/migrations/00122_url_free_sms_notifications.sql', import.meta.url), 'utf8');
 const templates = [...sql.matchAll(/'Bimal Pathology: Your laboratory report is ready\.[^']*'/g)].map(match => match[0].slice(1,-1));
 assert.equal(templates.length, 3);
 for (const body of templates) {
  let transmitted = '';
  const provider = new SparrowProvider('t','s',(async (_url: unknown, init?: RequestInit) => { transmitted = new URLSearchParams(String(init?.body)).get('text')!; return new Response(JSON.stringify({response_code:200,message_id:'id'})); }) as typeof fetch);
  assert.equal((await provider.send({...message,body},AbortSignal.timeout(1000))).outcome,'accepted');
  assert.equal(transmitted,body);
  assert.doesNotMatch(transmitted,/https?:|www\.|bimalpathology\.|\/(r|o)\//i);
 }
});
