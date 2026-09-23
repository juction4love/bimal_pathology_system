-- Admin-only, privacy-minimized SMS delivery visibility.
-- Delivery remains service-role managed; this migration grants no mutation path.

DROP POLICY IF EXISTS "Staff can view SMS queue items" ON public.sms_queue_items;
DROP POLICY IF EXISTS "Admins can view SMS queue items" ON public.sms_queue_items;
CREATE POLICY "Admins can view SMS queue items"
ON public.sms_queue_items FOR SELECT TO authenticated
USING (public.has_permission('can_manage_users') OR public.is_super_admin());

CREATE OR REPLACE FUNCTION public.get_sms_delivery_status(p_limit INT DEFAULT 200)
RETURNS TABLE (
    id UUID,
    event_type TEXT,
    lab_no TEXT,
    status TEXT,
    provider_status TEXT,
    retry_count INT,
    estimated_segments INT,
    created_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL OR NOT (
        public.has_permission('can_manage_users') OR public.is_super_admin()
    ) THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        q.id,
        CASE q.sms_type
            WHEN 'BillRegistration' THEN 'Payment Confirmation'
            WHEN 'ReportReady' THEN 'Report Ready'
            ELSE 'Transactional SMS'
        END::TEXT,
        COALESCE(o.order_number, ro.order_number, b.bill_number)::TEXT,
        q.status::TEXT,
        left(COALESCE(
            q.provider_response_json->>'response',
            q.error_message,
            CASE WHEN q.status = 'Sent' THEN 'Accepted' ELSE q.status END
        ), 500)::TEXT,
        q.retry_count,
        CASE
            WHEN q.message_body ~ '^[\u0000-\u007F]*$' THEN
                CASE WHEN length(q.message_body) <= 160 THEN 1
                     ELSE ceil(length(q.message_body)::NUMERIC / 153)::INT END
            ELSE
                CASE WHEN length(q.message_body) <= 70 THEN 1
                     ELSE ceil(length(q.message_body)::NUMERIC / 67)::INT END
        END,
        q.created_at,
        q.sent_at
    FROM public.sms_queue_items q
    LEFT JOIN public.bills b ON b.id = q.bill_id
    LEFT JOIN public.clinical_orders o ON o.bill_id = q.bill_id
    LEFT JOIN public.diagnostic_reports r ON r.id = q.diagnostic_report_id
    LEFT JOIN public.clinical_orders ro ON ro.id = r.order_id
    ORDER BY q.created_at DESC
    LIMIT greatest(1, least(COALESCE(p_limit, 200), 500));
END;
$$;

REVOKE ALL ON FUNCTION public.get_sms_delivery_status(INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_sms_delivery_status(INT) TO authenticated;
