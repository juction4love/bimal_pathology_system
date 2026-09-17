import assert from 'node:assert/strict';
import fs from 'node:fs';
const migration=fs.readFileSync('supabase/deferred_migrations/00070_cloud_sms_dispatch_coordination.sql','utf8');
const worker=fs.readFileSync('cloudflare/sms-dispatcher/src/index.ts','utf8');
const config=fs.readFileSync('cloudflare/sms-dispatcher/wrangler.toml','utf8');
const tests=[
 ['production database default remains WindowsGateway',/DEFAULT 'WindowsGateway'/.test(migration)&&/VALUES\(TRUE,'WindowsGateway'\)/.test(migration)],
 ['worker defaults disabled',/DISPATCH_ENABLED = "false"/.test(config)],
 ['existing queue is extended not replaced',/ALTER TABLE public\.sms_queue_items/.test(migration)&&!/CREATE TABLE (?:IF NOT EXISTS )?public\.sms_queue_items/.test(migration)],
 ['bounded skip-locked claim is service-role only',/p_batch_size>25/.test(migration)&&/FOR UPDATE SKIP LOCKED/.test(migration)&&/auth\.role\(\)<>'service_role'/.test(migration)],
 ['deferred migration retains duplicate-delivery begin barrier',/cloud_delivery_started_at IS NULL/.test(migration)&&/begin_cloud_sms_delivery/.test(migration)],
 ['successful completion is idempotent',/q\.status='Sent'.*already_completed/s.test(migration)],
 ['unknown provider outcome is dead-lettered',/outcome is unknown and automatic resend is blocked/.test(migration)],
 ['pre-provider handoff loss is retryable',/before provider delivery; safely retrying/.test(migration)],
 ['legacy cloud worker is an explicit non-sending tombstone',/only authoritative SMS sender/.test(worker)&&/status: 410/.test(worker)],
 ['legacy cloud worker has no provider or queue authority',!/SPARROW_TOKEN|DISPATCH_CONTROL_SECRET|begin_cloud_sms_delivery|complete_cloud_sms_attempt|fetch\(['"]https?:/.test(worker)],
 ['scheduled and queue handlers are inert',/scheduled: \(\) => undefined/.test(worker)&&/queue: \(\) => undefined/.test(worker)],
 ['legacy response is non-cacheable',/cache-control': 'no-store/.test(worker)],
 ['no Windows gateway removal',fs.existsSync('tools/sms-gateway/BimalPathology.SmsGateway.csproj')],
];
let failed=0;for(const [name,pass]of tests){console.log(`${pass?'PASS':'FAIL'} ${name}`);if(!pass)failed++}assert.equal(failed,0,`${failed} cloud SMS checks failed`);console.log(`Cloud SMS dispatcher: ${tests.length} passed, 0 failed`);
