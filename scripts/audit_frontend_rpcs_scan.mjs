import fs from 'node:fs';
import path from 'node:path';

function scanDirectory(dir, filterFn) {
  const results = [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...scanDirectory(fullPath, filterFn));
    } else if (filterFn(fullPath)) {
      results.push(fullPath);
    }
  }
  return results;
}

const srcFiles = scanDirectory('src', p => p.endsWith('.ts') || p.endsWith('.tsx') || p.endsWith('.js') || p.endsWith('.jsx'));
console.log(`Found ${srcFiles.length} frontend source files in src/`);

const rpcCalls = new Set();
const rpcCallLocations = [];

const rpcRegex = /\.rpc\s*\(\s*['"`]([^'"`]+)['"`]/g;

for (const file of srcFiles) {
  const content = fs.readFileSync(file, 'utf8');
  let match;
  while ((match = rpcRegex.exec(content)) !== null) {
    const rpcName = match[1];
    rpcCalls.add(rpcName);
    rpcCallLocations.push({ file, rpcName });
  }
}

console.log(`\nFound ${rpcCalls.size} unique frontend RPC calls:`);
const sortedRpcs = [...rpcCalls].sort();
sortedRpcs.forEach(r => console.log(`  - ${r}`));

// Now check if baseline SQL contains CREATE OR REPLACE FUNCTION public.<rpcName>
const baselineSql = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');

const baselineFuncRegex = /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.([a-zA-Z0-9_]+)/gi;
const baselineFuncs = new Set();
let fMatch;
while ((fMatch = baselineFuncRegex.exec(baselineSql)) !== null) {
  baselineFuncs.add(fMatch[1]);
}

console.log(`\nFound ${baselineFuncs.size} unique functions in baseline SQL`);

const missingRpcs = sortedRpcs.filter(r => !baselineFuncs.has(r));
console.log(`\nMISSING_FRONTEND_RPCS (${missingRpcs.length}):`);
missingRpcs.forEach(r => console.log(`  MISSING: ${r}`));
