-- Atomically orchestrate final report creation and its transactional outbox
-- event without allowing a notification failure to invalidate clinical sign-off.

CREATE OR REPLACE FUNCTION public.sign_and_queue_diagnostic_report(
    p_order_id UUID,
    p_performed_by_id UUID,
    p_signed_by_id UUID,
    p_amendment_reason TEXT,
    p_amended_from_report_id UUID,
    p_token_hash VARCHAR(128),
    p_public_report_url TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_report_result JSONB;
    v_notification_result JSONB;
BEGIN
    v_report_result := public.sign_and_freeze_diagnostic_report(
        p_order_id,
        p_performed_by_id,
        p_signed_by_id,
        p_amendment_reason,
        p_amended_from_report_id
    );

    BEGIN
        v_notification_result := public.create_public_report_token(
            (v_report_result->>'report_id')::UUID,
            p_token_hash,
            30,
            p_public_report_url
        );
    EXCEPTION WHEN OTHERS THEN
        -- This nested block rolls back partial token/outbox work only. It does
        -- not undo the completed immutable clinical report.
        v_notification_result := jsonb_build_object(
            'success', FALSE,
            'sms_queued', FALSE,
            'sms_status', 'Notification unavailable; report remains signed'
        );
    END;

    RETURN v_report_result || jsonb_build_object(
        'notification', v_notification_result,
        'sms_queued', COALESCE((v_notification_result->>'sms_queued')::BOOLEAN, FALSE),
        'sms_status', COALESCE(
            v_notification_result->>'sms_status',
            CASE WHEN COALESCE((v_notification_result->>'idempotency_replay')::BOOLEAN, FALSE)
                THEN 'Notification already processed'
                ELSE 'Notification status unavailable'
            END
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.sign_and_queue_diagnostic_report(
    UUID, UUID, UUID, TEXT, UUID, VARCHAR, TEXT
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sign_and_queue_diagnostic_report(
    UUID, UUID, UUID, TEXT, UUID, VARCHAR, TEXT
) TO authenticated;
