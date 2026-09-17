import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const sql = `
SELECT json_build_object(
    'panel_components', (
        SELECT json_agg(json_build_object(
            'display_order', c.display_order,
            'code', t.code,
            'name', t.name,
            'unit', t.unit,
            'component_role', c.component_role,
            'is_required', c.is_required
        ) ORDER BY c.display_order)
        FROM public.catalogue_panel_components c
        JOIN public.tests p ON p.id = c.panel_id
        JOIN public.tests t ON t.id = c.component_test_id
        WHERE p.code = 'HEM-0001'
    ),
    'hem_tests', (
        SELECT json_agg(json_build_object(
            'code', code,
            'name', name,
            'unit', unit
        ) ORDER BY code)
        FROM public.tests
        WHERE code LIKE 'HEM-00%'
    )
) as info;
`;

const tmp = path.resolve('tmp_cbc_details.sql');
writeFileSync(tmp, sql, 'utf8');
try {
  const out = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], shell: true });
  const jsonStart = out.indexOf('{');
  console.log(out.slice(jsonStart));
} finally {
  try { unlinkSync(tmp); } catch {}
}
