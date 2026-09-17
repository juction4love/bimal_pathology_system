import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import type { GatewayMode } from '../config/GatewayConfig.js';

export class HealthState {
  activeJobs = 0;
  readonly serviceStartedAt = new Date().toISOString();
  lastQueueAccessAt: string | undefined;
  lastProviderSuccessAt: string | undefined;
  safeLastErrorCode: string | undefined;
  providerHealth: 'Unknown' | 'Healthy' | 'Degraded' | 'Unavailable' | 'ConfigurationError' = 'Unknown';
  constructor(readonly instanceId: string, readonly workerId: string, readonly version: string, readonly mode: GatewayMode) {}
  queueOk(): void {
    this.lastQueueAccessAt = new Date().toISOString();
    if (this.safeLastErrorCode === 'QUEUE_RPC_FAILED') this.providerHealth = this.lastProviderSuccessAt ? 'Healthy' : 'Unknown';
    this.safeLastErrorCode = undefined;
  }
  providerOk(): void { this.lastProviderSuccessAt = new Date().toISOString(); this.providerHealth = 'Healthy'; }
  fail(code: string, health: typeof this.providerHealth = 'Degraded'): void { this.safeLastErrorCode = code; this.providerHealth = health; }
  async restore(path: string): Promise<void> {
    try {
      const saved = JSON.parse(await readFile(path, 'utf8')) as Record<string, unknown>;
      if (typeof saved.lastQueueAccessAt === 'string') this.lastQueueAccessAt = saved.lastQueueAccessAt;
      if (typeof saved.lastProviderSuccessAt === 'string') this.lastProviderSuccessAt = saved.lastProviderSuccessAt;
      if (typeof saved.safeLastErrorCode === 'string') this.safeLastErrorCode = saved.safeLastErrorCode;
      if (['Unknown','Healthy','Degraded','Unavailable','ConfigurationError'].includes(String(saved.providerHealth))) {
        this.providerHealth = String(saved.providerHealth) as typeof this.providerHealth;
      }
    } catch { /* first start or invalid stale snapshot: heartbeat remains conservative */ }
  }
  async write(path: string): Promise<void> {
    await mkdir(dirname(path), { recursive: true });
    const temp = `${path}.tmp`;
    await writeFile(temp, JSON.stringify({ instanceId: this.instanceId, workerId: this.workerId, version: this.version, mode: this.mode, serviceStartedAt: this.serviceStartedAt, activeJobs: this.activeJobs, lastQueueAccessAt: this.lastQueueAccessAt ?? null, lastProviderSuccessAt: this.lastProviderSuccessAt ?? null, safeLastErrorCode: this.safeLastErrorCode ?? null, providerHealth: this.providerHealth }), 'utf8');
    await rename(temp, path);
  }
}
