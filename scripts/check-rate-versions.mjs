import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const querySql = `
SELECT json_build_object(
    'rate_versions_count', (SELECT count(*) FROM public.catalogue_rate_versions),
    'sample_rates', (
        SELECT json_agg(json_build_object(
            'entity_type', CASE WHEN test_id IS NOT NULL THEN 'Test' WHEN panel_service_id IS NOT NULL THEN 'Panel' ELSE 'Package' END,
            'test_code', (SELECT code FROM public.tests WHERE id = crv.test_id),
            'price_paisa', crv.price_paisa,
            'status', crv.status,
            'version_number', crv.version_number
        ))
        FROM (SELECT * FROM public.catalogue_rate_versions LIMIT 20) crv
    )
) AS rate_data;
`;

async function run() {
  const tmpFile = path.resolve('tmp_rate_check.sql');
  writeFileSync(tmpFile, querySql, 'utf8');

  try {
    const res = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: true,
    });

    const jsonStart = res.indexOf('[');
    const jsonStartObj = res.indexOf('{');
    const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
    const parsed = JSON.parse(res.slice(start));
    console.log(JSON.stringify(Array.isArray(parsed) ? parsed[0]?.rate_data : parsed.rows?.[0]?.rate_data, null, 2));
  } catch (err) {
    console.error('Error:', err.message, err.stderr);
  } finally {
    try { unlinkSync(tmpFile); } catch {}
  }
}

run();
