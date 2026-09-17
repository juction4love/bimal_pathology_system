import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const sql = `
WITH target_tests AS (
  SELECT 
    t.id,
    t.code,
    t.name,
    t.short_name,
    t.department,
    t.method,
    t.specimen_type,
    t.unit,
    t.price_paisa,
    t.price_paisa / 100 AS price_npr,
    t.validation_status,
    t.billing_enabled,
    t.is_active,
    t.lifecycle_status,
    (SELECT json_agg(a.alias_name) FROM public.test_aliases a WHERE a.test_id = t.id) AS aliases,
    (SELECT json_agg(json_build_object('analyzer', an.name, 'channel_code', m.channel_code, 'channel_name', m.channel_name)) 
     FROM public.analyzer_parameter_mappings m 
     JOIN public.analyzers an ON an.id = m.analyzer_id 
     WHERE m.test_id = t.id) AS analyzer_mappings
  FROM public.tests t
  WHERE t.code IN (
    'END-0039', 'END-0010',
    'END-0031', 'END-0007',
    'END-0028', 'END-0008',
    'END-0027', 'END-0009',
    'END-0025', 'END-0006',
    'END-0037', 'END-0036',
    'IMM-0031',
    'TUM-0007', 'TUM-0004',
    'IMM-0003', 'IMM-0002'
  )
  ORDER BY t.code
)
SELECT json_agg(row_to_json(target_tests.*)) AS rows FROM target_tests;
`;

async function main() {
  const tmpFile = path.resolve('tmp_reconcile_10.sql');
  writeFileSync(tmpFile, sql, 'utf8');

  try {
    const raw = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: true,
      maxBuffer: 50 * 1024 * 1024,
    });
    const jsonStart = raw.indexOf('[');
    const jsonStartObj = raw.indexOf('{');
    const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
    const parsed = JSON.parse(raw.slice(start));
    const rows = Array.isArray(parsed) ? parsed[0]?.rows : parsed.rows?.[0]?.rows;
    writeFileSync('scripts/reconcile_10_output.json', JSON.stringify(rows, null, 2), 'utf8');
    console.log(`Fetched ${rows.length} test records successfully!`);
    console.log(JSON.stringify(rows, null, 2));
  } catch (err) {
    console.error('Error:', err.message, err.stderr);
    process.exit(1);
  } finally {
    try { unlinkSync(tmpFile); } catch {}
  }
}

main();
