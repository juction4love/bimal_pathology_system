-- BIMAL PATHOLOGY CLOUD LIS
-- One-time production baseline cleanup (not a schema migration).
--
-- Run 1 (pre-clean report only): leave v_execute FALSE.
-- Run 2 (authorized cleanup): change the single v_execute value to TRUE.
-- The operation is atomic and fails if an unexpected FK points at a cleanup table.

BEGIN;

CREATE TEMP TABLE cleanup_control (
    execute_cleanup BOOLEAN NOT NULL
) ON COMMIT DROP;

-- Safety restored after the approved 2026-08-21 execution.
INSERT INTO cleanup_control (execute_cleanup) VALUES (FALSE);

CREATE TEMP TABLE cleanup_targets (table_name TEXT PRIMARY KEY) ON COMMIT DROP;
INSERT INTO cleanup_targets(table_name) VALUES
    ('public_report_tokens'),
    ('sms_queue_items'),
    ('diagnostic_reports'),
    ('test_results'),
    ('outsource_sample_events'),
    ('outsource_samples'),
    ('sample_lifecycle_events'),
    ('clinical_order_items'),
    ('samples'),
    ('clinical_orders'),
    ('payment_transactions'),
    ('bill_items'),
    ('bills'),
    ('billing_idempotency_requests'),
    ('patients');

-- Fail closed if the deployed public FK graph contains an incoming relationship
-- from a table outside the explicitly reviewed cleanup set.
DO $fk_guard$
DECLARE
    v_unexpected TEXT;
BEGIN
    SELECT string_agg(format('%I.%I via %I', src_ns.nspname, src.relname, con.conname), ', ' ORDER BY src_ns.nspname, src.relname, con.conname)
      INTO v_unexpected
      FROM pg_constraint con
      JOIN pg_class src ON src.oid = con.conrelid
      JOIN pg_namespace src_ns ON src_ns.oid = src.relnamespace
      JOIN pg_class dst ON dst.oid = con.confrelid
      JOIN pg_namespace dst_ns ON dst_ns.oid = dst.relnamespace
     WHERE con.contype = 'f'
       AND dst_ns.nspname = 'public'
       AND dst.relname IN (SELECT table_name FROM cleanup_targets)
       AND NOT (src_ns.nspname = 'public' AND src.relname IN (SELECT table_name FROM cleanup_targets));

    IF v_unexpected IS NOT NULL THEN
        RAISE EXCEPTION 'Cleanup aborted: unexpected incoming FK relationship(s): %', v_unexpected;
    END IF;
END
$fk_guard$;

CREATE TEMP TABLE cleanup_counts (
    table_name TEXT PRIMARY KEY,
    rows_to_delete BIGINT NOT NULL,
    rows_to_preserve BIGINT NOT NULL
) ON COMMIT DROP;

DO $count_rows$
DECLARE
    v_table TEXT;
    v_count BIGINT;
BEGIN
    FOR v_table IN SELECT table_name FROM cleanup_targets ORDER BY table_name LOOP
        EXECUTE format('SELECT count(*) FROM public.%I', v_table) INTO v_count;
        INSERT INTO cleanup_counts VALUES (v_table, v_count, 0);
    END LOOP;

    -- Immutable audit rows are intentionally retained.
    SELECT count(*) INTO v_count FROM public.audit_logs;
    INSERT INTO cleanup_counts VALUES ('audit_logs', 0, v_count);

    -- Operational master/security tables: report preserved counts only.
    FOREACH v_table IN ARRAY ARRAY[
        'tests', 'parameters', 'reference_ranges', 'roles', 'role_permissions',
        'user_profiles', 'user_roles', 'user_direct_permissions',
        'reporting_personnel', 'referring_doctors'
    ] LOOP
        EXECUTE format('SELECT count(*) FROM public.%I', v_table) INTO v_count;
        INSERT INTO cleanup_counts VALUES (v_table, 0, v_count);
    END LOOP;
END
$count_rows$;

CREATE TEMP TABLE cleanup_sequences (
    sequence_name TEXT PRIMARY KEY,
    current_value BIGINT NOT NULL,
    is_called BOOLEAN NOT NULL,
    intended_next_value BIGINT NOT NULL
) ON COMMIT DROP;

DO $sequence_snapshot$
DECLARE
    v_sequence TEXT;
    v_last BIGINT;
    v_called BOOLEAN;
BEGIN
    FOREACH v_sequence IN ARRAY ARRAY[
        'uhid_seq', 'bill_seq', 'lab_order_seq', 'sample_seq',
        'receipt_seq', 'report_seq', 'outsource_tracking_seq'
    ] LOOP
        IF to_regclass('public.' || v_sequence) IS NULL THEN
            RAISE EXCEPTION 'Cleanup aborted: expected business sequence public.% is missing', v_sequence;
        END IF;
        EXECUTE format('SELECT last_value, is_called FROM public.%I', v_sequence) INTO v_last, v_called;
        INSERT INTO cleanup_sequences VALUES (v_sequence, v_last, v_called, 1);
    END LOOP;
END
$sequence_snapshot$;

-- PRE-CLEAN REPORT: deliberately limited to names/counts and sequence values.
SELECT table_name, rows_to_delete, rows_to_preserve
  FROM cleanup_counts
 ORDER BY table_name;

SELECT sequence_name, current_value, is_called, intended_next_value
  FROM cleanup_sequences
 ORDER BY sequence_name;

DO $execute_guard$
BEGIN
    IF NOT (SELECT execute_cleanup FROM cleanup_control) THEN
        RAISE EXCEPTION 'PRE-CLEAN ONLY: no data changed. Set cleanup_control.execute_cleanup to TRUE only after reviewing the report.';
    END IF;
END
$execute_guard$;

CREATE TEMP TABLE cleanup_deleted (
    table_name TEXT PRIMARY KEY,
    rows_deleted BIGINT NOT NULL
) ON COMMIT DROP;

DO $delete_rows$
DECLARE
    v_count BIGINT;
BEGIN
    DELETE FROM public.public_report_tokens; GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO cleanup_deleted VALUES ('public_report_tokens', v_count);

    DELETE FROM public.sms_queue_items; GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO cleanup_deleted VALUES ('sms_queue_items', v_count);

    -- Self-referencing amendments use ON DELETE SET NULL; deleting the complete
    -- test-report population is safe within this transaction.
    DELETE FROM public.diagnostic_reports; GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO cleanup_deleted VALUES ('diagnostic_reports', v_count);

    DELETE FROM public.test_results; GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO cleanup_deleted VALUES ('test_results', v_count);

    DELETE FROM public.outsource_sample_events; GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO cleanup_deleted VALUES ('outsource_sample_events', v_count);

    DELETE FROM public.outsource_samples; GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO cleanup_deleted VALUES ('outsource_samples', v_count);

    DELETE FROM public.sample_lifecycle_events; GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO cleanup_deleted VALUES ('sample_lifecycle_events', v_count);

    DELETE FROM public.clinical_order_items; GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO cleanup_deleted VALUES ('clinical_order_items', v_count);

    DELETE FROM public.samples; GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO cleanup_deleted VALUES ('samples', v_count);

    DELETE FROM public.clinical_orders; GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO cleanup_deleted VALUES ('clinical_orders', v_count);

    DELETE FROM public.payment_transactions; GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO cleanup_deleted VALUES ('payment_transactions', v_count);

    DELETE FROM public.bill_items; GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO cleanup_deleted VALUES ('bill_items', v_count);

    DELETE FROM public.bills; GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO cleanup_deleted VALUES ('bills', v_count);

    DELETE FROM public.billing_idempotency_requests; GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO cleanup_deleted VALUES ('billing_idempotency_requests', v_count);

    DELETE FROM public.patients; GET DIAGNOSTICS v_count = ROW_COUNT;
    INSERT INTO cleanup_deleted VALUES ('patients', v_count);
END
$delete_rows$;

-- Reset business numbering only after every disposable transaction is gone.
DO $reset_sequences$
DECLARE
    v_sequence TEXT;
    v_probe BIGINT;
BEGIN
    IF EXISTS (
        SELECT 1 FROM cleanup_targets t
        WHERE (SELECT rows_deleted FROM cleanup_deleted d WHERE d.table_name = t.table_name)
            <> (SELECT rows_to_delete FROM cleanup_counts c WHERE c.table_name = t.table_name)
    ) THEN
        RAISE EXCEPTION 'Cleanup aborted: deleted counts differ from pre-clean counts';
    END IF;

    FOREACH v_sequence IN ARRAY ARRAY[
        'uhid_seq', 'bill_seq', 'lab_order_seq', 'sample_seq',
        'receipt_seq', 'report_seq', 'outsource_tracking_seq'
    ] LOOP
        PERFORM setval(('public.' || v_sequence)::regclass, 1, FALSE);
        EXECUTE format('SELECT nextval(%L::regclass)', 'public.' || v_sequence) INTO v_probe;
        IF v_probe <> 1 THEN
            RAISE EXCEPTION 'Cleanup aborted: sequence public.% probed %, expected 1', v_sequence, v_probe;
        END IF;
        -- Restore the verified fresh state so the first production call returns 1.
        PERFORM setval(('public.' || v_sequence)::regclass, 1, FALSE);
    END LOOP;
END
$reset_sequences$;

-- Post-clean integrity assertions. Immutable audit rows and all masters remain.
DO $post_clean_assertions$
DECLARE
    v_table TEXT;
    v_count BIGINT;
BEGIN
    FOR v_table IN SELECT table_name FROM cleanup_targets ORDER BY table_name LOOP
        EXECUTE format('SELECT count(*) FROM public.%I', v_table) INTO v_count;
        IF v_count <> 0 THEN
            RAISE EXCEPTION 'Cleanup aborted: public.% retains % row(s)', v_table, v_count;
        END IF;
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY[
        'tests', 'parameters', 'reference_ranges', 'roles', 'role_permissions',
        'user_profiles', 'user_roles', 'reporting_personnel'
    ] LOOP
        EXECUTE format('SELECT count(*) FROM public.%I', v_table) INTO v_count;
        IF v_count = 0 THEN
            RAISE EXCEPTION 'Cleanup aborted: preserved table public.% is unexpectedly empty', v_table;
        END IF;
    END LOOP;
END
$post_clean_assertions$;

SELECT table_name, rows_deleted
  FROM cleanup_deleted
 ORDER BY table_name;

SELECT
    (SELECT count(*) FROM public.audit_logs) AS immutable_audit_rows_retained,
    (SELECT count(*) FROM public.tests) AS tests_preserved,
    (SELECT count(*) FROM public.parameters) AS parameters_preserved,
    (SELECT count(*) FROM public.reference_ranges) AS reference_ranges_preserved,
    (SELECT count(*) FROM public.roles) AS roles_preserved,
    (SELECT count(*) FROM public.role_permissions) AS role_permissions_preserved,
    (SELECT count(*) FROM public.user_profiles) AS user_profiles_preserved,
    (SELECT count(*) FROM public.user_roles) AS user_roles_preserved,
    (SELECT count(*) FROM public.reporting_personnel) AS reporting_personnel_preserved;

SELECT sequence_name, last_value AS current_value, is_called,
       CASE WHEN is_called THEN last_value + 1 ELSE last_value END AS verified_next_value
  FROM (
      SELECT 'uhid_seq'::TEXT AS sequence_name, last_value, is_called FROM public.uhid_seq
      UNION ALL SELECT 'bill_seq', last_value, is_called FROM public.bill_seq
      UNION ALL SELECT 'lab_order_seq', last_value, is_called FROM public.lab_order_seq
      UNION ALL SELECT 'sample_seq', last_value, is_called FROM public.sample_seq
      UNION ALL SELECT 'receipt_seq', last_value, is_called FROM public.receipt_seq
      UNION ALL SELECT 'report_seq', last_value, is_called FROM public.report_seq
      UNION ALL SELECT 'outsource_tracking_seq', last_value, is_called FROM public.outsource_tracking_seq
  ) s
 ORDER BY sequence_name;

COMMIT;
