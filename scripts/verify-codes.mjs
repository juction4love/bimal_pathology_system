import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const sql = `
SELECT json_agg(json_build_object('code', code, 'name', name, 'department', department)) as tests
FROM public.tests
WHERE code IN (
    'HEM-0001', 'HEM-0002', 'HEM-0004', 'HEM-0005', 'HEM-0006', 'HEM-0016',
    'BIO-0001', 'BIO-0002', 'BIO-0003', 'BIO-0007', 'BIO-0009', 'BIO-0010', 'BIO-0011', 'BIO-0014', 'BIO-0015',
    'END-0001', 'END-0002', 'END-0003', 'BIO-0051', 'BIO-0053', 'BIO-0063', 'BIO-0067'
);
`;

const tmp = path.resolve('tmp_test_codes.sql');
writeFileSync(tmp, sql, 'utf8');
try {
  const out = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], shell: true });
  const jsonStart = out.indexOf('{');
  console.log(out.slice(jsonStart));
} finally {
  try { unlinkSync(tmp); } catch {}
}
