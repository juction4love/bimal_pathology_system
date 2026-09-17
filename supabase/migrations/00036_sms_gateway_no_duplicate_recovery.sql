-- Prevent an accepted Sparrow message from being resent when the provider
-- response or subsequent local status update is lost. Sparrow exposes no
-- idempotency key, so an interrupted Processing outcome must require review.

CREATE OR REPLACE FUNCTION public.recover_stale_sms_gateway_items(
    p_stale_after_seconds INT DEFAULT 300
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
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
    ), quarantined AS (
        UPDATE public.sms_queue_items q
           SET retry_count = LEAST(q.retry_count + 1, q.max_attempts),
               status = 'DeadLetter',
               error_message = 'Gateway interrupted while item was Processing; provider outcome is unknown and automatic resend is blocked.',
               updated_at = NOW()
          FROM stale s
         WHERE q.id = s.id
        RETURNING q.id
    )
    SELECT COUNT(*) INTO v_deadlettered FROM quarantined;

    RETURN jsonb_build_object(
        'success', TRUE,
        'recovered', 0,
        'deadlettered', v_deadlettered
    );
END;
$$;

REVOKE ALL ON FUNCTION public.recover_stale_sms_gateway_items(INT)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.recover_stale_sms_gateway_items(INT) TO service_role;

CREATE OR REPLACE FUNCTION public.update_sms_status(
    p_sms_id UUID,
    p_status VARCHAR(50),
    p_provider_msg_id VARCHAR(100) DEFAULT NULL,
    p_provider_response JSONB DEFAULT NULL,
    p_error_msg TEXT DEFAULT NULL,
    p_is_permanent_failure BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_sms public.sms_queue_items%ROWTYPE;
    v_new_status VARCHAR(50);
    v_new_attempts INT;
    v_next_delay_secs INT;
BEGIN
    SELECT * INTO v_sms
      FROM public.sms_queue_items
     WHERE id = p_sms_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SMS item % not found.', p_sms_id;
    END IF;

    IF v_sms.status = 'Sent' THEN
        RETURN jsonb_build_object('success', TRUE, 'status', 'Sent', 'already_completed', TRUE);
    END IF;
    IF v_sms.status <> 'Processing' THEN
        RAISE EXCEPTION 'SMS item % is %, expected Processing.', p_sms_id, v_sms.status
            USING ERRCODE = '55000';
    END IF;

    IF p_status = 'Sent' THEN
        v_new_status := 'Sent';
        UPDATE public.sms_queue_items
           SET status = 'Sent',
               sent_at = NOW(),
               provider_message_id = p_provider_msg_id,
               provider_response_json = p_provider_response,
               error_message = NULL,
               updated_at = NOW()
         WHERE id = p_sms_id AND status = 'Processing';

        INSERT INTO public.audit_logs(action, entity_type, entity_id, new_data)
        VALUES ('SMS_SENT', 'SmsQueueItem', p_sms_id::TEXT,
            jsonb_build_object('sms_id', p_sms_id, 'provider_message_id', p_provider_msg_id));
    ELSE
        v_new_attempts := v_sms.retry_count + 1;
        IF p_is_permanent_failure OR v_new_attempts >= v_sms.max_attempts THEN
            v_new_status := 'DeadLetter';
            v_next_delay_secs := 0;
        ELSE
            v_new_status := 'Pending';
            v_next_delay_secs := CASE
                WHEN v_new_attempts = 1 THEN 120
                WHEN v_new_attempts = 2 THEN 600
                WHEN v_new_attempts = 3 THEN 1800
                ELSE 3600
            END;
        END IF;

        UPDATE public.sms_queue_items
           SET status = v_new_status,
               retry_count = v_new_attempts,
               error_message = p_error_msg,
               provider_response_json = p_provider_response,
               scheduled_at = CASE WHEN v_new_status = 'Pending'
                   THEN NOW() + make_interval(secs => v_next_delay_secs)
                   ELSE scheduled_at END,
               updated_at = NOW()
         WHERE id = p_sms_id AND status = 'Processing';

        INSERT INTO public.audit_logs(action, entity_type, entity_id, new_data)
        VALUES ('SMS_FAILED', 'SmsQueueItem', p_sms_id::TEXT,
            jsonb_build_object('sms_id', p_sms_id, 'attempt', v_new_attempts,
                'status', v_new_status, 'error', p_error_msg));
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'status', v_new_status);
END;
$$;

REVOKE ALL ON FUNCTION public.update_sms_status(UUID, VARCHAR, VARCHAR, JSONB, TEXT, BOOLEAN)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_sms_status(UUID, VARCHAR, VARCHAR, JSONB, TEXT, BOOLEAN)
TO service_role;
