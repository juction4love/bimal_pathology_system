import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const sqlScript = `
SELECT json_build_object(
    'patients', (SELECT count(*) FROM public.patients),
    'bills', (SELECT count(*) FROM public.bills),
    'clinical_orders', (SELECT count(*) FROM public.clinical_orders),
    'clinical_order_items', (SELECT count(*) FROM public.clinical_order_items),
    'test_results', (SELECT count(*) FROM public.test_results),
    'diagnostic_reports', (SELECT count(*) FROM public.diagnostic_reports),
    'payments', (
        SELECT count(*) 
        FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name LIKE '%pay%'
    )
) as counts;
`;

const tmpFile = path.resolve('tmp_db_empty_check.sql');
writeFileSync(tmpFile, sqlScript, 'utf8');

try {
  const output = execSync(`npx supabase db query --linked -f "${tmpFile}"`, {
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
    shell: true,
    maxBuffer: 20 * 1024 * 1024,
  });
  const jsonStart = output.indexOf('{');
  if (jsonStart !== -1) {
    const parsed = JSON.parse(output.slice(jsonStart));
    console.log('Database Row Counts:', JSON.stringify(parsed.rows?.[0]?.counts, null, 2));
  } else {
    console.log(output);
  }
} catch (e) {
  console.error(e.message);
} finally {
  try { unlinkSync(tmpFile); } catch {}
}
