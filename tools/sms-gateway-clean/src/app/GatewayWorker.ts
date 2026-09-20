import { randomUUID } from 'node:crypto';
import type { GatewayConfig } from '../config/GatewayConfig.js';
import type { HealthState } from '../observability/HealthState.js';
import type { JsonLogger } from '../observability/JsonLogger.js';
import type { SmsProvider, SmsProviderResult } from '../providers/SmsProvider.js';
import type { ClaimedSms } from '../supabase/Contracts.js';
import type { GatewayRpcClient } from '../supabase/GatewayRpcClient.js';
import { countSmsSegments } from './SmsSegments.js';
import { containsSmsLink } from '../providers/SmsContentSafety.js';

export class GatewayWorker {
  private readonly inflight = new Set<Promise<void>>();
  constructor(private readonly config: GatewayConfig, private readonly queue: GatewayRpcClient, private readonly provider: SmsProvider, private readonly health: HealthState, private readonly logger: JsonLogger, readonly workerId: string = randomUUID()) {}

  async run(signal: AbortSignal): Promise<void> {
    if (this.config.mode === 'shadow') {
      await this.queue.preflight(this.config.instanceId, signal);
      this.health.queueOk();
      await this.logger.info('gateway.shadow.ready', { workerId: this.workerId });
      return;
    }
    while (!signal.aborted) {
      await this.poll(signal);
      if (!await this.delay(this.config.pollMs, signal)) break;
    }
    await this.drain();
  }

  async poll(signal?: AbortSignal): Promise<void> {
    if (this.config.mode !== 'active') throw new Error('SHADOW_MODE_QUEUE_ACCESS_BLOCKED');
    try {
      await this.queue.recover(this.config.instanceId, this.config.leaseSeconds, signal);
      const capacity = this.config.maxConcurrency - this.inflight.size;
      if (capacity <= 0) return;
      const rows = await this.queue.claim(this.config.instanceId, this.workerId, Math.min(capacity, this.config.claimBatchSize), this.config.leaseSeconds, signal);
      this.health.queueOk();
      for (const row of rows) {
        let task!: Promise<void>;
        task = this.deliver(row).catch(async error => {
          this.health.fail('DELIVERY_PROTOCOL_FAILED');
          await this.logger.error('sms.delivery.protocol_failed', { queueId: row.id, workerId: this.workerId, error: error instanceof Error ? error.message : 'unknown' });
        }).finally(() => { this.inflight.delete(task); this.health.activeJobs = this.inflight.size; });
        this.inflight.add(task);
      }
      this.health.activeJobs = this.inflight.size;
    } catch (error) {
      this.health.fail('QUEUE_RPC_FAILED', 'Unavailable');
      await this.logger.error('queue.poll.failed', { error: error instanceof Error ? error.message : 'unknown' });
    }
  }

  private async deliver(row: ClaimedSms, outer?: AbortSignal): Promise<void> {
    if (containsSmsLink(row.message_body)) {
      await this.queue.rejectLocal(this.config.instanceId, row.id, this.workerId, 'SMS_URL_BLOCKED', outer);
      await this.logger.warn('sms.content_rejected', { queueId: row.id, code: 'SMS_URL_BLOCKED' });
      return;
    }
    const messageBody = row.message_body;
    if (!/^(97|98)\d{8}$/.test(row.recipient_phone)) { await this.queue.rejectLocal(this.config.instanceId, row.id, this.workerId, 'INVALID_NEPAL_MOBILE', outer); return; }
    if (!messageBody) { await this.queue.rejectLocal(this.config.instanceId, row.id, this.workerId, 'EMPTY_MESSAGE', outer); return; }
    const segmentInfo = countSmsSegments(messageBody);
    if (segmentInfo.segments > this.config.maxSegments || (segmentInfo.encoding === 'UCS-2' && messageBody.length > 70)) {
      await this.queue.rejectLocal(this.config.instanceId, row.id, this.workerId, 'SEGMENT_LIMIT_EXCEEDED', outer);
      await this.logger.warn('sms.content_rejected', { queueId: row.id, code: 'SEGMENT_LIMIT_EXCEEDED', length: messageBody.length, segments: segmentInfo.segments });
      return;
    }
    if (!await this.queue.markStarted(this.config.instanceId, row.id, this.workerId, outer)) throw new Error('Lease lost before provider call.');
    const timeout = AbortSignal.timeout(this.config.providerTimeoutMs);
    const signal = outer ? AbortSignal.any([outer, timeout]) : timeout;
    let result: SmsProviderResult;
    try { result = await this.provider.send({ queueId: row.id, recipient: row.recipient_phone, body: messageBody }, signal); }
    catch { result = { outcome: 'unknown_outcome', safeErrorCode: 'PROVIDER_OUTCOME_UNKNOWN' }; }
    await this.queue.complete(this.config.instanceId, row.id, this.workerId, { ...result, accepted: result.outcome === 'accepted' }, outer);
    if (result.outcome === 'accepted') { this.health.providerOk(); await this.logger.info('sms.accepted', { queueId: row.id, workerId: this.workerId, segments: segmentInfo.segments, encoding: segmentInfo.encoding }); }
    else { this.health.fail(result.safeErrorCode ?? result.outcome, result.outcome === 'provider_unavailable' ? 'ConfigurationError' : 'Degraded'); await this.logger.warn('sms.failed', { queueId: row.id, workerId: this.workerId, outcome: result.outcome, code: result.safeErrorCode }); }
  }

  private async drain(): Promise<void> {
    if (this.inflight.size === 0) return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      await Promise.race([
        Promise.allSettled([...this.inflight]),
        new Promise(resolve => { timer = setTimeout(resolve, this.config.shutdownMs); })
      ]);
    } finally {
      if (timer) clearTimeout(timer);
    }
  }
  private async delay(ms: number, signal: AbortSignal): Promise<boolean> { return await new Promise(resolve => { const timer = setTimeout(() => resolve(true), ms); signal.addEventListener('abort', () => { clearTimeout(timer); resolve(false); }, { once: true }); }); }
}
