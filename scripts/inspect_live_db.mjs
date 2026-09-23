import { execSync } from 'node:child_process';
import fs from 'node:fs';

const sql = `
SELECT 
  table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_type = 'BASE TABLE' 
ORDER BY table_name;
`;

fs.writeFileSync('tmp_query.sql', sql, 'utf8');
const output = execSync('npx supabase db query --linked -f tmp_query.sql', { encoding: 'utf8' });
console.log(output);
