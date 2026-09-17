import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const migration = read('supabase/migrations/00075_catalogue_readiness_approval_workflow.sql');
const hardening = migration;
const edge = read('supabase/functions/dispatch-sms/index.ts');
const project = read('tools/sms-gateway/BimalPathology.SmsGateway.csproj');
const worker = read('tools/sms-gateway/SmsGatewayWorker.cs');
const queue = read('tools/sms-gateway/SupabaseQueueClient.cs');
const sparrow = read('tools/sms-gateway/SparrowClient.cs');
const secrets = read('tools/sms-gateway/ProtectedSettings.cs');
const healthStore = read('tools/sms-gateway/HealthStore.cs');
const health = healthStore + read('tools/sms-gateway/GatewayModels.cs');
const install = read('tools/sms-gateway/install/Install-SmsGateway.ps1');
const docs = read('tools/sms-gateway/README.md');
const paymentMigration = read('supabase/migrations/00028_transactional_payment_and_report_sms.sql');

let passed = 0;
const check = (condition, label) => {
  if (!condition) throw new Error(`FAIL: ${label}`);
  passed++;
  console.log(`PASS: ${label}`);
};

check(project.includes('<TargetFramework>net8.0-windows</TargetFramework>') && project.includes('<RuntimeIdentifier>win-x64</RuntimeIdentifier>'), 'gateway targets .NET 8 Windows x64');
check(worker.includes('TimeSpan.FromSeconds(20)') || read('tools/sms-gateway/GatewayModels.cs').includes('TimeSpan.FromSeconds(20)'), 'poll interval defaults to 20 seconds');
check(worker.includes('Task.Delay(options.PollInterval') && !worker.includes('while (true)'), 'worker has cancellable non-busy polling');
check(migration.includes('claim_next_sms_gateway_item') && migration.includes('FOR UPDATE SKIP LOCKED'), 'next-item claim is atomic and skip-locked');
check(migration.includes("q.status IN ('Pending','Failed')") && migration.includes('q.scheduled_at<=NOW()') && migration.includes('q.retry_count<q.max_attempts'), 'claim accepts only due retryable rows');
check(hardening.includes('recover_stale_sms_gateway_items') && hardening.includes('ProviderOutcomeUnknown') && hardening.includes('LeaseExpiredBeforeProviderCall'), 'stale pre-call leases recover and unknown provider outcomes quarantine');
check(hardening.includes('SMS lease ownership conflict') && hardening.includes("q.status='Sent'"), 'completion enforces lease ownership and Sent idempotency');
check(migration.includes('FROM PUBLIC,anon,authenticated') && migration.includes('TO service_role'), 'gateway RPCs are service-role-only');
check(worker.includes('ClaimNextAsync') && worker.includes('MarkProviderCallStartedAsync'), 'poller atomically claims one item and marks provider boundary');
check(queue.includes('rpc/complete_sms_gateway_item') && !queue.includes('.insert') && !queue.includes('message_body='), 'gateway only claims existing rows and uses guarded completion RPC');
check(sparrow.includes('https://api.sparrowsms.com/v2/sms/') && sparrow.includes('FormUrlEncodedContent'), 'gateway uses exact Sparrow endpoint and form encoding');
check(/"token"[\s\S]*"from"[\s\S]*"to"[\s\S]*"text"/.test(sparrow), 'provider fields are exactly ordered token, from, to, text');
check(sparrow.includes('httpStatus == 200') && sparrow.includes('parsed.ResponseCode == 200') && sparrow.includes('parsed.Count >= 1'), 'success requires all three provider acceptance gates');
check(sparrow.includes('1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1010, 1011, 1012, 1013'), 'all required permanent provider codes are classified');
check(sparrow.includes('httpStatus is 408 or 429 || httpStatus >= 500') && sparrow.includes('HttpRequestException') && sparrow.includes('timed out'), 'only bounded network timeout throttling and server failures are transient');
check(secrets.includes('DataProtectionScope.LocalMachine') && secrets.includes('ProtectedData.Protect') && secrets.includes('ProtectedData.Unprotect'), 'secrets use Windows machine-scope DPAPI');
check(!fs.existsSync('tools/sms-gateway/appsettings.json') && !fs.existsSync('tools/sms-gateway/appsettings.Production.json'), 'no plaintext gateway appsettings secrets exist');
check(health.includes('last_successful_send_at') && health.includes('queue_error_count') && !healthStore.includes('RecipientPhone'), 'health is operational and contains no patient identifier');
check(read('tools/sms-gateway/JsonFileLogger.cs').includes('Redaction.SafeProviderMessage') && read('tools/sms-gateway/Redaction.cs').includes('[mobile-redacted]'), 'structured logs redact credentials and mobiles');
check(install.includes("BimalPathologySMSGateway") && install.includes('-StartupType Automatic') && !install.includes('Start-Service'), 'installer registers Automatic service without activating it');
check(edge.includes('providerEnabled = false') && !edge.includes('sparrowsms.com') && !edge.includes('sms_queue_items'), 'Edge sender is a non-sending tombstone');
check(paymentMigration.includes("'PAYMENT_CONFIRMATION:' || v_payment.id::TEXT") && paymentMigration.includes("'REPORT_READY:' || p_report_id::TEXT || ':' || v_report.version::TEXT"), 'existing payment and report idempotency keys remain unchanged');
check(docs.includes('Sparrow does not accept an idempotency key') && docs.includes('HTTP response is lost'), 'exactly-once provider limitation is documented');
check(!worker.includes('HttpListener') && !worker.includes('MapPost') && !worker.includes('Console.ReadLine'), 'gateway exposes no compose or arbitrary-send endpoint');

console.log(`\nPhase 32 Windows SMS Gateway verification: ${passed} passed, 0 failed`);
