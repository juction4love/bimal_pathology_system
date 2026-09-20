import { execSync } from 'node:child_process';
import { writeFileSync, unlinkSync } from 'node:fs';

const sql = `
SELECT json_agg(x) AS res FROM (
    SELECT column_name, udt_name, data_type
    FROM information_schema.columns 
    WHERE table_name = 'parameters' AND table_schema = 'public'
) x;
`;

writeFileSync('tmp_enums.sql', sql);
try {
    const raw = execSync('npx supabase db query --linked -f tmp_enums.sql', { encoding: 'utf8' });
    const jsonStart = raw.indexOf('{');
    const jsonEnd = raw.lastIndexOf('}');
    const parsed = JSON.parse(raw.slice(jsonStart, jsonEnd + 1));
    console.log(JSON.stringify(parsed.rows[0].res, null, 2));
} finally {
    try { unlinkSync('tmp_enums.sql'); } catch {}
}
