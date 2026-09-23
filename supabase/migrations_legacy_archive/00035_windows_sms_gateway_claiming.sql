-- Windows SMS Gateway worker internals.
-- Business transactions continue to create the existing outbox rows; this
-- migration only adds service-role-only claiming and interruption recovery.

CREATE OR REPLACE FUNCTION public.claim_sms_gateway_item(p_sms_id UUID)
RETURNS TABLE (
    id UUID,
    sms_type VARCHAR,
    recipient_phone VARCHAR,
    message_body TEXT,
    retry_count INT,
    max_attempts INT,
    idempotency_key VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_sms_id IS NULL THEN
        RAISE EXCEPTION 'An explicit SMS queue UUID is required.' USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH claimed AS (
        SELECT q.id
        FROM public.sms_queue_items q
        WHERE q.id = p_sms_id
          AND q.status = 'Pending'
          AND q.scheduled_at <= NOW()
          AND q.retry_count < q.max_attempts
        FOR UPDATE SKIP LOCKED
    )
    UPDATE public.sms_queue_items q
       SET status = 'Processing',
           updated_at = NOW()
      FROM claimed c
     WHERE q.id = c.id
    RETURNING q.id, q.sms_type, q.recipient_phone, q.message_body,
              q.retry_count, q.max_attempts, q.idempotency_key;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_sms_gateway_item(UUID)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_sms_gateway_item(UUID) TO service_role;

CREATE OR REPLACE FUNCTION public.recover_stale_sms_gateway_items(
    p_stale_after_seconds INT DEFAULT 300
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_recovered INT := 0;
    v_deadlettered INT := 0;
BEGIN
    IF p_stale_after_seconds < 60 OR p_stale_after_seconds > 3600 THEN
        RAISE EXCEPTION 'Stale threshold must be between 60 and 3600 seconds.'
            USING ERRCODE = '22023';
    END IF;

    WITH stale AS (
        SELECT q.id
        FROM public.sms_queue_items q
        WHERE q.status = 'Processing'
          AND q.updated_at <= NOW() - make_interval(secs => p_stale_after_seconds)
        FOR UPDATE SKIP LOCKED
    ), recovered AS (
        UPDATE public.sms_queue_items q
           SET retry_count = q.retry_count + 1,
               status = CASE
                   WHEN q.retry_count + 1 >= q.max_attempts THEN 'DeadLetter'
                   ELSE 'Pending'
               END,
               scheduled_at = CASE
                   WHEN q.retry_count + 1 >= q.max_attempts THEN q.scheduled_at
                   ELSE NOW() + make_interval(secs => CASE
                       WHEN q.retry_count + 1 = 1 THEN 120
                       WHEN q.retry_count + 1 = 2 THEN 600
                       WHEN q.retry_count + 1 = 3 THEN 1800
                       ELSE 3600
                   END)
               END,
               error_message = 'Gateway interrupted while item was Processing; delivery outcome is unknown.',
               updated_at = NOW()
          FROM stale s
         WHERE q.id = s.id
        RETURNING q.status
    )
    SELECT COUNT(*) FILTER (WHERE status = 'Pending'),
           COUNT(*) FILTER (WHERE status = 'DeadLetter')
      INTO v_recovered, v_deadlettered
      FROM recovered;

    RETURN jsonb_build_object(
        'success', TRUE,
        'recovered', v_recovered,
        'deadlettered', v_deadlettered
    );
END;
$$;

REVOKE ALL ON FUNCTION public.recover_stale_sms_gateway_items(INT)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.recover_stale_sms_gateway_items(INT) TO service_role;

