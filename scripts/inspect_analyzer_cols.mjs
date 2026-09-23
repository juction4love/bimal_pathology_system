import { execSync } from 'node:child_process';
import fs from 'node:fs';

const sql = `
SELECT 
  column_name, 
  data_type 
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'analyzers'
ORDER BY ordinal_position;
`;

fs.writeFileSync('tmp_q6_analyzer_schema.sql', sql, 'utf8');
const res = execSync('npx supabase db query --linked -f tmp_q6_analyzer_schema.sql', { encoding: 'utf8' });
console.log(res);
