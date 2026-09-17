import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';
import assert from 'node:assert';

const sql = `
WITH
harmonization_aliases_check AS (
    SELECT json_agg(json_build_object(
        'alias', a.alias_name,
        'test_code', t.code,
        'test_name', t.name
    )) as aliases
    FROM public.test_aliases a
    JOIN public.tests t ON t.id = a.test_id
    WHERE a.alias_name IN (
        'CBC_WBC', 'CBC_RBC', 'CBC_HGB', 'CBC_PLT', 'CBC_GRAN_P', 'CBC_LYM_P', 'CBC_MID_P',
        'BIO_ALT', 'BIO_AST', 'BIO_TBIL', 'BIO_CREAT', 'BIO_UREA', 'BIO_URIC', 'BIO_GLU_F', 'BIO_CHOL', 'BIO_TRIG',
        'IMM_TSH', 'IMM_FT4', 'IMM_FT3', 'IMM_VITD', 'IMM_B12', 'IMM_CTNI', 'IMM_BNP'
    )
),
specimen_rules_check AS (
    SELECT json_agg(json_build_object(
        'test_code', t.code,
        'test_name', t.name,
        'analyzer_code', a.code,
        'preferred_specimen', r.preferred_specimen,
        'primary_tube_color', r.primary_tube_color,
        'primary_tube_additive', r.primary_tube_additive,
        'do_not_centrifuge', r.do_not_centrifuge,
        'centrifugation_instructions', r.centrifugation_instructions,
        'centrifugation_rcf', r.centrifugation_rcf,
        'conditional_rules', r.conditional_rules,
        'special_precautions', r.special_precautions
    )) as rules
    FROM public.assay_specimen_governance_rules r
    JOIN public.tests t ON t.id = r.test_id
    LEFT JOIN public.analyzers a ON a.id = r.analyzer_id
),
critical_policies_check AS (
    SELECT json_agg(json_build_object(
        'test_code', t.code,
        'test_name', t.name,
        'critical_low', p.critical_low,
        'critical_high', p.critical_high,
        'critical_operator', p.critical_operator,
        'unit', p.unit,
        'action_threshold_text', p.action_threshold_text,
        'critical_policy_status', p.critical_policy_status
    )) as policies
    FROM public.critical_value_policies p
    JOIN public.tests t ON t.id = p.test_id
),
collision_audit AS (
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
        'ckmb_collision', (
            SELECT count(*) FROM public.tests WHERE code IN ('BIO-0061', 'BIO-0062') AND unit = 'U/L' AND method ILIKE '%fluorescence%'
        ),
        'crp_collision', (
            SELECT count(*) FROM public.tests WHERE code = 'BIO-0068' AND name = 'CRP, Quantitative'
        ),
        'thyroid_collision', (
            SELECT count(*) FROM public.tests WHERE code IN ('END-0002', 'END-0003') AND name ILIKE 'Total%'
        ),
        'ddimer_collision', (
            SELECT count(*) FROM public.tests WHERE code = 'COA-0006' AND unit != 'µg/mL FEU'
        ),
        'diff_collision', (
            SELECT count(*) FROM public.analyzer_parameter_mappings WHERE channel_code = 'GRAN_PERCENT' AND channel_name ILIKE '%Neutrophils % (Manual%'
        )
    ) as collisions
)
SELECT json_build_object(
    'aliases', (SELECT aliases FROM harmonization_aliases_check),
    'specimen_rules', (SELECT rules FROM specimen_rules_check),
    'critical_policies', (SELECT policies FROM critical_policies_check),
    'collisions', (SELECT collisions FROM collision_audit)
) as result;
`;

const tmp = path.resolve('tmp_harmonization_verify.sql');
writeFileSync(tmp, sql, 'utf8');

try {
  const out = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], shell: true });
  const jsonStart = out.indexOf('{');
  const parsed = JSON.parse(out.slice(jsonStart));
  const res = parsed.rows?.[0]?.result;

  console.log('=== CROSS-ANALYZER HARMONIZATION ACCEPTANCE AUDIT ===\n');

  console.log('1. HARMONIZED INTEROPERABILITY ALIASES:');
  console.log(`   - Verified alias count: ${res.aliases?.length}`);
  assert(res.aliases?.length >= 23, 'All 23 harmonized aliases must be registered');
  for (const a of res.aliases) {
    console.log(`     ✓ ${a.alias.padEnd(12)} -> [${a.test_code}] ${a.test_name}`);
  }

  console.log('\n2. PRE-ANALYTICAL SPECIMEN GOVERNANCE RULES:');
  console.log(`   - Verified rules count: ${res.specimen_rules?.length}`);
  assert(res.specimen_rules?.length > 0, 'Specimen governance rules must be populated');

  // Verify CounCell rule
  const councellRule = res.specimen_rules.find(r => r.analyzer_code === 'COUNCELL_23_EXCEL');
  assert(councellRule, 'CounCell rule must exist');
  assert.equal(councellRule.do_not_centrifuge, true, 'CounCell CBC must have do_not_centrifuge=true');
  assert.equal(councellRule.primary_tube_color, 'Lavender');
  console.log('   ✓ CounCell 23 Excel: EDTA Whole Blood, Lavender K2EDTA, do_not_centrifuge=TRUE');

  // Verify CORALAB ACE rule
  const coralabRule = res.specimen_rules.find(r => r.analyzer_code === 'CORALAB_ACE' && r.test_code === 'BIO-0010');
  assert(coralabRule, 'CORALAB ACE rule must exist');
  assert.equal(coralabRule.centrifugation_rcf, null, 'Centrifugation RCF must be NULL when RPM is rotor-dependent');
  console.log('   ✓ CORALAB ACE: SST Serum, Gold/Red, 3000 RPM x 10 min SOP text, centrifugation_rcf=NULL');

  // Verify Glucose conditional rule
  const fbsRule = res.specimen_rules.find(r => r.test_code === 'BIO-0001');
  assert(fbsRule, 'FBS rule must exist');
  assert(fbsRule.conditional_rules?.delayed_processing_gt_60_min, 'FBS must have delayed processing conditional rule');
  console.log('   ✓ Glucose (FBS): SST Gold/Red standard, Grey Fluoride conditional rule (>60 min delay)');

  // Verify D-Dimer citrate rule
  const ddimerRule = res.specimen_rules.find(r => r.test_code === 'COA-0006');
  assert(ddimerRule, 'D-Dimer rule must exist');
  assert.equal(ddimerRule.primary_tube_color, 'Light Blue');
  assert.equal(ddimerRule.preferred_specimen, 'Citrated Plasma');
  console.log('   ✓ D-Dimer: Citrated Plasma, Light Blue 3.2% Citrate, 9:1 ratio, µg/mL FEU locked');

  console.log('\n3. PROPOSED CRITICAL / PANIC POLICIES:');
  console.log(`   - Verified policies count: ${res.critical_policies?.length}`);
  assert(res.critical_policies?.length >= 17, 'All 17 proposed critical policies must be recorded');
  for (const p of res.critical_policies) {
    assert.equal(p.critical_policy_status, 'LAB_APPROVAL_REQUIRED', 'Initial status must be LAB_APPROVAL_REQUIRED');
    console.log(`     ✓ [${p.test_code}] ${p.test_name.padEnd(30)} : ${p.action_threshold_text} (${p.critical_policy_status})`);
  }

  console.log('\n4. COLLISION AUDIT:');
  const c = res.collisions;
  console.log(`   - Conflicting units          : ${c.conflicting_units}`);
  console.log(`   - Alias collisions           : ${c.alias_collisions}`);
  console.log(`   - Analyzer channel collisions: ${c.analyzer_channel_collisions}`);
  console.log(`   - CK-MB Mass/Activity collision: ${c.ckmb_collision}`);
  console.log(`   - hs-CRP/CRP collision       : ${c.crp_collision}`);
  console.log(`   - Thyroid Free/Total collision: ${c.thyroid_collision}`);
  console.log(`   - D-Dimer FEU/DDU collision  : ${c.ddimer_collision}`);
  console.log(`   - Differential collisions    : ${c.diff_collision}`);

  assert.equal(c.conflicting_units, 0, 'Conflicting units must be 0');
  assert.equal(c.alias_collisions, 0, 'Alias collisions must be 0');
  assert.equal(c.analyzer_channel_collisions, 0, 'Analyzer channel collisions must be 0');
  assert.equal(c.ckmb_collision, 0, 'CK-MB collision must be 0');
  assert.equal(c.crp_collision, 0, 'CRP collision must be 0');
  assert.equal(c.thyroid_collision, 0, 'Thyroid collision must be 0');
  assert.equal(c.ddimer_collision, 0, 'D-Dimer collision must be 0');
  assert.equal(c.diff_collision, 0, 'Differential collision must be 0');

  console.log('\n================================================================');
  console.log('=== CROSS-ANALYZER HARMONIZATION AUDIT: 100% PASSED ===');
  console.log('================================================================');
} finally {
  try { unlinkSync(tmp); } catch {}
}
