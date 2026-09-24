-- =============================================================================
-- BIMAL PATHOLOGY LIS - SAMPLE LIFECYCLE PRODUCTION DELTA
-- Target: Live Production Database (Targeted Function Replace Only)
-- Scope:
--   1. save_test_results_unversioned_internal: Enforces sample 'Received' status with valid
--      collected_at and received_at timestamps before SubmittedForVerification or Verified.
--   2. sign_report_group: Enforces sample 'Received' status for all specimen-required items
--      before sign-off, and binds collected_at and received_at into snapshot['order'].
-- =============================================================================

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

    -- Guard: Specimen-required investigations must have a Received sample with valid timestamps before verification
    IF p_target_status IN ('SubmittedForVerification', 'Verified') THEN
        IF v_item.collection_required THEN
            IF v_item.sample_id IS NULL THEN
                RAISE EXCEPTION 'SAMPLE_NOT_RECEIVED: Specimen must be collected and received in laboratory accessioning before results can be verified.' USING ERRCODE = '23514';
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM public.samples
                WHERE id = v_item.sample_id AND status = 'Received' AND collected_at IS NOT NULL AND received_at IS NOT NULL
            ) THEN
                RAISE EXCEPTION 'SAMPLE_NOT_RECEIVED: Sample must be received before results can be verified.' USING ERRCODE = '23514';
            END IF;
        END IF;
    END IF;

    SELECT COALESCE(full_name, 'Lab Staff') INTO v_user_name
    FROM public.user_profiles WHERE id = auth.uid();

    FOR v_result IN SELECT value FROM jsonb_array_elements(p_results)
    LOOP
        SELECT p.* INTO v_parameter
        FROM public.parameters p
        WHERE p.id = (v_result->>'parameter_id')::UUID
          AND (
            p.test_id = v_item.test_id
            OR p.test_id IN (
              SELECT cpc.component_test_id 
              FROM public.catalogue_panel_components cpc
              WHERE (cpc.panel_test_id = v_item.test_id OR cpc.panel_id = v_item.test_id)
                AND cpc.component_test_id IS NOT NULL
            )
            OR p.id IN (
              SELECT cpc.component_parameter_id
              FROM public.catalogue_panel_components cpc
              WHERE (cpc.panel_test_id = v_item.test_id OR cpc.panel_id = v_item.test_id)
                AND cpc.component_parameter_id IS NOT NULL
            )
          )
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

GRANT EXECUTE ON FUNCTION public.save_test_results_unversioned_internal TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.sign_report_group(
    p_report_group_id UUID,
    p_performed_by_id UUID,
    p_signed_by_id UUID DEFAULT NULL::UUID,
    p_amendment_reason TEXT DEFAULT NULL::TEXT,
    p_amended_from_report_id UUID DEFAULT NULL::UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    g public.clinical_report_groups%ROWTYPE;
    o public.clinical_orders%ROWTYPE;
    b public.bills%ROWTYPE;
    patient public.patients%ROWTYPE;
    performer public.reporting_personnel%ROWTYPE;
    signer public.reporting_personnel%ROWTYPE;
    parent public.diagnostic_reports%ROWTYPE;
    ready JSONB;
    investigations JSONB;
    snapshot JSONB;
    v_sample_dates JSONB;
    version_no INT;
    report_id UUID;
    report_no TEXT;
    integrity TEXT;
    is_amendment BOOLEAN:=p_amended_from_report_id IS NOT NULL;
    item RECORD;
BEGIN
    IF auth.uid() IS NULL OR NOT public.has_permission('can_sign_reports') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
    END IF;

    SELECT * INTO g FROM public.clinical_report_groups WHERE id=p_report_group_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Report group not found.' USING ERRCODE='P0002';
    END IF;

    SELECT * INTO o FROM public.clinical_orders WHERE id=g.order_id;
    SELECT * INTO b FROM public.bills WHERE id=o.bill_id;
    SELECT * INTO patient FROM public.patients WHERE id=o.patient_id;

    SELECT * INTO performer FROM public.reporting_personnel WHERE id=p_performed_by_id AND is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active reporting personnel is required.' USING ERRCODE='23514';
    END IF;

    IF p_signed_by_id IS NOT NULL THEN
        SELECT * INTO signer FROM public.reporting_personnel WHERE id=p_signed_by_id AND is_active AND can_sign_reports;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Active authorized signatory is required.' USING ERRCODE='23514';
        END IF;
    END IF;

    ready:=public.check_report_group_readiness(g.id);
    IF NOT (ready->>'is_ready')::boolean THEN
        RAISE EXCEPTION 'Report group is not ready: %', ready USING ERRCODE='23514';
    END IF;

    -- Guard: Specimen-required investigations must have a Received sample with valid timestamps before sign-off
    IF EXISTS (
        SELECT 1 FROM public.clinical_report_group_items gi
        JOIN public.clinical_order_items oi ON oi.id = gi.order_item_id
        LEFT JOIN public.samples s ON s.id = oi.sample_id
        WHERE gi.report_group_id = g.id
          AND oi.collection_required
          AND (s.id IS NULL OR s.status <> 'Received' OR s.collected_at IS NULL OR s.received_at IS NULL)
    ) THEN
        RAISE EXCEPTION 'SAMPLE_NOT_RECEIVED: Specimen must be collected and received in laboratory accessioning before report can be signed.' USING ERRCODE = '23514';
    END IF;

    IF is_amendment THEN
        IF NOT public.has_permission('can_amend_reports') OR btrim(coalesce(p_amendment_reason,''))='' THEN
            RAISE EXCEPTION 'Amendment permission and reason are required.' USING ERRCODE='42501';
        END IF;
        SELECT * INTO parent FROM public.diagnostic_reports WHERE id=p_amended_from_report_id AND report_group_id=g.id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Amendment parent is outside this report group.' USING ERRCODE='23514';
        END IF;
        version_no:=parent.version+1;
        UPDATE public.diagnostic_reports SET status='Amended',updated_at=now() WHERE id=parent.id;
    ELSE
        IF EXISTS(SELECT 1 FROM public.diagnostic_reports WHERE report_group_id=g.id AND status='SignedOff') THEN
            RAISE EXCEPTION 'This report group is already signed.' USING ERRCODE='23505';
        END IF;
        SELECT coalesce(max(version),0)+1 INTO version_no FROM public.diagnostic_reports WHERE report_group_id=g.id;
    END IF;

    FOR item IN SELECT oi.id FROM public.clinical_report_group_items gi JOIN public.clinical_order_items oi ON oi.id=gi.order_item_id WHERE gi.report_group_id=g.id LOOP
        PERFORM public.recompute_order_item_calculated_results(item.id);
    END LOOP;

    SELECT coalesce(jsonb_agg(jsonb_build_object(
        'order_item_id', x.order_item_id,
        'test_id', x.test_id,
        'test_name', x.test_name,
        'test_code', x.test_code,
        'department', x.department,
        'reporting_type', x.reporting_type,
        'execution_route', x.execution_route,
        'outsource_lab_name', x.outsource_lab_name,
        'outsource_external_reference', x.outsource_external_reference,
        'outsource_source_report_reference', x.outsource_source_report_reference,
        'outsource_method', x.outsource_method,
        'outsource_interpretation', x.outsource_interpretation,
        'outsource_result_payload', x.outsource_result_payload,
        'method', x.method,
        'interpretation_template', x.interpretation_template,
        'specimen_type', x.specimen_type,
        'container_type', x.container_type,
        'results', x.results
    ) ORDER BY x.item_order), '[]'::jsonb)
    INTO investigations FROM (
        SELECT oi.id order_item_id, oi.test_id, gi.frozen_test_name test_name, gi.frozen_test_code test_code, oi.department, oi.reporting_type, oi.execution_route, oi.outsource_lab_name, oi.outsource_external_reference, oi.outsource_source_report_reference, oi.outsource_method, oi.outsource_interpretation, oi.outsource_result_payload, t.method, t.interpretation_template, oi.specimen_type, oi.container_type, gi.display_order item_order,
        coalesce(jsonb_agg(jsonb_build_object(
            'parameter_id', tr.parameter_id,
            'code', p.code,
            'name', tr.parameter_name,
            'value_type', tr.value_type,
            'display_value', tr.display_value,
            'numeric_value', tr.numeric_value,
            'unit', tr.unit,
            'formula', p.formula,
            'flag', tr.flag,
            'is_critical', tr.is_critical,
            'result_source', tr.result_source,
            'reference_range', coalesce(case when tr.normal_min is not null and tr.normal_max is not null then tr.normal_min::text||' - '||tr.normal_max::text end, tr.normal_range_text, 'Standard'),
            'normal_min', tr.normal_min,
            'normal_max', tr.normal_max,
            'critical_low', tr.critical_low,
            'critical_high', tr.critical_high
        ) ORDER BY p.display_order) FILTER(WHERE tr.id IS NOT NULL), '[]'::jsonb) results
        FROM public.clinical_report_group_items gi
        JOIN public.clinical_order_items oi ON oi.id=gi.order_item_id
        JOIN public.tests t ON t.id=oi.test_id
        LEFT JOIN public.test_results tr ON tr.order_item_id=oi.id
        LEFT JOIN public.parameters p ON p.id=tr.parameter_id
        WHERE gi.report_group_id=g.id
        GROUP BY oi.id, gi.frozen_test_name, gi.frozen_test_code, t.method, t.interpretation_template, gi.display_order
    ) x;

    IF jsonb_array_length(investigations)=0 THEN
        RAISE EXCEPTION 'Report group contains no reportable investigations.' USING ERRCODE='23514';
    END IF;

    SELECT jsonb_build_object(
        'collected_at', to_char(min(s.collected_at), 'YYYY-MM-DD HH24:MI'),
        'received_at', to_char(max(s.received_at), 'YYYY-MM-DD HH24:MI')
    ) INTO v_sample_dates
    FROM public.clinical_report_group_items gi
    JOIN public.clinical_order_items oi ON oi.id = gi.order_item_id
    JOIN public.samples s ON s.id = oi.sample_id
    WHERE gi.report_group_id = g.id;

    snapshot:=jsonb_build_object(
        'organization', jsonb_build_object(
            'name_en', 'BIMAL PATHOLOGY & DIAGNOSTIC CENTER',
            'name_ne', 'बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर',
            'address_en', 'Bharatpur-7, Chitwan, Nepal',
            'reg_no', '7-1496',
            'pan_no', '302481477',
            'phone', '056-593288'
        ),
        'patient', jsonb_build_object(
            'uhid', patient.uhid,
            'full_name', patient.full_name,
            'title', patient.title,
            'mobile', patient.mobile,
            'gender', patient.gender,
            'dob', patient.dob,
            'age_years', patient.age_years,
            'age_months', patient.age_months,
            'age_days', patient.age_days,
            'address', patient.address
        ),
        'order', jsonb_build_object(
            'order_number', o.order_number,
            'bill_number', b.bill_number,
            'registered_date_ad', o.order_date_ad,
            'registered_date_bs', o.order_date_bs,
            'collected_at', v_sample_dates->>'collected_at',
            'received_at', v_sample_dates->>'received_at',
            'reported_at', now(),
            'referring_doctor_name', coalesce(b.referring_doctor_name_snapshot, 'Self / Walk-in')
        ),
        'report_group', jsonb_build_object(
            'id', g.id,
            'key', g.group_key,
            'title', g.title,
            'clinical_section', g.clinical_section,
            'configuration_version', g.configuration_version
        ),
        'signatories', jsonb_build_object(
            'performed_by', jsonb_build_object(
                'id', performer.id,
                'full_name', performer.full_name,
                'qualification', performer.qualification,
                'professional_type', performer.professional_type,
                'registration_council', performer.registration_council,
                'registration_number', performer.registration_number,
                'signature_url', performer.signature_url
            ),
            'authorized_by', case when signer.id is null then null else jsonb_build_object(
                'id', signer.id,
                'full_name', signer.full_name,
                'qualification', signer.qualification,
                'professional_type', signer.professional_type,
                'registration_council', signer.registration_council,
                'registration_number', signer.registration_number,
                'signature_url', signer.signature_url
            ) end
        ),
        'investigations', investigations,
        'meta', jsonb_build_object(
            'version', version_no,
            'is_amendment', is_amendment,
            'amendment_reason', p_amendment_reason,
            'amended_from_report_id', p_amended_from_report_id,
            'signed_at', now(),
            'signed_by_user_id', auth.uid()
        )
    );

    integrity:=encode(extensions.digest(convert_to(o.order_number||'|'||g.group_key||'|v'||version_no||'|'||snapshot::text,'UTF8'),'sha256'),'hex');
    report_no:='REP-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('report_seq')::text,5,'0');

    INSERT INTO public.diagnostic_reports(
        order_id, report_group_id, patient_id, report_number, version, is_amendment, amendment_reason, amended_from_report_id, status, integrity_hash, performed_by_personnel_id, performed_by_personnel_name, verified_by_personnel_id, verified_by_personnel_name, signed_by_personnel_id, signed_by_personnel_name, signed_at, pdf_storage_path, clinical_snapshot_json
    ) VALUES (
        o.id, g.id, o.patient_id, report_no, version_no, is_amendment, p_amendment_reason, p_amended_from_report_id, 'SignedOff', integrity, performer.id, performer.full_name, signer.id, signer.full_name, signer.id, signer.full_name, now(), 'reports/'||o.id||'/'||g.group_key||'/v'||version_no||'/report.pdf', snapshot
    ) RETURNING id INTO report_id;

    UPDATE public.clinical_order_items oi
    SET status='SignedOff',
        outsource_state=CASE WHEN oi.execution_route='OUTSOURCE' THEN 'Signed'::public.outsource_item_state_enum ELSE oi.outsource_state END,
        updated_at=now()
    FROM public.clinical_report_group_items gi
    WHERE gi.report_group_id=g.id AND gi.order_item_id=oi.id;

    UPDATE public.test_results tr
    SET status='SignedOff',
        signed_off_by=auth.uid(),
        signed_off_name=coalesce(signer.full_name, performer.full_name),
        signed_off_at=now(),
        updated_at=now()
    FROM public.clinical_report_group_items gi
    WHERE gi.report_group_id=g.id AND gi.order_item_id=tr.order_item_id;

    UPDATE public.clinical_report_groups
    SET lifecycle_state=CASE WHEN is_amendment THEN 'Amended' ELSE 'Signed' END,
        updated_at=now(),
        row_version=row_version+1
    WHERE id=g.id;

    UPDATE public.clinical_orders
    SET status=public.derive_order_reporting_state(o.id),
        updated_at=now()
    WHERE id=o.id;

    INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES (
        auth.uid(),
        performer.full_name,
        case when is_amendment then 'REPORT_GROUP_AMENDMENT_SIGNED' else 'REPORT_GROUP_SIGNED' end,
        'ClinicalReportGroup',
        g.id::text,
        jsonb_build_object('report_id', report_id, 'order_id', o.id, 'group_key', g.group_key, 'version', version_no, 'integrity_hash', integrity)
    );

    RETURN jsonb_build_object(
        'success', true,
        'report_id', report_id,
        'report_group_id', g.id,
        'report_group_key', g.group_key,
        'report_number', report_no,
        'version', version_no,
        'integrity_hash', integrity,
        'snapshot', snapshot,
        'order_reporting_state', public.derive_order_reporting_state(o.id)
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.sign_report_group TO authenticated, service_role;
