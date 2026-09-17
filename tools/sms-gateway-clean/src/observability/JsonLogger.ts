import { appendFile, mkdir, rename, rm, stat } from 'node:fs/promises';
import { dirname } from 'node:path';
import { redact } from '../security/Redaction.js';

export class JsonLogger {
  constructor(private readonly path: string, private readonly maxBytes = 10 * 1024 * 1024) {}
  info(event: string, fields: Record<string, unknown> = {}): Promise<void> { return this.write('info', event, fields); }
  warn(event: string, fields: Record<string, unknown> = {}): Promise<void> { return this.write('warn', event, fields); }
  error(event: string, fields: Record<string, unknown> = {}): Promise<void> { return this.write('error', event, fields); }
  private async write(level: string, event: string, fields: Record<string, unknown>): Promise<void> {
    await mkdir(dirname(this.path), { recursive: true });
    try {
      if ((await stat(this.path)).size >= this.maxBytes) {
        await rm(`${this.path}.1`, { force: true });
        await rename(this.path, `${this.path}.1`);
      }
    } catch { /* first write or concurrent rotation */ }
    await appendFile(this.path, `${JSON.stringify(redact({ timestamp: new Date().toISOString(), level, event, ...fields }))}\n`, 'utf8');
  }
}
