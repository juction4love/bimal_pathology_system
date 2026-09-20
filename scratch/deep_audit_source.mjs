import { execSync } from 'node:child_process';
import fs from 'node:fs';

const query = `
SELECT json_build_object(
  'all_mappings', (
    SELECT json_agg(json_build_object(
      'test_code', t.code,
      'test_name', t.name,
      'test_kind', t.test_kind,
      'param_code', p.code,
      'param_name', p.name,
      'param_value_type', p.value_type,
      'analyzer_code', a.code,
      'analyzer_name', a.name,
      'channel_code', m.channel_code,
      'channel_name', m.channel_name
    ))
    FROM public.analyzer_parameter_mappings m
    JOIN public.analyzers a ON a.id = m.analyzer_id
    JOIN public.tests t ON t.id = m.test_id
    LEFT JOIN public.parameters p ON p.id = m.parameter_id
  ),
  'tests_by_source_breakdown', (
    SELECT json_agg(json_build_object(
      'code', t.code,
      'name', t.name,
      'reporting_type', t.reporting_type,
      'test_kind', t.test_kind,
      'param_count', (SELECT count(*) FROM public.parameters WHERE test_id = t.id AND is_active = TRUE),
      'calc_count', (SELECT count(*) FROM public.parameters WHERE test_id = t.id AND is_active = TRUE AND value_type = 'Calculated'),
      'analyzer_mappings', (
        SELECT json_agg(DISTINCT a.code)
        FROM public.analyzer_parameter_mappings m
        JOIN public.analyzers a ON a.id = m.analyzer_id
        WHERE m.test_id = t.id
      )
    ))
    FROM public.tests t
    WHERE t.is_active = TRUE
  )
) as result;
`;

fs.writeFileSync('scratch/temp_deep_audit.sql', query);
try {
  const raw = execSync('npx supabase db query --linked --output json -f scratch/temp_deep_audit.sql', { encoding: 'utf8', shell: true, maxBuffer: 30 * 1024 * 1024 });
  const parsed = JSON.parse(raw);
  const data = parsed.rows?.[0]?.result || parsed[0]?.result;
  fs.writeFileSync('scratch/deep_audit_result.json', JSON.stringify(data, null, 2));
  console.log('Saved deep audit result. Total mappings:', data.all_mappings.length, 'Total active tests:', data.tests_by_source_breakdown.length);
} finally {
  if (fs.existsSync('scratch/temp_deep_audit.sql')) {
    fs.unlinkSync('scratch/temp_deep_audit.sql');
  }
}
