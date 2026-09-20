import { execSync } from 'node:child_process';
import { writeFileSync, unlinkSync } from 'node:fs';

const sql = `
SELECT json_agg(x) AS res FROM (
    SELECT table_name, column_name, data_type, is_nullable
    FROM information_schema.columns 
    WHERE table_name IN ('parameters', 'reference_ranges') 
      AND table_schema = 'public'
    ORDER BY table_name, ordinal_position
) x;
`;

writeFileSync('tmp_schema_check.sql', sql);
try {
    const raw = execSync('npx supabase db query --linked -f tmp_schema_check.sql', { encoding: 'utf8' });
    const jsonStart = raw.indexOf('{');
    const jsonEnd = raw.lastIndexOf('}');
    const parsed = JSON.parse(raw.slice(jsonStart, jsonEnd + 1));
    console.log(JSON.stringify(parsed.rows[0].res, null, 2));
} finally {
    try { unlinkSync('tmp_schema_check.sql'); } catch {}
}
