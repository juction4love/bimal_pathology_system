import { execSync } from 'node:child_process';
import fs from 'node:fs';

const sql = `
SELECT 
  apm.id,
  a.code AS analyzer_code,
  a.name AS analyzer_name,
  t.code AS test_code,
  t.name AS test_name,
  p.code AS param_code,
  p.name AS param_name,
  apm.channel_code,
  apm.channel_name,
  apm.measurement_type,
  apm.analytical_method,
  apm.unit,
  apm.differential_type,
  apm.is_automated_5part_supported
FROM public.analyzer_parameter_mappings apm
JOIN public.analyzers a ON a.id = apm.analyzer_id
LEFT JOIN public.tests t ON t.id = apm.test_id
LEFT JOIN public.parameters p ON p.id = apm.parameter_id
ORDER BY a.code, apm.channel_code;
`;

fs.writeFileSync('tmp_q3_mappings.sql', sql, 'utf8');
const res = execSync('npx supabase db query --linked -f tmp_q3_mappings.sql', { encoding: 'utf8' });
console.log(res);
