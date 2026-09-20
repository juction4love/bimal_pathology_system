import { execSync } from 'node:child_process';
import fs from 'node:fs';

const query = `
SELECT json_build_object(
  'analyzers', (SELECT json_agg(a) FROM public.analyzers a),
  'mapping_counts_by_analyzer', (
    SELECT json_object_agg(COALESCE(a.name, 'Unknown'), cnt)
    FROM (
      SELECT analyzer_id, count(*) as cnt
      FROM public.analyzer_parameter_mappings
      GROUP BY analyzer_id
    ) m
    JOIN public.analyzers a ON a.id = m.analyzer_id
  ),
  'tests_with_mappings_count', (
    SELECT count(DISTINCT test_id) FROM public.analyzer_parameter_mappings
  ),
  'distinct_tests_count', (
    SELECT count(*) FROM public.tests
  ),
  'active_tests_count', (
    SELECT count(*) FROM public.tests WHERE is_active = TRUE
  )
) as info;
`;

fs.writeFileSync('scratch/temp_audit_analyzers.sql', query);
try {
  const raw = execSync('npx supabase db query --linked --output json -f scratch/temp_audit_analyzers.sql', { encoding: 'utf8', shell: true });
  console.log(raw);
} finally {
  if (fs.existsSync('scratch/temp_audit_analyzers.sql')) {
    fs.unlinkSync('scratch/temp_audit_analyzers.sql');
  }
}
