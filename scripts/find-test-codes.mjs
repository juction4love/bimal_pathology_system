// scripts/find-test-codes.mjs
import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

function runSql(sql) {
  const tmp = path.resolve('tmp_find_codes.sql');
  writeFileSync(tmp, sql, 'utf8');
  try {
    const out = execSync(`npx supabase db query --linked -f "${tmp}"`, {
      encoding: 'utf8',
      shell: true,
      maxBuffer: 20 * 1024 * 1024
    });
    const jsonStart = out.indexOf('{');
    if (jsonStart === -1) return null;
    return JSON.parse(out.slice(jsonStart));
  } finally {
    try { unlinkSync(tmp); } catch {}
  }
}

const sql = `
  SELECT json_agg(t) as rows
  FROM (
    SELECT code, name, department, report_data_type, price_paisa
    FROM public.tests
    WHERE name ILIKE '%glucose%'
       OR name ILIKE '%hemoglobin%'
       OR name ILIKE '%complete blood count%'
       OR name ILIKE '%platelet%'
       OR name ILIKE '%esr%'
       OR name ILIKE '%erythrocyte sedimentation%'
       OR name ILIKE '%peripheral blood smear%'
       OR name ILIKE '%smear%'
       OR name ILIKE '%urea%'
       OR name ILIKE '%creatinine%'
       OR name ILIKE '%uric acid%'
       OR name ILIKE '%sodium%'
       OR name ILIKE '%potassium%'
       OR name ILIKE '%calcium%'
       OR name ILIKE '%phosphorus%'
       OR name ILIKE '%amylase%'
       OR name ILIKE '%lipase%'
       OR name ILIKE '%liver function%'
       OR name ILIKE '%lipid%'
       OR name ILIKE '%tsh%'
       OR name ILIKE '%thyroid stimulating%'
       OR name ILIKE '%free t3%'
       OR name ILIKE '%free t4%'
       OR name ILIKE '%prothrombin%'
       OR name ILIKE '%inr%'
       OR name ILIKE '%aptt%'
       OR name ILIKE '%urine routine%'
       OR name ILIKE '%stool routine%'
       OR name ILIKE '%hbsag%'
       OR name ILIKE '%hcv%'
       OR name ILIKE '%hiv%'
       OR name ILIKE '%dengue%'
       OR name ILIKE '%c-reactive%'
       OR name ILIKE '%rheumatoid factor%'
       OR name ILIKE '%crp%'
    ORDER BY code
  ) t;
`;

const res = runSql(sql);
const rows = res?.rows?.[0]?.rows || res?.[0]?.rows || [];
console.log(`Found ${rows.length} matching candidate tests:`);
for (const r of rows) {
  console.log(`${r.code.padEnd(12)} | ${r.department.padEnd(25)} | ${r.report_data_type.padEnd(18)} | ${r.name}`);
}
