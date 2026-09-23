-- Exactly two automatic transactional notifications: payment confirmation and
-- signed report ready. Sparrow delivery remains asynchronous and optional.

CREATE OR REPLACE FUNCTION public.create_patient_bill_and_order(
    p_patient_data JSONB,
    p_bill_data JSONB,
    p_items_data JSONB[],
    p_payment_data JSONB,
    p_idempotency_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_key TEXT := btrim(COALESCE(p_idempotency_key, ''));
    v_hash TEXT;
    v_existing public.billing_idempotency_requests%ROWTYPE;
    v_response JSONB;
    v_payment public.payment_transactions%ROWTYPE;
    v_bill public.bills%ROWTYPE;
    v_phone TEXT;
    v_lab_no TEXT;
    v_message TEXT;
    v_sms_id UUID;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.has_permission('can_create_bill') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;
    IF v_key = '' OR length(v_key) > 200 THEN
        RAISE EXCEPTION 'A valid billing request key is required.' USING ERRCODE = '22023';
    END IF;

    v_hash := encode(extensions.digest(
        convert_to(jsonb_build_object(
            'patient', p_patient_data,
            'bill', p_bill_data,
            'items', to_jsonb(p_items_data),
            'payment', p_payment_data
        )::TEXT, 'UTF8'),
        'sha256'
    ), 'hex');

    INSERT INTO public.billing_idempotency_requests(caller_id, idempotency_key, request_hash)
    VALUES (v_caller, v_key, v_hash)
    ON CONFLICT (caller_id, idempotency_key) DO NOTHING;

    SELECT * INTO v_existing
      FROM public.billing_idempotency_requests
     WHERE caller_id = v_caller AND idempotency_key = v_key
     FOR UPDATE;

    IF v_existing.request_hash <> v_hash THEN
        RAISE EXCEPTION 'Billing request key was already used for different data.' USING ERRCODE = '22023';
    END IF;
    IF v_existing.response_json IS NOT NULL THEN
        RETURN v_existing.response_json || jsonb_build_object('idempotency_replay', TRUE);
    END IF;

    v_response := public.create_patient_bill_and_order(
        p_patient_data, p_bill_data, p_items_data, p_payment_data
    );

    SELECT * INTO v_bill FROM public.bills WHERE id = (v_response->>'bill_id')::UUID;
    SELECT * INTO v_payment
      FROM public.payment_transactions
     WHERE bill_id = v_bill.id
     ORDER BY created_at DESC, id DESC
     LIMIT 1;

    -- A zero-payment bill has no payment event and therefore no payment SMS.
    IF FOUND THEN
        v_phone := regexp_replace(COALESCE(v_bill.patient_mobile_snapshot, ''), '[^0-9]', '', 'g');
        IF v_phone LIKE '977%' AND length(v_phone) = 13 THEN
            v_phone := substring(v_phone FROM 4);
        END IF;
        v_lab_no := COALESCE(NULLIF(v_response->>'order_number', ''), v_response->>'bill_number');

        IF v_phone ~ '^(97|98)[0-9]{8}$' THEN
            IF v_bill.due_amount_paisa = 0 THEN
                v_message := 'Bimal Pathology: Payment received NPR '
                    || (v_bill.paid_amount_paisa / 100)::TEXT || '.' || lpad((v_bill.paid_amount_paisa % 100)::TEXT, 2, '0')
                    || ' against bill NPR '
                    || (v_bill.net_amount_paisa / 100)::TEXT || '.' || lpad((v_bill.net_amount_paisa % 100)::TEXT, 2, '0')
                    || '. Thank you for your payment. Lab No: ' || v_lab_no || '.';
            ELSE
                v_message := 'Bimal Pathology: Bill NPR '
                    || (v_bill.net_amount_paisa / 100)::TEXT || '.' || lpad((v_bill.net_amount_paisa % 100)::TEXT, 2, '0')
                    || '. Received NPR '
                    || (v_bill.paid_amount_paisa / 100)::TEXT || '.' || lpad((v_bill.paid_amount_paisa % 100)::TEXT, 2, '0')
                    || '. Remaining due NPR '
                    || (v_bill.due_amount_paisa / 100)::TEXT || '.' || lpad((v_bill.due_amount_paisa % 100)::TEXT, 2, '0')
                    || '. Lab No: ' || v_lab_no || '. Thank you.';
            END IF;

            INSERT INTO public.sms_queue_items(
                sms_type, recipient_phone, recipient_name, message_body,
                status, idempotency_key, bill_id
            ) VALUES (
                'BillRegistration', v_phone, v_bill.patient_name_snapshot, v_message,
                'Pending', 'PAYMENT_CONFIRMATION:' || v_payment.id::TEXT, v_bill.id
            )
            ON CONFLICT (idempotency_key) DO NOTHING
            RETURNING id INTO v_sms_id;
        END IF;
    END IF;

    v_response := v_response || jsonb_build_object(
        'sms_queued', v_sms_id IS NOT NULL,
        'sms_status', CASE
            WHEN v_payment.id IS NULL THEN 'No payment notification required'
            WHEN v_sms_id IS NULL THEN 'SMS skipped: invalid or missing Nepal mobile'
            ELSE 'Payment notification queued'
        END
    );

    UPDATE public.billing_idempotency_requests
       SET response_json = v_response, completed_at = NOW()
     WHERE caller_id = v_caller AND idempotency_key = v_key;

    RETURN v_response || jsonb_build_object('idempotency_replay', FALSE);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
TO authenticated;

-- Manual/browser queueing is retired. Only the billing transaction inserts the
-- payment outbox event.
REVOKE ALL ON FUNCTION public.queue_bill_sms(UUID) FROM PUBLIC, anon, authenticated;

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

    IF p_public_url_base IS NULL OR p_public_url_base !~ '^https://lis[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]{32,256}$' THEN
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
        v_message := CASE WHEN v_report.version > 1 OR v_report.is_amendment THEN
            'Bimal Pathology: Your amended report is ready. Lab No: '
        ELSE
            'Bimal Pathology: Your report is ready. Lab No: '
        END || v_order.order_number || '. View report: ' || p_public_url_base;

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
