import fs from 'node:fs';
import path from 'node:path';

function getFiles(dir) {
  let results = [];
  const list = fs.readdirSync(dir);
  for (const file of list) {
    const fullPath = path.join(dir, file);
    const stat = fs.statSync(fullPath);
    if (stat && stat.isDirectory()) {
      results = results.concat(getFiles(fullPath));
    } else if (file.endsWith('.ts') || file.endsWith('.tsx') || file.endsWith('.js') || file.endsWith('.jsx')) {
      results.push(fullPath);
    }
  }
  return results;
}

const srcFiles = getFiles('src');
const rpcCalls = new Set();
const rpcRegex = /\.rpc\(\s*['"]([a-zA-Z0-9_-]+)['"]/g;

for (const file of srcFiles) {
  const content = fs.readFileSync(file, 'utf8');
  let match;
  while ((match = rpcRegex.exec(content)) !== null) {
    rpcCalls.add(match[1]);
  }
}

const baselineSql = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');

console.log(`Found ${rpcCalls.size} unique RPC calls referenced across frontend:`);
const rpcs = Array.from(rpcCalls).sort();

const found = [];
const missing = [];

for (const rpc of rpcs) {
  // Check if CREATE FUNCTION ... rpc_name OR CREATE OR REPLACE FUNCTION ... rpc_name is in baseline
  const funcRegex = new RegExp(`CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+(?:public\\.)?${rpc}\\s*\\(`, 'i');
  if (funcRegex.test(baselineSql) || baselineSql.includes(`public.${rpc}(`) || baselineSql.includes(`FUNCTION ${rpc}(`)) {
    found.push(rpc);
  } else {
    missing.push(rpc);
  }
}

console.log(`\nRPCs found in baseline (${found.length}):`);
for (const r of found) console.log(`  [FOUND] ${r}`);

console.log(`\nRPCs missing from baseline (${missing.length}):`);
for (const r of missing) console.log(`  [MISSING] ${r}`);
