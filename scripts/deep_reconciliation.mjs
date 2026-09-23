import fs from 'node:fs';

const live = JSON.parse(fs.readFileSync('scripts/output/live_audit_dump.json', 'utf8'));
const baselineSql = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');

// Load legacy 00134 and 00135 if needed
console.log('================================================================');
console.log('RECONCILIATION ANALYSIS: LIVE PRODUCTION (00134) vs BASELINE');
console.log('================================================================\n');

// 1. ANALYZERS RECONCILIATION
console.log('--- 1. ANALYZERS ---');
console.log('Live Analyzers:');
live.analyzers.forEach(a => {
  console.log(`  id=${a.id}, code=${a.code}, name="${a.name}", type/mfg="${a.manufacturer}", model="${a.model}", status=${a.lifecycle_status}`);
});

// Check analyzers in baseline
const baselineAnalyzers = [];
const analyzerInserts = baselineSql.match(/INSERT INTO public\.analyzers[^\;]+;/gi) || [];
for (const stmt of analyzerInserts) {
  const valuesMatch = stmt.match(/VALUES\s*([\s\S]+);/i);
  if (valuesMatch) {
    const rows = valuesMatch[1].split(/\),\s*\(/);
    for (const row of rows) {
      const parts = row.replace(/^[(\s]+/, '').replace(/[)\s;]+$/, '').split(/,\s*/);
      const code = parts[0]?.replace(/'/g, '').trim();
      const name = parts[1]?.replace(/'/g, '').trim();
      if (code && !baselineAnalyzers.some(b => b.code === code)) {
        baselineAnalyzers.push({ code, name });
      }
    }
  }
}
console.log('\nBaseline Analyzers:');
baselineAnalyzers.forEach(a => console.log(`  code=${a.code}, name="${a.name}"`));

const liveAnalyzerCodes = new Set(live.analyzers.map(a => a.code));
const baselineAnalyzerCodes = new Set(baselineAnalyzers.map(a => a.code));

const analyzersOnlyInLive = [...liveAnalyzerCodes].filter(c => !baselineAnalyzerCodes.has(c));
const analyzersOnlyInBaseline = [...baselineAnalyzerCodes].filter(c => !liveAnalyzerCodes.has(c));
console.log(`ANALYZERS_ONLY_IN_LIVE: ${JSON.stringify(analyzersOnlyInLive)}`);
console.log(`ANALYZERS_ONLY_IN_BASELINE: ${JSON.stringify(analyzersOnlyInBaseline)}`);

// 2. ANALYZER MAPPINGS RECONCILIATION
console.log('\n--- 2. ANALYZER MAPPINGS ---');
console.log(`Live Analyzer Mappings Count: ${live.analyzer_mappings.length}`);
live.analyzer_mappings.forEach(m => {
  console.log(`  [${m.analyzer_code}] channel=${m.channel_code}, test=${m.test_code}, param=${m.parameter_code}, name="${m.channel_name || m.parameter_name}", type=${m.measurement_type}`);
});

// 3. REFERENCE RANGES RECONCILIATION
console.log('\n--- 3. REFERENCE RANGES ---');
console.log(`Live Reference Ranges (Total): ${live.reference_ranges.length} (Active: ${live.reference_ranges.filter(r => r.is_active).length}, Inactive: ${live.reference_ranges.filter(r => !r.is_active).length})`);

// Let's inspect inactive live reference ranges
const inactiveLiveRR = live.reference_ranges.filter(r => !r.is_active);
console.log(`\nInactive Live Reference Ranges (${inactiveLiveRR.length}):`);
inactiveLiveRR.forEach(r => {
  console.log(`  test=${r.test_code}, param=${r.parameter_code} (${r.parameter_name}), gender=${r.gender}, age=${r.age_min_days}-${r.age_max_days}, min=${r.normal_min}, max=${r.normal_max}, text="${r.normal_text}", is_active=${r.is_active}`);
});

// Let's parse baseline reference ranges
// Look for INSERT INTO public.reference_ranges
const baselineRR = [];
const rrInserts = baselineSql.match(/INSERT INTO public\.reference_ranges[^\;]+;/gi) || [];
for (const stmt of rrInserts) {
  // Let's extract values
  const lines = stmt.split('\n');
  for (const l of lines) {
    if (l.trim().startsWith('(') && (l.includes("'M'") || l.includes("'F'") || l.includes("'Both'") || l.includes("'All'"))) {
      baselineRR.push(l.trim());
    }
  }
}
console.log(`\nBaseline Reference Range rows matched: ${baselineRR.length}`);

// 4. PANEL COMPONENTS RECONCILIATION
console.log('\n--- 4. PANEL COMPONENTS ---');
console.log(`Live Panel Components Count: ${live.panel_components.length}`);

// Group live panel components by panel_code
const livePanels = {};
for (const pc of live.panel_components) {
  if (!livePanels[pc.panel_code]) livePanels[pc.panel_code] = [];
  livePanels[pc.panel_code].push(pc);
}
console.log(`Live distinct panels configured: ${Object.keys(livePanels).length}`);
for (const [code, items] of Object.entries(livePanels)) {
  console.log(`  Panel ${code} (${items[0].panel_name}): ${items.length} components`);
}

// Check for self-referential panel links in live
const liveSelfLinks = live.panel_components.filter(pc => pc.panel_code === pc.component_test_code || (pc.panel_id === pc.component_test_id));
console.log(`Live Self-referential panel links: ${liveSelfLinks.length}`);

// 5. ALG-0049 CHECK
console.log('\n--- 5. ALG-0049 CHECK ---');
const alg0049Tests = live.tests.filter(t => t.code === 'ALG-0049');
const alg0049Params = live.parameters.filter(p => p.test_code === 'ALG-0049');
const alg0049Comps = live.panel_components.filter(pc => pc.panel_code === 'ALG-0049' || pc.component_test_code === 'ALG-0049');
console.log(`Live ALG-0049 Test Count: ${alg0049Tests.length}`);
console.log(`Live ALG-0049 Parameters: ${alg0049Params.length}`);
alg0049Params.forEach(p => console.log(`  param: code=${p.code}, name="${p.name}", active=${p.is_active}, unit="${p.unit}"`));
console.log(`Live ALG-0049 Panel Components: ${alg0049Comps.length}`);
alg0049Comps.forEach(c => console.log(`  comp: panel=${c.panel_code}, child_test=${c.component_test_code}, child_param=${c.component_parameter_code}`));
