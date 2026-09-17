-- Converge legacy hosted default privileges before the accepted 00057/00058.
-- ACL/default-ACL only: no clinical or transactional row mutation.

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Remove legacy blanket privileges, including TRUNCATE/REFERENCES/TRIGGER.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated, service_role;

-- Prevent future objects created by the migration owner from recreating drift.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

-- Authenticated operational reads remain RLS-governed.
GRANT SELECT ON TABLE
  public.user_profiles, public.roles, public.role_permissions, public.user_roles,
  public.user_direct_permissions, public.referring_doctors, public.reporting_personnel,
  public.patients, public.bills, public.bill_items, public.payment_transactions,
  public.tests, public.parameters, public.reference_ranges, public.clinical_orders,
  public.samples, public.sample_lifecycle_events, public.clinical_order_items,
  public.test_results, public.diagnostic_reports, public.audit_logs,
  public.outsource_samples, public.outsource_sample_events,
  public.hmis_facility_configuration, public.hmis_monthly_reports,
  public.hmis_monthly_manual_values, public.hmis_monthly_report_versions,
  public.hmis_submission_events, public.test_categories,
  public.catalogue_calculation_definitions, public.health_packages,
  public.health_package_components, public.bill_package_selections,
  public.bill_package_components, public.analyzers,
  public.test_analyzer_configurations
TO authenticated;

-- Existing permission-gated HMIS editor compatibility only.
GRANT INSERT, UPDATE ON TABLE public.hmis_facility_configuration TO authenticated;
GRANT INSERT ON TABLE public.hmis_monthly_reports TO authenticated;
GRANT INSERT, UPDATE ON TABLE public.hmis_monthly_manual_values TO authenticated;

-- Anonymous access is only the opaque-token resolver.
GRANT EXECUTE ON FUNCTION public.resolve_public_report_by_token(VARCHAR) TO anon, authenticated;

-- Explicit authenticated application RPC allowlist.
GRANT EXECUTE ON FUNCTION public.catalogue_clinical_missing_configuration(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_clone_test(UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_delete_category(UUID,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_delete_package(UUID,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_delete_parameter(UUID,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_delete_range(UUID,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_delete_test(UUID,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_expand_package(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_replace_ranges(UUID[],JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_save_analyzer(JSONB,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_save_category(JSONB,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_save_package(JSONB,UUID[],BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_save_parameter(JSONB,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_save_range(JSONB,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_save_test(JSONB,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_save_test_analyzer_configuration(JSONB,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_set_category_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_set_package_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_set_parameter_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_set_range_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_set_test_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_set_test_operational_gates(UUID,BOOLEAN,BOOLEAN,BOOLEAN,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_test_missing_configuration(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_update_test_price(UUID,BIGINT,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_order_report_readiness(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_order_with_packages(JSONB,JSONB,JSONB[],JSONB,TEXT,JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_public_report_token(UUID,VARCHAR,INT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_unused_patient(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_hmis_report(UUID,JSONB,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_dashboard_collection_summary() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_dashboard_operational_summary() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_report_secure_link_status(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sms_delivery_status(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_permission(VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hmis_auto_summary(DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hmis_identity_options() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_active_user() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.provision_historical_report_secure_link(UUID,VARCHAR,TEXT,INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.receive_bill_payment(UUID,BIGINT,public.payment_mode_enum,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_critical_value_acknowledgement(UUID,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_hmis_submission(UUID,DATE,TEXT,TEXT,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.replace_role_permission_matrix(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_public_report_token(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_referring_doctor(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_reporting_personnel(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_test_results(UUID,JSONB,public.result_status_enum,UUID,TEXT,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_billable_catalogue(TEXT,INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_patient_archived(UUID,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sign_and_queue_diagnostic_report(UUID,UUID,UUID,TEXT,UUID,VARCHAR,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_sample_lifecycle(UUID,public.sample_status_enum,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_outsource_sample_status(UUID,public.outsource_sample_status_enum,TEXT,JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_patient_demographics(UUID,JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_user_access(UUID,BOOLEAN,BOOLEAN,UUID[]) TO authenticated;

-- Existing Windows Gateway contract; no browser execution and no table grants.
GRANT EXECUTE ON FUNCTION public.claim_sms_gateway_item(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.recover_stale_sms_gateway_items(INT) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_sms_status(UUID,VARCHAR,VARCHAR,JSONB,TEXT,BOOLEAN) TO service_role;

DO $$
DECLARE role_name TEXT; sequence_name TEXT;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
    FOR sequence_name IN SELECT c.oid::regclass::TEXT FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='S' LOOP
      IF has_sequence_privilege(role_name,sequence_name,'USAGE') OR has_sequence_privilege(role_name,sequence_name,'UPDATE') THEN
        RAISE EXCEPTION 'LEGACY_ACL_SEQUENCE_DENIAL_FAILED: % %',role_name,sequence_name;
      END IF;
    END LOOP;
  END LOOP;
  IF has_table_privilege('anon','public.test_categories','SELECT')
     OR has_table_privilege('anon','public.test_results','SELECT')
     OR has_table_privilege('anon','public.public_report_tokens','SELECT')
     OR has_table_privilege('anon','public.sms_queue_items','SELECT')
     OR has_table_privilege('authenticated','public.test_results','INSERT')
     OR has_table_privilege('authenticated','public.test_results','UPDATE')
     OR has_table_privilege('authenticated','public.test_results','TRUNCATE')
     OR NOT has_table_privilege('authenticated','public.test_results','SELECT')
     OR NOT has_table_privilege('authenticated','public.hmis_monthly_manual_values','UPDATE') THEN
    RAISE EXCEPTION 'LEGACY_ACL_TABLE_CONVERGENCE_FAILED';
  END IF;
  IF NOT has_function_privilege('anon','public.resolve_public_report_by_token(VARCHAR)','EXECUTE')
     OR has_function_privilege('anon','public.assert_clinical_result_ready(UUID)','EXECUTE')
     OR has_function_privilege('authenticated','public.guard_clinical_result_write()','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.save_test_results(UUID,JSONB,public.result_status_enum,UUID,TEXT,BIGINT)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.claim_sms_gateway_item(UUID)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.recover_stale_sms_gateway_items(INT)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.update_sms_status(UUID,VARCHAR,VARCHAR,JSONB,TEXT,BOOLEAN)','EXECUTE') THEN
    RAISE EXCEPTION 'LEGACY_ACL_FUNCTION_CONVERGENCE_FAILED';
  END IF;
END $$;
