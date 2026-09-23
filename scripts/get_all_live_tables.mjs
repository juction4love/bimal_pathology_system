import { execSync } from 'node:child_process';
import fs from 'node:fs';

const sql = `
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;
`;

fs.writeFileSync('tmp_q7_all_tables.sql', sql, 'utf8');
const res = execSync('npx supabase db query --linked -f tmp_q7_all_tables.sql', { encoding: 'utf8' });
console.log(res);
