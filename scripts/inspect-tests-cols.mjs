import { execSync } from 'node:child_process';
import { writeFileSync, unlinkSync } from 'node:fs';
import path from 'node:path';

const sql = `
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'tests' AND table_schema = 'public'
ORDER BY ordinal_position;
`;

const tmpFile = path.resolve('tmp_inspect_tests_cols.sql');
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
  console.log('Columns of tests:', results.map(c => `${c.column_name} (${c.data_type})`).join(', '));
} catch (e) {
  console.error('Error:', e);
} finally {
  try { unlinkSync(tmpFile); } catch {}
}
