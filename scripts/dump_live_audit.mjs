import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

if (!fs.existsSync('scripts/output')) {
  fs.mkdirSync('scripts/output', { recursive: true });
}

const sql = `
SELECT jsonb_build_object(
  'tests', (
    SELECT jsonb_agg(jsonb_build_object(
      'id', t.id,
      'code', t.code,
      'name', t.name,
      'category', t.category,
      'department', t.department,
      'is_active', t.is_active
    ) ORDER BY t.code)
    FROM public.tests t
  ),
  'parameters', (
    SELECT jsonb_agg(jsonb_build_object(
      'id', p.id,
      'test_id', p.test_id,
      'test_code', t.code,
      'code', p.code,
      'name', p.name,
      'unit', p.unit,
      'value_type', p.value_type::text,
      'is_active', p.is_active,
      'display_order', p.display_order
    ) ORDER BY t.code, p.display_order, p.code)
    FROM public.parameters p
    LEFT JOIN public.tests t ON t.id = p.test_id
  ),
  'panel_components', (
    SELECT jsonb_agg(jsonb_build_object(
      'id', cpc.id,
      'panel_id', COALESCE(cpc.panel_test_id, cpc.panel_id),
      'panel_code', pt.code,
      'panel_name', pt.name,
      'component_test_id', cpc.component_test_id,
      'component_test_code', ct.code,
      'component_test_name', ct.name,
      'component_parameter_id', cpc.component_parameter_id,
      'component_parameter_code', cp.code,
      'component_parameter_name', cp.name,
      'display_order', cpc.display_order
    ) ORDER BY pt.code, cpc.display_order)
    FROM public.catalogue_panel_components cpc
    LEFT JOIN public.tests pt ON pt.id = COALESCE(cpc.panel_test_id, cpc.panel_id)
    LEFT JOIN public.tests ct ON ct.id = cpc.component_test_id
    LEFT JOIN public.parameters cp ON cp.id = cpc.component_parameter_id
  ),
  'reference_ranges', (
    SELECT jsonb_agg(jsonb_build_object(
      'id', rr.id,
      'test_code', t.code,
      'test_name', t.name,
      'parameter_code', p.code,
      'parameter_name', p.name,
      'gender', rr.gender,
      'age_min_days', rr.age_min_days,
      'age_max_days', rr.age_max_days,
      'normal_min', rr.normal_min,
      'normal_max', rr.normal_max,
      'normal_text', rr.normal_text,
      'critical_low', rr.critical_low,
      'critical_high', rr.critical_high,
      'unit', rr.unit,
      'method', rr.method,
      'is_active', rr.is_active,
      'is_approved', rr.is_approved
    ) ORDER BY t.code, p.code, rr.gender, rr.age_min_days)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
  ),
  'analyzers', (
    SELECT jsonb_agg(jsonb_build_object(
      'id', a.id,
      'code', a.code,
      'name', a.name,
      'manufacturer', a.manufacturer,
      'model', a.model,
      'lifecycle_status', a.lifecycle_status,
      'laboratory_location', a.laboratory_location
    ) ORDER BY a.code)
    FROM public.analyzers a
  ),
  'analyzer_mappings', (
    SELECT jsonb_agg(jsonb_build_object(
      'id', apm.id,
      'analyzer_code', a.code,
      'analyzer_name', a.name,
      'test_code', t.code,
      'test_name', t.name,
      'parameter_code', p.code,
      'parameter_name', p.name,
      'channel_code', apm.channel_code,
      'channel_name', apm.channel_name,
      'measurement_type', apm.measurement_type,
      'analytical_method', apm.analytical_method,
      'unit', apm.unit
    ) ORDER BY a.code, apm.channel_code)
    FROM public.analyzer_parameter_mappings apm
    JOIN public.analyzers a ON a.id = apm.analyzer_id
    LEFT JOIN public.tests t ON t.id = apm.test_id
    LEFT JOIN public.parameters p ON p.id = apm.parameter_id
  ),
  'rates', (
    SELECT jsonb_agg(jsonb_build_object(
      'id', crv.id,
      'test_id', crv.test_id,
      'test_code', t.code,
      'test_name', t.name,
      'price_paisa', crv.price_paisa,
      'status', crv.status
    ) ORDER BY t.code)
    FROM public.catalogue_rate_versions crv
    LEFT JOIN public.tests t ON t.id = crv.test_id
    WHERE crv.status = 'Active'
  )
) AS live_data;
`;

fs.writeFileSync('tmp_full_live_dump.sql', sql, 'utf8');
console.log('Querying full live catalogue master data from linked DB...');
const res = execSync('npx supabase db query --linked -f tmp_full_live_dump.sql', { encoding: 'utf8', maxBuffer: 100 * 1024 * 1024 });

const jsonStart = res.indexOf('{');
const jsonEnd = res.lastIndexOf('}');
const parsed = JSON.parse(res.slice(jsonStart, jsonEnd + 1));
const liveData = parsed.rows[0].live_data;

fs.writeFileSync('scripts/output/live_audit_dump.json', JSON.stringify(liveData, null, 2), 'utf8');

console.log('--- LIVE AUDIT SUMMARY ---');
console.log(`Active Tests: ${liveData.tests.filter(t => t.is_active).length}`);
console.log(`Active Parameters: ${liveData.parameters.filter(p => p.is_active).length}`);
console.log(`Panel Components: ${liveData.panel_components?.length || 0}`);
console.log(`Reference Ranges (Total): ${liveData.reference_ranges?.length || 0}`);
console.log(`Reference Ranges (Active): ${liveData.reference_ranges?.filter(r => r.is_active).length || 0}`);
console.log(`Analyzers: ${liveData.analyzers?.length || 0}`);
console.log(`Analyzer Mappings: ${liveData.analyzer_mappings?.length || 0}`);
console.log(`Active Rates: ${liveData.rates?.length || 0}`);
