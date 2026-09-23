-- Hosted PostgreSQL privilege convergence for the existing RLS/RPC architecture.
-- This migration changes ACLs only. It does not update clinical or historical data.

GRANT USAGE ON SCHEMA public TO authenticated, service_role;
GRANT USAGE ON SCHEMA public TO anon;

-- Application read paths. RLS remains authoritative for row visibility.
GRANT SELECT ON TABLE
  public.user_profiles,
  public.roles,
  public.role_permissions,
  public.user_roles,
  public.user_direct_permissions,
  public.referring_doctors,
  public.reporting_personnel,
  public.patients,
  public.bills,
  public.bill_items,
  public.payment_transactions,
  public.tests,
  public.parameters,
  public.reference_ranges,
  public.clinical_orders,
  public.samples,
  public.sample_lifecycle_events,
  public.clinical_order_items,
  public.test_results,
  public.diagnostic_reports,
  public.audit_logs,
  public.outsource_samples,
  public.outsource_sample_events,
  public.hmis_facility_configuration,
  public.hmis_monthly_reports,
  public.hmis_monthly_manual_values,
  public.hmis_monthly_report_versions,
  public.hmis_submission_events,
  public.test_categories,
  public.catalogue_calculation_definitions,
  public.health_packages,
  public.health_package_components,
  public.bill_package_selections,
  public.bill_package_components,
  public.analyzers,
  public.test_analyzer_configurations
TO authenticated;

-- All ordinary clinical/catalogue writes stay RPC-only. Existing RLS policies
-- remain defense in depth but do not constitute a direct-table write contract.
REVOKE INSERT, UPDATE, DELETE ON TABLE
  public.user_profiles,
  public.roles,
  public.role_permissions,
  public.user_roles,
  public.user_direct_permissions,
  public.referring_doctors,
  public.reporting_personnel,
  public.patients,
  public.bills,
  public.bill_items,
  public.payment_transactions,
  public.tests,
  public.parameters,
  public.reference_ranges,
  public.clinical_orders,
  public.samples,
  public.sample_lifecycle_events,
  public.clinical_order_items,
  public.test_results,
  public.diagnostic_reports,
  public.audit_logs,
  public.outsource_samples,
  public.outsource_sample_events,
  public.test_categories,
  public.catalogue_calculation_definitions,
  public.health_packages,
  public.health_package_components,
  public.bill_package_selections,
  public.bill_package_components,
  public.analyzers,
  public.test_analyzer_configurations
FROM authenticated;

-- The current HMIS editor intentionally uses direct draft/config writes and
-- already has permission-gated RLS WITH CHECK predicates for these operations.
GRANT INSERT, UPDATE ON TABLE public.hmis_facility_configuration TO authenticated;
GRANT INSERT ON TABLE public.hmis_monthly_reports TO authenticated;
GRANT INSERT, UPDATE ON TABLE public.hmis_monthly_manual_values TO authenticated;
REVOKE DELETE ON TABLE
  public.hmis_facility_configuration,
  public.hmis_monthly_reports,
  public.hmis_monthly_manual_values,
  public.hmis_monthly_report_versions,
  public.hmis_submission_events
FROM authenticated;

-- Public report access is RPC-only. No protected table or sequence becomes a
-- public/anonymous data source, and browser sessions allocate no sequences.
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE
  public.public_report_tokens,
  public.report_secure_link_presentations,
  public.sms_queue_items,
  public.billing_idempotency_requests,
  public.payment_idempotency_requests,
  public.lab_number_registry
FROM PUBLIC, anon, authenticated;

-- Internal readiness/allocator workers are never externally executable.
REVOKE ALL ON FUNCTION public.clinical_result_collection_readiness(UUID) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.assert_clinical_result_ready(UUID) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.save_test_results_unversioned_internal(UUID,JSONB,public.result_status_enum,UUID,TEXT) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.assign_bpdc_lab_no(), public.bind_bpdc_lab_no(), public.guard_lab_number_registry() FROM PUBLIC, anon, authenticated, service_role;

-- Fail the migration if the intended hosted boundary is not exactly present.
DO $$
BEGIN
  IF NOT has_table_privilege('authenticated', 'public.test_categories', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.tests', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.clinical_order_items', 'SELECT') THEN
    RAISE EXCEPTION 'HOSTED_PRIVILEGE_CONVERGENCE_SELECT_FAILED';
  END IF;
  IF has_table_privilege('anon', 'public.test_categories', 'SELECT')
     OR has_table_privilege('anon', 'public.test_results', 'SELECT')
     OR has_table_privilege('authenticated', 'public.test_results', 'INSERT')
     OR has_table_privilege('authenticated', 'public.test_results', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.tests', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.user_profiles', 'UPDATE') THEN
    RAISE EXCEPTION 'HOSTED_PRIVILEGE_CONVERGENCE_DENIAL_FAILED';
  END IF;
  IF has_function_privilege('authenticated', 'public.assert_clinical_result_ready(UUID)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.clinical_result_collection_readiness(UUID)', 'EXECUTE') THEN
    RAISE EXCEPTION 'HOSTED_PRIVILEGE_CONVERGENCE_INTERNAL_RPC_FAILED';
  END IF;
END $$;
