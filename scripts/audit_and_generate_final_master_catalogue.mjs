// scripts/audit_and_generate_final_master_catalogue.mjs
// Comprehensive Master Catalogue Rebuild & Audit across all 1,139 tests

import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const outputDir = path.resolve('scripts/output');
if (!existsSync(outputDir)) mkdirSync(outputDir, { recursive: true });

function csvEscape(val) {
  if (val === null || val === undefined) return '""';
  const str = String(val);
  if (str.includes(',') || str.includes('"') || str.includes('\n') || str.includes('\r')) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return `"${str}"`;
}

function writeCsv(filePath, headers, rows) {
  const content = [
    headers.map(csvEscape).join(','),
    ...rows.map(r => headers.map(h => csvEscape(r[h])).join(','))
  ].join('\n');
  writeFileSync(filePath, content, 'utf8');
  console.log(`Saved ${filePath} (${rows.length} rows)`);
}

// 1. Audit Live DB Before Migration 00135
const auditSql = `
WITH test_direct_params AS (
  SELECT 
    p.test_id,
    COUNT(p.id) FILTER (
      WHERE p.is_active = TRUE 
        AND (p.lifecycle_status IS NULL OR p.lifecycle_status = 'Active')
        AND LOWER(COALESCE(p.unit, '')) <> 'panel'
        AND LOWER(COALESCE(p.value_type::text, '')) NOT IN ('panel', 'profile')
    ) AS direct_active_param_count,
    jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'code', p.code,
        'name', p.name,
        'unit', p.unit,
        'value_type', p.value_type::text,
        'display_order', p.display_order,
        'is_mandatory', p.is_mandatory,
        'lifecycle_status', p.lifecycle_status,
        'is_active', p.is_active,
        'formula', p.formula,
        'options', p.options
      ) ORDER BY p.display_order
    ) FILTER (
      WHERE p.is_active = TRUE 
        AND (p.lifecycle_status IS NULL OR p.lifecycle_status = 'Active')
        AND LOWER(COALESCE(p.unit, '')) <> 'panel'
        AND LOWER(COALESCE(p.value_type::text, '')) NOT IN ('panel', 'profile')
    ) AS direct_params
  FROM public.parameters p
  GROUP BY p.test_id
),
panel_comps AS (
  SELECT 
    COALESCE(cpc.panel_test_id, cpc.panel_id) AS panel_id,
    COUNT(cpc.id) AS component_count,
    jsonb_agg(
      jsonb_build_object(
        'component_test_id', cpc.component_test_id,
        'component_parameter_id', cpc.component_parameter_id,
        'display_order', cpc.display_order,
        'is_required', cpc.is_required,
        'component_role', cpc.component_role
      ) ORDER BY cpc.display_order
    ) AS components
  FROM public.catalogue_panel_components cpc
  GROUP BY COALESCE(cpc.panel_test_id, cpc.panel_id)
),
active_rates AS (
  SELECT 
    COALESCE(rv.test_id, rv.panel_service_id, rv.package_id) AS entity_id,
    rv.price_paisa,
    rv.status AS rate_status,
    rv.effective_from,
    rv.effective_to,
    rv.version_number
  FROM public.catalogue_rate_versions rv
  WHERE rv.status = 'Active'
    AND (rv.effective_to IS NULL OR rv.effective_to > NOW())
),
analyzer_maps AS (
  SELECT 
    am.test_id,
    COUNT(am.id) AS mapping_count
  FROM public.analyzer_parameter_mappings am
  WHERE am.test_id IS NOT NULL
  GROUP BY am.test_id
),
ref_ranges AS (
  SELECT 
    p.test_id,
    COUNT(rr.id) AS ref_count
  FROM public.reference_ranges rr
  JOIN public.parameters p ON rr.parameter_id = p.id
  GROUP BY p.test_id
)
SELECT jsonb_build_object(
  'tests', jsonb_agg(
    jsonb_build_object(
      'test_id', t.id,
      'test_code', t.code,
      'test_name', t.name,
      'category', t.category,
      'department', t.department,
      'test_type', t.test_type,
      'reporting_model', t.reporting_model,
      'workflow_type', t.workflow_type,
      'clinical_reporting_enabled', t.clinical_reporting_enabled,
      'billing_enabled', t.billing_enabled,
      'method', t.method,
      'sample_type', t.sample_type,
      'container', t.container,
      'tat_hours', t.tat_hours,
      'direct_param_count', COALESCE(tdp.direct_active_param_count, 0),
      'component_count', COALESCE(pc.component_count, 0),
      'direct_params', tdp.direct_params,
      'components', pc.components,
      'active_price_paisa', ar.price_paisa,
      'legacy_price_paisa', t.price_paisa,
      'rate_status', ar.rate_status,
      'rate_effective_from', ar.effective_from,
      'rate_effective_to', ar.effective_to,
      'analyzer_mapping_count', COALESCE(am.mapping_count, 0),
      'ref_range_count', COALESCE(rr.ref_count, 0)
    ) ORDER BY t.code
  )
) AS audit_data
FROM public.tests t
LEFT JOIN test_direct_params tdp ON tdp.test_id = t.id
LEFT JOIN panel_comps pc ON pc.panel_id = t.id
LEFT JOIN active_rates ar ON ar.entity_id = t.id
LEFT JOIN analyzer_maps am ON am.test_id = t.id
LEFT JOIN ref_ranges rr ON rr.test_id = t.id
WHERE t.is_active = TRUE;
`;

const tmpFile = path.resolve('tmp_audit_query.sql');
writeFileSync(tmpFile, auditSql, 'utf8');

console.log('Querying live linked database...');
const rawOut = execSync(`npx supabase db query --linked -f "${tmpFile}"`, { encoding: 'utf8', maxBuffer: 50 * 1024 * 1024 });
const jsonStart = rawOut.indexOf('{');
const jsonEnd = rawOut.lastIndexOf('}');
const parsed = JSON.parse(rawOut.slice(jsonStart, jsonEnd + 1));
const tests = (parsed.rows || [])[0]?.audit_data?.tests || [];

console.log(`Retrieved ${tests.length} active tests from live database.`);

// Map of tests
const testsById = new Map(tests.map(t => [t.test_id, t]));
const testsByCode = new Map(tests.map(t => [t.test_code, t]));

function resolveLeafCount(t) {
  if (t.direct_param_count > 0) return t.direct_param_count;
  if (t.components && t.components.length > 0) {
    let sum = 0;
    for (const c of t.components) {
      if (c.component_parameter_id) sum += 1;
      else if (c.component_test_id) {
        const child = testsById.get(c.component_test_id);
        sum += (child?.direct_param_count || 0);
      }
    }
    return sum;
  }
  return 0;
}

// 2. Generate final_master_catalogue_before.csv
const beforeRows = tests.map(t => {
  const leafCount = resolveLeafCount(t);
  const pricePaisa = t.active_price_paisa ?? t.legacy_price_paisa;
  const hasRate = pricePaisa !== null && pricePaisa !== undefined && Number(pricePaisa) > 0;
  
  return {
    test_id: t.test_id,
    test_code: t.test_code,
    test_name: t.test_name,
    category: t.category,
    clinical_domain: t.department || t.category,
    workflow_type: t.workflow_type || 'Standard',
    is_active: t.is_active ? 'TRUE' : 'FALSE',
    billing_enabled: t.billing_enabled ? 'TRUE' : 'FALSE',
    clinical_reporting_enabled: t.clinical_reporting_enabled ? 'TRUE' : 'FALSE',
    direct_parameter_count: t.direct_param_count,
    resolved_leaf_parameter_count: leafCount,
    component_count: t.component_count,
    method: t.method || 'METHOD_PENDING',
    specimen: t.sample_type || 'SPECIMEN_PENDING',
    configured_source: t.analyzer_mapping_count > 0 ? 'ANALYZER' : 'MANUAL',
    analyzer_mapping_count: t.analyzer_mapping_count,
    reference_rule_count: t.ref_range_count,
    qualitative_option_count: (t.direct_params || []).filter(p => Array.isArray(p.options) && p.options.length > 0).length,
    calculation_rule_count: (t.direct_params || []).filter(p => p.formula || p.value_type === 'Calculated').length,
    active_rate: hasRate ? (Number(pricePaisa) / 100).toFixed(2) : 'RATE_PENDING',
    rate_source: hasRate ? (t.active_price_paisa ? 'CATALOGUE_RATE_VERSIONS' : 'TESTS_PRICE_PAISA') : 'NONE',
    rate_effective_date: t.rate_effective_from || 'N/A',
    result_entry_supported: leafCount > 0 ? 'TRUE' : 'FALSE',
    verification_supported: leafCount > 0 ? 'TRUE' : 'FALSE',
    signoff_supported: leafCount > 0 ? 'TRUE' : 'FALSE',
    pdf_supported: leafCount > 0 ? 'TRUE' : 'FALSE'
  };
});

writeCsv(
  path.join(outputDir, 'final_master_catalogue_before.csv'),
  [
    'test_id', 'test_code', 'test_name', 'category', 'clinical_domain', 'workflow_type',
    'is_active', 'billing_enabled', 'clinical_reporting_enabled', 'direct_parameter_count',
    'resolved_leaf_parameter_count', 'component_count', 'method', 'specimen',
    'configured_source', 'analyzer_mapping_count', 'reference_rule_count',
    'qualitative_option_count', 'calculation_rule_count', 'active_rate', 'rate_source',
    'rate_effective_date', 'result_entry_supported', 'verification_supported',
    'signoff_supported', 'pdf_supported'
  ],
  beforeRows
);
