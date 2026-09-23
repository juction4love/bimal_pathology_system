import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const srcDir = path.resolve('src');
const rpcCalls = new Set();

function walk(dir) {
  const files = fs.readdirSync(dir);
  for (const f of files) {
    const full = path.join(dir, f);
    if (fs.statSync(full).isDirectory()) {
      walk(full);
    } else if (/\.(ts|tsx|js|jsx)$/.test(f)) {
      const content = fs.readFileSync(full, 'utf8');
      const matches = content.matchAll(/\.rpc\(\s*['"]([^'"]+)['"]/g);
      for (const m of matches) {
        rpcCalls.add(m[1]);
      }
    }
  }
}

walk(srcDir);
const rpcList = Array.from(rpcCalls).sort();
console.log('Frontend RPCs found:', rpcList);

const sqlQuery = `
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_schema = 'public' 
  AND routine_name IN (${rpcList.map(r => `'${r}'`).join(', ')});
`;

const tmpFile = path.resolve('scripts/output/tmp_rpc_check.sql');
fs.writeFileSync(tmpFile, sqlQuery, 'utf8');

try {
  const out = execSync(`npx supabase db query --linked -f "${tmpFile}"`, {
    encoding: 'utf8',
    maxBuffer: 10 * 1024 * 1024,
    stdio: ['pipe', 'pipe', 'pipe']
  });
  const marker = out.indexOf('{');
  if (marker !== -1) {
    const json = JSON.parse(out.slice(marker));
    const foundRpcs = new Set(json.rows.map(r => r.routine_name));
    const missing = rpcList.filter(r => !foundRpcs.has(r));
    console.log('Found remote RPCs:', Array.from(foundRpcs).sort());
    console.log('Missing remote RPCs:', missing);
  }
} finally {
  if (fs.existsSync(tmpFile)) fs.unlinkSync(tmpFile);
}
