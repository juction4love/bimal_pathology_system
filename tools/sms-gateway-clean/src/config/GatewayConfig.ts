import { readFile } from 'node:fs/promises';

export type GatewayMode = 'shadow' | 'active';
export interface GatewayConfig {
  instanceId: string;
  version: string;
  mode: GatewayMode;
  pollMs: number;
  heartbeatMs: number;
  rpcTimeoutMs: number;
  providerTimeoutMs: number;
  leaseSeconds: number;
  claimBatchSize: number;
  maxConcurrency: number;
  maxSegments: number;
  shutdownMs: number;
  dataDirectory: string;
}
export interface GatewaySecrets {
  supabaseUrl: string;
  supabasePublishableKey: string;
  gatewayEmail: string;
  gatewayPassword: string;
  sparrowToken: string;
  sparrowSender: string;
}

export function validateConfig(c: GatewayConfig): GatewayConfig {
  if (!/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(c.instanceId)) throw new Error('Invalid stable instance ID.');
  if (!['shadow', 'active'].includes(c.mode)) throw new Error('Invalid Gateway mode.');
  const bounds: Array<[keyof GatewayConfig, number, number]> = [
    ['pollMs', 1000, 60000], ['heartbeatMs', 30000, 120000], ['rpcTimeoutMs', 1000, 60000],
    ['providerTimeoutMs', 1000, 60000], ['leaseSeconds', 60, 900], ['claimBatchSize', 1, 10],
    ['maxConcurrency', 1, 10], ['maxSegments', 1, 10], ['shutdownMs', 1000, 60000]
  ];
  for (const [key, min, max] of bounds) {
    const value = c[key];
    if (typeof value !== 'number' || !Number.isInteger(value) || value < min || value > max) {
      throw new Error(`Invalid ${key}.`);
    }
  }
  if (!c.version.trim() || !c.dataDirectory.trim()) throw new Error('Version and data directory are required.');
  return c;
}

export function validateSecrets(s: GatewaySecrets): GatewaySecrets {
  const url = new URL(s.supabaseUrl);
  if (url.protocol !== 'https:' || !url.hostname.endsWith('.supabase.co')) throw new Error('Invalid Supabase URL.');
  for (const [key, value] of Object.entries(s)) if (!value.trim()) throw new Error(`Missing protected ${key}.`);
  return s;
}

export async function loadConfig(path: string): Promise<GatewayConfig> {
  const text = await readFile(path, 'utf8');
  return validateConfig(JSON.parse(text.replace(/^\uFEFF/, '')) as GatewayConfig);
}
