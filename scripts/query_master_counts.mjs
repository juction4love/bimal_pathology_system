import { execSync } from 'node:child_process';
import fs from 'node:fs';

// Query 1: Master data counts (tests, parameters, panel components, rates)
const sql = `
SELECT
  (SELECT COUNT(*) FROM public.tests WHERE is_active = TRUE) AS active_tests,
  (SELECT COUNT(*) FROM public.parameters WHERE is_active = TRUE) AS active_parameters,
  (SELECT COUNT(*) FROM public.catalogue_panel_components) AS panel_components,
  (SELECT COUNT(*) FROM public.reference_ranges WHERE is_active = TRUE) AS active_ref_ranges,
  (SELECT COUNT(*) FROM public.reference_ranges) AS total_ref_ranges,
  (SELECT COUNT(*) FROM public.analyzers WHERE lifecycle_status = 'Active') AS active_analyzers,
  (SELECT COUNT(*) FROM public.analyzer_parameter_mappings) AS analyzer_mappings,
  (SELECT COUNT(*) FROM public.catalogue_rate_versions WHERE status = 'Active') AS active_rates,
  (SELECT COUNT(*) FROM public.tests WHERE is_active = TRUE 
    AND NOT EXISTS (
      SELECT 1 FROM public.parameters p WHERE p.test_id = tests.id AND p.is_active = TRUE
      AND (p.unit IS NULL OR LOWER(p.unit) <> 'panel')
      AND (p.value_type::text IS NULL OR LOWER(p.value_type::text) NOT IN ('panel', 'profile'))
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.catalogue_panel_components cpc WHERE cpc.panel_test_id = tests.id OR cpc.panel_id = tests.id
    )
  ) AS unresolved_tests;
`;

fs.writeFileSync('tmp_audit_query.sql', sql, 'utf8');
const res = execSync('npx supabase db query --linked -f tmp_audit_query.sql', { encoding: 'utf8' });
console.log('=== MASTER DATA COUNTS ===');
console.log(res);
