import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const outputDir = path.resolve('scripts/output');
if (!existsSync(outputDir)) mkdirSync(outputDir, { recursive: true });

console.log('Fetching live database schema objects & master data...');

const m135 = readFileSync(path.resolve('supabase/migrations_legacy_archive/00135_complete_master_catalogue.sql'), 'utf8')
  .replace(/^BEGIN;/m, '')
  .replace(/^COMMIT;/m, '');

// Query full master data
const queryMasterSql = `
BEGIN;

-- Include 00135 in transaction to ensure final catalogue state is captured
${m135}

SELECT jsonb_build_object(
  'test_categories', (
    SELECT jsonb_agg(row_to_json(tc.*)) FROM public.test_categories tc
  ),
  'tests', (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', id, 'code', code, 'name', name, 'short_name', short_name,
        'department', department, 'category', category, 'category_id', category_id,
        'reporting_type', reporting_type::text, 'outsource_lab_name', outsource_lab_name,
        'price_paisa', price_paisa, 'sample_type', sample_type, 'container', container,
        'method', method, 'tat_hours', tat_hours, 'interpretation_template', interpretation_template,
        'is_active', is_active, 'display_order', display_order,
        'test_type', test_type, 'workflow_type', workflow_type,
        'reporting_model', reporting_model, 'clinical_reporting_enabled', clinical_reporting_enabled,
        'billing_enabled', billing_enabled, 'price_configured', price_configured,
        'pricing_policy', pricing_policy, 'lifecycle_status', lifecycle_status
      ) ORDER BY code
    ) FROM public.tests WHERE is_active = TRUE
  ),
  'parameters', (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', p.id, 'test_id', p.test_id, 'test_code', t.code, 'code', p.code, 'name', p.name,
        'value_type', p.value_type::text, 'unit', p.unit, 'options', p.options,
        'formula', p.formula, 'formula_dependencies', p.formula_dependencies,
        'calculation_identifier', p.calculation_identifier,
        'display_order', p.display_order, 'is_mandatory', p.is_mandatory,
        'is_active', p.is_active, 'lifecycle_status', p.lifecycle_status,
        'clinical_configuration_status', p.clinical_configuration_status,
        'interpretation_config', p.interpretation_config
      ) ORDER BY t.code, p.display_order
    ) FROM public.parameters p
    JOIN public.tests t ON p.test_id = t.id
    WHERE p.is_active = TRUE 
      AND (p.lifecycle_status IS NULL OR p.lifecycle_status = 'Active')
      AND LOWER(COALESCE(p.unit, '')) <> 'panel'
      AND LOWER(COALESCE(p.value_type::text, '')) NOT IN ('panel', 'profile')
  ),
  'reference_ranges', (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', rr.id, 'parameter_id', rr.parameter_id, 'test_code', t.code, 'parameter_code', p.code,
        'gender', rr.gender, 'age_min_days', rr.age_min_days, 'age_max_days', rr.age_max_days,
        'normal_min', rr.normal_min, 'normal_max', rr.normal_max,
        'critical_low', rr.critical_low, 'critical_high', rr.critical_high,
        'normal_text', rr.normal_text, 'unit', rr.unit
      ) ORDER BY t.code, p.display_order, rr.gender, rr.age_min_days
    ) FROM public.reference_ranges rr
    JOIN public.parameters p ON rr.parameter_id = p.id
    JOIN public.tests t ON p.test_id = t.id
    WHERE p.is_active = TRUE
  ),
  'catalogue_panel_components', (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', cpc.id,
        'panel_test_id', COALESCE(cpc.panel_test_id, cpc.panel_id),
        'panel_test_code', pt.code,
        'component_test_id', cpc.component_test_id,
        'component_test_code', ct.code,
        'component_parameter_id', cpc.component_parameter_id,
        'component_parameter_code', cp.code,
        'display_order', cpc.display_order,
        'is_required', cpc.is_required,
        'component_role', cpc.component_role
      ) ORDER BY pt.code, cpc.display_order
    ) FROM public.catalogue_panel_components cpc
    JOIN public.tests pt ON pt.id = COALESCE(cpc.panel_test_id, cpc.panel_id)
    LEFT JOIN public.tests ct ON ct.id = cpc.component_test_id
    LEFT JOIN public.parameters cp ON cp.id = cpc.component_parameter_id
    WHERE pt.is_active = TRUE
  ),
  'analyzers', (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', id, 'code', code, 'name', name, 'manufacturer', manufacturer,
        'model', model, 'laboratory_location', laboratory_location,
        'lifecycle_status', lifecycle_status, 'row_version', row_version
      ) ORDER BY code
    ) FROM public.analyzers
  ),
  'analyzer_parameter_mappings', (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', apm.id, 'analyzer_code', a.code, 'channel_code', apm.channel_code,
        'channel_name', apm.channel_name, 'test_code', t.code, 'parameter_code', p.code,
        'measurement_type', apm.measurement_type, 'analytical_method', apm.analytical_method,
        'unit', apm.unit, 'differential_type', apm.differential_type,
        'is_automated_5part_supported', apm.is_automated_5part_supported
      ) ORDER BY a.code, apm.channel_code
    ) FROM public.analyzer_parameter_mappings apm
    JOIN public.analyzers a ON a.id = apm.analyzer_id
    LEFT JOIN public.tests t ON t.id = apm.test_id
    LEFT JOIN public.parameters p ON p.id = apm.parameter_id
  ),
  'catalogue_rate_versions', (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', rv.id, 'entity_type', rv.entity_type::text,
        'test_code', t.code, 'version_number', rv.version_number,
        'price_paisa', rv.price_paisa, 'effective_from', rv.effective_from,
        'effective_to', rv.effective_to, 'status', rv.status
      ) ORDER BY t.code, rv.version_number
    ) FROM public.catalogue_rate_versions rv
    JOIN public.tests t ON t.id = rv.test_id
    WHERE rv.status = 'Active' AND (rv.effective_to IS NULL OR rv.effective_to > NOW())
  ),
  'roles', (
    SELECT jsonb_agg(row_to_json(r.*)) FROM public.roles r
  ),
  'role_permissions', (
    SELECT jsonb_agg(row_to_json(rp.*)) FROM public.role_permissions rp
  ),
  'referring_doctors', (
    SELECT jsonb_agg(row_to_json(rd.*)) FROM public.referring_doctors rd
  ),
  'reporting_personnel', (
    SELECT jsonb_agg(row_to_json(rp.*)) FROM public.reporting_personnel rp
  ),
  'catalogue_calculation_definitions', (
    SELECT jsonb_agg(row_to_json(ccd.*)) FROM public.catalogue_calculation_definitions ccd
  ),
  'pt_inr_reagent_configs', (
    SELECT jsonb_agg(row_to_json(pt.*)) FROM public.pt_inr_reagent_configs pt
  ),
  'ast_antibiotics', (
    SELECT jsonb_agg(row_to_json(aa.*)) FROM public.ast_antibiotics aa
  ),
  'ast_microorganisms', (
    SELECT jsonb_agg(row_to_json(am.*)) FROM public.ast_microorganisms am
  ),
  'ast_breakpoint_sets', (
    SELECT jsonb_agg(row_to_json(abs.*)) FROM public.ast_breakpoint_sets abs
  ),
  'ast_breakpoint_rules', (
    SELECT jsonb_agg(row_to_json(abr.*)) FROM public.ast_breakpoint_rules abr
  )
) AS master_payload;

ROLLBACK;
`;

const tmp = path.resolve('tmp_query_master_data.sql');
writeFileSync(tmp, queryMasterSql, 'utf8');

const raw = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8', maxBuffer: 100 * 1024 * 1024 });
const jsonStart = raw.indexOf('{');
const jsonEnd = raw.lastIndexOf('}');
const parsed = JSON.parse(raw.slice(jsonStart, jsonEnd + 1));
const payload = (parsed.rows || [])[0]?.master_payload;

if (!payload) {
  throw new Error('Failed to retrieve master payload from database.');
}

console.log(`Extracted:
  - Test Categories: ${payload.test_categories?.length || 0}
  - Tests: ${payload.tests?.length || 0}
  - Parameters: ${payload.parameters?.length || 0}
  - Reference Ranges: ${payload.reference_ranges?.length || 0}
  - Panel Components: ${payload.catalogue_panel_components?.length || 0}
  - Analyzers: ${payload.analyzers?.length || 0}
  - Analyzer Mappings: ${payload.analyzer_parameter_mappings?.length || 0}
  - Active Rate Versions: ${payload.catalogue_rate_versions?.length || 0}
`);

writeFileSync(path.join(outputDir, 'extracted_master_payload.json'), JSON.stringify(payload, null, 2), 'utf8');
console.log('Saved scripts/output/extracted_master_payload.json');
