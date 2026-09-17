import { randomUUID } from 'node:crypto';
import { access, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { GatewayWorker } from './app/GatewayWorker.js';
import { HeartbeatWorker } from './app/HeartbeatWorker.js';
import { loadConfig } from './config/GatewayConfig.js';
import { HealthState } from './observability/HealthState.js';
import { JsonLogger } from './observability/JsonLogger.js';
import { SparrowProvider } from './providers/sparrow/SparrowProvider.js';
import { DpapiSecretStore } from './security/DpapiSecretStore.js';
import { GatewayAuth } from './supabase/GatewayAuth.js';
import { GatewayRpcClient } from './supabase/GatewayRpcClient.js';
import { servicePaths } from './platform/ServicePaths.js';

const dataDirectory = process.env.BIMAL_SMS_GATEWAY_DATA ?? 'C:\\ProgramData\\BimalPathology\\SmsGatewayClean';
const paths = servicePaths(dataDirectory);
const config = await loadConfig(paths.config);
const bridgePath = join(import.meta.dirname, 'security', 'DpapiBridge.ps1');
const secrets = await new DpapiSecretStore(paths.secrets, bridgePath).load();
const logger = new JsonLogger(paths.log);
const auth = new GatewayAuth(secrets);
const queue = new GatewayRpcClient(secrets, auth, config.rpcTimeoutMs);
const provider = new SparrowProvider(secrets.sparrowToken, secrets.sparrowSender);
const workerId = randomUUID();
const health = new HealthState(config.instanceId, workerId, config.version, config.mode);
await health.restore(paths.health);
const controller = new AbortController();
const stop = (): void => controller.abort(new Error('Service stop requested.'));
process.once('SIGINT', stop); process.once('SIGTERM', stop);
await rm(paths.stopRequest, { force: true });
const sentinel = setInterval(async () => { try { await access(paths.stopRequest); stop(); } catch { /* absent */ } }, 250);
try { await Promise.all([new GatewayWorker(config, queue, provider, health, logger, workerId).run(controller.signal), new HeartbeatWorker(config, queue, provider, health, logger, paths.health).run(controller.signal)]); }
finally { clearInterval(sentinel); await health.write(paths.health); await rm(paths.stopRequest, { force: true }); await logger.info('gateway.stopped'); }
