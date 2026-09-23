import { execSync } from 'node:child_process';
import fs from 'node:fs';

const sql = `
SELECT 
  rr.id,
  t.code AS test_code,
  t.name AS test_name,
  p.code AS param_code,
  p.name AS param_name,
  rr.gender,
  rr.age_min_days,
  rr.age_max_days,
  rr.normal_min,
  rr.normal_max,
  rr.normal_text,
  rr.critical_low,
  rr.critical_high,
  rr.unit,
  rr.method,
  rr.is_active,
  rr.is_approved,
  rr.validation_state,
  rr.validation_source
FROM public.reference_ranges rr
JOIN public.parameters p ON p.id = rr.parameter_id
JOIN public.tests t ON t.id = p.test_id
ORDER BY t.code, p.code, rr.gender, rr.age_min_days;
`;

fs.writeFileSync('tmp_q10_ref_ranges_fixed.sql', sql, 'utf8');
const res = execSync('npx supabase db query --linked -f tmp_q10_ref_ranges_fixed.sql', { encoding: 'utf8', maxBuffer: 50 * 1024 * 1024 });
fs.writeFileSync('scripts/output/live_reference_ranges.json', res, 'utf8');
const parsed = JSON.parse(res.slice(res.indexOf('{'), res.lastIndexOf('}') + 1));
console.log(`Live reference ranges count: ${parsed.rows.length}`);
