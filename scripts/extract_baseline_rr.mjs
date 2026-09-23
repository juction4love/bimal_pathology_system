import fs from 'node:fs';

const live = JSON.parse(fs.readFileSync('scripts/output/live_audit_dump.json', 'utf8'));
const baselineSql = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');

// Find all reference range inserts in baseline SQL
const rrBlockMatches = [...baselineSql.matchAll(/INSERT INTO public\.reference_ranges\s*\(([^)]+)\)\s*VALUES\s*([\s\S]*?);/g)];

console.log(`Found ${rrBlockMatches.length} reference_ranges INSERT blocks in baseline SQL`);

const baselineRRs = [];
for (const [_, cols, vals] of rrBlockMatches) {
  // Let's parse each tuple ( ... )
  // We can match tuples by splitting or regex
  const tuples = vals.match(/\((?:[^)(]+|\([^)(]*\))*\)/g) || [];
  for (const t of tuples) {
    baselineRRs.push({ cols, raw: t.trim() });
  }
}

console.log(`Total Baseline Reference Ranges rows found: ${baselineRRs.length}`);
console.log(`Total Live Reference Ranges: ${live.reference_ranges.length} (Active: ${live.reference_ranges.filter(r => r.is_active).length})`);
