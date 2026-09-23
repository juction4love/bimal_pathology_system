import { execSync } from 'node:child_process';
import fs from 'node:fs';

const sql = `
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'catalogue_rate_versions' AND table_schema = 'public'
ORDER BY ordinal_position;
`;
fs.writeFileSync('tmp_query.sql', sql, 'utf8');
console.log(execSync('npx supabase db query --linked -f tmp_query.sql', { encoding: 'utf8' }));
