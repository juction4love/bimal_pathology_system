import { execSync } from 'node:child_process';
import fs from 'node:fs';

const sql = `
SELECT json_build_object(
  'cpc_rows', (
    SELECT json_agg(json_build_object(
      'id', cpc.id,
      'panel_id', cpc.panel_id,
      'panel_test_id', cpc.panel_test_id,
      'panel_code', pt.code,
      'panel_name', pt.name,
      'component_test_id', cpc.component_test_id,
      'child_code', ct.code,
      'child_name', ct.name,
      'display_order', cpc.display_order
    ))
    FROM public.catalogue_panel_components cpc
    LEFT JOIN public.tests pt ON pt.id = coalesce(cpc.panel_test_id, cpc.panel_id)
    LEFT JOIN public.tests ct ON ct.id = cpc.component_test_id
    WHERE pt.code IN ('PRO-0026','PRO-0027','PRO-0028','PRO-0029','PRO-0030','PRO-0031','PRO-0032','PRO-0033')
  )
) as cpc_summary;
`;

const tmpFile = 'tmp_cpc_check.sql';
fs.writeFileSync(tmpFile, sql, 'utf8');

try {
  const out = execSync(`npx supabase db query --linked --output json -f ${tmpFile}`, {
    encoding: 'utf8',
    shell: true,
    maxBuffer: 20 * 1024 * 1024
  });
  const raw = JSON.parse(out);
  const rows = Array.isArray(raw) ? raw : (raw.rows || []);
  console.log(JSON.stringify(rows[0]?.cpc_summary, null, 2));
} finally {
  if (fs.existsSync(tmpFile)) fs.unlinkSync(tmpFile);
}
