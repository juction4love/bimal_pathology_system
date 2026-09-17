-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Migration 00006: SMS Queue Outbox, Sparrow Integration & Public Report Tokens
-- Production-hardened, forward-only, idempotent, security definer search_path protected
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. SMS QUEUE OUTBOX TABLE
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sms_queue_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sms_type VARCHAR(50) NOT NULL CHECK (sms_type IN ('BillRegistration', 'ReportReady')),
    recipient_phone VARCHAR(20) NOT NULL,
    recipient_name VARCHAR(255) NOT NULL,
    message_body TEXT NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'Pending' CHECK (status IN ('Pending', 'Processing', 'Sent', 'Failed', 'DeadLetter')),
    retry_count INT NOT NULL DEFAULT 0,
    max_attempts INT NOT NULL DEFAULT 5,
    scheduled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at TIMESTAMPTZ,
    provider_message_id VARCHAR(100),
    provider_response_json JSONB,
    error_message TEXT,
    idempotency_key VARCHAR(255) NOT NULL UNIQUE,
    bill_id UUID REFERENCES public.bills(id) ON DELETE SET NULL,
    diagnostic_report_id UUID REFERENCES public.diagnostic_reports(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sms_queue_status_scheduled ON public.sms_queue_items(status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_sms_queue_idempotency ON public.sms_queue_items(idempotency_key);
CREATE INDEX IF NOT EXISTS idx_sms_queue_bill ON public.sms_queue_items(bill_id);
CREATE INDEX IF NOT EXISTS idx_sms_queue_report ON public.sms_queue_items(diagnostic_report_id);

-- ----------------------------------------------------------------------------
-- 2. PUBLIC REPORT TOKENS TABLE (Stores SHA-256 Hashes Only)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.public_report_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    diagnostic_report_id UUID NOT NULL REFERENCES public.diagnostic_reports(id) ON DELETE CASCADE,
    token_hash VARCHAR(128) NOT NULL UNIQUE, -- SHA-256 hash of unguessable random token
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    last_accessed_at TIMESTAMPTZ,
    access_count INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_public_report_token_hash ON public.public_report_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_public_report_tokens_report ON public.public_report_tokens(diagnostic_report_id);

-- ----------------------------------------------------------------------------
-- 3. RLS POLICIES FOR SMS QUEUE & REPORT TOKENS (Idempotent: DROP IF EXISTS)
-- ----------------------------------------------------------------------------
ALTER TABLE public.sms_queue_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.public_report_tokens ENABLE ROW LEVEL SECURITY;

-- SMS Queue: Staff read-only
DROP POLICY IF EXISTS "Staff can view SMS queue items" ON public.sms_queue_items;
CREATE POLICY "Staff can view SMS queue items"
ON public.sms_queue_items FOR SELECT TO authenticated
USING (
    public.has_permission('can_create_bill') OR
    public.has_permission('can_sign_reports') OR
    public.has_permission('can_print_reports') OR
    public.is_super_admin()
);

-- Deny direct client mutation on SMS queue
DROP POLICY IF EXISTS "Deny direct client inserts on SMS queue" ON public.sms_queue_items;
CREATE POLICY "Deny direct client inserts on SMS queue"
ON public.sms_queue_items FOR INSERT TO authenticated
WITH CHECK (FALSE);

DROP POLICY IF EXISTS "Deny direct client updates on SMS queue" ON public.sms_queue_items;
CREATE POLICY "Deny direct client updates on SMS queue"
ON public.sms_queue_items FOR UPDATE TO authenticated
USING (FALSE);

DROP POLICY IF EXISTS "Deny direct client deletes on SMS queue" ON public.sms_queue_items;
CREATE POLICY "Deny direct client deletes on SMS queue"
ON public.sms_queue_items FOR DELETE TO authenticated
USING (FALSE);

-- Public Report Tokens: Staff view only
DROP POLICY IF EXISTS "Staff can view public report tokens" ON public.public_report_tokens;
CREATE POLICY "Staff can view public report tokens"
ON public.public_report_tokens FOR SELECT TO authenticated
USING (
    public.has_permission('can_sign_reports') OR
    public.has_permission('can_print_reports') OR
    public.is_super_admin()
);

-- Deny direct client mutation on report tokens
DROP POLICY IF EXISTS "Deny direct client inserts on report tokens" ON public.public_report_tokens;
CREATE POLICY "Deny direct client inserts on report tokens"
ON public.public_report_tokens FOR INSERT TO authenticated
WITH CHECK (FALSE);

DROP POLICY IF EXISTS "Deny direct client updates on report tokens" ON public.public_report_tokens;
CREATE POLICY "Deny direct client updates on report tokens"
ON public.public_report_tokens FOR UPDATE TO authenticated
USING (FALSE);

DROP POLICY IF EXISTS "Deny direct client deletes on report tokens" ON public.public_report_tokens;
CREATE POLICY "Deny direct client deletes on report tokens"
ON public.public_report_tokens FOR DELETE TO authenticated
USING (FALSE);

-- ----------------------------------------------------------------------------
-- 4. RPC: QUEUE BILL REGISTRATION SMS
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.queue_bill_sms(p_bill_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_bill RECORD;
    v_order RECORD;
    v_clean_phone VARCHAR(20);
    v_idempotency_key VARCHAR(255);
    v_msg TEXT;
    v_sms_id UUID;
    v_net_rupees TEXT;
    v_paid_rupees TEXT;
    v_due_rupees TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    SELECT * INTO v_bill FROM public.bills WHERE id = p_bill_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bill record % not found.', p_bill_id;
    END IF;

    SELECT * INTO v_order FROM public.clinical_orders WHERE bill_id = p_bill_id LIMIT 1;

    -- Clean phone number
    v_clean_phone := REGEXP_REPLACE(TRIM(v_bill.patient_mobile_snapshot), '[^0-9]', '', 'g');
    IF v_clean_phone LIKE '977%' AND LENGTH(v_clean_phone) > 10 THEN
        v_clean_phone := SUBSTRING(v_clean_phone FROM 4);
    END IF;

    IF LENGTH(v_clean_phone) < 10 OR (v_clean_phone NOT LIKE '98%' AND v_clean_phone NOT LIKE '97%') THEN
        -- Invalid Nepal mobile: log and skip without throwing (SMS must not break clinical billing)
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid mobile number format: ' || v_clean_phone);
    END IF;

    v_net_rupees := TRIM(TO_CHAR(v_bill.net_amount_paisa / 100.0, '999999990.00'));
    v_paid_rupees := TRIM(TO_CHAR(v_bill.paid_amount_paisa / 100.0, '999999990.00'));
    v_due_rupees := TRIM(TO_CHAR(v_bill.due_amount_paisa / 100.0, '999999990.00'));

    v_idempotency_key := 'BILL_CREATED:' || p_bill_id::TEXT;

    v_msg := 'Dear ' || v_bill.patient_name_snapshot || ', your booking ' || COALESCE(v_order.order_number, v_bill.bill_number) || ' at Bimal Pathology is confirmed. Bill: NPR ' || v_net_rupees || ', Paid: NPR ' || v_paid_rupees || ', Due: NPR ' || v_due_rupees || '. Ph: 056-593288';

    INSERT INTO public.sms_queue_items (
        sms_type,
        recipient_phone,
        recipient_name,
        message_body,
        status,
        idempotency_key,
        bill_id
    ) VALUES (
        'BillRegistration',
        v_clean_phone,
        v_bill.patient_name_snapshot,
        v_msg,
        'Pending',
        v_idempotency_key,
        p_bill_id
    )
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING id INTO v_sms_id;

    -- Audit log
    INSERT INTO public.audit_logs (
        user_id,
        user_name,
        action,
        entity_type,
        entity_id,
        new_data
    ) VALUES (
        auth.uid(),
        'Front Desk / System',
        'SMS_QUEUED',
        'Bill',
        v_bill.bill_number,
        jsonb_build_object('sms_type', 'BillRegistration', 'recipient_phone', v_clean_phone, 'bill_id', p_bill_id)
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'sms_id', v_sms_id,
        'idempotency_key', v_idempotency_key,
        'recipient_phone', v_clean_phone
    );
END;
$$;

REVOKE ALL ON FUNCTION public.queue_bill_sms(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.queue_bill_sms(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. RPC: CREATE PUBLIC REPORT TOKEN & QUEUE REPORT READY SMS
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_public_report_token(
    p_report_id UUID,
    p_token_hash VARCHAR(128),
    p_expiry_days INT DEFAULT 30,
    p_public_url_base TEXT DEFAULT 'https://bimalpathology.com.np/r/'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_report RECORD;
    v_patient RECORD;
    v_order RECORD;
    v_token_id UUID;
    v_expires_at TIMESTAMPTZ;
    v_clean_phone VARCHAR(20);
    v_sms_msg TEXT;
    v_sms_idempotency VARCHAR(255);
    v_sms_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    IF NOT (public.has_permission('can_sign_reports') OR public.has_permission('can_print_reports') OR public.is_super_admin()) THEN
        RAISE EXCEPTION 'Access Denied: Missing permissions to manage public report tokens.';
    END IF;

    SELECT * INTO v_report FROM public.diagnostic_reports WHERE id = p_report_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Diagnostic report % not found.', p_report_id;
    END IF;

    IF v_report.status NOT IN ('SignedOff', 'Amended') THEN
        RAISE EXCEPTION 'Cannot generate public token for unsigned report (Status: %).', v_report.status;
    END IF;

    SELECT * INTO v_patient FROM public.patients WHERE id = v_report.patient_id;
    SELECT * INTO v_order FROM public.clinical_orders WHERE id = v_report.order_id;

    -- Deactivate any previous active tokens for this report
    UPDATE public.public_report_tokens
    SET is_active = FALSE, updated_at = NOW()
    WHERE diagnostic_report_id = p_report_id AND is_active = TRUE;

    v_expires_at := NOW() + (COALESCE(p_expiry_days, 30) || ' days')::INTERVAL;

    -- Insert new token hash
    INSERT INTO public.public_report_tokens (
        diagnostic_report_id,
        token_hash,
        expires_at,
        created_by,
        is_active
    ) VALUES (
        p_report_id,
        p_token_hash,
        v_expires_at,
        auth.uid(),
        TRUE
    ) RETURNING id INTO v_token_id;

    -- Audit log token creation
    INSERT INTO public.audit_logs (
        user_id,
        user_name,
        action,
        entity_type,
        entity_id,
        new_data
    ) VALUES (
        auth.uid(),
        'Authorized Signatory',
        'PUBLIC_REPORT_TOKEN_CREATED',
        'DiagnosticReport',
        v_report.report_number,
        jsonb_build_object(
            'report_id', p_report_id,
            'token_id', v_token_id,
            'token_hash', p_token_hash,
            'expires_at', v_expires_at
        )
    );

    -- Queue Report Ready SMS
    v_clean_phone := REGEXP_REPLACE(TRIM(v_patient.mobile), '[^0-9]', '', 'g');
    IF v_clean_phone LIKE '977%' AND LENGTH(v_clean_phone) > 10 THEN
        v_clean_phone := SUBSTRING(v_clean_phone FROM 4);
    END IF;

    IF LENGTH(v_clean_phone) >= 10 AND (v_clean_phone LIKE '98%' OR v_clean_phone LIKE '97%') THEN
        v_sms_idempotency := 'REPORT_READY:' || p_report_id::TEXT || ':v' || v_report.version::TEXT;
        v_sms_msg := 'Dear ' || v_patient.full_name || ', your lab report ' || v_order.order_number || ' from Bimal Pathology is ready. View/Download report at: ' || p_public_url_base || ' (Valid for ' || p_expiry_days || ' days). Ph: 056-593288';

        INSERT INTO public.sms_queue_items (
            sms_type,
            recipient_phone,
            recipient_name,
            message_body,
            status,
            idempotency_key,
            diagnostic_report_id
        ) VALUES (
            'ReportReady',
            v_clean_phone,
            v_patient.full_name,
            v_sms_msg,
            'Pending',
            v_sms_idempotency,
            p_report_id
        )
        ON CONFLICT (idempotency_key) DO NOTHING
        RETURNING id INTO v_sms_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'token_id', v_token_id,
        'expires_at', v_expires_at,
        'report_number', v_report.report_number,
        'sms_queued', (v_sms_id IS NOT NULL)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.create_public_report_token(UUID, VARCHAR, INT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_public_report_token(UUID, VARCHAR, INT, TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- 6. RPC: REVOKE PUBLIC REPORT TOKEN
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.revoke_public_report_token(
    p_token_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_tok RECORD;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    IF NOT (public.has_permission('can_sign_reports') OR public.is_super_admin()) THEN
        RAISE EXCEPTION 'Access Denied: Missing permissions to revoke public report tokens.';
    END IF;

    SELECT * INTO v_tok FROM public.public_report_tokens WHERE id = p_token_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Token % not found.', p_token_id;
    END IF;

    UPDATE public.public_report_tokens
    SET is_active = FALSE,
        revoked_at = NOW(),
        updated_at = NOW()
    WHERE id = p_token_id;

    INSERT INTO public.audit_logs (
        user_id,
        user_name,
        action,
        entity_type,
        entity_id,
        new_data
    ) VALUES (
        auth.uid(),
        'Authorized Staff',
        'PUBLIC_REPORT_TOKEN_REVOKED',
        'PublicReportToken',
        p_token_id::TEXT,
        jsonb_build_object('token_id', p_token_id, 'reason', p_reason)
    );

    RETURN jsonb_build_object('success', TRUE, 'revoked_token_id', p_token_id);
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_public_report_token(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_public_report_token(UUID, TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- 7. RPC: RESOLVE PUBLIC REPORT BY TOKEN HASH (Safe Public Gateway Resolver)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_public_report_by_token(p_token_hash VARCHAR(128))
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_token RECORD;
    v_report RECORD;
    v_snapshot JSONB;
BEGIN
    IF p_token_hash IS NULL OR TRIM(p_token_hash) = '' THEN
        RETURN jsonb_build_object('valid', FALSE, 'error', 'Token is required.');
    END IF;

    -- Lookup token hash
    SELECT * INTO v_token
    FROM public.public_report_tokens
    WHERE token_hash = TRIM(p_token_hash);

    IF NOT FOUND THEN
        RETURN jsonb_build_object('valid', FALSE, 'error', 'Invalid or expired report link.');
    END IF;

    IF v_token.is_active IS NOT TRUE THEN
        RETURN jsonb_build_object('valid', FALSE, 'error', 'This report link has been deactivated or superseded.');
    END IF;

    IF v_token.revoked_at IS NOT NULL THEN
        RETURN jsonb_build_object('valid', FALSE, 'error', 'This report link has been revoked.');
    END IF;

    IF v_token.expires_at < NOW() THEN
        RETURN jsonb_build_object('valid', FALSE, 'error', 'This report link has expired.');
    END IF;

    -- Fetch linked report
    SELECT * INTO v_report
    FROM public.diagnostic_reports
    WHERE id = v_token.diagnostic_report_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('valid', FALSE, 'error', 'Associated diagnostic report not found.');
    END IF;

    IF v_report.status NOT IN ('SignedOff', 'Amended') THEN
        RETURN jsonb_build_object('valid', FALSE, 'error', 'Report is not in signed status.');
    END IF;

    -- Increment access telemetry
    UPDATE public.public_report_tokens
    SET access_count = access_count + 1,
        last_accessed_at = NOW()
    WHERE id = v_token.id;

    -- Log public view audit event
    INSERT INTO public.audit_logs (
        action,
        entity_type,
        entity_id,
        new_data
    ) VALUES (
        'PUBLIC_REPORT_VIEWED',
        'DiagnosticReport',
        v_report.report_number,
        jsonb_build_object(
            'token_id', v_token.id,
            'report_id', v_report.id,
            'version', v_report.version,
            'access_count', v_token.access_count + 1
        )
    );

    v_snapshot := v_report.clinical_snapshot_json;

    -- Return safe patient-facing payload (Excludes internal user IDs, billing calculations, and staff permissions)
    RETURN jsonb_build_object(
        'valid', TRUE,
        'report_number', v_report.report_number,
        'version', v_report.version,
        'is_amendment', v_report.is_amendment,
        'amendment_reason', v_report.amendment_reason,
        'signed_at', v_report.signed_at,
        'integrity_hash', v_report.integrity_hash,
        'pdf_storage_path', v_report.pdf_storage_path,
        'snapshot', v_snapshot
    );
END;
$$;

-- Grant EXECUTE to anon and authenticated for public report verification
REVOKE ALL ON FUNCTION public.resolve_public_report_by_token(VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_public_report_by_token(VARCHAR) TO anon, authenticated;

-- ----------------------------------------------------------------------------
-- 8. RPC: ATOMIC ROW CLAIMING & BATCH DISPATCH FOR SMS WORKER
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_sms_batch(p_batch_size INT DEFAULT 10)
RETURNS TABLE (
    id UUID,
    sms_type VARCHAR,
    recipient_phone VARCHAR,
    recipient_name VARCHAR,
    message_body TEXT,
    retry_count INT,
    max_attempts INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    WITH claimed AS (
        SELECT s.id
        FROM public.sms_queue_items s
        WHERE s.status = 'Pending'
          AND s.scheduled_at <= NOW()
          AND s.retry_count < s.max_attempts
        ORDER BY s.scheduled_at ASC
        LIMIT p_batch_size
        FOR UPDATE SKIP LOCKED
    )
    UPDATE public.sms_queue_items q
    SET status = 'Processing',
        updated_at = NOW()
    FROM claimed c
    WHERE q.id = c.id
    RETURNING q.id, q.sms_type, q.recipient_phone, q.recipient_name, q.message_body, q.retry_count, q.max_attempts;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_sms_batch(INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_sms_batch(INT) TO authenticated;

-- ----------------------------------------------------------------------------
-- 9. RPC: UPDATE SMS DELIVERY STATUS
-- ----------------------------------------------------------------------------
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
    v_sms RECORD;
    v_new_status VARCHAR(50);
    v_new_attempts INT;
    v_next_delay_secs INT;
BEGIN
    SELECT * INTO v_sms FROM public.sms_queue_items WHERE id = p_sms_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'SMS item % not found.', p_sms_id;
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
        WHERE id = p_sms_id;

        INSERT INTO public.audit_logs (
            action,
            entity_type,
            entity_id,
            new_data
        ) VALUES (
            'SMS_SENT',
            'SmsQueueItem',
            p_sms_id::TEXT,
            jsonb_build_object('sms_id', p_sms_id, 'provider_message_id', p_provider_msg_id)
        );

    ELSE
        -- Failure handling with exponential backoff or deadletter
        v_new_attempts := v_sms.retry_count + 1;

        IF p_is_permanent_failure OR v_new_attempts >= v_sms.max_attempts THEN
            v_new_status := 'DeadLetter';
        ELSE
            v_new_status := 'Pending';
            -- Exponential backoff: attempt 1 -> 2 min, attempt 2 -> 10 min, attempt 3 -> 30 min
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
            scheduled_at = CASE WHEN v_new_status = 'Pending' THEN NOW() + (v_next_delay_secs || ' seconds')::INTERVAL ELSE scheduled_at END,
            updated_at = NOW()
        WHERE id = p_sms_id;

        INSERT INTO public.audit_logs (
            action,
            entity_type,
            entity_id,
            new_data
        ) VALUES (
            'SMS_FAILED',
            'SmsQueueItem',
            p_sms_id::TEXT,
            jsonb_build_object('sms_id', p_sms_id, 'attempt', v_new_attempts, 'status', v_new_status, 'error', p_error_msg)
        );
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'status', v_new_status);
END;
$$;

REVOKE ALL ON FUNCTION public.update_sms_status(UUID, VARCHAR, VARCHAR, JSONB, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_sms_status(UUID, VARCHAR, VARCHAR, JSONB, TEXT, BOOLEAN) TO authenticated;
