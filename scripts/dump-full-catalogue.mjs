import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const querySql = `
SELECT json_build_object(
    'total_tests', (SELECT count(*) FROM public.tests),
    'tests', (
        SELECT json_agg(json_build_object(
            'id', t.id,
            'code', t.code,
            'name', t.name,
            'short_name', t.short_name,
            'department', t.department,
            'subdepartment', t.subdepartment,
            'category', t.category,
            'test_type', t.test_type,
            'sample_type', t.sample_type,
            'specimen_type', t.specimen_type,
            'container', t.container,
            'container_type', t.container_type,
            'method', t.method,
            'unit', t.unit,
            'price_paisa', t.price_paisa,
            'is_active', t.is_active,
            'billing_enabled', t.billing_enabled,
            'clinical_reporting_enabled', t.clinical_reporting_enabled,
            'validation_status', t.validation_status,
            'configuration_status', t.configuration_status,
            'clinical_configuration_status', t.clinical_configuration_status,
            'lifecycle_status', t.lifecycle_status,
            'report_data_type', t.report_data_type,
            'search_aliases', t.search_aliases,
            'notes', t.notes
        ) ORDER BY t.department, t.code)
        FROM public.tests t
    ),
    'panels', (
        SELECT json_agg(json_build_object(
            'id', p.id,
            'code', p.code,
            'name', p.name,
            'department', p.department,
            'price_paisa', p.price_paisa,
            'is_active', p.is_active,
            'billing_enabled', p.billing_enabled,
            'components', (
                SELECT json_agg(json_build_object(
                    'component_test_id', cpc.component_test_id,
                    'test_code', t.code,
                    'test_name', t.name,
                    'display_order', cpc.display_order,
                    'is_required', cpc.is_required
                ) ORDER BY cpc.display_order)
                FROM public.catalogue_panel_components cpc
                JOIN public.tests t ON t.id = cpc.component_test_id
                WHERE cpc.panel_id = p.id
            )
        ) ORDER BY p.code)
        FROM public.tests p
        WHERE p.test_type = 'Panel'
    ),
    'test_aliases', (
        SELECT json_agg(json_build_object(
            'test_code', t.code,
            'alias_name', a.alias_name,
            'alias_type', a.alias_type
        ))
        FROM public.test_aliases a
        JOIN public.tests t ON t.id = a.test_id
    )
) AS full_dump;
`;

async function run() {
  const tmpFile = path.resolve('tmp_full_dump.sql');
  writeFileSync(tmpFile, querySql, 'utf8');

  try {
    const res = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: true,
      maxBuffer: 50 * 1024 * 1024,
    });

    const jsonStart = res.indexOf('[');
    const jsonStartObj = res.indexOf('{');
    const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
    const parsed = JSON.parse(res.slice(start));
    const payload = Array.isArray(parsed) ? parsed[0]?.full_dump : parsed.rows?.[0]?.full_dump;
    writeFileSync('scripts/full_catalogue_dump.json', JSON.stringify(payload, null, 2), 'utf8');
    console.log('Full catalogue dumped! Tests count:', payload.total_tests);
    console.log('Panels count:', payload.panels?.length);
    console.log('Aliases count:', payload.test_aliases?.length);
  } catch (err) {
    console.error('Error executing query:');
    console.error('stdout:', err.stdout);
    console.error('stderr:', err.stderr);
  } finally {
    try { unlinkSync(tmpFile); } catch {}
  }
}

run();
