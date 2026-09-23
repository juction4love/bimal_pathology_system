import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const sqlQuery = `
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
        'code', p.code,
        'name', p.name,
        'unit', p.unit,
        'value_type', p.value_type::text,
        'display_order', p.display_order,
        'lifecycle_status', p.lifecycle_status,
        'is_active', p.is_active
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
)
SELECT 
  t.id AS test_id,
  t.code AS test_code,
  t.name AS test_name,
  t.category AS category,
  t.department AS department,
  t.test_type AS test_type,
  t.reporting_model AS reporting_model,
  t.workflow_type AS workflow_type,
  t.clinical_reporting_enabled AS clinical_reporting_enabled,
  COALESCE(tdp.direct_active_param_count, 0) AS direct_param_count,
  COALESCE(pc.component_count, 0) AS component_count,
  tdp.direct_params AS direct_params,
  pc.components AS components
FROM public.tests t
LEFT JOIN test_direct_params tdp ON tdp.test_id = t.id
LEFT JOIN panel_comps pc ON pc.panel_id = t.id
WHERE t.is_active = TRUE
ORDER BY t.code;
`;

const tmp = path.resolve('tmp_live_catalogue_audit.sql');
fs.writeFileSync(tmp, sqlQuery, 'utf8');

try {
  console.log('Querying live database for 1139 active tests...');
  const raw = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8', maxBuffer: 50 * 1024 * 1024 });
  const jsonStart = raw.indexOf('{');
  const jsonEnd = raw.lastIndexOf('}');
  const data = JSON.parse(raw.slice(jsonStart, jsonEnd + 1));
  const rows = data.rows || [];

  console.log(`Successfully fetched ${rows.length} active tests from DB.`);

  const outputDir = path.resolve('scripts/output');
  if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir, { recursive: true });

  const missing = [];
  const profileRows = [];
  const singleRows = [];
  const multiRows = [];

  for (const r of rows) {
    const directCount = parseInt(r.direct_param_count, 10) || 0;
    const compCount = parseInt(r.component_count, 10) || 0;
    const isProfile = compCount > 0 || (r.test_type && r.test_type.toLowerCase() === 'profile') || (r.code && r.code.startsWith('PRO-'));

    if (directCount === 0 && compCount === 0) {
      missing.push({
        test_code: r.test_code,
        test_name: r.test_name,
        category: r.category,
        department: r.department,
        test_type: r.test_type,
        reporting_model: r.reporting_model || 'UNRESOLVED',
        current_parameter_count: directCount,
        current_child_component_count: compCount,
        expected_result_structure: isProfile ? 'PROFILE_COMPONENTS' : 'SINGLE_OR_MULTI_ANALYTE',
        missing_structure: isProfile ? 'MISSING_PANEL_COMPONENTS' : 'MISSING_REPORTABLE_PARAMETERS'
      });
    } else if (compCount > 0) {
      profileRows.push(r);
    } else if (directCount === 1) {
      singleRows.push(r);
    } else {
      multiRows.push(r);
    }
  }

  console.log(`Breakdown:
  - Tests with direct parameters only: ${singleRows.length + multiRows.length} (Single: ${singleRows.length}, Multi: ${multiRows.length})
  - Tests with panel components: ${profileRows.length}
  - Unresolved tests (0 params & 0 components): ${missing.length}`);

  function csvEscape(val) {
    if (val === null || val === undefined) return '""';
    const str = String(val);
    if (str.includes(',') || str.includes('"') || str.includes('\n')) {
      return `"${str.replace(/"/g, '""')}"`;
    }
    return `"${str}"`;
  }

  const headers = [
    'test_code',
    'test_name',
    'category',
    'department',
    'test_type',
    'reporting_model',
    'current_parameter_count',
    'current_child_component_count',
    'expected_result_structure',
    'missing_structure'
  ];

  fs.writeFileSync(
    path.join(outputDir, 'catalogue_missing_parameters_before.csv'),
    [
      headers.map(csvEscape).join(','),
      ...missing.map(r => headers.map(h => csvEscape(r[h])).join(','))
    ].join('\n'),
    'utf8'
  );

  console.log('Saved scripts/output/catalogue_missing_parameters_before.csv');
  console.log('Missing tests list:');
  for (const m of missing) {
    console.log(`  [${m.test_code}] ${m.test_name} (${m.category}) -> ${m.missing_structure}`);
  }

  fs.writeFileSync(
    path.resolve('scripts/output/full_active_catalogue_audit.json'),
    JSON.stringify(rows, null, 2),
    'utf8'
  );
  console.log('Saved scripts/output/full_active_catalogue_audit.json');

} finally {
  try { fs.unlinkSync(tmp); } catch {}
}
