-- Bounded, server-side dashboard aggregation. No clinical rows are mutated.
CREATE OR REPLACE FUNCTION public.get_dashboard_operational_summary()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_today_start TIMESTAMPTZ :=
        (date_trunc('day', now() AT TIME ZONE 'Asia/Kathmandu')) AT TIME ZONE 'Asia/Kathmandu';
    v_departments JSONB;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.has_permission('can_view_financials') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object('dept', department, 'count', item_count)
               ORDER BY department), '[]'::jsonb)
      INTO v_departments
      FROM (
        SELECT COALESCE(NULLIF(btrim(department), ''), 'Unassigned') AS department,
               count(*)::INT AS item_count
          FROM public.clinical_order_items
         WHERE status IN ('Pending', 'SampleCollected', 'SampleReceived', 'ResultDrafted')
         GROUP BY 1
      ) workload;

    RETURN jsonb_build_object(
        'today_patients', (SELECT count(*) FROM public.patients WHERE created_at >= v_today_start),
        'today_invoices', (SELECT count(*) FROM public.bills WHERE created_at >= v_today_start),
        'today_collection_paisa', (SELECT COALESCE(sum(amount_paisa), 0) FROM public.payment_transactions WHERE created_at >= v_today_start),
        'outstanding_due_paisa', (SELECT COALESCE(sum(due_amount_paisa), 0) FROM public.bills WHERE due_amount_paisa > 0),
        'pending_samples', (SELECT count(*) FROM public.samples WHERE status = 'Pending'),
        'received_samples', (SELECT count(*) FROM public.samples WHERE status = 'Received'),
        'rejected_samples', (SELECT count(*) FROM public.samples WHERE status = 'Rejected'),
        'pending_results', (SELECT count(*) FROM public.clinical_order_items WHERE status IN ('SampleReceived', 'ResultDrafted')),
        'awaiting_verification', (SELECT count(DISTINCT order_item_id) FROM public.test_results WHERE status = 'SubmittedForVerification'),
        'signed_reports', (SELECT count(*) FROM public.diagnostic_reports WHERE status IN ('SignedOff', 'Amended')),
        'critical_unacknowledged', (SELECT count(*) FROM public.test_results WHERE is_critical = TRUE AND critical_acknowledged = FALSE),
        'department_workload', v_departments
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_dashboard_operational_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_dashboard_operational_summary() TO authenticated;
