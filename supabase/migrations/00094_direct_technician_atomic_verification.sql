-- ============================================================================
-- 00094_direct_technician_atomic_verification.sql
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Server-authoritative direct 1-click Technician Result Entry & Verification.
-- Removes artificial intermediate Submitted requirement so that valid complete
-- results entered by authorized technicians/verifiers can be verified directly.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.save_test_results_unversioned_internal(
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
       AND NOT (public.has_permission('can_enter_results') OR public.has_permission('can_verify_results')) THEN
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
       AND NOT EXISTS (SELECT 1 FROM public.test_results WHERE order_item_id = p_order_item_id AND status IN ('SubmittedForVerification', 'Verified')) THEN
        RAISE EXCEPTION 'Only submitted results may be returned for correction.' USING ERRCODE = '55000';
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
            COALESCE(v_existing.entered_by, auth.uid()),
            COALESCE(v_existing.entered_by_name, v_user_name),
            COALESCE(v_existing.entered_at, NOW()),
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
            entered_by = COALESCE(public.test_results.entered_by, EXCLUDED.entered_by),
            entered_by_name = COALESCE(public.test_results.entered_by_name, EXCLUDED.entered_by_name),
            entered_at = COALESCE(public.test_results.entered_at, EXCLUDED.entered_at),
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

REVOKE ALL ON FUNCTION public.save_test_results_unversioned_internal(UUID, JSONB, public.result_status_enum, UUID, TEXT)
FROM PUBLIC, anon, authenticated, service_role;
