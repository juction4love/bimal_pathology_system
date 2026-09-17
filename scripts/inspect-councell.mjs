import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const sql = `
SELECT json_build_object(
    'analyzer', (
        SELECT json_build_object(
            'code', code,
            'name', name,
            'model', model,
            'manufacturer', manufacturer,
            'lifecycle_status', lifecycle_status
        )
        FROM public.analyzers
        WHERE code = 'COUNCELL_23_EXCEL'
    ),
    'channels', (
        SELECT json_agg(json_build_object(
            'channel_code', m.channel_code,
            'channel_name', m.channel_name,
            'measurement_type', m.measurement_type,
            'diff_type', m.differential_type,
            'unit', m.unit,
            'test_code', t.code,
            'test_name', t.name
        ) ORDER BY m.channel_code)
        FROM public.analyzer_parameter_mappings m
        LEFT JOIN public.tests t ON t.id = m.test_id
        WHERE m.analyzer_id IN (SELECT id FROM public.analyzers WHERE code = 'COUNCELL_23_EXCEL')
    ),
    'cbc_aliases', (
        SELECT json_agg(json_build_object(
            'alias', a.alias_name,
            'test_code', t.code,
            'test_name', t.name
        ))
        FROM public.test_aliases a
        JOIN public.tests t ON t.id = a.test_id
        WHERE a.alias_name LIKE 'CBC_%'
    )
) as result;
`;

const tmp = path.resolve('tmp_inspect_councell.sql');
writeFileSync(tmp, sql, 'utf8');
try {
  const out = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], shell: true });
  const jsonStart = out.indexOf('{');
  console.log(out.slice(jsonStart));
} finally {
  try { unlinkSync(tmp); } catch {}
}
