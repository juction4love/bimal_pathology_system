import { execSync } from 'node:child_process';
import { writeFileSync, unlinkSync } from 'node:fs';
import path from 'node:path';

const sql = `
SELECT 
  t.id, t.code, t.name, t.short_name, t.department, t.specimen_type, t.method, t.reporting_type, t.is_active,
  (SELECT json_agg(row_to_json(p.*)) FROM public.parameters p WHERE p.test_id = t.id) as parameters,
  (SELECT json_agg(row_to_json(a.*)) FROM public.test_aliases a WHERE a.test_id = t.id) as aliases,
  (SELECT json_agg(row_to_json(r.*)) FROM public.catalogue_rate_versions r WHERE r.test_id = t.id) as rates,
  (SELECT json_agg(row_to_json(rr.*)) FROM public.reference_ranges rr JOIN public.parameters p ON p.id = rr.parameter_id WHERE p.test_id = t.id) as ranges
FROM public.tests t
WHERE t.code ILIKE 'COA-%' OR t.department ILIKE '%Coagulation%'
ORDER BY t.code;
`;

const tmpFile = path.resolve('tmp_inspect_coa_all.sql');
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
  const results = Array.isArray(parsed) ? parsed : parsed.rows;
  console.log(`Found ${results?.length || 0} tests in Coagulation:`);
  for (const r of results || []) {
    console.log(`- [${r.id}] Code: "${r.code}", Name: "${r.name}", Dept: "${r.department}", Active: ${r.is_active}`);
    console.log(`  Params: ${JSON.stringify(r.parameters)}`);
    console.log(`  Aliases: ${JSON.stringify(r.aliases)}`);
    console.log(`  Rates: ${JSON.stringify(r.rates)}`);
    console.log(`  Ranges: ${JSON.stringify(r.ranges)}`);
  }
} catch (e) {
  console.error('Error running inspection:', e);
} finally {
  try { unlinkSync(tmpFile); } catch {}
}
