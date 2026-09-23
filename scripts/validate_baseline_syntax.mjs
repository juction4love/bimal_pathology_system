// scripts/validate_baseline_syntax.mjs
// Validates 00001_bimal_pathology_clean_baseline.sql using text-pattern checks.
// Uses a more accurate dollar-quote-aware parser for stray END IF detection.

import { readFileSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const baselinePath = path.resolve('supabase/migrations/00001_bimal_pathology_clean_baseline.sql');
const baselineSql = readFileSync(baselinePath, 'utf8');

// ---- Step 1: Dollar-quote-aware extraction of code OUTSIDE function bodies ----
// We remove everything between any $tag$...$tag$ patterns
const outsideSql = baselineSql.replace(/\$[A-Za-z0-9_]*\$[\s\S]*?\$[A-Za-z0-9_]*\$/g, '/* FUNC_BODY_REMOVED */');

// ---- Step 2: Check procedural variable leaks ----
const tokens = ['v_test_id', 'v_panel_id', 'v_comp_id'];
const leaks = tokens.filter(t => outsideSql.includes(t));
if (leaks.length > 0) {
  console.error('[FAIL] Procedural variable leaks outside function bodies: ' + leaks.join(', '));
  process.exit(1);
}
console.log('[PASS] No procedural variable leaks outside function bodies.');

// ---- Step 3: Transaction structure ----
const beginCount = (baselineSql.match(/^BEGIN;/gm) || []).length;
const commitCount = (baselineSql.match(/^COMMIT;/gm) || []).length;
if (beginCount !== 1) { console.error(`[FAIL] Expected 1 BEGIN; found ${beginCount}`); process.exit(1); }
if (commitCount !== 1) { console.error(`[FAIL] Expected 1 COMMIT; found ${commitCount}`); process.exit(1); }
console.log(`[PASS] Transaction structure: ${beginCount} BEGIN, ${commitCount} COMMIT.`);

// ---- Step 4: Stray END IF outside function bodies ----
const strayEndIf = outsideSql.split('\n').some(l => /^\s*END\s+IF\s*;/.test(l));
if (strayEndIf) { console.error('[FAIL] Stray END IF; found outside function body'); process.exit(1); }
console.log('[PASS] No stray END IF outside function bodies.');

// ---- Step 5: Static counts ----
const kb = (Buffer.byteLength(baselineSql,'utf8')/1024).toFixed(1);
const lines = baselineSql.split('\n').length;
console.log(`\n=== STATIC ANALYSIS ===`);
console.log(`File: ${kb} KB, ${lines} lines`);

// ---- Step 6: Query live DB for current record counts ----
const countSql = `SELECT (SELECT COUNT(*) FROM public.tests WHERE is_active=TRUE) active_tests, (SELECT COUNT(*) FROM public.parameters WHERE is_active=TRUE) active_params, (SELECT COUNT(*) FROM public.reference_ranges) ref_ranges, (SELECT COUNT(*) FROM public.catalogue_panel_components) panel_components, (SELECT COUNT(*) FROM public.analyzers) analyzers, (SELECT COUNT(*) FROM public.analyzer_parameter_mappings) analyzer_mappings;`;
const tmpFile = path.resolve('tmp_live_count_query.sql');
writeFileSync(tmpFile, countSql, 'utf8');
console.log('\n=== LIVE PRODUCTION COUNTS (current state) ===');
try {
  const raw = execSync(`npx supabase db query --linked -f "${tmpFile}"`, { encoding:'utf8', maxBuffer:10*1024*1024 });
  const j = raw.slice(raw.indexOf('{'), raw.lastIndexOf('}')+1);
  if (j) {
    const d = JSON.parse(j);
    const r = (d.rows||[])[0]||{};
    console.log(`  Active Tests:         ${r.active_tests}`);
    console.log(`  Active Parameters:    ${r.active_params}`);
    console.log(`  Reference Ranges:     ${r.ref_ranges}`);
    console.log(`  Panel Components:     ${r.panel_components}`);
    console.log(`  Analyzers:            ${r.analyzers}`);
    console.log(`  Analyzer Mappings:    ${r.analyzer_mappings}`);
  } else { console.log(raw); }
} catch(e) { console.warn('[WARN] Live DB query failed:', e.message?.slice(0,200)); }

console.log('\n[PASS] All structural checks passed.');
console.log('Baseline 00001_bimal_pathology_clean_baseline.sql is structurally sound.');
