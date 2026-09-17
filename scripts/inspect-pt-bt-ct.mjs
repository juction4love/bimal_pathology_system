import { execSync } from 'node:child_process';
import { writeFileSync, unlinkSync } from 'node:fs';
import path from 'node:path';

const sql = `
WITH test_matches AS (
  SELECT 
    t.*,
    (SELECT json_agg(row_to_json(p.*))
     FROM public.parameters p WHERE p.test_id = t.id) as parameters,
    (SELECT json_agg(row_to_json(a.*))
     FROM public.test_aliases a WHERE a.test_id = t.id) as aliases,
    (SELECT json_agg(row_to_json(r.*))
     FROM public.catalogue_rate_versions r WHERE r.test_id = t.id) as rates,
    (SELECT json_agg(row_to_json(rr.*))
     FROM public.reference_ranges rr JOIN public.parameters p ON p.id = rr.parameter_id WHERE p.test_id = t.id) as ranges
  FROM public.tests t
  WHERE 
    t.code ILIKE '%PT%' OR t.code ILIKE '%BT%' OR t.code ILIKE '%CT%'
    OR t.name ILIKE '%Prothrombin%' OR t.name ILIKE '%Bleeding%' OR t.name ILIKE '%Clotting%' OR t.name ILIKE '%Coagulation%'
    OR t.short_name ILIKE '%PT%' OR t.short_name ILIKE '%BT%' OR t.short_name ILIKE '%CT%'
    OR EXISTS (SELECT 1 FROM public.test_aliases a WHERE a.test_id = t.id AND (a.alias_name ILIKE '%PT%' OR a.alias_name ILIKE '%BT%' OR a.alias_name ILIKE '%CT%' OR a.alias_name ILIKE '%Prothrombin%' OR a.alias_name ILIKE '%Bleeding%' OR a.alias_name ILIKE '%Clotting%'))
)
SELECT json_agg(row_to_json(test_matches.*)) as results FROM test_matches;
`;

const tmpFile = path.resolve('tmp_inspect_pt_bt_ct.sql');
writeFileSync(tmpFile, sql, 'utf8');

try {
  const res = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
    shell: true,
    maxBuffer: 50 * 1024 * 1024,
  });

  const jsonStart = res.indexOf('[');
  const jsonStartObj = res.indexOf('{');
  const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
  const parsed = JSON.parse(res.slice(start));
  const results = Array.isArray(parsed) ? parsed[0]?.results : parsed.rows?.[0]?.results;
  writeFileSync('scripts/inspect_pt_bt_ct_results.json', JSON.stringify(results, null, 2), 'utf8');
  console.log(`Found ${results?.length || 0} matching tests in database.`);
} catch (e) {
  console.error('Error running inspection:', e);
} finally {
  try { unlinkSync(tmpFile); } catch {}
}
