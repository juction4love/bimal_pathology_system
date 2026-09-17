export interface SmsMessage { queueId: string; recipient: string; body: string }
export type ProviderOutcome = 'accepted' | 'retryable_failure' | 'permanent_failure' | 'provider_unavailable' | 'unknown_outcome';
export interface SmsProviderResult {
  outcome: ProviderOutcome;
  providerMessageId?: string;
  responseCode?: string;
  safeErrorCode?: string;
  metadata?: Record<string, unknown>;
}
export interface SmsProvider {
  readonly name: string;
  validateConfiguration(): void;
  send(message: SmsMessage, signal: AbortSignal): Promise<SmsProviderResult>;
}
