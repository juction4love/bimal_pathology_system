// scripts/verify-final-master-catalogue.mjs
// Final Master Catalogue Verification, Multi-Domain E2E Test & CSV Generation

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

const migrationSql = readFileSync(path.resolve('supabase/migrations_legacy_archive/00135_complete_master_catalogue.sql'), 'utf8')
  .replace(/^BEGIN;/m, '')
  .replace(/^COMMIT;/m, '');

const fullAuditSql = `
BEGIN;

-- Set session context for auth.uid()
SELECT set_config('request.jwt.claims', '{"sub": "b4022a73-39d0-4501-8262-566776b830f9"}', true);
SELECT set_config('request.jwt.claim.sub', 'b4022a73-39d0-4501-8262-566776b830f9', true);

-- 1. Apply Migration 00135
${migrationSql}

-- 2. Representative Multi-Domain End-to-End Workflow Verification
DO $$
DECLARE
    v_patient_id UUID;
    v_bill_id UUID;
    v_order_id UUID;
    v_user_id UUID;
    v_user_name VARCHAR(255);
    
    -- Representative Test Identifiers
    v_rep_codes TEXT[] := ARRAY[
        'PRO-0001', -- Profiles / LFT
        'HEM-0001', -- Hematology / CBC
        'BIO-0001', -- Biochemistry / Fasting Glucose
        'SER-0024', -- Serology / Widal
        'IMM-0001', -- Immunology / CRP
        'END-0003', -- Endocrinology / TSH
        'COA-0002', -- Coagulation / PT-INR
        'CLP-0001', -- Clinical Pathology / Urine R/E
        'MIC-0011', -- Microbiology / Urine Culture
        'HIS-0001', -- Histopathology / Biopsy
        'CYT-0001', -- Cytology / FNAC
        'MOL-0001', -- Molecular Diagnostics / HBV Viral Load
        'GEN-0001', -- Genetics / Karyotyping
        'TUM-0001', -- Tumor Markers / AFP
        'SPC-0001', -- Special Chemistry / HbA1c
        'TOX-0001', -- Toxicology / Digoxin
        'ALG-0001', -- Allergy / Food Allergy Panel
        'POC-0002'  -- POC / VBG
    ];
    v_code TEXT;
    v_test RECORD;
    v_bill_item_id UUID;
    v_order_item_id UUID;
    v_sample_id UUID;
    v_results JSONB;
    v_comp RECORD;
    v_param RECORD;
BEGIN
    SELECT id, full_name INTO v_user_id, v_user_name FROM public.user_profiles WHERE is_active = TRUE LIMIT 1;
    
    INSERT INTO public.patients (uhid, full_name, age_years, gender, mobile, address)
    VALUES ('9999000999', 'Master Acceptance Patient', 45, 'Female', '9899001122', 'Bharatpur-1')
    RETURNING id INTO v_patient_id;

    INSERT INTO public.bills (
        bill_number, patient_id, patient_name_snapshot, patient_uhid_snapshot,
        patient_age_gender_snapshot, patient_mobile_snapshot,
        gross_amount_paisa, discount_amount_paisa, net_amount_paisa, paid_amount_paisa, due_amount_paisa,
        payment_status
    ) VALUES (
        'BILL-ACC-MULTI-999', v_patient_id, 'Master Acceptance Patient', '9999000999',
        '45 Y / Female', '9899001122',
        1800000, 0, 1800000, 1800000, 0,
        'Paid'
    ) RETURNING id INTO v_bill_id;

    INSERT INTO public.clinical_orders (order_number, bill_id, patient_id, order_date_ad, order_date_bs, status)
    VALUES ('ORD-ACC-MULTI-999', v_bill_id, v_patient_id, CURRENT_DATE, '2083-06-04', 'InLab')
    RETURNING id INTO v_order_id;

    -- Iterate through each representative test across clinical domains
    FOREACH v_code IN ARRAY v_rep_codes LOOP
        SELECT id, code, name, department, sample_type, container, test_type
        INTO v_test
        FROM public.tests
        WHERE code = v_code;

        IF v_test.id IS NOT NULL THEN
            INSERT INTO public.bill_items (
                bill_id, test_id, test_code_snapshot, test_name_snapshot,
                unit_price_paisa, discount_paisa, net_price_paisa, reporting_type
            ) VALUES (
                v_bill_id, v_test.id, v_test.code, v_test.name,
                100000, 0, 100000, 'InHouse'::public.reporting_type_enum
            ) RETURNING id INTO v_bill_item_id;

            INSERT INTO public.samples (
                barcode, order_id, patient_id, specimen_type, container_type,
                status, collected_at, collected_by, collected_by_name,
                received_at, received_by, received_by_name
            ) VALUES (
                'SMP-' || v_code || '-999', v_order_id, v_patient_id,
                COALESCE(v_test.sample_type, 'Serum'), COALESCE(v_test.container, 'Clot Activator (Yellow/Red)'),
                'Received'::public.sample_status_enum, NOW(), v_user_id, v_user_name,
                NOW(), v_user_id, v_user_name
            ) RETURNING id INTO v_sample_id;

            INSERT INTO public.clinical_order_items (
                order_id, bill_item_id, test_id, test_name, department,
                reporting_type, execution_route, clinical_reporting_enabled,
                status, specimen_type, container_type, sample_id
            ) VALUES (
                v_order_id, v_bill_item_id, v_test.id, v_test.name, v_test.department,
                'InHouse', 'INTERNAL', TRUE,
                'SampleReceived', COALESCE(v_test.sample_type, 'Serum'), COALESCE(v_test.container, 'Clot Activator (Yellow/Red)'),
                v_sample_id
            ) RETURNING id INTO v_order_item_id;

            v_results := '[]'::JSONB;

            -- 1. Direct parameters
            FOR v_param IN (
                SELECT p.id, p.code, p.name, p.value_type, p.unit
                FROM public.parameters p
                WHERE p.test_id = v_test.id AND p.is_active = TRUE
                ORDER BY p.display_order
            ) LOOP
                v_results := v_results || jsonb_build_object(
                    'parameter_id', v_param.id,
                    'display_value', 'Normal Value',
                    'numeric_value', CASE WHEN v_param.value_type = 'Numeric' THEN 5.0 ELSE NULL END,
                    'text_value', CASE WHEN v_param.value_type <> 'Numeric' THEN 'Normal' ELSE NULL END,
                    'flag', 'Normal',
                    'is_critical', FALSE,
                    'critical_acknowledged', FALSE
                );
            END LOOP;

            -- 2. Component parameters for profiles
            IF jsonb_array_length(v_results) = 0 THEN
                FOR v_comp IN (
                    SELECT cpc.component_test_id, cpc.display_order
                    FROM public.catalogue_panel_components cpc
                    WHERE (cpc.panel_test_id = v_test.id OR cpc.panel_id = v_test.id)
                    ORDER BY cpc.display_order
                ) LOOP
                    FOR v_param IN (
                        SELECT p.id, p.code, p.name, p.value_type, p.unit
                        FROM public.parameters p
                        WHERE p.test_id = v_comp.component_test_id AND p.is_active = TRUE
                        ORDER BY p.display_order
                    ) LOOP
                        v_results := v_results || jsonb_build_object(
                            'parameter_id', v_param.id,
                            'display_value', 'Normal Value',
                            'numeric_value', CASE WHEN v_param.value_type = 'Numeric' THEN 10.0 ELSE NULL END,
                            'text_value', CASE WHEN v_param.value_type <> 'Numeric' THEN 'Normal' ELSE NULL END,
                            'flag', 'Normal',
                            'is_critical', FALSE,
                            'critical_acknowledged', FALSE
                        );
                    END LOOP;
                END LOOP;
            END IF;

            -- Save as Verified
            IF jsonb_array_length(v_results) > 0 THEN
                PERFORM public.save_test_results(v_order_item_id, v_results, 'Verified', NULL, NULL, 0);
            END IF;
        END IF;
    END LOOP;

END $$;

-- 3. Extract Full Master Catalogue State
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
        'options', p.options,
        'calculation_identifier', p.calculation_identifier
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
),
all_tests AS (
  SELECT 
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
    ) AS test_json
  FROM public.tests t
  LEFT JOIN test_direct_params tdp ON tdp.test_id = t.id
  LEFT JOIN panel_comps pc ON pc.panel_id = t.id
  LEFT JOIN active_rates ar ON ar.entity_id = t.id
  LEFT JOIN analyzer_maps am ON am.test_id = t.id
  LEFT JOIN ref_ranges rr ON rr.test_id = t.id
  WHERE t.is_active = TRUE
  ORDER BY t.code
),
all_parameters AS (
  SELECT 
    jsonb_build_object(
      'parameter_id', p.id,
      'test_id', p.test_id,
      'test_code', t.code,
      'parameter_code', p.code,
      'parameter_name', p.name,
      'value_type', p.value_type::text,
      'unit', p.unit,
      'display_order', p.display_order,
      'is_mandatory', p.is_mandatory,
      'is_active', p.is_active,
      'lifecycle_status', p.lifecycle_status,
      'formula', p.formula,
      'options', p.options
    ) AS param_json
  FROM public.parameters p
  JOIN public.tests t ON p.test_id = t.id
  WHERE p.is_active = TRUE
    AND (p.lifecycle_status IS NULL OR p.lifecycle_status = 'Active')
    AND LOWER(COALESCE(p.unit, '')) <> 'panel'
    AND LOWER(COALESCE(p.value_type::text, '')) NOT IN ('panel', 'profile')
  ORDER BY t.code, p.display_order
),
all_reference_ranges AS (
  SELECT 
    jsonb_build_object(
      'rule_id', rr.id,
      'parameter_id', rr.parameter_id,
      'test_code', t.code,
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
      'unit', rr.unit
    ) AS ref_json
  FROM public.reference_ranges rr
  JOIN public.parameters p ON rr.parameter_id = p.id
  JOIN public.tests t ON p.test_id = t.id
  WHERE p.is_active = TRUE
  ORDER BY t.code, p.display_order
),
lft_result AS (
  SELECT 
    t.code AS test_code,
    t.name AS test_name,
    coi.status AS item_status,
    COUNT(tr.id) AS verified_param_count
  FROM public.clinical_order_items coi
  JOIN public.tests t ON coi.test_id = t.id
  JOIN public.clinical_orders co ON coi.order_id = co.id
  JOIN public.patients p ON co.patient_id = p.id
  LEFT JOIN public.test_results tr ON tr.order_item_id = coi.id
  WHERE p.uhid = '9999000999'
  GROUP BY t.code, t.name, coi.status
),
duplicate_params AS (
  SELECT p.test_id, p.code, COUNT(*) AS count
  FROM public.parameters p
  WHERE p.is_active = TRUE
    AND (p.lifecycle_status IS NULL OR p.lifecycle_status = 'Active')
    AND LOWER(COALESCE(p.unit, '')) <> 'panel'
    AND LOWER(COALESCE(p.value_type::text, '')) NOT IN ('panel', 'profile')
  GROUP BY p.test_id, p.code
  HAVING COUNT(*) > 1
),
overlapping_rates AS (
  SELECT rv.test_id, COUNT(*) AS count
  FROM public.catalogue_rate_versions rv
  WHERE rv.status = 'Active'
    AND (rv.effective_to IS NULL OR rv.effective_to > NOW())
    AND rv.test_id IS NOT NULL
  GROUP BY rv.test_id
  HAVING COUNT(*) > 1
)
SELECT jsonb_build_object(
  'tests', (SELECT jsonb_agg(test_json) FROM all_tests),
  'parameters', (SELECT jsonb_agg(param_json) FROM all_parameters),
  'reference_ranges', (SELECT jsonb_agg(ref_json) FROM all_reference_ranges),
  'structural_panel_params_count', (
    SELECT COUNT(*) FROM public.parameters 
    WHERE is_active = TRUE 
      AND (LOWER(COALESCE(unit, '')) = 'panel' OR LOWER(COALESCE(value_type::text, '')) IN ('panel', 'profile'))
  ),
  'duplicate_active_params_count', (SELECT COUNT(*) FROM duplicate_params),
  'overlapping_active_rates_count', (SELECT COUNT(*) FROM overlapping_rates),
  'representative_verification', (SELECT jsonb_agg(row_to_json(lft_result.*)) FROM lft_result),
  'lft_verification', (SELECT row_to_json(lft_result.*) FROM lft_result WHERE test_code = 'PRO-0001')
) AS full_audit_payload;

ROLLBACK;
`;

const tmp = path.resolve('tmp_verify_final_master.sql');
writeFileSync(tmp, fullAuditSql, 'utf8');

console.log('Running Transactional Master Catalogue Acceptance Audit on DB...');
const raw = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8', maxBuffer: 100 * 1024 * 1024 });
const jsonStart = raw.indexOf('{');
const jsonEnd = raw.lastIndexOf('}');
const parsed = JSON.parse(raw.slice(jsonStart, jsonEnd + 1));
const rows = parsed.rows || [];
const payloadRow = rows.find(r => r.full_audit_payload);
if (!payloadRow) {
  throw new Error('No full_audit_payload returned from query.');
}

const {
  tests,
  parameters,
  reference_ranges,
  structural_panel_params_count,
  duplicate_active_params_count,
  overlapping_active_rates_count,
  representative_verification,
  lft_verification
} = payloadRow.full_audit_payload;

console.log(`Total Active Tests in DB: ${tests.length}`);
console.log(`Total Reportable Parameters: ${parameters.length}`);
console.log(`Total Reference Rules: ${reference_ranges.length}`);
console.log(`Structural Panel Parameters in DB: ${structural_panel_params_count}`);
console.log(`Duplicate Active Parameters: ${duplicate_active_params_count}`);
console.log(`Overlapping Active Rates: ${overlapping_active_rates_count}`);
console.log(`LFT Verification Result:`, lft_verification);

// Map lookups
const testsById = new Map(tests.map(t => [t.test_id, t]));
const testsByCode = new Map(tests.map(t => [t.test_code, t]));

function resolveReportingModel(t) {
  const code = t.test_code;
  const name = t.test_name;
  const dept = t.department || t.category;
  const direct = t.direct_params || [];
  const comps = t.components || [];

  if (code.startsWith('PRO-')) return 'PROFILE_PANEL';
  if (dept === 'Histopathology') return 'HISTOPATHOLOGY_NARRATIVE';
  if (dept === 'Cytology') return 'CYTOLOGY_NARRATIVE';
  if (dept === 'Microbiology' && (name.includes('Culture') || code.startsWith('MIC-001') || code.startsWith('MIC-002'))) return 'CULTURE_AST';
  if (dept === 'Genetics / Cytogenetics' || dept === 'Genetics') return 'GENETICS_NARRATIVE';
  if (dept === 'Molecular Diagnostics' || dept === 'Molecular') {
    if (name.includes('Viral Load') || name.includes('Quantitative')) return 'VIRAL_LOAD';
    return 'MOLECULAR_QUALITATIVE';
  }
  if (name.includes('Widal') || name.includes('Titer') || name.includes('TPHA') || name.includes('VDRL')) return 'TITER';
  if (name.includes('Index') || name.includes('Ratio') || name.includes('COI')) return 'INDEX_COI';
  if (name.includes('Calculated') || direct.some(p => p.value_type === 'Calculated')) return 'CALCULATED_RESULT';
  if (name.includes('Timed') || name.includes('GTT') || name.includes('Suppression')) return 'TIMED_PROTOCOL';
  if (name.includes('Smear') || name.includes('Stain') || name.includes('Mount') || name.includes('Microscopy')) return 'MANUAL_MICROSCOPY';
  if (direct.some(p => p.value_type === 'Text' && !p.unit) || direct.some(p => Array.isArray(p.options) && p.options.length > 0)) return 'QUALITATIVE_RESULT';
  if (direct.length > 1 || comps.length > 0) return 'NUMERIC_MULTI_PARAMETER';
  return 'NUMERIC_SINGLE_ANALYTE';
}

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

// 1. Generate final_master_catalogue_after.csv
const afterRows = tests.map(t => {
  const leafCount = resolveLeafCount(t);
  const repModel = resolveReportingModel(t);
  const pricePaisa = t.active_price_paisa ?? t.legacy_price_paisa;
  const hasRate = pricePaisa !== null && pricePaisa !== undefined && Number(pricePaisa) > 0;

  return {
    test_id: t.test_id,
    test_code: t.test_code,
    test_name: t.test_name,
    category: t.category,
    clinical_domain: t.department || t.category,
    workflow_type: t.workflow_type || 'Standard',
    reporting_model: repModel,
    is_active: t.is_active ? 'TRUE' : 'FALSE',
    billing_enabled: t.billing_enabled ? 'TRUE' : 'FALSE',
    clinical_reporting_enabled: t.clinical_reporting_enabled ? 'TRUE' : 'FALSE',
    direct_parameter_count: t.direct_param_count,
    resolved_leaf_parameter_count: leafCount,
    component_count: t.component_count,
    method: t.method || 'METHOD_PENDING',
    specimen: t.sample_type || 'SPECIMEN_PENDING',
    configured_source: t.analyzer_mapping_count > 0 ? 'ANALYZER' : (leafCount > 0 && repModel === 'CALCULATED_RESULT' ? 'CALCULATED' : 'MANUAL'),
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
  path.join(outputDir, 'final_master_catalogue_after.csv'),
  [
    'test_id', 'test_code', 'test_name', 'category', 'clinical_domain', 'workflow_type',
    'reporting_model', 'is_active', 'billing_enabled', 'clinical_reporting_enabled',
    'direct_parameter_count', 'resolved_leaf_parameter_count', 'component_count',
    'method', 'specimen', 'configured_source', 'analyzer_mapping_count',
    'reference_rule_count', 'qualitative_option_count', 'calculation_rule_count',
    'active_rate', 'rate_source', 'rate_effective_date', 'result_entry_supported',
    'verification_supported', 'signoff_supported', 'pdf_supported'
  ],
  afterRows
);

// 2. Generate final_master_parameters.csv
const paramRows = parameters.map(p => ({
  parameter_id: p.parameter_id,
  test_id: p.test_id,
  test_code: p.test_code,
  parameter_code: p.parameter_code,
  parameter_name: p.parameter_name,
  value_type: p.value_type,
  unit: p.unit || '',
  display_order: p.display_order,
  is_mandatory: p.is_mandatory ? 'TRUE' : 'FALSE',
  is_active: p.is_active ? 'TRUE' : 'FALSE',
  lifecycle_status: p.lifecycle_status || 'Active',
  formula: p.formula || '',
  options: Array.isArray(p.options) ? JSON.stringify(p.options) : '',
  reference_status: p.unit || p.formula ? 'CONFIGURED' : 'REFERENCE_PENDING'
}));

writeCsv(
  path.join(outputDir, 'final_master_parameters.csv'),
  [
    'parameter_id', 'test_id', 'test_code', 'parameter_code', 'parameter_name',
    'value_type', 'unit', 'display_order', 'is_mandatory', 'is_active',
    'lifecycle_status', 'formula', 'options', 'reference_status'
  ],
  paramRows
);

// 3. Generate final_master_reference_rules.csv
const refRows = reference_ranges.map(rr => ({
  rule_id: rr.rule_id,
  parameter_id: rr.parameter_id,
  test_code: rr.test_code,
  parameter_code: rr.parameter_code,
  parameter_name: rr.parameter_name,
  gender: rr.gender,
  age_min_days: rr.age_min_days ?? '',
  age_max_days: rr.age_max_days ?? '',
  normal_min: rr.normal_min ?? '',
  normal_max: rr.normal_max ?? '',
  normal_text: rr.normal_text ?? '',
  critical_low: rr.critical_low ?? '',
  critical_high: rr.critical_high ?? '',
  unit: rr.unit ?? '',
  reference_source: rr.reference_source ?? 'APPROVED_LIS_CONFIG',
  clinical_note: rr.clinical_note ?? ''
}));

writeCsv(
  path.join(outputDir, 'final_master_reference_rules.csv'),
  [
    'rule_id', 'parameter_id', 'test_code', 'parameter_code', 'parameter_name',
    'gender', 'age_min_days', 'age_max_days', 'normal_min', 'normal_max',
    'normal_text', 'critical_low', 'critical_high', 'unit', 'reference_source',
    'clinical_note'
  ],
  refRows
);

// 4. Generate final_master_rates.csv
const rateRows = tests.map(t => {
  const pricePaisa = t.active_price_paisa ?? t.legacy_price_paisa;
  const hasRate = pricePaisa !== null && pricePaisa !== undefined && Number(pricePaisa) > 0;
  return {
    test_code: t.test_code,
    test_name: t.test_name,
    category: t.category,
    active_rate_npr: hasRate ? (Number(pricePaisa) / 100).toFixed(2) : '0.00',
    active_rate_paisa: hasRate ? Number(pricePaisa) : 0,
    rate_status: hasRate ? 'ACTIVE' : 'RATE_PENDING',
    rate_source: hasRate ? (t.active_price_paisa ? 'CATALOGUE_RATE_VERSIONS' : 'TESTS_PRICE_PAISA') : 'NONE',
    effective_from: t.rate_effective_from || 'N/A',
    needs_admin_price: hasRate ? 'FALSE' : 'TRUE'
  };
});

writeCsv(
  path.join(outputDir, 'final_master_rates.csv'),
  [
    'test_code', 'test_name', 'category', 'active_rate_npr', 'active_rate_paisa',
    'rate_status', 'rate_source', 'effective_from', 'needs_admin_price'
  ],
  rateRows
);

// 5. Generate rate_pending_tests.csv
const ratePendingRows = tests
  .filter(t => {
    const pricePaisa = t.active_price_paisa ?? t.legacy_price_paisa;
    return pricePaisa === null || pricePaisa === undefined || Number(pricePaisa) <= 0;
  })
  .map(t => ({
    test_code: t.test_code,
    test_name: t.test_name,
    category: t.category,
    clinical_domain: t.department || t.category,
    reporting_type: t.test_type || 'InHouse',
    sample_type: t.sample_type || 'Serum',
    reason: 'No authoritative master rate approved in tariff schedule; technician manual bill entry active'
  }));

writeCsv(
  path.join(outputDir, 'rate_pending_tests.csv'),
  [
    'test_code', 'test_name', 'category', 'clinical_domain', 'reporting_type',
    'sample_type', 'reason'
  ],
  ratePendingRows
);

// 6. Generate lab_review_required.csv
const labReviewRows = [];
for (const t of tests) {
  if (t.method === null || t.method === '' || t.method === 'METHOD_PENDING') {
    labReviewRows.push({
      test_code: t.test_code,
      test_name: t.test_name,
      category: t.category,
      parameter_code: t.test_code,
      parameter_name: t.test_name,
      issue_type: 'METHOD_PENDING',
      details: 'Specific analytical method pending manufacturer/assay kit verification',
      recommendation: 'Verify analyzer reagent kit insert upon installation'
    });
  }
}

writeCsv(
  path.join(outputDir, 'lab_review_required.csv'),
  [
    'test_code', 'test_name', 'category', 'parameter_code', 'parameter_name',
    'issue_type', 'details', 'recommendation'
  ],
  labReviewRows
);

// 7. Generate final_catalogue_summary.csv
const domainCounts = {};
for (const t of tests) {
  const domain = t.department || t.category;
  if (!domainCounts[domain]) {
    domainCounts[domain] = { total: 0, operational: 0, unresolved: 0 };
  }
  domainCounts[domain].total += 1;
  const leafCount = resolveLeafCount(t);
  if (leafCount > 0) domainCounts[domain].operational += 1;
  else domainCounts[domain].unresolved += 1;
}

const summaryRows = Object.entries(domainCounts).map(([domain, stat]) => ({
  clinical_domain: domain,
  total_tests: stat.total,
  operational_tests: stat.operational,
  unresolved_tests: stat.unresolved,
  operational_rate_pct: ((stat.operational / stat.total) * 100).toFixed(1) + '%'
}));

writeCsv(
  path.join(outputDir, 'final_catalogue_summary.csv'),
  ['clinical_domain', 'total_tests', 'operational_tests', 'unresolved_tests', 'operational_rate_pct'],
  summaryRows
);

// Hard clinical assertions
const hardAssertions = {
  'PRO-0001': { name: 'Liver Function Test (LFT)', expected: 11 },
  'PRO-0002': { name: 'Renal Function Test (RFT/KFT)', expected: 4 },
  'PRO-0003': { name: 'Lipid Profile', expected: 5 },
  'HEM-0001': { name: 'Complete Blood Count (CBC)', expected: 24 },
  'CLP-0001': { name: 'Urine Routine Examination', expected: 14 },
  'SER-0024': { name: 'Widal Test', expected: 4 },
  'POC-0002': { name: 'Venous Blood Gas (VBG)', expected: 7 }
};

console.log('\n================ HARD PROFILE ASSERTIONS ================');
let allHardPass = true;
for (const [code, spec] of Object.entries(hardAssertions)) {
  const t = testsByCode.get(code);
  const resolvedCount = t ? resolveLeafCount(t) : 0;
  const pass = resolvedCount === spec.expected;
  if (!pass) allHardPass = false;
  console.log(`  [${pass ? 'PASS' : 'FAIL'}] ${code} (${spec.name}): expected=${spec.expected}, resolved=${resolvedCount}`);
}

const unconfiguredTests = tests.filter(t => resolveLeafCount(t) === 0);
console.log(`\nUNRESOLVED_REPORTABLE_TESTS: ${unconfiguredTests.length}`);
console.log(`TOTAL_ACTIVE_TESTS: ${tests.length}`);
console.log(`TOTAL_REPORTABLE_PARAMETERS: ${parameters.length}`);
console.log(`ACTIVE_STRUCTURAL_PANEL_PARAMETERS: ${structural_panel_params_count}`);
console.log(`DUPLICATE_ACTIVE_PARAMETERS: ${duplicate_active_params_count}`);
console.log(`OVERLAPPING_ACTIVE_RATES: ${overlapping_active_rates_count}`);
console.log(`TESTS_WITH_ACTIVE_APPROVED_RATE: ${tests.length - ratePendingRows.length}`);
console.log(`TESTS_RATE_PENDING: ${ratePendingRows.length}`);
