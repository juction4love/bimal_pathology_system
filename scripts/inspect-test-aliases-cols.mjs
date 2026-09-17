import { execSync } from 'node:child_process';
import { writeFileSync, unlinkSync } from 'node:fs';
import path from 'node:path';

const sql = `
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'test_aliases' AND table_schema = 'public';
`;

const tmpFile = path.resolve('tmp_inspect_test_aliases_cols.sql');
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
  console.log('Columns of test_aliases:', results);
} catch (e) {
  console.error('Error:', e);
} finally {
  try { unlinkSync(tmpFile); } catch {}
}
