import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const sql = `
SELECT json_agg(json_build_object('code', code, 'name', name) ORDER BY code) as bio_tests
FROM public.tests
WHERE code LIKE 'BIO-00%';
`;

const tmp = path.resolve('tmp_bio_codes.sql');
writeFileSync(tmp, sql, 'utf8');
try {
  const out = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], shell: true });
  const jsonStart = out.indexOf('{');
  console.log(out.slice(jsonStart));
} finally {
  try { unlinkSync(tmp); } catch {}
}
