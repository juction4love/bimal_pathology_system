// scripts/audit-full-catalogue-details.mjs
// Read-only audit of the entire master catalogue

import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const sql = `
WITH test_details AS (
    SELECT 
        t.id,
        t.code,
        t.name,
        COALESCE(c.name, t.department, 'General') AS category,
        t.is_active,
        t.billing_enabled,
        t.clinical_reporting_enabled,
        t.method,
        t.sample_type AS specimen,
        t.test_kind,
        t.reporting_model,
        (
            SELECT COUNT(*) 
            FROM public.parameters p 
            WHERE p.test_id = t.id AND p.is_active = TRUE
        ) AS parameter_count,
        (
            SELECT COUNT(*) 
            FROM public.reference_ranges rr 
            JOIN public.parameters p ON p.id = rr.parameter_id 
            WHERE p.test_id = t.id AND rr.is_active = TRUE AND rr.is_approved = TRUE
        ) AS reference_range_count,
        (
            SELECT COUNT(*) 
            FROM public.analyzer_parameter_mappings apm 
            WHERE apm.test_id = t.id
        ) AS analyzer_mapping_count,
        (
            SELECT r.price_paisa 
            FROM public.catalogue_rate_versions r 
            WHERE r.test_id = t.id AND r.status = 'Active' AND (r.effective_to IS NULL OR r.effective_to > NOW())
            ORDER BY r.effective_from DESC 
            LIMIT 1
        ) AS active_rate_paisa,
        EXISTS (
            SELECT 1 
            FROM public.catalogue_panel_components cpc 
            WHERE cpc.component_test_id = t.id
        ) AS is_profile_member,
        EXISTS (
            SELECT 1 
            FROM public.catalogue_panel_components cpc 
            WHERE cpc.panel_id = t.id
        ) AS is_profile_container
    FROM public.tests t
    LEFT JOIN public.test_categories c ON c.id = t.category_id
)
SELECT json_build_object(
    'summary', json_build_object(
        'total_tests', (SELECT COUNT(*) FROM test_details),
        'active_tests', (SELECT COUNT(*) FROM test_details WHERE is_active = TRUE),
        'billing_enabled', (SELECT COUNT(*) FROM test_details WHERE billing_enabled = TRUE),
        'fully_configured', (
            SELECT COUNT(*) 
            FROM test_details 
            WHERE (parameter_count > 0 OR is_profile_container)
              AND (reference_range_count > 0 OR is_profile_container)
              AND method IS NOT NULL 
              AND active_rate_paisa IS NOT NULL
        ),
        'partially_configured', (
            SELECT COUNT(*) 
            FROM test_details 
            WHERE (parameter_count > 0 OR reference_range_count > 0 OR method IS NOT NULL OR active_rate_paisa IS NOT NULL)
              AND NOT (
                (parameter_count > 0 OR is_profile_container)
                AND (reference_range_count > 0 OR is_profile_container)
                AND method IS NOT NULL 
                AND active_rate_paisa IS NOT NULL
              )
        ),
        'unconfigured_parameters', (SELECT COUNT(*) FROM test_details WHERE parameter_count = 0 AND NOT is_profile_container),
        'missing_reference_ranges', (SELECT COUNT(*) FROM test_details WHERE reference_range_count = 0 AND NOT is_profile_container),
        'missing_methods', (SELECT COUNT(*) FROM test_details WHERE method IS NULL OR TRIM(method) = ''),
        'missing_analyzer_mappings', (SELECT COUNT(*) FROM test_details WHERE analyzer_mapping_count = 0),
        'tests_with_active_rate', (SELECT COUNT(*) FROM test_details WHERE active_rate_paisa IS NOT NULL),
        'tests_without_rate', (SELECT COUNT(*) FROM test_details WHERE active_rate_paisa IS NULL),
        'overlapping_rates', (
            SELECT COUNT(*) FROM (
                SELECT test_id 
                FROM public.catalogue_rate_versions 
                WHERE status = 'Active' AND (effective_to IS NULL OR effective_to > NOW())
                GROUP BY test_id 
                HAVING COUNT(*) > 1
            ) x
        )
    ),
    'sample_tests', (
        SELECT json_agg(json_build_object(
            'code', code,
            'name', name,
            'is_active', is_active,
            'billing_enabled', billing_enabled,
            'param_count', parameter_count,
            'rr_count', reference_range_count,
            'method', method,
            'rate_paisa', active_rate_paisa
        ))
        FROM (
            SELECT * FROM test_details 
            WHERE code IN ('HEM-0001', 'HEM-0002', 'HEM-0027', 'PRO-0001', 'PRO-0002', 'PRO-0003', 'BIO-0001', 'BIO-0010', 'BIO-0051', 'BIO-0053', 'BIO-0063', 'END-0001', 'END-0002', 'END-0003', 'CLP-0001', 'SER-0024', 'SER-0015', 'SER-0016', 'SER-0004', 'SER-0010')
            ORDER BY code
        ) s
    )
) AS audit_result;
`;

const tmp = path.resolve('tmp_catalogue_audit.sql');
writeFileSync(tmp, sql, 'utf8');
try {
  const out = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], shell: true });
  const jsonStart = out.indexOf('{');
  console.log(out.slice(jsonStart));
} finally {
  try { unlinkSync(tmp); } catch {}
}

