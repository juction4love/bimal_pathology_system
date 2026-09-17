-- Read-only post-clean production baseline verification.
DO $verify$
DECLARE
    v_table TEXT;
    v_count BIGINT;
    v_last BIGINT;
    v_called BOOLEAN;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'patients', 'bills', 'payment_transactions', 'clinical_orders',
        'clinical_order_items', 'samples', 'sample_lifecycle_events',
        'test_results', 'diagnostic_reports', 'public_report_tokens',
        'sms_queue_items', 'outsource_samples', 'outsource_sample_events',
        'bill_items', 'billing_idempotency_requests'
    ] LOOP
        EXECUTE format('SELECT count(*) FROM public.%I', v_table) INTO v_count;
        RAISE NOTICE 'POST_COUNT %.% = %', 'public', v_table, v_count;
        IF v_count <> 0 THEN
            RAISE EXCEPTION 'Post-clean verification failed: public.% has % rows', v_table, v_count;
        END IF;
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'audit_logs', 'tests', 'parameters', 'reference_ranges', 'roles',
        'role_permissions', 'user_profiles', 'user_roles',
        'user_direct_permissions', 'reporting_personnel', 'referring_doctors'
    ] LOOP
        EXECUTE format('SELECT count(*) FROM public.%I', v_table) INTO v_count;
        RAISE NOTICE 'PRESERVED_COUNT %.% = %', 'public', v_table, v_count;
    END LOOP;

    SELECT count(*) INTO v_count FROM auth.users;
    RAISE NOTICE 'PRESERVED_COUNT auth.users = %', v_count;
    SELECT count(*) INTO v_count FROM public.user_profiles WHERE is_super_admin AND is_active;
    RAISE NOTICE 'PRESERVED_COUNT active_super_admin_profiles = %', v_count;
    SELECT count(*) INTO v_count
      FROM public.user_roles ur JOIN public.roles r ON r.id = ur.role_id
     WHERE r.code = 'technician';
    RAISE NOTICE 'PRESERVED_COUNT technician_role_assignments = %', v_count;

    FOREACH v_table IN ARRAY ARRAY[
        'uhid_seq', 'bill_seq', 'lab_order_seq', 'sample_seq',
        'receipt_seq', 'report_seq', 'outsource_tracking_seq'
    ] LOOP
        EXECUTE format('SELECT last_value, is_called FROM public.%I', v_table) INTO v_last, v_called;
        RAISE NOTICE 'SEQUENCE public.% last_value=% is_called=% next_value=%',
            v_table, v_last, v_called, CASE WHEN v_called THEN v_last + 1 ELSE v_last END;
        IF v_last <> 1 OR v_called THEN
            RAISE EXCEPTION 'Sequence public.% is not at fresh state', v_table;
        END IF;
    END LOOP;

    SELECT count(*) INTO v_count FROM supabase_migrations.schema_migrations;
    RAISE NOTICE 'MIGRATION_COUNT = %', v_count;
    SELECT max(version)::BIGINT INTO v_last FROM supabase_migrations.schema_migrations;
    RAISE NOTICE 'MIGRATION_MAX = %', v_last;
    -- Versions 00000 through 00060 are applied, with the historical 000565
    -- pre-convergence entry between 00056 and 00057 (62 ledger rows total).
    IF v_count <> 62 OR v_last <> 60 THEN
        RAISE EXCEPTION 'Migration history is not aligned through production head 00060';
    END IF;

END
$verify$;
