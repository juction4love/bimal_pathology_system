-- Report, audit, and result security hardening.
-- All changes are forward-only and preserve existing clinical/history rows.

-- Signed reports are created exclusively by the guarded SECURITY DEFINER RPC.
DROP POLICY IF EXISTS "diagnostic_reports_insert" ON public.diagnostic_reports;
REVOKE INSERT ON public.diagnostic_reports FROM authenticated;

-- Audit evidence is server-authored. Clients retain permission-gated read only.
DROP POLICY IF EXISTS "audit_logs_insert" ON public.audit_logs;
REVOKE INSERT, UPDATE, DELETE ON public.audit_logs FROM authenticated;

-- Result writes are state-sensitive and are performed only by save_test_results.
DROP POLICY IF EXISTS "test_results_insert" ON public.test_results;
DROP POLICY IF EXISTS "test_results_update" ON public.test_results;
REVOKE INSERT, UPDATE, DELETE ON public.test_results FROM authenticated;

CREATE OR REPLACE FUNCTION public.record_critical_value_acknowledgement(
    p_order_item_id UUID,
    p_notification_method TEXT,
    p_notified_person TEXT,
    p_comment TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_item public.clinical_order_items%ROWTYPE;
    v_user_name TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF NOT (public.has_permission('can_enter_results') OR public.has_permission('can_verify_results')) THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;
    IF NULLIF(btrim(p_notified_person), '') IS NULL THEN
        RAISE EXCEPTION 'The notified clinician or ward staff is required.' USING ERRCODE = '22023';
    END IF;
    IF p_notification_method NOT IN (
        'Direct Phone Call', 'In-Person Verbal Alert',
        'Hospital Intercom', 'Official WhatsApp / SMS'
    ) THEN
        RAISE EXCEPTION 'A supported notification method is required.' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_item
    FROM public.clinical_order_items
    WHERE id = p_order_item_id
    FOR UPDATE;
    IF NOT FOUND OR v_item.status = 'SignedOff' THEN
        RAISE EXCEPTION 'This result can no longer be modified.' USING ERRCODE = '55000';
    END IF;

    SELECT COALESCE(full_name, 'Lab Staff') INTO v_user_name
    FROM public.user_profiles WHERE id = auth.uid();

    INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES (
        auth.uid(), v_user_name, 'CRITICAL_VALUE_ACKNOWLEDGED',
        'ClinicalOrderItem', p_order_item_id::TEXT,
        jsonb_strip_nulls(jsonb_build_object(
            'notification_method', p_notification_method,
            'notified_person', left(btrim(p_notified_person), 255),
            'comment', NULLIF(left(btrim(COALESCE(p_comment, '')), 1000), '')
        ))
    );

    RETURN jsonb_build_object('success', TRUE);
END;
$$;

REVOKE ALL ON FUNCTION public.record_critical_value_acknowledgement(UUID, TEXT, TEXT, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_critical_value_acknowledgement(UUID, TEXT, TEXT, TEXT)
TO authenticated;

CREATE OR REPLACE FUNCTION public.save_test_results(
    p_order_item_id UUID,
    p_results JSONB,
    p_target_status public.result_status_enum,
    p_amended_from_report_id UUID DEFAULT NULL,
    p_amendment_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_item public.clinical_order_items%ROWTYPE;
    v_order public.clinical_orders%ROWTYPE;
    v_parent public.diagnostic_reports%ROWTYPE;
    v_result JSONB;
    v_parameter public.parameters%ROWTYPE;
    v_existing public.test_results%ROWTYPE;
    v_user_name TEXT;
    v_is_amendment BOOLEAN := FALSE;
    v_count INT := 0;
    v_item_status TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF jsonb_typeof(p_results) <> 'array' OR jsonb_array_length(p_results) = 0 THEN
        RAISE EXCEPTION 'At least one result is required.' USING ERRCODE = '22023';
    END IF;
    IF p_target_status NOT IN ('Draft', 'SubmittedForVerification', 'ReturnedForCorrection', 'Verified') THEN
        RAISE EXCEPTION 'Unsupported result workflow state.' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_item FROM public.clinical_order_items
    WHERE id = p_order_item_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Result work item was not found.' USING ERRCODE = 'P0002';
    END IF;
    SELECT * INTO v_order FROM public.clinical_orders WHERE id = v_item.order_id FOR UPDATE;

    IF p_amended_from_report_id IS NOT NULL THEN
        SELECT * INTO v_parent FROM public.diagnostic_reports
        WHERE id = p_amended_from_report_id AND order_id = v_item.order_id
          AND status IN ('SignedOff', 'Amended');
        IF NOT FOUND OR NULLIF(btrim(p_amendment_reason), '') IS NULL
           OR NOT public.has_permission('can_amend_reports') THEN
            RAISE EXCEPTION 'A valid authorized amendment and reason are required.' USING ERRCODE = '42501';
        END IF;
        v_is_amendment := TRUE;
    END IF;

    IF p_target_status IN ('Draft', 'SubmittedForVerification')
       AND NOT public.has_permission('can_enter_results') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;
    IF p_target_status IN ('ReturnedForCorrection', 'Verified')
       AND NOT public.has_permission('can_verify_results') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;
    IF v_item.status = 'SignedOff' AND NOT v_is_amendment THEN
        RAISE EXCEPTION 'This result can no longer be modified.' USING ERRCODE = '55000';
    END IF;
    IF p_target_status = 'ReturnedForCorrection'
       AND NOT EXISTS (SELECT 1 FROM public.test_results WHERE order_item_id = p_order_item_id AND status = 'SubmittedForVerification') THEN
        RAISE EXCEPTION 'Only submitted results may be returned for correction.' USING ERRCODE = '55000';
    END IF;
    IF p_target_status = 'Verified'
       AND NOT EXISTS (SELECT 1 FROM public.test_results WHERE order_item_id = p_order_item_id AND status IN ('SubmittedForVerification', 'Verified')) THEN
        RAISE EXCEPTION 'Results must be submitted before verification.' USING ERRCODE = '55000';
    END IF;
    IF p_target_status = 'Verified' AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_results) r
        WHERE COALESCE((r->>'is_critical')::BOOLEAN, FALSE)
          AND NOT COALESCE((r->>'critical_acknowledged')::BOOLEAN, FALSE)
    ) THEN
        RAISE EXCEPTION 'Critical results must be acknowledged before verification.' USING ERRCODE = '55000';
    END IF;

    SELECT COALESCE(full_name, 'Lab Staff') INTO v_user_name
    FROM public.user_profiles WHERE id = auth.uid();

    FOR v_result IN SELECT value FROM jsonb_array_elements(p_results)
    LOOP
        SELECT p.* INTO v_parameter
        FROM public.parameters p
        WHERE p.id = (v_result->>'parameter_id')::UUID
          AND p.test_id = v_item.test_id
          AND p.is_active = TRUE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'A submitted parameter is not valid for this investigation.' USING ERRCODE = '22023';
        END IF;

        SELECT * INTO v_existing FROM public.test_results
        WHERE order_item_id = p_order_item_id AND parameter_id = v_parameter.id
        FOR UPDATE;
        IF FOUND AND v_existing.status = 'SignedOff' AND NOT v_is_amendment THEN
            RAISE EXCEPTION 'This result can no longer be modified.' USING ERRCODE = '55000';
        END IF;

        INSERT INTO public.test_results(
            order_item_id, parameter_id, parameter_name, unit, value_type,
            numeric_value, text_value, display_value, flag, is_critical,
            critical_acknowledged, critical_acknowledged_by, critical_acknowledged_at,
            normal_range_text, normal_min, normal_max, critical_low, critical_high,
            status, entered_by, entered_by_name, entered_at,
            verified_by, verified_by_name, verified_at, updated_at
        ) VALUES (
            p_order_item_id, v_parameter.id, v_parameter.name, v_parameter.unit, v_parameter.value_type,
            NULLIF(v_result->>'numeric_value', '')::NUMERIC,
            NULLIF(v_result->>'text_value', ''), COALESCE(v_result->>'display_value', ''),
            COALESCE((v_result->>'flag')::public.result_flag_enum, 'Normal'),
            COALESCE((v_result->>'is_critical')::BOOLEAN, FALSE),
            COALESCE((v_result->>'critical_acknowledged')::BOOLEAN, FALSE),
            CASE WHEN COALESCE((v_result->>'critical_acknowledged')::BOOLEAN, FALSE) THEN auth.uid() ELSE NULL END,
            CASE WHEN COALESCE((v_result->>'critical_acknowledged')::BOOLEAN, FALSE) THEN NOW() ELSE NULL END,
            NULLIF(v_result->>'normal_range_text', ''), NULLIF(v_result->>'normal_min', '')::NUMERIC,
            NULLIF(v_result->>'normal_max', '')::NUMERIC, NULLIF(v_result->>'critical_low', '')::NUMERIC,
            NULLIF(v_result->>'critical_high', '')::NUMERIC, p_target_status,
            CASE WHEN p_target_status IN ('Draft','SubmittedForVerification') THEN auth.uid() ELSE v_existing.entered_by END,
            CASE WHEN p_target_status IN ('Draft','SubmittedForVerification') THEN v_user_name ELSE v_existing.entered_by_name END,
            CASE WHEN p_target_status IN ('Draft','SubmittedForVerification') THEN NOW() ELSE v_existing.entered_at END,
            CASE WHEN p_target_status = 'Verified' THEN auth.uid() ELSE NULL END,
            CASE WHEN p_target_status = 'Verified' THEN v_user_name ELSE NULL END,
            CASE WHEN p_target_status = 'Verified' THEN NOW() ELSE NULL END,
            NOW()
        )
        ON CONFLICT (order_item_id, parameter_id) DO UPDATE SET
            parameter_name = EXCLUDED.parameter_name, unit = EXCLUDED.unit, value_type = EXCLUDED.value_type,
            numeric_value = EXCLUDED.numeric_value, text_value = EXCLUDED.text_value,
            display_value = EXCLUDED.display_value, flag = EXCLUDED.flag,
            is_critical = EXCLUDED.is_critical, critical_acknowledged = EXCLUDED.critical_acknowledged,
            critical_acknowledged_by = EXCLUDED.critical_acknowledged_by,
            critical_acknowledged_at = EXCLUDED.critical_acknowledged_at,
            normal_range_text = EXCLUDED.normal_range_text, normal_min = EXCLUDED.normal_min,
            normal_max = EXCLUDED.normal_max, critical_low = EXCLUDED.critical_low,
            critical_high = EXCLUDED.critical_high, status = EXCLUDED.status,
            entered_by = COALESCE(EXCLUDED.entered_by, public.test_results.entered_by),
            entered_by_name = COALESCE(EXCLUDED.entered_by_name, public.test_results.entered_by_name),
            entered_at = COALESCE(EXCLUDED.entered_at, public.test_results.entered_at),
            verified_by = EXCLUDED.verified_by, verified_by_name = EXCLUDED.verified_by_name,
            verified_at = EXCLUDED.verified_at, signed_off_by = NULL, signed_off_name = NULL,
            signed_off_at = NULL, updated_at = NOW();
        v_count := v_count + 1;
    END LOOP;

    v_item_status := CASE WHEN p_target_status = 'Verified' THEN 'Verified' ELSE 'ResultDrafted' END;
    UPDATE public.clinical_order_items SET status = v_item_status, updated_at = NOW()
    WHERE id = p_order_item_id;
    IF v_order.status = 'SignedOff' AND v_is_amendment THEN
        UPDATE public.clinical_orders SET status = 'InProgress', updated_at = NOW() WHERE id = v_order.id;
    END IF;

    INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES (
        auth.uid(), v_user_name,
        CASE p_target_status WHEN 'Verified' THEN 'RESULTS_VERIFIED'
          WHEN 'SubmittedForVerification' THEN 'RESULTS_SUBMITTED'
          WHEN 'ReturnedForCorrection' THEN 'RESULTS_RETURNED' ELSE 'RESULTS_SAVED' END,
        'ClinicalOrderItem', p_order_item_id::TEXT,
        jsonb_strip_nulls(jsonb_build_object(
            'status', p_target_status, 'result_count', v_count,
            'amended_from_report_id', p_amended_from_report_id,
            'amendment_reason_recorded', CASE WHEN v_is_amendment THEN TRUE ELSE NULL END
        ))
    );

    RETURN jsonb_build_object('success', TRUE, 'status', p_target_status, 'result_count', v_count);
END;
$$;

REVOKE ALL ON FUNCTION public.save_test_results(UUID, JSONB, public.result_status_enum, UUID, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_test_results(UUID, JSONB, public.result_status_enum, UUID, TEXT)
TO authenticated;

-- At most one non-revoked active token can represent a report version.
-- Expired rows are made inactive by the token-creation RPC before replacement.
CREATE UNIQUE INDEX IF NOT EXISTS uq_public_report_tokens_one_active_report
ON public.public_report_tokens(diagnostic_report_id)
WHERE is_active = TRUE AND revoked_at IS NULL;

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
    v_token_id UUID; v_expires_at TIMESTAMPTZ; v_phone TEXT; v_message TEXT;
    v_sms_id UUID; v_public_token TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE='42501'; END IF;
    IF NOT (public.has_permission('can_sign_reports') OR public.is_super_admin()) THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
    END IF;
    SELECT * INTO v_report FROM public.diagnostic_reports WHERE id=p_report_id FOR UPDATE;
    IF NOT FOUND OR v_report.status NOT IN ('SignedOff','Amended') THEN
        RAISE EXCEPTION 'A signed or amended report is required.' USING ERRCODE='22023';
    END IF;
    UPDATE public.public_report_tokens SET is_active=FALSE, updated_at=NOW()
    WHERE diagnostic_report_id=p_report_id AND is_active=TRUE
      AND (revoked_at IS NOT NULL OR expires_at <= NOW());
    SELECT * INTO v_existing_token FROM public.public_report_tokens
    WHERE diagnostic_report_id=p_report_id AND is_active=TRUE AND revoked_at IS NULL AND expires_at>NOW()
    ORDER BY created_at LIMIT 1 FOR UPDATE;
    IF FOUND THEN
        RETURN jsonb_build_object('success',TRUE,'token_id',v_existing_token.id,
          'expires_at',v_existing_token.expires_at,'report_number',v_report.report_number,
          'sms_queued',FALSE,'idempotency_replay',TRUE);
    END IF;
    v_public_token := substring(p_public_url_base FROM '^https://lis[.]bimalpathology[.]com[.]np/r/([A-Za-z0-9_-]+)$');
    IF v_public_token IS NULL OR length(v_public_token) NOT BETWEEN 32 AND 256
       OR p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'A valid production report token is required.' USING ERRCODE='22023';
    END IF;
    SELECT * INTO v_patient FROM public.patients WHERE id=v_report.patient_id;
    SELECT * INTO v_order FROM public.clinical_orders WHERE id=v_report.order_id;
    v_expires_at := NOW() + (greatest(1,least(COALESCE(p_expiry_days,30),90)) || ' days')::INTERVAL;
    INSERT INTO public.public_report_tokens(diagnostic_report_id,token_hash,expires_at,created_by,is_active)
    VALUES(p_report_id,p_token_hash,v_expires_at,auth.uid(),TRUE) RETURNING id INTO v_token_id;
    INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
    VALUES(auth.uid(),'Authorized Signatory','PUBLIC_REPORT_TOKEN_CREATED','DiagnosticReport',v_report.report_number,
      jsonb_build_object('report_id',p_report_id,'token_id',v_token_id,'expires_at',v_expires_at));
    v_phone := regexp_replace(COALESCE(v_patient.mobile,''),'[^0-9]','','g');
    IF v_phone LIKE '977%' AND length(v_phone)=13 THEN v_phone:=substring(v_phone FROM 4); END IF;
    IF v_phone ~ '^(97|98)[0-9]{8}$' THEN
        v_message := 'Bimal Pathology: Your report is ready. Lab No: ' || v_order.order_number || '. View report: ' || p_public_url_base;
        INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,diagnostic_report_id)
        VALUES('ReportReady',v_phone,v_patient.full_name,v_message,'Pending',
          'REPORT_READY:'||p_report_id::TEXT||':'||v_report.version::TEXT,p_report_id)
        ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO v_sms_id;
    END IF;
    RETURN jsonb_build_object('success',TRUE,'token_id',v_token_id,'expires_at',v_expires_at,
      'report_number',v_report.report_number,'sms_queued',v_sms_id IS NOT NULL,
      'sms_status',CASE WHEN v_sms_id IS NULL THEN 'SMS skipped: invalid or missing Nepal mobile' ELSE 'Report notification queued' END,
      'idempotency_replay',FALSE);
END;
$$;

REVOKE ALL ON FUNCTION public.create_public_report_token(UUID, VARCHAR, INT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_public_report_token(UUID, VARCHAR, INT, TEXT) TO authenticated;

-- Lock the logical order before checking for a completed outcome. A retry after
-- a successful commit returns that report and reuses its token/SMS identity.
CREATE OR REPLACE FUNCTION public.sign_and_queue_diagnostic_report(
    p_order_id UUID, p_performed_by_id UUID, p_signed_by_id UUID,
    p_amendment_reason TEXT, p_amended_from_report_id UUID,
    p_token_hash VARCHAR(128), p_public_report_url TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_report_result JSONB; v_notification_result JSONB; v_notification_sqlstate TEXT;
    v_existing public.diagnostic_reports%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL OR NOT public.has_permission('can_sign_reports') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(p_order_id::TEXT, 0));
    IF p_amended_from_report_id IS NULL THEN
        SELECT * INTO v_existing FROM public.diagnostic_reports
        WHERE order_id=p_order_id AND is_amendment=FALSE AND status IN ('SignedOff','Amended')
        ORDER BY version LIMIT 1;
    ELSE
        SELECT * INTO v_existing FROM public.diagnostic_reports
        WHERE order_id=p_order_id AND amended_from_report_id=p_amended_from_report_id
          AND status IN ('SignedOff','Amended') ORDER BY version LIMIT 1;
    END IF;
    IF FOUND THEN
        v_report_result := jsonb_build_object('success',TRUE,'report_id',v_existing.id,
          'report_number',v_existing.report_number,'version',v_existing.version,
          'integrity_hash',v_existing.integrity_hash,'idempotency_replay',TRUE);
    ELSE
        v_report_result := public.sign_and_freeze_diagnostic_report(
          p_order_id,p_performed_by_id,p_signed_by_id,p_amendment_reason,p_amended_from_report_id);
    END IF;
    BEGIN
        v_notification_result := public.create_public_report_token(
          (v_report_result->>'report_id')::UUID,p_token_hash,30,p_public_report_url);
    EXCEPTION WHEN OTHERS THEN
        v_notification_sqlstate:=SQLSTATE;
        v_notification_result:=jsonb_build_object('success',FALSE,'sms_queued',FALSE,
          'sms_status','Notification unavailable; report remains signed','error_code',v_notification_sqlstate);
    END;
    IF v_notification_sqlstate IS NOT NULL THEN
        INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
        VALUES(auth.uid(),'Authorized Signatory','REPORT_NOTIFICATION_FAILED','DiagnosticReport',
          v_report_result->>'report_number',jsonb_build_object('report_id',v_report_result->>'report_id','error_code',v_notification_sqlstate));
    END IF;
    RETURN v_report_result || jsonb_build_object('notification',v_notification_result,
      'sms_queued',COALESCE((v_notification_result->>'sms_queued')::BOOLEAN,FALSE),
      'sms_status',COALESCE(v_notification_result->>'sms_status',
        CASE WHEN COALESCE((v_notification_result->>'idempotency_replay')::BOOLEAN,FALSE)
          THEN 'Notification already processed' ELSE 'Notification status unavailable' END));
END;
$$;

REVOKE ALL ON FUNCTION public.sign_and_queue_diagnostic_report(UUID,UUID,UUID,TEXT,UUID,VARCHAR,TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sign_and_queue_diagnostic_report(UUID,UUID,UUID,TEXT,UUID,VARCHAR,TEXT)
TO authenticated;
