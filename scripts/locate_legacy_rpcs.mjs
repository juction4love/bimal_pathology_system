import fs from 'node:fs';
import path from 'node:path';

const legacyDir = 'supabase/migrations_legacy_archive';
const files = fs.readdirSync(legacyDir).filter(f => f.endsWith('.sql')).sort();

// Find missing RPCs list
import { execSync } from 'node:child_process';

const missingRaw = execSync('node scripts/audit_frontend_rpcs.mjs', { encoding: 'utf8' });
const missing = missingRaw.split('\n')
  .filter(l => l.includes('[MISSING]'))
  .map(l => l.replace(/.*\[MISSING\]\s+/, '').trim());

console.log(`Searching for latest definition of ${missing.length} RPCs in legacy archive...`);

const rpcFoundIn = new Map();

for (const file of files) {
  const content = fs.readFileSync(path.join(legacyDir, file), 'utf8');
  for (const rpc of missing) {
    const reg = new RegExp(`CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+(?:public\\.)?${rpc}\\s*\\(`, 'i');
    if (reg.test(content)) {
      rpcFoundIn.set(rpc, file);
    }
  }
}

console.log(`Found definitions in legacy archive for: ${rpcFoundIn.size} / ${missing.length}`);
const notFound = missing.filter(rpc => !rpcFoundIn.has(rpc));
if (notFound.length > 0) {
  console.log('STILL NOT FOUND ANYWHERE in legacy migrations:', notFound);
}
for (const [rpc, file] of rpcFoundIn.entries()) {
  console.log(`  ${rpc.padEnd(45)} -> ${file}`);
}
