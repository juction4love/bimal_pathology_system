import { join } from 'node:path';
export function servicePaths(dataDirectory: string) { return { config: join(dataDirectory, 'gateway.config.json'), secrets: join(dataDirectory, 'gateway.secrets.dpapi'), health: join(dataDirectory, 'health.json'), log: join(dataDirectory, 'logs', 'gateway.jsonl'), stopRequest: join(dataDirectory, 'service-stop.request') }; }
