-- Historical signed-report QR provisioning without snapshot mutation or SMS.
-- Raw tokens remain absent from database storage; an existing URL is returned
-- only when it can be recovered from its immutable ReportReady message and its
-- SHA-256 digest matches the active token row.

CREATE TABLE IF NOT EXISTS public.report_secure_link_presentations (
    report_token_id UUID PRIMARY KEY
      REFERENCES public.public_report_tokens(id) ON DELETE CASCADE,
    public_url TEXT NOT NULL
      CHECK (public_url ~ '^https://lis[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]+$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.report_secure_link_presentations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.report_secure_link_presentations FROM PUBLIC, anon, authenticated;

COMMENT ON TABLE public.report_secure_link_presentations IS
'Private, RPC-only canonical URL escrow for authenticated report rendering. Public resolution remains SHA-256 hash based.';

CREATE OR REPLACE FUNCTION public.get_report_secure_link_status(p_report_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_report public.diagnostic_reports%ROWTYPE;
    v_token public.public_report_tokens%ROWTYPE;
    v_url TEXT;
    v_raw_token TEXT;
    v_state TEXT := 'Missing';
    v_first_token_at TIMESTAMPTZ;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF NOT (public.has_permission('can_print_reports') OR public.is_super_admin()) THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_report
    FROM public.diagnostic_reports
    WHERE id = p_report_id;

    IF NOT FOUND OR v_report.status NOT IN ('SignedOff', 'Amended') THEN
        RAISE EXCEPTION 'A signed or amended report is required.' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_token
    FROM public.public_report_tokens
    WHERE diagnostic_report_id = p_report_id
    ORDER BY
      CASE WHEN is_active AND revoked_at IS NULL AND expires_at > NOW() THEN 0
           WHEN revoked_at IS NOT NULL THEN 1
           WHEN expires_at <= NOW() THEN 2 ELSE 3 END,
      created_at DESC
    LIMIT 1;

    IF FOUND THEN
        IF v_token.revoked_at IS NOT NULL THEN
            v_state := 'Revoked';
        ELSIF v_token.expires_at <= NOW() OR NOT v_token.is_active THEN
            v_state := 'Expired';
        ELSE
            SELECT p.public_url INTO v_url
            FROM public.report_secure_link_presentations p
            WHERE p.report_token_id = v_token.id;

            IF v_url IS NULL THEN
                SELECT substring(s.message_body FROM '(https://lis[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]+)')
                  INTO v_url
                FROM public.sms_queue_items s
                WHERE s.diagnostic_report_id = p_report_id
                  AND s.sms_type = 'ReportReady'
                  AND s.idempotency_key = 'REPORT_READY:' || p_report_id::TEXT || ':' || v_report.version::TEXT
                ORDER BY s.created_at DESC
                LIMIT 1;
            END IF;

            v_raw_token := substring(v_url FROM '/r/([A-Za-z0-9_-]+)$');
            IF v_raw_token IS NOT NULL
               AND length(v_raw_token) BETWEEN 32 AND 256
               AND encode(extensions.digest(convert_to(v_raw_token, 'UTF8'), 'sha256'), 'hex') = v_token.token_hash THEN
                v_state := 'Active';
            ELSE
                v_url := NULL;
                v_state := 'ActiveUnrecoverable';
            END IF;
        END IF;
    END IF;

    SELECT MIN(created_at) INTO v_first_token_at FROM public.public_report_tokens;

    RETURN jsonb_build_object(
      'report_id', v_report.id,
      'report_version', v_report.version,
      'state', v_state,
      'has_valid_token', v_state IN ('Active', 'ActiveUnrecoverable'),
      'qr_available', v_state = 'Active',
      'public_url', v_url,
      'expires_at', CASE WHEN FOUND THEN v_token.expires_at ELSE NULL END,
      'signed_before_first_token', CASE WHEN v_first_token_at IS NULL THEN NULL ELSE v_report.signed_at < v_first_token_at END
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_report_secure_link_status(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_report_secure_link_status(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.provision_historical_report_secure_link(
    p_report_id UUID,
    p_token_hash VARCHAR(128),
    p_public_url TEXT,
    p_expiry_days INT DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_report public.diagnostic_reports%ROWTYPE;
    v_existing public.public_report_tokens%ROWTYPE;
    v_token_id UUID;
    v_expires_at TIMESTAMPTZ;
    v_raw_token TEXT;
    v_existing_url TEXT;
    v_existing_raw TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF NOT (public.has_permission('can_print_reports') OR public.is_super_admin()) THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_report
    FROM public.diagnostic_reports
    WHERE id = p_report_id
    FOR UPDATE;

    IF NOT FOUND OR v_report.status NOT IN ('SignedOff', 'Amended') THEN
        RAISE EXCEPTION 'A signed or amended report is required.' USING ERRCODE = '22023';
    END IF;

    v_raw_token := substring(p_public_url FROM '^https://lis[.]bimalpathology[.]com[.]np/r/([A-Za-z0-9_-]+)$');
    IF v_raw_token IS NULL OR length(v_raw_token) NOT BETWEEN 32 AND 256
       OR p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$'
       OR encode(extensions.digest(convert_to(v_raw_token, 'UTF8'), 'sha256'), 'hex') <> p_token_hash THEN
        RAISE EXCEPTION 'A valid secure report token is required.' USING ERRCODE = '22023';
    END IF;

    UPDATE public.public_report_tokens
       SET is_active = FALSE, updated_at = NOW()
     WHERE diagnostic_report_id = p_report_id
       AND is_active = TRUE
       AND (revoked_at IS NOT NULL OR expires_at <= NOW());

    SELECT * INTO v_existing
    FROM public.public_report_tokens
    WHERE diagnostic_report_id = p_report_id
      AND is_active = TRUE AND revoked_at IS NULL AND expires_at > NOW()
    ORDER BY created_at DESC
    LIMIT 1
    FOR UPDATE;

    IF FOUND THEN
        SELECT p.public_url INTO v_existing_url
        FROM public.report_secure_link_presentations p
        WHERE p.report_token_id = v_existing.id;

        IF v_existing_url IS NULL THEN
            SELECT substring(s.message_body FROM '(https://lis[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]+)')
              INTO v_existing_url
            FROM public.sms_queue_items s
            WHERE s.diagnostic_report_id = p_report_id
              AND s.sms_type = 'ReportReady'
              AND s.idempotency_key = 'REPORT_READY:' || p_report_id::TEXT || ':' || v_report.version::TEXT
            ORDER BY s.created_at DESC
            LIMIT 1;
        END IF;
        v_existing_raw := substring(v_existing_url FROM '/r/([A-Za-z0-9_-]+)$');

        IF v_existing_raw IS NOT NULL
           AND encode(extensions.digest(convert_to(v_existing_raw, 'UTF8'), 'sha256'), 'hex') = v_existing.token_hash THEN
            RETURN jsonb_build_object('success', TRUE, 'created', FALSE, 'reused', TRUE,
              'report_id', v_report.id, 'report_version', v_report.version,
              'public_url', v_existing_url, 'expires_at', v_existing.expires_at,
              'sms_queued', FALSE);
        END IF;

        -- An unrecoverable one-way token cannot produce a QR. Replacement is
        -- explicit user action and is recorded; no notification is generated.
        UPDATE public.public_report_tokens
           SET is_active = FALSE, revoked_at = COALESCE(revoked_at, NOW()), updated_at = NOW()
         WHERE id = v_existing.id;
    END IF;

    v_expires_at := NOW() + (GREATEST(1, LEAST(COALESCE(p_expiry_days, 30), 90)) || ' days')::INTERVAL;
    INSERT INTO public.public_report_tokens(
      diagnostic_report_id, token_hash, expires_at, created_by, is_active
    ) VALUES (
      p_report_id, p_token_hash, v_expires_at, auth.uid(), TRUE
    ) RETURNING id INTO v_token_id;

    INSERT INTO public.report_secure_link_presentations(report_token_id, public_url)
    VALUES(v_token_id, p_public_url);

    INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES(auth.uid(), 'Authorized Reporting User', 'HISTORICAL_REPORT_LINK_PROVISIONED',
      'DiagnosticReport', v_report.report_number,
      jsonb_build_object('report_id', v_report.id, 'report_version', v_report.version,
        'token_id', v_token_id, 'expires_at', v_expires_at));

    -- Intentionally no sms_queue_items write: link provisioning is not a
    -- ReportReady notification and never resends historical SMS.
    RETURN jsonb_build_object('success', TRUE, 'created', TRUE, 'reused', FALSE,
      'report_id', v_report.id, 'report_version', v_report.version,
      'public_url', p_public_url, 'expires_at', v_expires_at,
      'sms_queued', FALSE);
END;
$$;

REVOKE ALL ON FUNCTION public.provision_historical_report_secure_link(UUID, VARCHAR, TEXT, INT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.provision_historical_report_secure_link(UUID, VARCHAR, TEXT, INT)
TO authenticated;
