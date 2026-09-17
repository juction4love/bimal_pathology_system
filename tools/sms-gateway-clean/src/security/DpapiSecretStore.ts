import { spawn } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import type { GatewaySecrets } from '../config/GatewayConfig.js';
import { validateSecrets } from '../config/GatewayConfig.js';

async function bridge(script: string, action: 'Protect' | 'Unprotect', input: string): Promise<string> {
  return await new Promise((resolve, reject) => {
    const child = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', script, '-Action', action], { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    let output = ''; let error = '';
    child.stdout.setEncoding('utf8').on('data', chunk => output += chunk);
    child.stderr.setEncoding('utf8').on('data', chunk => error += chunk);
    child.once('error', reject);
    child.once('exit', code => code === 0 ? resolve(output) : reject(new Error(`DPAPI bridge failed (${code}): ${error.slice(0, 120)}`)));
    child.stdin.end(input);
  });
}
export class DpapiSecretStore {
  constructor(private readonly path: string, private readonly bridgePath: string) {}
  async save(secrets: GatewaySecrets): Promise<void> { await writeFile(this.path, await bridge(this.bridgePath, 'Protect', JSON.stringify(validateSecrets(secrets))), { encoding: 'ascii', mode: 0o600 }); }
  async load(): Promise<GatewaySecrets> { return validateSecrets(JSON.parse(await bridge(this.bridgePath, 'Unprotect', await readFile(this.path, 'ascii'))) as GatewaySecrets); }
}
