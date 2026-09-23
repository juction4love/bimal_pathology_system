import fs from 'node:fs';
import path from 'node:path';

const legacyDir = 'supabase/migrations_legacy_archive';
const files = fs.readdirSync(legacyDir).filter(f => f.endsWith('.sql')).sort();

// Collect all table names created across all legacy migrations
const allLegacyTables = new Set();
for (const file of files) {
  const content = fs.readFileSync(path.join(legacyDir, file), 'utf8');
  const matches = content.matchAll(/CREATE TABLE (?:IF NOT EXISTS )?public\.([a-zA-Z0-9_]+)/gi);
  for (const m of matches) {
    allLegacyTables.add(m[1]);
  }
}

console.log(`Found ${allLegacyTables.size} unique tables created across all legacy migrations:`);
console.log(Array.from(allLegacyTables).sort());

const baselineContent = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');
const baselineMatches = baselineContent.matchAll(/CREATE TABLE (?:IF NOT EXISTS )?public\.([a-zA-Z0-9_]+)/gi);
const baselineTables = new Set(Array.from(baselineMatches).map(m => m[1]));

console.log(`\nTables in baseline: ${baselineTables.size}`);
const missingInBaseline = Array.from(allLegacyTables).filter(t => !baselineTables.has(t));
console.log(`\nTables in legacy archive but not in baseline (${missingInBaseline.length}):`, missingInBaseline);
