import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const sql = `
SELECT json_build_object(
    'cbc_components', (
        SELECT json_agg(json_build_object(
            'order', c.display_order,
            'code', t.code,
            'name', t.name,
            'unit', t.unit,
            'role', c.component_role,
            'required', c.is_required
        ) ORDER BY c.display_order)
        FROM public.catalogue_panel_components c
        JOIN public.tests p ON p.id = c.panel_id
        JOIN public.tests t ON t.id = c.component_test_id
        WHERE p.code = 'HEM-0001'
    ),
    'myoglobin_ranges', (
        SELECT json_agg(json_build_object(
            'id', r.id,
            'gender', r.gender,
            'min', r.normal_min,
            'max', r.normal_max,
            'text', r.normal_text,
            'unit', r.unit,
            'method', r.method
        ))
        FROM public.reference_ranges r
        JOIN public.parameters p ON p.id = r.parameter_id
        JOIN public.tests t ON t.id = p.test_id
        WHERE t.code = 'BIO-0065'
    ),
    'councell_mappings', (
        SELECT json_agg(json_build_object(
            'channel_code', m.channel_code,
            'channel_name', m.channel_name,
            'test_code', t.code,
            'measurement_type', m.measurement_type,
            'diff_type', m.differential_type,
            'unit', m.unit
        ))
        FROM public.analyzer_parameter_mappings m
        LEFT JOIN public.tests t ON t.id = m.test_id
        WHERE m.analyzer_id IN (SELECT id FROM public.analyzers WHERE code = 'COUNCELL_23_EXCEL')
    ),
    'all_hem_tests', (
        SELECT json_agg(json_build_object(
            'code', code,
            'name', name,
            'unit', unit
        ) ORDER BY code)
        FROM public.tests
        WHERE code IN ('HEM-0001', 'HEM-0002', 'HEM-0003', 'HEM-0004', 'HEM-0005', 'HEM-0006', 'HEM-0007', 'HEM-0008', 'HEM-0009', 'HEM-0010', 'HEM-0011', 'HEM-0012', 'HEM-0013', 'HEM-0014', 'HEM-0015', 'HEM-0016', 'HEM-0017', 'HEM-0018', 'HEM-0019', 'HEM-0020', 'HEM-0021', 'HEM-0022', 'HEM-0023', 'HEM-0024', 'HEM-0025')
    )
) as result;
`;

const tmp = path.resolve('tmp_inspect.sql');
writeFileSync(tmp, sql, 'utf8');
try {
  const out = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], shell: true });
  const jsonStart = out.indexOf('{');
  console.log(out.slice(jsonStart));
} finally {
  try { unlinkSync(tmp); } catch {}
}
