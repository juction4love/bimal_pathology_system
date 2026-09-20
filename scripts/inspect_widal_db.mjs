import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const sql = `
SELECT json_build_object(
  'tests_widal', (SELECT json_agg(row_to_json(t)) FROM public.tests t WHERE t.code ILIKE '%WIDAL%' OR t.name ILIKE '%Widal%'),
  'params_widal', (SELECT json_agg(row_to_json(p)) FROM public.parameters p WHERE p.code ILIKE '%WIDAL%' OR p.name ILIKE '%Typhi%' OR p.name ILIKE '%Widal%'),
  'option_sets', (SELECT json_agg(row_to_json(os)) FROM public.catalogue_option_sets os WHERE os.name ILIKE '%Widal%' OR os.code ILIKE '%Widal%'),
  'option_values', (
    SELECT json_agg(row_to_json(ov))
    FROM public.catalogue_option_values ov
    JOIN public.catalogue_option_sets os ON os.id = ov.option_set_id
    WHERE os.name ILIKE '%Widal%' OR os.code ILIKE '%Widal%'
  )
);
`;

const tmp = path.resolve('tmp_widal_db.sql');
writeFileSync(tmp, sql, 'utf8');
try {
  const out = execSync('npx supabase db query --linked -f tmp_widal_db.sql', { encoding: 'utf8', shell: true });
  console.log(out);
} finally {
  try { unlinkSync(tmp); } catch {}
}
