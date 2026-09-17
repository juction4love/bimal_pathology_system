import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';
import assert from 'node:assert';

const sql = `
WITH
councell_channels AS (
    SELECT json_agg(json_build_object(
        'channel_code', m.channel_code,
        'channel_name', m.channel_name,
        'measurement_type', m.measurement_type,
        'differential_type', m.differential_type,
        'analytical_method', m.analytical_method,
        'unit', m.unit,
        'test_code', t.code,
        'test_name', t.name
    ) ORDER BY m.channel_code) as channels
    FROM public.analyzer_parameter_mappings m
    LEFT JOIN public.tests t ON t.id = m.test_id
    WHERE m.analyzer_id IN (SELECT id FROM public.analyzers WHERE code = 'COUNCELL_23_EXCEL')
),
councell_config AS (
    SELECT json_agg(json_build_object(
        'method', tac.method,
        'validation_source', tac.validation_source,
        'validation_state', tac.validation_state
    )) as configs
    FROM public.test_analyzer_configurations tac
    WHERE tac.analyzer_id IN (SELECT id FROM public.analyzers WHERE code = 'COUNCELL_23_EXCEL')
),
cbc_aliases AS (
    SELECT json_agg(json_build_object(
        'alias', a.alias_name,
        'test_code', t.code,
        'test_name', t.name
    ) ORDER BY a.alias_name) as aliases
    FROM public.test_aliases a
    JOIN public.tests t ON t.id = a.test_id
    WHERE a.alias_name LIKE 'CBC_%'
),
collisions AS (
    SELECT json_build_object(
        'conflicting_units', (
            SELECT count(*) FROM (
                SELECT code, count(DISTINCT unit) FROM public.tests WHERE unit IS NOT NULL AND unit != '' GROUP BY code HAVING count(DISTINCT unit) > 1
            ) c
        ),
        'alias_collisions', (
            SELECT count(*) FROM (
                SELECT alias_name, count(DISTINCT test_id) FROM public.test_aliases GROUP BY alias_name HAVING count(DISTINCT test_id) > 1
            ) c
        ),
        'analyzer_channel_collisions', (
            SELECT count(*) FROM (
                SELECT analyzer_id, channel_code, count(DISTINCT test_id) 
                FROM public.analyzer_parameter_mappings 
                WHERE test_id IS NOT NULL 
                GROUP BY analyzer_id, channel_code 
                HAVING count(DISTINCT test_id) > 1
            ) c
        ),
        'semantic_lym_bug', (
            SELECT count(*) FROM public.test_aliases a
            JOIN public.tests t ON t.id = a.test_id
            WHERE a.alias_name = 'CBC_LYM_P' AND t.code = 'HEM-0016'
        )
    ) as collision_data
)
SELECT json_build_object(
    'councell_channels', (SELECT channels FROM councell_channels),
    'councell_config', (SELECT configs FROM councell_config),
    'cbc_aliases', (SELECT aliases FROM cbc_aliases),
    'collisions', (SELECT collision_data FROM collisions)
) as result;
`;

const tmp = path.resolve('tmp_verify_councell_24.sql');
writeFileSync(tmp, sql, 'utf8');

try {
  const out = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], shell: true });
  const jsonStart = out.indexOf('{');
  const parsed = JSON.parse(out.slice(jsonStart));
  const res = parsed.rows?.[0]?.result;

  console.log('================================================================');
  console.log('=== COUNCELL 23 EXCEL OFFICIAL 24-PARAMETER RECONCILIATION ===');
  console.log('================================================================\n');

  const allChannels = res.councell_channels || [];
  
  // Categorize channels
  const automated24 = allChannels.filter(c => c.differential_type !== '5-Part Manual');
  const manual5Part = allChannels.filter(c => c.differential_type === '5-Part Manual');

  console.log('1. PARAMETER COUNT AUDIT:');
  console.log(`   - Total Channels Registered : ${allChannels.length}`);
  console.log(`   - Automated CounCell Channels: ${automated24.length} (Expected: exactly 24)`);
  console.log(`   - Manual Differential Guard : ${manual5Part.length} (Expected: 8)`);
  assert.equal(automated24.length, 24, 'CounCell 23 Excel must have exactly 24 automated parameters');

  const expected24 = [
    'WBC', 'LYM_ABS', 'LYM_PERCENT', 'MID_ABS', 'MID_PERCENT', 'GRAN_ABS', 'GRAN_PERCENT',
    'RBC', 'HGB', 'HCT', 'MCV', 'MCH', 'MCHC', 'RDW_SD', 'RDW_CV',
    'PLT', 'MPV', 'PCT', 'PDW_SD', 'PDW_CV', 'P_LCC', 'P_LCR', 'NLR', 'PLR'
  ];

  console.log('\n2. 24 CANONICAL ANALYZER CHANNELS:');
  for (const exp of expected24) {
    const ch = automated24.find(c => c.channel_code === exp);
    assert(ch, `Channel ${exp} must exist in CounCell parameter mappings`);
    const mappedTest = ch.test_code ? `-> [${ch.test_code}] ${ch.test_name}` : '(Analyzer Internal Channel)';
    console.log(`   ✓ ${ch.channel_code.padEnd(14)} | ${ch.channel_name.padEnd(42)} | ${ch.measurement_type.padEnd(19)} | ${ch.unit.padEnd(8)} | ${mappedTest}`);
  }

  console.log('\n3. PDW-SD / PDW-CV SEPARATION AUDIT:');
  const pdwSd = automated24.find(c => c.channel_code === 'PDW_SD');
  const pdwCv = automated24.find(c => c.channel_code === 'PDW_CV');
  const pdwGeneric = allChannels.find(c => c.channel_code === 'PDW');
  assert(pdwSd, 'PDW_SD must exist');
  assert.equal(pdwSd.unit, 'fL', 'PDW_SD unit must be fL');
  assert(pdwCv, 'PDW_CV must exist');
  assert.equal(pdwCv.unit, '%', 'PDW_CV unit must be %');
  assert(!pdwGeneric, 'Generic PDW channel must NOT exist in CounCell mappings');
  console.log(`   ✓ PDW-SD: ${pdwSd.channel_name} (${pdwSd.unit})`);
  console.log(`   ✓ PDW-CV: ${pdwCv.channel_name} (${pdwCv.unit})`);
  console.log('   ✓ Generic PDW removed from analyzer channels');

  console.log('\n4. P-LCR / P-LCC CHANNELS AUDIT:');
  const plcr = automated24.find(c => c.channel_code === 'P_LCR');
  const plcc = automated24.find(c => c.channel_code === 'P_LCC');
  assert(plcr, 'P_LCR must exist');
  assert.equal(plcr.unit, '%');
  assert(plcc, 'P_LCC must exist');
  assert.equal(plcc.unit, '10^3/µL');
  console.log(`   ✓ P-LCR: ${plcr.channel_name} (${plcr.unit}) - ${plcr.measurement_type}`);
  console.log(`   ✓ P-LCC: ${plcc.channel_name} (${plcc.unit}) - ${plcc.measurement_type}`);

  console.log('\n5. NLR / PLR CHANNELS AUDIT:');
  const nlr = automated24.find(c => c.channel_code === 'NLR');
  const plr = automated24.find(c => c.channel_code === 'PLR');
  assert(nlr, 'NLR must exist');
  assert.equal(nlr.unit, 'Ratio');
  assert(plr, 'PLR must exist');
  assert.equal(plr.unit, 'Ratio');
  console.log(`   ✓ NLR: ${nlr.channel_name} (${nlr.unit}) - ${nlr.measurement_type}`);
  console.log(`   ✓ PLR: ${plr.channel_name} (${plr.unit}) - ${plr.measurement_type}`);

  console.log('\n6. 3-PART DIFFERENTIAL VS MANUAL 5-PART MICROSCOPY AUDIT:');
  const diff3Part = automated24.filter(c => c.differential_type === '3-Part');
  assert.equal(diff3Part.length, 6, 'Must have 6 3-part differential channels');
  for (const d of diff3Part) {
    assert.equal(d.test_code, null, `${d.channel_code} must have test_id=null to avoid collision with manual differential`);
    console.log(`   ✓ 3-Part Automated: ${d.channel_code.padEnd(14)} (${d.channel_name}) -> test_id = NULL`);
  }

  console.log('\n   Manual 5-Part Microscopy Channels:');
  assert.equal(manual5Part.length, 8, 'Must have 8 manual microscopy differential fields');
  for (const m of manual5Part) {
    assert(m.test_code, `${m.channel_code} must be linked to a manual test`);
    console.log(`   ✓ Manual Microscopy: ${m.channel_code.padEnd(20)} -> [${m.test_code}] ${m.test_name}`);
  }

  console.log('\n7. CROSS-ANALYZER CBC ALIAS AUDIT:');
  for (const a of res.cbc_aliases) {
    console.log(`   ✓ ${a.alias.padEnd(14)} -> [${a.test_code}] ${a.test_name}`);
  }
  const lymAlias = res.cbc_aliases.find(a => a.alias === 'CBC_LYM_P');
  assert(lymAlias, 'CBC_LYM_P alias must exist');
  assert.equal(lymAlias.test_code, 'HEM-0001', 'CBC_LYM_P must point to HEM-0001 (CBC Panel), NOT HEM-0016');

  console.log('\n8. COLLISION INTEGRITY AUDIT:');
  const c = res.collisions;
  console.log(`   - Conflicting units          : ${c.conflicting_units}`);
  console.log(`   - Alias collisions           : ${c.alias_collisions}`);
  console.log(`   - Analyzer channel collisions: ${c.analyzer_channel_collisions}`);
  console.log(`   - Semantic LYM% bug count    : ${c.semantic_lym_bug}`);

  assert.equal(c.conflicting_units, 0, 'Conflicting units must be 0');
  assert.equal(c.alias_collisions, 0, 'Alias collisions must be 0');
  assert.equal(c.analyzer_channel_collisions, 0, 'Analyzer channel collisions must be 0');
  assert.equal(c.semantic_lym_bug, 0, 'Semantic LYM% bug must be 0');

  console.log('\n9. INSTRUMENT SPECIFICATIONS & CONNECTIVITY:');
  const cfg = res.councell_config?.[0];
  console.log(`   - Analytical Method: ${cfg?.method}`);
  console.log(`   - Brochure Validation Source: ${cfg?.validation_source}`);

  console.log('\n================================================================');
  console.log('=== VERDICT: ALL AUDIT INVARIANTS SATISFIED (100% PASS) ===');
  console.log('================================================================');
} finally {
  try { unlinkSync(tmp); } catch {}
}
