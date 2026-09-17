-- Short commercial Payment Confirmation SMS. This replaces only the billing
-- RPC's message construction; existing rows and idempotency keys are untouched.

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
            v_message := 'Bimal Pathology: Payment of NPR '
                || (v_payment.amount_paisa / 100)::TEXT || '.'
                || lpad((v_payment.amount_paisa % 100)::TEXT, 2, '0')
                || ' received for Lab No: ' || v_lab_no || '. Thank you.';

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

REVOKE ALL ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
TO authenticated;
