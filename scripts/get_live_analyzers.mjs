import { execSync } from 'node:child_process';
import fs from 'node:fs';

const sql = `
SELECT 
  id, code, name, manufacturer, model, serial_number, laboratory_location, lifecycle_status, created_at
FROM public.analyzers
ORDER BY code;
`;

fs.writeFileSync('tmp_q9_analyzers_fixed.sql', sql, 'utf8');
const res = execSync('npx supabase db query --linked -f tmp_q9_analyzers_fixed.sql', { encoding: 'utf8' });
console.log(res);
