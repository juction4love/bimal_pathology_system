import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

async function main() {
  const m119 = readFileSync('supabase/migrations/00119_pt_inr_bt_ct_clinical_configuration.sql', 'utf8');
  const m120 = readFileSync('supabase/migrations/00120_oncology_routine_preop_tumor_marker_catalogue_reconciliation.sql', 'utf8');

  const dryRunSql = `
  BEGIN;
  
  -- Apply 00119
  ${m119.replace(/^BEGIN;/m, '-- BEGIN 119').replace(/^COMMIT;/m, '-- COMMIT 119')}
  
  -- Apply 00120
  ${m120.replace(/^BEGIN;/m, '-- BEGIN 120').replace(/^COMMIT;/m, '-- COMMIT 120')}

  -- Verification queries
  SELECT json_build_object(
    'lbc', (SELECT row_to_json(t) FROM (SELECT code, name, reporting_type, price_paisa, search_aliases FROM public.tests WHERE code = 'CYT-0008') t),
    'hpv', (SELECT row_to_json(t) FROM (SELECT code, name, reporting_type, price_paisa, search_aliases FROM public.tests WHERE code = 'MOL-0014') t),
    'hpv_rates', (SELECT json_agg(row_to_json(rv)) FROM public.catalogue_rate_versions rv JOIN public.tests t ON t.id = rv.test_id WHERE t.code = 'MOL-0014'),
    'viral_panel', (SELECT row_to_json(t) FROM (SELECT code, name, reporting_type, test_kind, price_paisa FROM public.tests WHERE code = 'PRO-0031') t),
    'viral_components', (
      SELECT json_agg(row_to_json(c)) FROM (
        SELECT pc.display_order, t.code, t.name, t.price_paisa
        FROM public.catalogue_panel_components pc
        JOIN public.tests t ON t.id = pc.component_test_id
        JOIN public.tests p ON p.id = pc.panel_id
        WHERE p.code = 'PRO-0031'
        ORDER BY pc.display_order
      ) c
    ),
    'chemo_panel', (SELECT row_to_json(t) FROM (SELECT code, name, reporting_type, test_kind, price_paisa FROM public.tests WHERE code = 'PRO-0032') t),
    'chemo_components', (
      SELECT json_agg(row_to_json(c)) FROM (
        SELECT pc.display_order, t.code, t.name, t.price_paisa
        FROM public.catalogue_panel_components pc
        JOIN public.tests t ON t.id = pc.component_test_id
        JOIN public.tests p ON p.id = pc.panel_id
        WHERE p.code = 'PRO-0032'
        ORDER BY pc.display_order
      ) c
    ),
    'preop_panel', (SELECT row_to_json(t) FROM (SELECT code, name, reporting_type, test_kind, price_paisa FROM public.tests WHERE code = 'PRO-0033') t),
    'preop_components', (
      SELECT json_agg(row_to_json(c)) FROM (
        SELECT pc.display_order, t.code, t.name, t.price_paisa
        FROM public.catalogue_panel_components pc
        JOIN public.tests t ON t.id = pc.component_test_id
        JOIN public.tests p ON p.id = pc.panel_id
        WHERE p.code = 'PRO-0033'
        ORDER BY pc.display_order
      ) c
    ),
    'target_aliases_count', (
      SELECT count(*) FROM public.tests 
      WHERE code IN ('HEM-0001', 'HEM-0020', 'PRO-0001', 'PRO-0002', 'PRO-0008', 'CLP-0001', 'COA-0001', 'COA-0003', 'COA-0007', 'COA-0008', 'PRO-0030', 'SER-0086', 'SER-0087', 'SER-0088', 'TUM-0002', 'TUM-0001', 'TUM-0003', 'TUM-0004', 'TUM-0005', 'TUM-0007', 'TUM-0008', 'END-0039', 'CYT-0008', 'MOL-0014', 'BIO-0050', 'PRO-0005', 'BIO-0053', 'BIO-0051', 'BIO-0068', 'PCT_SEPSIS')
        AND array_length(search_aliases, 1) > 0
    )
  ) AS dryrun_result;

  ROLLBACK;
  `;

  const tmpFile = path.resolve('tmp_dryrun_00120.sql');
  writeFileSync(tmpFile, dryRunSql, 'utf8');

  try {
    const raw = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
      encoding: 'utf8',
      shell: true,
      maxBuffer: 20 * 1024 * 1024
    });
    const jsonStart = raw.indexOf('[');
    const jsonStartObj = raw.indexOf('{');
    const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
    const parsed = JSON.parse(raw.slice(start));
    const data = Array.isArray(parsed) ? parsed[0]?.dryrun_result : parsed.rows?.[0]?.dryrun_result;
    console.log('DRY RUN 00120 RESULT:');
    console.log(JSON.stringify(data, null, 2));
    console.log('\nDRY RUN SUCCESSFUL (ROLLED BACK CLEANLY).');
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
