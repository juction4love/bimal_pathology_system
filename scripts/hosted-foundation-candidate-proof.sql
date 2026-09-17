\set ON_ERROR_STOP on

DO $$
DECLARE v_head text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations;
  IF v_head IS DISTINCT FROM '00056' THEN RAISE EXCEPTION 'FOUNDATION_HEAD_MISMATCH:%', coalesce(v_head, '<empty>'); END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('claim_cloud_sms_batch','complete_cloud_sms_job','recover_stale_cloud_sms_jobs')) THEN
    RAISE EXCEPTION 'CLOUD_SMS_FUNCTION_PRESENT';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='sms_dispatch_configuration') THEN
    RAISE EXCEPTION 'CLOUD_SMS_TABLE_PRESENT';
  END IF;
END $$;

SELECT p.oid::regprocedure::text AS signature, pg_get_functiondef(p.oid) AS definition
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN (
  'save_test_results','assert_order_item_result_collection_ready',
  'check_order_report_readiness','sign_and_queue_diagnostic_report',
  'create_patient_bill_order_with_packages','transition_sample_lifecycle'
) ORDER BY 1;

SELECT c.conrelid::regclass::text AS relation, c.conname, c.contype, pg_get_constraintdef(c.oid, true) AS definition
FROM pg_constraint c
WHERE c.connamespace='public'::regnamespace
  AND c.conrelid::regclass::text IN ('clinical_orders','clinical_order_items','samples','test_results','diagnostic_reports','public_report_tokens','sms_queue_items')
ORDER BY 1,2;

SELECT schemaname, tablename, policyname, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname='public' AND tablename IN ('clinical_order_items','samples','test_results','diagnostic_reports','public_report_tokens','sms_queue_items')
ORDER BY tablename,policyname;

SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE specific_schema='public' AND routine_name IN ('save_test_results','assert_order_item_result_collection_ready','check_order_report_readiness','sign_and_queue_diagnostic_report')
ORDER BY routine_name,grantee;
