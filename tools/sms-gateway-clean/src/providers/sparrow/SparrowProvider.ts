import type { SmsMessage, SmsProvider, SmsProviderResult } from '../SmsProvider.js';

interface SparrowPayload { response_code?: number; response?: string; message_id?: string; count?: number }

export class SparrowProvider implements SmsProvider {
  readonly name = 'Sparrow';
  constructor(
    private readonly token: string,
    private readonly sender: string,
    private readonly fetcher: typeof fetch = fetch,
    private readonly endpoint = 'https://api.sparrowsms.com/v2/sms/'
  ) {}
  validateConfiguration(): void {
    if (!this.token.trim() || !this.sender.trim()) throw new Error('SPARROW_CONFIGURATION_MISSING');
    if (!this.endpoint.startsWith('https://')) throw new Error('SPARROW_ENDPOINT_INSECURE');
  }
  async send(message: SmsMessage, signal: AbortSignal): Promise<SmsProviderResult> {
    this.validateConfiguration();
    const form = new URLSearchParams([['token', this.token], ['from', this.sender], ['to', message.recipient], ['text', message.body]]);
    let response: Response;
    try {
      response = await this.fetcher(this.endpoint, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: form, signal });
    } catch (error) {
      if (signal.aborted) return { outcome: 'unknown_outcome', safeErrorCode: 'PROVIDER_OUTCOME_UNKNOWN' };
      return { outcome: 'retryable_failure', safeErrorCode: 'PROVIDER_NETWORK_FAILURE' };
    }
    let payload: SparrowPayload;
    try { payload = await response.json() as SparrowPayload; }
    catch { return { outcome: 'unknown_outcome', safeErrorCode: 'PROVIDER_RESPONSE_INVALID' }; }
    const code = payload.response_code;
    if (response.ok && code === 200 && payload.message_id) {
      return { outcome: 'accepted', providerMessageId: payload.message_id, responseCode: String(code), metadata: { count: payload.count ?? null } };
    }
    if (response.status === 401 || response.status === 403) return { outcome: 'provider_unavailable', responseCode: String(code ?? response.status), safeErrorCode: 'PROVIDER_AUTH_REJECTED' };
    if (response.status === 429 || response.status >= 500) return { outcome: 'retryable_failure', responseCode: String(code ?? response.status), safeErrorCode: 'PROVIDER_TRANSIENT_FAILURE' };
    if (code && [1001, 1002, 1003, 1004, 1005].includes(code)) return { outcome: 'permanent_failure', responseCode: String(code), safeErrorCode: 'PROVIDER_PERMANENT_REJECTION' };
    return { outcome: 'unknown_outcome', responseCode: String(code ?? response.status), safeErrorCode: 'PROVIDER_OUTCOME_UNKNOWN' };
  }
}
