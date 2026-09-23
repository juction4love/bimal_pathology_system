-- Standardize every eligible signed report version on one privacy-minimized
-- ReportReady template. Token security and queue idempotency are unchanged.

CREATE OR REPLACE FUNCTION public.create_public_report_token(
    p_report_id UUID,
    p_token_hash VARCHAR(128),
    p_expiry_days INT DEFAULT 30,
    p_public_url_base TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_report public.diagnostic_reports%ROWTYPE;
    v_patient public.patients%ROWTYPE;
    v_order public.clinical_orders%ROWTYPE;
    v_existing_token public.public_report_tokens%ROWTYPE;
    v_token_id UUID;
    v_expires_at TIMESTAMPTZ;
    v_phone TEXT;
    v_message TEXT;
    v_sms_id UUID;
    v_public_token TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF NOT (public.has_permission('can_sign_reports') OR public.is_super_admin()) THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_report FROM public.diagnostic_reports WHERE id = p_report_id;
    IF NOT FOUND OR v_report.status NOT IN ('SignedOff', 'Amended') THEN
        RAISE EXCEPTION 'A signed or amended report is required.' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_existing_token
      FROM public.public_report_tokens
     WHERE diagnostic_report_id = p_report_id AND is_active = TRUE
     ORDER BY created_at DESC LIMIT 1;
    IF FOUND THEN
        RETURN jsonb_build_object(
            'success', TRUE, 'token_id', v_existing_token.id,
            'expires_at', v_existing_token.expires_at,
            'report_number', v_report.report_number,
            'sms_queued', FALSE, 'idempotency_replay', TRUE
        );
    END IF;

    v_public_token := substring(
        p_public_url_base
        FROM '^https://lis[.]bimalpathology[.]com[.]np/r/([A-Za-z0-9_-]+)$'
    );
    IF v_public_token IS NULL OR length(v_public_token) NOT BETWEEN 32 AND 256 THEN
        RAISE EXCEPTION 'A valid production public report URL is required.' USING ERRCODE = '22023';
    END IF;
    IF p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'A valid report token hash is required.' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_patient FROM public.patients WHERE id = v_report.patient_id;
    SELECT * INTO v_order FROM public.clinical_orders WHERE id = v_report.order_id;
    v_expires_at := NOW() + (greatest(1, least(COALESCE(p_expiry_days, 30), 90)) || ' days')::INTERVAL;

    INSERT INTO public.public_report_tokens(
        diagnostic_report_id, token_hash, expires_at, created_by, is_active
    ) VALUES (
        p_report_id, p_token_hash, v_expires_at, auth.uid(), TRUE
    ) RETURNING id INTO v_token_id;

    INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES (
        auth.uid(), 'Authorized Signatory', 'PUBLIC_REPORT_TOKEN_CREATED',
        'DiagnosticReport', v_report.report_number,
        jsonb_build_object('report_id', p_report_id, 'token_id', v_token_id, 'expires_at', v_expires_at)
    );

    v_phone := regexp_replace(COALESCE(v_patient.mobile, ''), '[^0-9]', '', 'g');
    IF v_phone LIKE '977%' AND length(v_phone) = 13 THEN
        v_phone := substring(v_phone FROM 4);
    END IF;

    IF v_phone ~ '^(97|98)[0-9]{8}$' THEN
        v_message := 'Bimal Pathology: Your report is ready. Lab No: '
            || v_order.order_number || '. View report: ' || p_public_url_base;

        INSERT INTO public.sms_queue_items(
            sms_type, recipient_phone, recipient_name, message_body,
            status, idempotency_key, diagnostic_report_id
        ) VALUES (
            'ReportReady', v_phone, v_patient.full_name, v_message,
            'Pending', 'REPORT_READY:' || p_report_id::TEXT || ':' || v_report.version::TEXT,
            p_report_id
        )
        ON CONFLICT (idempotency_key) DO NOTHING
        RETURNING id INTO v_sms_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE, 'token_id', v_token_id, 'expires_at', v_expires_at,
        'report_number', v_report.report_number,
        'sms_queued', v_sms_id IS NOT NULL,
        'sms_status', CASE WHEN v_sms_id IS NULL
            THEN 'SMS skipped: invalid or missing Nepal mobile'
            ELSE 'Report notification queued' END,
        'idempotency_replay', FALSE
    );
END;
$$;

REVOKE ALL ON FUNCTION public.create_public_report_token(UUID, VARCHAR, INT, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_public_report_token(UUID, VARCHAR, INT, TEXT)
TO authenticated;
