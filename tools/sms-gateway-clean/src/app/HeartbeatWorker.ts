import { hostname } from 'node:os';
import type { GatewayConfig } from '../config/GatewayConfig.js';
import type { HealthState } from '../observability/HealthState.js';
import type { JsonLogger } from '../observability/JsonLogger.js';
import type { SmsProvider } from '../providers/SmsProvider.js';
import type { GatewayRpcClient } from '../supabase/GatewayRpcClient.js';

export class HeartbeatWorker {
  constructor(private readonly config: GatewayConfig, private readonly queue: GatewayRpcClient, private readonly provider: SmsProvider, private readonly health: HealthState, private readonly logger: JsonLogger, private readonly healthPath: string) {}
  async run(signal: AbortSignal): Promise<void> {
    while (!signal.aborted) {
      try {
        this.provider.validateConfiguration();
        await this.queue.heartbeat(this.config.instanceId, {
          hostname: hostname(), gatewayVersion: this.config.version, providerName: this.provider.name,
          serviceStartedAt: this.health.serviceStartedAt, providerHealth: this.health.providerHealth, activeJobs: this.health.activeJobs,
          ...(this.health.lastQueueAccessAt ? { lastQueueAccessAt: this.health.lastQueueAccessAt } : {}),
          ...(this.health.lastProviderSuccessAt ? { lastProviderSuccessAt: this.health.lastProviderSuccessAt } : {}),
          ...(this.health.safeLastErrorCode ? { safeLastErrorCode: this.health.safeLastErrorCode } : {})
        }, signal);
        await this.health.write(this.healthPath);
      } catch (error) { await this.logger.error('heartbeat.failed', { error: error instanceof Error ? error.message : 'unknown' }); }
      if (!await this.delay(signal)) break;
    }
  }
  private async delay(signal: AbortSignal): Promise<boolean> { return await new Promise(resolve => { const timer = setTimeout(() => resolve(true), this.config.heartbeatMs); signal.addEventListener('abort', () => { clearTimeout(timer); resolve(false); }, { once: true }); }); }
}
