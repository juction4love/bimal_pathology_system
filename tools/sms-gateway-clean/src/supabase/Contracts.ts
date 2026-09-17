export interface ClaimedSms {
  id: string;
  sms_type: string;
  recipient_phone: string;
  message_body: string;
  retry_count: number;
  max_attempts: number;
  idempotency_key: string;
  lease_owner: string;
}
export interface QueueCompletion {
  accepted: boolean;
  outcome: 'accepted' | 'retryable_failure' | 'permanent_failure' | 'provider_unavailable' | 'unknown_outcome';
  providerMessageId?: string;
  responseCode?: string;
  metadata?: Record<string, unknown>;
  safeErrorCode?: string;
}
export interface HeartbeatPayload {
  hostname: string;
  gatewayVersion: string;
  providerName: string;
  serviceStartedAt: string;
  lastQueueAccessAt?: string;
  lastProviderSuccessAt?: string;
  providerHealth: 'Unknown' | 'Healthy' | 'Degraded' | 'Unavailable' | 'ConfigurationError';
  safeLastErrorCode?: string;
  activeJobs: number;
}
