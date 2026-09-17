import { execSync } from 'node:child_process';
import { writeFileSync, unlinkSync } from 'node:fs';
import path from 'node:path';

const sql = `
SELECT id, code, name, short_name, department, is_active
FROM public.tests
WHERE 
  code IN ('PT', 'BT', 'CT', 'COA-0001', 'COA-0007', 'COA-0008')
  OR name ILIKE 'Prothrombin Time%'
  OR name ILIKE 'Bleeding Time%'
  OR name ILIKE 'Clotting Time%'
  OR name ILIKE 'Coagulation Time%'
  OR short_name IN ('PT', 'BT', 'CT')
ORDER BY code;
`;

const tmpFile = path.resolve('tmp_check_duplicates.sql');
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
  console.log('=== DUPLICATE AUDIT RESULTS ===');
  for (const r of results || []) {
    console.log(`- [${r.id}] Code: "${r.code}", Name: "${r.name}", Short: "${r.short_name}", Dept: "${r.department}", Active: ${r.is_active}`);
  }
} catch (e) {
  console.error('Error:', e);
} finally {
  try { unlinkSync(tmpFile); } catch {}
}
