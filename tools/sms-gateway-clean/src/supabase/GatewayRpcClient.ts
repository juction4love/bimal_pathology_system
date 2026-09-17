import type { GatewaySecrets } from '../config/GatewayConfig.js';
import type { ClaimedSms, HeartbeatPayload, QueueCompletion } from './Contracts.js';
import type { GatewayAuth } from './GatewayAuth.js';

export class GatewayRpcClient {
  constructor(
    private readonly secrets: GatewaySecrets,
    private readonly auth: GatewayAuth,
    private readonly timeoutMs: number,
    private readonly fetcher: typeof fetch = fetch
  ) {}

  preflight(instanceId: string, signal?: AbortSignal): Promise<unknown> {
    return this.rpc('sms_gateway_v2_preflight', { p_instance_id: instanceId }, signal);
  }
  heartbeat(instanceId: string, h: HeartbeatPayload, signal?: AbortSignal): Promise<unknown> {
    return this.rpc('heartbeat_sms_gateway_v2', {
      p_instance_id: instanceId, p_hostname: h.hostname, p_gateway_version: h.gatewayVersion,
      p_provider_name: h.providerName, p_service_started_at: h.serviceStartedAt,
      p_last_successful_queue_access_at: h.lastQueueAccessAt ?? null,
      p_last_provider_success_at: h.lastProviderSuccessAt ?? null, p_provider_health: h.providerHealth,
      p_safe_last_error_code: h.safeLastErrorCode ?? null, p_active_job_count: h.activeJobs
    }, signal);
  }
  recover(instanceId: string, seconds: number, signal?: AbortSignal): Promise<unknown> {
    return this.rpc('recover_stale_sms_gateway_v2_items', { p_instance_id: instanceId, p_stale_after_seconds: seconds }, signal);
  }
  claim(instanceId: string, workerId: string, batch: number, lease: number, signal?: AbortSignal): Promise<ClaimedSms[]> {
    return this.rpc('claim_sms_gateway_v2_batch', {
      p_instance_id: instanceId, p_worker_id: workerId, p_batch_size: batch, p_lease_seconds: lease
    }, signal) as Promise<ClaimedSms[]>;
  }
  markStarted(instanceId: string, id: string, workerId: string, signal?: AbortSignal): Promise<boolean> {
    return this.rpc('mark_sms_gateway_v2_provider_call_started', {
      p_instance_id: instanceId, p_sms_id: id, p_worker_id: workerId
    }, signal) as Promise<boolean>;
  }
  rejectLocal(instanceId: string, id: string, workerId: string, code: string, signal?: AbortSignal): Promise<boolean> {
    return this.rpc('reject_sms_gateway_v2_local_validation', {
      p_instance_id: instanceId, p_sms_id: id, p_worker_id: workerId, p_error_code: code
    }, signal) as Promise<boolean>;
  }
  complete(instanceId: string, id: string, workerId: string, result: QueueCompletion, signal?: AbortSignal): Promise<unknown> {
    const retryable = result.outcome === 'retryable_failure';
    const classification = result.accepted ? null : result.outcome === 'unknown_outcome' ? 'ProviderOutcomeUnknown'
      : result.outcome === 'provider_unavailable' ? 'ProviderUnavailable'
      : retryable ? 'RetryableProviderFailure' : 'PermanentProviderFailure';
    return this.rpc('complete_sms_gateway_v2_item', {
      p_instance_id: instanceId, p_sms_id: id, p_worker_id: workerId, p_accepted: result.accepted,
      p_provider_msg_id: result.providerMessageId ?? null, p_provider_response: result.metadata ?? {},
      p_provider_response_code: result.responseCode ?? null,
      p_error_msg: result.accepted ? null : result.safeErrorCode ?? result.outcome,
      p_error_classification: classification, p_retryable: retryable
    }, signal);
  }

  private async rpc(name: string, body: unknown, outer?: AbortSignal): Promise<unknown> {
    const timeout = AbortSignal.timeout(this.timeoutMs);
    const signal = outer ? AbortSignal.any([outer, timeout]) : timeout;
    const token = await this.auth.getAccessToken(signal);
    const response = await this.fetcher(`${this.secrets.supabaseUrl}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { apikey: this.secrets.supabasePublishableKey, authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify(body), signal
    });
    if (response.status === 401) { this.auth.invalidate(); throw new Error(`Gateway RPC ${name} authentication rejected (HTTP 401).`); }
    if (!response.ok) throw new Error(`Gateway RPC ${name} failed (HTTP ${response.status}).`);
    return await response.json();
  }
}
