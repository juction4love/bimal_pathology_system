import { execSync } from 'node:child_process';
import fs from 'node:fs';

const query = `
SELECT json_build_object(
  'tests_cols', (
    SELECT json_agg(column_name) FROM information_schema.columns WHERE table_schema='public' AND table_name='tests'
  ),
  'parameters_cols', (
    SELECT json_agg(column_name) FROM information_schema.columns WHERE table_schema='public' AND table_name='parameters'
  ),
  'test_results_cols', (
    SELECT json_agg(column_name) FROM information_schema.columns WHERE table_schema='public' AND table_name='test_results'
  )
) as cols;
`;

fs.writeFileSync('scratch/temp_cols.sql', query);
try {
  const raw = execSync('npx supabase db query --linked --output json -f scratch/temp_cols.sql', { encoding: 'utf8', shell: true });
  console.log(raw);
} finally {
  if (fs.existsSync('scratch/temp_cols.sql')) fs.unlinkSync('scratch/temp_cols.sql');
}
