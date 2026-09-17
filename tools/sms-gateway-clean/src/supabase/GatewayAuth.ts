import type { GatewaySecrets } from '../config/GatewayConfig.js';

interface AuthResponse { access_token: string; expires_in: number }

export class GatewayAuth {
  private token: string | undefined;
  private expiresAt = 0;
  constructor(private readonly secrets: GatewaySecrets, private readonly fetcher: typeof fetch = fetch) {}

  invalidate(): void { this.token = undefined; this.expiresAt = 0; }

  async getAccessToken(signal?: AbortSignal): Promise<string> {
    if (this.token && Date.now() < this.expiresAt - 60_000) return this.token;
    const init: RequestInit = {
      method: 'POST',
      headers: { apikey: this.secrets.supabasePublishableKey, 'content-type': 'application/json' },
      body: JSON.stringify({ email: this.secrets.gatewayEmail, password: this.secrets.gatewayPassword })
    };
    if (signal) init.signal = signal;
    const response = await this.fetcher(`${this.secrets.supabaseUrl}/auth/v1/token?grant_type=password`, init);
    if (!response.ok) throw new Error(`Gateway authentication failed (HTTP ${response.status}).`);
    const payload = await response.json() as AuthResponse;
    if (!payload.access_token || !Number.isFinite(payload.expires_in)) throw new Error('Gateway authentication response is invalid.');
    this.token = payload.access_token;
    this.expiresAt = Date.now() + payload.expires_in * 1000;
    return this.token;
  }
}
