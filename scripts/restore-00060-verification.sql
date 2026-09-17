\set ON_ERROR_STOP on
SET default_transaction_read_only = on;

WITH
ledger AS (
  SELECT
    max(version) AS head,
    count(*) FILTER (WHERE version = '000565') AS has_000565,
    count(*) FILTER (WHERE version IN ('00061','00062','00063','00064','00065','00066','00067','00068','00069','00070')) AS forbidden_versions,
    count(*) - count(DISTINCT version) AS duplicate_versions
  FROM supabase_migrations.schema_migrations
),
counts AS (
  SELECT jsonb_build_object(
    'patients',(SELECT count(*) FROM public.patients),
    'bills',(SELECT count(*) FROM public.bills),
    'clinical_orders',(SELECT count(*) FROM public.clinical_orders),
    'order_items',(SELECT count(*) FROM public.clinical_order_items),
    'samples',(SELECT count(*) FROM public.samples),
    'results',(SELECT count(*) FROM public.test_results),
    'reports',(SELECT count(*) FROM public.diagnostic_reports),
    'public_tokens',(SELECT count(*) FROM public.public_report_tokens),
    'sms_rows',(SELECT count(*) FROM public.sms_queue_items),
    'audit_rows',(SELECT count(*) FROM public.audit_logs)
  ) AS value
),
violations AS (
  SELECT jsonb_build_object(
    'orphan_bill_patient',(SELECT count(*) FROM public.bills x LEFT JOIN public.patients p ON p.id=x.patient_id WHERE p.id IS NULL),
    'orphan_bill_item_bill',(SELECT count(*) FROM public.bill_items x LEFT JOIN public.bills p ON p.id=x.bill_id WHERE p.id IS NULL),
    'orphan_bill_item_test',(SELECT count(*) FROM public.bill_items x LEFT JOIN public.tests p ON p.id=x.test_id WHERE p.id IS NULL),
    'orphan_payment',(SELECT count(*) FROM public.payment_transactions x LEFT JOIN public.bills p ON p.id=x.bill_id WHERE p.id IS NULL),
    'orphan_order',(SELECT count(*) FROM public.clinical_orders x LEFT JOIN public.bills p ON p.id=x.bill_id WHERE p.id IS NULL),
    'orphan_order_item',(SELECT count(*) FROM public.clinical_order_items x LEFT JOIN public.clinical_orders p ON p.id=x.order_id WHERE p.id IS NULL),
    'orphan_sample',(SELECT count(*) FROM public.samples x LEFT JOIN public.clinical_orders p ON p.id=x.order_id WHERE p.id IS NULL),
    'dangling_recollection_parent',(SELECT count(*) FROM public.samples x LEFT JOIN public.samples p ON p.id=x.recollected_from_sample_id WHERE x.recollected_from_sample_id IS NOT NULL AND p.id IS NULL),
    'sample_order_patient_mismatch',(SELECT count(*) FROM public.samples s JOIN public.clinical_orders o ON o.id=s.order_id WHERE s.patient_id<>o.patient_id),
    'rejected_without_reason',(SELECT count(*) FROM public.samples WHERE status='Rejected' AND coalesce(rejection_reason,'')=''),
    'collected_without_timestamp',(SELECT count(*) FROM public.samples WHERE status IN('Collected','Received','Processing','Completed') AND collected_at IS NULL),
    'received_without_timestamp',(SELECT count(*) FROM public.samples WHERE status IN('Received','Processing','Completed') AND received_at IS NULL),
    'negative_result_revision',(SELECT count(*) FROM public.clinical_order_items WHERE result_revision<0),
    'orphan_result_item',(SELECT count(*) FROM public.test_results x LEFT JOIN public.clinical_order_items p ON p.id=x.order_item_id WHERE p.id IS NULL),
    'orphan_result_parameter',(SELECT count(*) FROM public.test_results x LEFT JOIN public.parameters p ON p.id=x.parameter_id WHERE p.id IS NULL),
    'orphan_report',(SELECT count(*) FROM public.diagnostic_reports x LEFT JOIN public.clinical_orders p ON p.id=x.order_id WHERE p.id IS NULL),
    'invalid_amendment_parent',(SELECT count(*) FROM public.diagnostic_reports x LEFT JOIN public.diagnostic_reports p ON p.id=x.amended_from_report_id WHERE x.amended_from_report_id IS NOT NULL AND (p.id IS NULL OR p.order_id<>x.order_id OR p.version>=x.version)),
    'duplicate_report_version',(SELECT count(*) FROM(SELECT order_id,version FROM public.diagnostic_reports GROUP BY 1,2 HAVING count(*)>1)d),
    'token_report_mismatch',(SELECT count(*) FROM public.public_report_tokens x LEFT JOIN public.diagnostic_reports p ON p.id=x.diagnostic_report_id WHERE p.id IS NULL),
    'presentation_orphan',(SELECT count(*) FROM public.report_secure_link_presentations x LEFT JOIN public.public_report_tokens p ON p.id=x.report_token_id WHERE p.id IS NULL),
    'sms_report_mismatch',(SELECT count(*) FROM public.sms_queue_items x LEFT JOIN public.diagnostic_reports p ON p.id=x.diagnostic_report_id WHERE x.diagnostic_report_id IS NOT NULL AND p.id IS NULL),
    'duplicate_sms_idempotency',(SELECT count(*) FROM(SELECT idempotency_key FROM public.sms_queue_items GROUP BY 1 HAVING count(*)>1)d),
    'duplicate_lab_registry',(SELECT count(*) FROM(SELECT lab_no FROM public.lab_number_registry GROUP BY 1 HAVING count(*)>1)d),
    'unbound_lab_registry',(SELECT count(*) FROM public.lab_number_registry r LEFT JOIN public.clinical_orders o ON o.id=r.order_id WHERE r.order_id IS NULL OR o.id IS NULL),
    'registry_order_mismatch',(SELECT count(*) FROM public.lab_number_registry r JOIN public.clinical_orders o ON o.id=r.order_id WHERE r.lab_no<>o.order_number)
  ) AS value
),
objects AS (
  SELECT jsonb_build_object(
    'tables',(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r'),
    'sequences',(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='S'),
    'indexes',(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='i'),
    'functions',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'),
    'triggers',(SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal),
    'foreign_keys',(SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname='public' AND c.contype='f'),
    'enums',(SELECT count(DISTINCT t.oid) FROM pg_type t JOIN pg_enum e ON e.enumtypid=t.oid JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public'),
    'rls_tables',(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relrowsecurity),
    'policies',(SELECT count(*) FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public'),
    'six_argument_save_results',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='save_test_results' AND p.pronargs=6),
    'public_report_resolver',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='resolve_public_report_by_token'),
    'collection_readiness_guard',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='assert_order_item_result_collection_ready'),
    'result_write_trigger',(SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='test_results' AND NOT t.tgisinternal),
    'protected_rls',(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname IN('patients','bills','clinical_orders','clinical_order_items','samples','test_results','diagnostic_reports','public_report_tokens','sms_queue_items','audit_logs') AND c.relrowsecurity)
  ) AS value
)
SELECT jsonb_build_object(
  'migration_head',ledger.head,
  'has_000565',ledger.has_000565,
  'forbidden_versions',ledger.forbidden_versions,
  'duplicate_versions',ledger.duplicate_versions,
  'counts',counts.value,
  'violations',violations.value,
  'objects',objects.value
)::text
FROM ledger,counts,violations,objects;
