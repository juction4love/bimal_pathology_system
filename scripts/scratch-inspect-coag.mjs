import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const sql = `
SELECT json_build_object(
  'pt_ranges', (
    SELECT json_agg(row_to_json(r.*))
    FROM public.reference_ranges r
    JOIN public.parameters p ON p.id = r.parameter_id
    WHERE p.test_id = '2f8b4df3-40e4-4141-b003-9a124fdc75a8'
  ),
  'bt_ranges', (
    SELECT json_agg(row_to_json(r.*))
    FROM public.reference_ranges r
    JOIN public.parameters p ON p.id = r.parameter_id
    WHERE p.test_id = '3531fc7b-db20-4f22-85c2-4a2076763113'
  ),
  'ct_ranges', (
    SELECT json_agg(row_to_json(r.*))
    FROM public.reference_ranges r
    JOIN public.parameters p ON p.id = r.parameter_id
    WHERE p.test_id = '1e03e664-18f1-4893-b651-0f25642e83c1'
  ),
  'inr_ranges', (
    SELECT json_agg(row_to_json(r.*))
    FROM public.reference_ranges r
    JOIN public.parameters p ON p.id = r.parameter_id
    WHERE p.test_id = '327a90fa-c2fd-4af9-ba3b-84fb478caf4a'
  )
) AS res;
`;

const tmp = path.resolve('tmp_inspect_coag_ranges.sql');
writeFileSync(tmp, sql, 'utf8');
try {
  const raw = execSync(`npx supabase db query --linked --output json -f "${tmp}"`, {
    encoding: 'utf8',
    shell: true,
    maxBuffer: 10 * 1024 * 1024
  });
  const jsonStart = raw.indexOf('[');
  const jsonStartObj = raw.indexOf('{');
  const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
  const parsed = JSON.parse(raw.slice(start));
  const data = Array.isArray(parsed) ? parsed[0]?.res : parsed.rows?.[0]?.res;
  console.log(JSON.stringify(data, null, 2));
} finally {
  unlinkSync(tmp);
}
