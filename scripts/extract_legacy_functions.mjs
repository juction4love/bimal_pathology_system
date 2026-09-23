import fs from 'node:fs';
import path from 'node:path';

const legacyDir = 'supabase/migrations_legacy_archive';
const files = fs.readdirSync(legacyDir).filter(f => f.endsWith('.sql')).sort();

// Collect all functions
const functionsMap = new Map();

for (const file of files) {
  const content = fs.readFileSync(path.join(legacyDir, file), 'utf8');
  // Match CREATE OR REPLACE FUNCTION public.func_name(...) ... $$ LANGUAGE ...; or similar
  const regex = /CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION\s+(?:public\.)?([a-zA-Z0-9_]+)\s*\(([\s\S]*?)\)\s*RETURNS([\s\S]*?)(?:AS\s*\$\$[\s\S]*?\$\$|\$func\$[\s\S]*?\$func\$|\$body\$[\s\S]*?\$body\$)[\s\S]*?;/gi;
  
  let match;
  while ((match = regex.exec(content)) !== null) {
    const fullDef = match[0];
    const funcName = match[1];
    functionsMap.set(funcName, {
      file,
      name: funcName,
      sql: fullDef
    });
  }
}

console.log(`Extracted latest definitions for ${functionsMap.size} unique functions/RPCs from legacy migrations.`);

// Let's check which frontend RPCs are still missing from this map
import { execSync } from 'node:child_process';
const missingRaw = execSync('node scripts/audit_frontend_rpcs.mjs', { encoding: 'utf8' });
const missing = missingRaw.split('\n')
  .filter(l => l.includes('[MISSING]'))
  .map(l => l.replace(/.*\[MISSING\]\s+/, '').trim());

console.log(`\nFrontend RPCs to resolve: ${missing.length}`);
const stillMissing = [];
for (const rpc of missing) {
  if (functionsMap.has(rpc)) {
    console.log(`  [RESOLVED] ${rpc} -> from ${functionsMap.get(rpc).file}`);
  } else {
    stillMissing.push(rpc);
    console.log(`  [UNRESOLVED] ${rpc}`);
  }
}

console.log(`\nStill unresolved: ${stillMissing.length}`);
