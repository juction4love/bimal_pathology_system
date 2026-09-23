import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

async function main() {
  const migrationContent = readFileSync('supabase/migrations_legacy_archive/00119_pt_inr_bt_ct_clinical_configuration.sql', 'utf8');
  
  // Wrap migration content with ROLLBACK instead of COMMIT for safety
  const dryRunSql = `
  BEGIN;
  ${migrationContent.replace(/^BEGIN;/m, '-- BEGIN').replace(/^COMMIT;/m, '-- COMMIT')}
  
  -- Verification queries within transaction
  SELECT json_build_object(
    'pt_test', (SELECT row_to_json(t) FROM (SELECT id, code, name, short_name, method, price_paisa FROM public.tests WHERE code = 'COA-0001') t),
    'bt_test', (SELECT row_to_json(t) FROM (SELECT id, code, name, short_name, method, price_paisa FROM public.tests WHERE code = 'COA-0007') t),
    'ct_test', (SELECT row_to_json(t) FROM (SELECT id, code, name, short_name, method, price_paisa FROM public.tests WHERE code = 'COA-0008') t),
    'combo_test', (SELECT row_to_json(t) FROM (SELECT id, code, name, short_name, method, price_paisa FROM public.tests WHERE code = 'PRO-0030') t),
    'combo_components', (SELECT json_agg(row_to_json(c)) FROM (
      SELECT pc.display_order, t.code, t.name, pc.is_required
      FROM public.catalogue_panel_components pc
      JOIN public.tests t ON t.id = pc.component_test_id
      JOIN public.tests p ON p.id = pc.panel_id
      WHERE p.code = 'PRO-0030'
      ORDER BY pc.display_order
    ) c),
    'pt_inr_parameters', (SELECT json_agg(row_to_json(p)) FROM (
      SELECT code, name, unit, value_type, formula, display_order
      FROM public.parameters
      WHERE test_id = '2f8b4df3-40e4-4141-b003-9a124fdc75a8'
      ORDER BY display_order
    ) p),
    'pt_ranges', (SELECT json_agg(row_to_json(r)) FROM (
      SELECT p.code, p.name, rr.normal_min, rr.normal_max, rr.unit, rr.method, rr.reference_text
      FROM public.reference_ranges rr
      JOIN public.parameters p ON p.id = rr.parameter_id
      WHERE p.test_id = '2f8b4df3-40e4-4141-b003-9a124fdc75a8'
    ) r),
    'bt_ranges', (SELECT json_agg(row_to_json(r)) FROM (
      SELECT p.code, p.name, rr.normal_min, rr.normal_max, rr.unit, rr.method, rr.reference_text
      FROM public.reference_ranges rr
      JOIN public.parameters p ON p.id = rr.parameter_id
      WHERE p.test_id = '3531fc7b-db20-4f22-85c2-4a2076763113'
    ) r),
    'ct_ranges', (SELECT json_agg(row_to_json(r)) FROM (
      SELECT p.code, p.name, rr.normal_min, rr.normal_max, rr.unit, rr.method, rr.reference_text
      FROM public.reference_ranges rr
      JOIN public.parameters p ON p.id = rr.parameter_id
      WHERE p.test_id = '1e03e664-18f1-4893-b651-0f25642e83c1'
    ) r),
    'reagent_config_test', (
      SELECT count(*) FROM public.pt_inr_reagent_configs
    )
  ) AS dryrun_result;
  
  ROLLBACK;
  `;

  const tmpFile = path.resolve('tmp_dryrun_00119.sql');
  writeFileSync(tmpFile, dryRunSql, 'utf8');

  try {
    const raw = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
      encoding: 'utf8',
      shell: true,
      maxBuffer: 10 * 1024 * 1024
    });
    const jsonStart = raw.indexOf('[');
    const jsonStartObj = raw.indexOf('{');
    const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
    const parsed = JSON.parse(raw.slice(start));
    const data = Array.isArray(parsed) ? parsed[0]?.dryrun_result : parsed.rows?.[0]?.dryrun_result;
    console.log('DRY RUN 00119 RESULT:');
    console.log(JSON.stringify(data, null, 2));
    console.log('\nDRY RUN SUCCESSFUL (ROLLED BACK).');
  } catch (err) {
    console.error('DRY RUN FAILED:', err.message);
    if (err.stdout) console.log('STDOUT:', err.stdout);
    if (err.stderr) console.error('STDERR:', err.stderr);
    process.exit(1);
  } finally {
    unlinkSync(tmpFile);
  }
}

main();
