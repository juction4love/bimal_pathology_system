import { execSync } from 'node:child_process';
import fs from 'node:fs';

const sql = `
SELECT json_build_object(
  'cbc_duplicate_active_ranges', (
    SELECT count(*) FROM (
      SELECT rr.parameter_id, rr.gender, rr.age_min_days, rr.age_max_days
      FROM public.reference_ranges rr
      JOIN public.parameters p ON p.id = rr.parameter_id
      JOIN public.tests t ON t.id = p.test_id
      WHERE t.code = 'HEM-0001' AND rr.is_active = TRUE
      GROUP BY rr.parameter_id, rr.gender, rr.age_min_days, rr.age_max_days
      HAVING count(*) > 1
    ) sub
  ),
  'other_duplicate_active_ranges', (
    SELECT json_agg(row_to_json(grp))
    FROM (
      SELECT t.code as test_code, p.code as param_code, rr.gender, rr.age_min_days, rr.age_max_days, count(*) as cnt
      FROM public.reference_ranges rr
      JOIN public.parameters p ON p.id = rr.parameter_id
      JOIN public.tests t ON t.id = p.test_id
      WHERE rr.is_active = TRUE
      GROUP BY t.code, p.code, rr.parameter_id, rr.gender, rr.age_min_days, rr.age_max_days
      HAVING count(*) > 1
    ) grp
  )
) as result;
`;

fs.writeFileSync('tmp_rr.sql', sql);
try {
  const raw = execSync('npx supabase db query --linked --output json -f tmp_rr.sql', { encoding: 'utf8', shell: true });
  const parsed = JSON.parse(raw);
  const result = parsed[0]?.result || parsed.rows?.[0]?.result;
  console.log('Columns:', JSON.stringify(result, null, 2));
} finally {
  if (fs.existsSync('tmp_rr.sql')) fs.unlinkSync('tmp_rr.sql');
}
