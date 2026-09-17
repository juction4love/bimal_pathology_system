import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const sql = `
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'test_aliases'
ORDER BY ordinal_position;
`;
const tmpFile = path.resolve('tmp_test_aliases.sql');
writeFileSync(tmpFile, sql, 'utf8');
try {
  const raw = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, { encoding: 'utf8', shell: true });
  console.log(raw);
} finally {
  unlinkSync(tmpFile);
}
