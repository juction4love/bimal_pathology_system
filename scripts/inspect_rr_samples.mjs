import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const sql = `
SELECT json_agg(json_build_object(
  'param_name', p.name,
  'value_type', p.value_type,
  'gender', rr.gender,
  'normal_min', rr.normal_min,
  'normal_max', rr.normal_max,
  'normal_text', rr.normal_text,
  'reference_text', rr.reference_text
))
FROM public.reference_ranges rr
JOIN public.parameters p ON p.id = rr.parameter_id
WHERE p.value_type IN ('Select', 'Text', 'Categorical') OR p.name ILIKE '%Dengue%' OR p.name ILIKE '%HBsAg%'
LIMIT 10;
`;

const tmp = path.resolve('tmp_rr_sample.sql');
writeFileSync(tmp, sql, 'utf8');
try {
  const out = execSync('npx supabase db query --linked -f tmp_rr_sample.sql', { encoding: 'utf8', shell: true });
  console.log(out);
} finally {
  try { unlinkSync(tmp); } catch {}
}
