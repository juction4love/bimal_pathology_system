-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Migration 00005: Final Reporting, Authorized Sign-Off, PDF Storage & Amendments
-- Production-hardened, forward-only, security definer search_path protected
-- ============================================================================

CREATE SEQUENCE IF NOT EXISTS report_seq START 1;

-- Ensure storage bucket exists for diagnostic-reports (private)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'diagnostic-reports',
    'diagnostic-reports',
    FALSE,
    10485760, -- 10MB limit
    ARRAY['application/pdf']::text[]
)
ON CONFLICT (id) DO UPDATE SET
    public = FALSE,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['application/pdf']::text[];

-- Storage RLS Policies
CREATE POLICY "Authenticated staff can upload signed diagnostic reports"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'diagnostic-reports' AND
    (public.has_permission('can_sign_reports') OR public.has_permission('can_verify_results') OR public.is_super_admin())
);

CREATE POLICY "Authorized staff can download diagnostic reports"
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'diagnostic-reports' AND
    (public.has_permission('can_print_reports') OR public.has_permission('can_sign_reports') OR public.has_permission('can_verify_results') OR public.is_super_admin())
);

CREATE POLICY "Deny direct storage updates and deletions on signed reports"
ON storage.objects FOR UPDATE TO authenticated
USING (FALSE);

CREATE POLICY "Deny storage deletions on signed reports"
ON storage.objects FOR DELETE TO authenticated
USING (FALSE);

-- ============================================================================
-- 1. AUTHORITATIVE CLINICAL ORDER READINESS FUNCTION
-- ============================================================================
CREATE OR REPLACE FUNCTION public.check_order_report_readiness(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_reportable_count INT := 0;
    v_verified_count INT := 0;
    v_unverified_items JSONB := '[]'::JSONB;
    v_unack_critical_count INT := 0;
    v_unack_critical_items JSONB := '[]'::JSONB;
    v_is_ready BOOLEAN := FALSE;
    v_item RECORD;
    v_res RECORD;
BEGIN
    -- 1. Check all reportable items for this clinical order
    FOR v_item IN (
        SELECT coi.id, coi.test_name, coi.department, coi.reporting_type, coi.status
        FROM public.clinical_order_items coi
        WHERE coi.order_id = p_order_id
          AND coi.reporting_type IN ('InHouse', 'OutsourceWithBimalReport')
    ) LOOP
        v_reportable_count := v_reportable_count + 1;
        
        IF v_item.status IN ('Verified', 'SignedOff') THEN
            v_verified_count := v_verified_count + 1;
        ELSE
            v_unverified_items := v_unverified_items || jsonb_build_object(
                'order_item_id', v_item.id,
                'test_name', v_item.test_name,
                'department', v_item.department,
                'status', v_item.status
            );
        END IF;
    END LOOP;

    -- 2. Check for any unacknowledged critical panic values
    FOR v_res IN (
        SELECT tr.id, tr.parameter_name, tr.display_value, tr.unit, tr.flag, tr.critical_acknowledged, coi.test_name
        FROM public.test_results tr
        JOIN public.clinical_order_items coi ON tr.order_item_id = coi.id
        WHERE coi.order_id = p_order_id
          AND (tr.is_critical = TRUE OR tr.flag IN ('CriticalLow', 'CriticalHigh'))
          AND tr.critical_acknowledged = FALSE
    ) LOOP
        v_unack_critical_count := v_unack_critical_count + 1;
        v_unack_critical_items := v_unack_critical_items || jsonb_build_object(
            'result_id', v_res.id,
            'test_name', v_res.test_name,
            'parameter_name', v_res.parameter_name,
            'display_value', v_res.display_value,
            'unit', v_res.unit,
            'flag', v_res.flag
        );
    END LOOP;

    -- Ready condition: at least 1 reportable item, ALL reportable items verified/signed off, 0 unack criticals
    IF v_reportable_count > 0 AND v_verified_count = v_reportable_count AND v_unack_critical_count = 0 THEN
        v_is_ready := TRUE;
    ELSE
        v_is_ready := FALSE;
    END IF;

    RETURN jsonb_build_object(
        'is_ready', v_is_ready,
        'reportable_count', v_reportable_count,
        'verified_count', v_verified_count,
        'unverified_count', (v_reportable_count - v_verified_count),
        'unverified_items', v_unverified_items,
        'unacknowledged_critical_count', v_unack_critical_count,
        'unacknowledged_critical_items', v_unack_critical_items
    );
END;
$$;

REVOKE ALL ON FUNCTION public.check_order_report_readiness(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_order_report_readiness(UUID) TO authenticated;

-- ============================================================================
-- 2. CRITICAL VALUE CLINICAL ACKNOWLEDGMENT RPC
-- ============================================================================
CREATE OR REPLACE FUNCTION public.acknowledge_critical_result(
    p_result_id UUID,
    p_notified_person VARCHAR(255),
    p_notification_method VARCHAR(100),
    p_notification_comment TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor_name VARCHAR(255);
    v_res RECORD;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    IF NOT (public.has_permission('can_acknowledge_critical') OR public.has_permission('can_verify_results') OR public.has_permission('can_sign_reports')) THEN
        RAISE EXCEPTION 'Access Denied: Missing can_acknowledge_critical permission.';
    END IF;

    IF TRIM(COALESCE(p_notified_person, '')) = '' THEN
        RAISE EXCEPTION 'Notified person (clinician/nurse) is mandatory.';
    END IF;

    SELECT full_name INTO v_actor_name FROM public.user_profiles WHERE id = auth.uid();
    IF v_actor_name IS NULL THEN
        v_actor_name := 'Authorized Staff';
    END IF;

    SELECT tr.*, coi.test_name, coi.order_id INTO v_res
    FROM public.test_results tr
    JOIN public.clinical_order_items coi ON tr.order_item_id = coi.id
    WHERE tr.id = p_result_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Result record % not found.', p_result_id;
    END IF;

    UPDATE public.test_results
    SET critical_acknowledged = TRUE,
        critical_acknowledged_by = auth.uid(),
        critical_acknowledged_at = NOW(),
        updated_at = NOW()
    WHERE id = p_result_id;

    -- Append to audit log
    INSERT INTO public.audit_logs (
        user_id,
        user_name,
        action,
        entity_type,
        entity_id,
        new_data
    ) VALUES (
        auth.uid(),
        v_actor_name,
        'CRITICAL_VALUE_ACKNOWLEDGED',
        'TestResult',
        p_result_id::TEXT,
        jsonb_build_object(
            'parameter_name', v_res.parameter_name,
            'test_name', v_res.test_name,
            'flag', v_res.flag,
            'display_value', v_res.display_value,
            'notified_person', p_notified_person,
            'notification_method', p_notification_method,
            'notification_comment', p_notification_comment
        )
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'result_id', p_result_id,
        'critical_acknowledged', TRUE,
        'acknowledged_at', NOW()
    );
END;
$$;

REVOKE ALL ON FUNCTION public.acknowledge_critical_result(UUID, VARCHAR, VARCHAR, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_critical_result(UUID, VARCHAR, VARCHAR, TEXT) TO authenticated;

-- ============================================================================
-- 3. ATOMIC REPORT SIGN-OFF & IMMUTABLE SNAPSHOT CREATION RPC
-- ============================================================================
CREATE OR REPLACE FUNCTION public.sign_and_freeze_diagnostic_report(
    p_order_id UUID,
    p_performed_by_id UUID,
    p_signed_by_id UUID,
    p_amendment_reason TEXT DEFAULT NULL,
    p_amended_from_report_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order RECORD;
    v_bill RECORD;
    v_patient RECORD;
    v_performed_by RECORD;
    v_signed_by RECORD;
    v_readiness JSONB;
    v_version INT := 1;
    v_is_amendment BOOLEAN := FALSE;
    v_parent_report RECORD;
    v_report_number VARCHAR(50);
    v_current_year VARCHAR(4);
    v_report_id UUID;
    v_snapshot JSONB;
    v_investigations JSONB := '[]'::JSONB;
    v_item RECORD;
    v_results JSONB;
    v_param RECORD;
    v_hash_input TEXT;
    v_integrity_hash VARCHAR(128);
    v_sample_dates JSONB;
BEGIN
    -- ------------------------------------------------------------------------
    -- 0. CALLER & SIGNATORY CLINICAL AUTHORITY VALIDATION
    -- ------------------------------------------------------------------------
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    IF NOT public.has_permission('can_sign_reports') THEN
        RAISE EXCEPTION 'Access Denied: Caller does not possess can_sign_reports permission.';
    END IF;

    -- Validate Signed By signatory record in reporting_personnel
    SELECT * INTO v_signed_by
    FROM public.reporting_personnel
    WHERE id = p_signed_by_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Authorizing signatory ID % does not exist.', p_signed_by_id;
    END IF;

    IF v_signed_by.is_active IS NOT TRUE THEN
        RAISE EXCEPTION 'Signatory % is currently marked inactive.', v_signed_by.full_name;
    END IF;

    IF v_signed_by.can_sign_reports IS NOT TRUE THEN
        RAISE EXCEPTION 'Signatory % is not clinically authorized to sign reports (can_sign_reports = FALSE).', v_signed_by.full_name;
    END IF;

    -- Validate Performed By signatory
    SELECT * INTO v_performed_by
    FROM public.reporting_personnel
    WHERE id = p_performed_by_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reporting personnel (performed by) ID % does not exist.', p_performed_by_id;
    END IF;

    -- ------------------------------------------------------------------------
    -- 1. ORDER-LEVEL READINESS GATE (Must be 100% verified, 0 unack criticals)
    -- ------------------------------------------------------------------------
    v_readiness := public.check_order_report_readiness(p_order_id);

    IF NOT (v_readiness->>'is_ready')::BOOLEAN THEN
        IF (v_readiness->>'unacknowledged_critical_count')::INT > 0 THEN
            RAISE EXCEPTION 'Cannot sign report: Order has % unacknowledged critical panic value(s). Immediate clinical documentation required.', v_readiness->>'unacknowledged_critical_count';
        ELSE
            RAISE EXCEPTION 'Cannot sign report: Clinical order is not ready (% unverified investigation(s) remaining).', v_readiness->>'unverified_count';
        END IF;
    END IF;

    -- ------------------------------------------------------------------------
    -- 2. AMENDMENT VS INITIAL VERSION RESOLUTION
    -- ------------------------------------------------------------------------
    IF p_amended_from_report_id IS NOT NULL THEN
        IF NOT public.has_permission('can_amend_reports') THEN
            RAISE EXCEPTION 'Access Denied: Missing can_amend_reports permission for amendment.';
        END IF;

        IF TRIM(COALESCE(p_amendment_reason, '')) = '' THEN
            RAISE EXCEPTION 'Amendment reason is mandatory when issuing report revision.';
        END IF;

        SELECT * INTO v_parent_report
        FROM public.diagnostic_reports
        WHERE id = p_amended_from_report_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Parent report % not found for amendment.', p_amended_from_report_id;
        END IF;

        v_version := v_parent_report.version + 1;
        v_is_amendment := TRUE;

        -- Mark parent report as Amended
        UPDATE public.diagnostic_reports
        SET status = 'Amended', updated_at = NOW()
        WHERE id = p_amended_from_report_id;
    ELSE
        v_version := 1;
        v_is_amendment := FALSE;
    END IF;

    -- ------------------------------------------------------------------------
    -- 3. FETCH FULL METADATA FOR IMMUTABLE SNAPSHOT
    -- ------------------------------------------------------------------------
    SELECT * INTO v_order FROM public.clinical_orders WHERE id = p_order_id;
    SELECT * INTO v_bill FROM public.bills WHERE id = v_order.bill_id;
    SELECT * INTO v_patient FROM public.patients WHERE id = v_order.patient_id;

    -- Collect sample collection/reception timestamps
    SELECT jsonb_build_object(
        'collected_at', MIN(collected_at),
        'received_at', MAX(received_at)
    ) INTO v_sample_dates
    FROM public.samples
    WHERE order_id = p_order_id;

    -- Build investigations array (Reportable items only)
    FOR v_item IN (
        SELECT coi.*, t.method, t.interpretation_template
        FROM public.clinical_order_items coi
        JOIN public.tests t ON coi.test_id = t.id
        WHERE coi.order_id = p_order_id
          AND coi.reporting_type IN ('InHouse', 'OutsourceWithBimalReport')
        ORDER BY coi.created_at ASC
    ) LOOP
        v_results := '[]'::JSONB;

        FOR v_param IN (
            SELECT tr.*, p.code as param_code, p.display_order, p.formula
            FROM public.test_results tr
            JOIN public.parameters p ON tr.parameter_id = p.id
            WHERE tr.order_item_id = v_item.id
            ORDER BY p.display_order ASC
        ) LOOP
            v_results := v_results || jsonb_build_object(
                'parameter_id', v_param.parameter_id,
                'code', v_param.param_code,
                'name', v_param.parameter_name,
                'value_type', v_param.value_type,
                'display_value', v_param.display_value,
                'numeric_value', v_param.numeric_value,
                'unit', v_param.unit,
                'formula', v_param.formula,
                'flag', v_param.flag,
                'is_critical', v_param.is_critical,
                'reference_range', COALESCE(
                    CASE 
                        WHEN v_param.normal_min IS NOT NULL AND v_param.normal_max IS NOT NULL 
                        THEN v_param.normal_min::TEXT || ' - ' || v_param.normal_max::TEXT 
                        ELSE NULL 
                    END,
                    v_param.normal_range_text,
                    'Standard'
                ),
                'normal_min', v_param.normal_min,
                'normal_max', v_param.normal_max,
                'critical_low', v_param.critical_low,
                'critical_high', v_param.critical_high
            );
        END LOOP;

        v_investigations := v_investigations || jsonb_build_object(
            'order_item_id', v_item.id,
            'test_id', v_item.test_id,
            'test_name', v_item.test_name,
            'department', v_item.department,
            'reporting_type', v_item.reporting_type,
            'outsource_lab_name', v_item.outsource_lab_name,
            'method', v_item.method,
            'interpretation_template', v_item.interpretation_template,
            'specimen_type', v_item.specimen_type,
            'container_type', v_item.container_type,
            'results', v_results
        );
    END LOOP;

    -- ------------------------------------------------------------------------
    -- 4. CONSTRUCT FROZEN IMMUTABLE SNAPSHOT
    -- ------------------------------------------------------------------------
    v_snapshot := jsonb_build_object(
        'organization', jsonb_build_object(
            'name_en', 'BIMAL PATHOLOGY & DIAGNOSTIC CENTER',
            'name_ne', 'बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर',
            'address_en', 'Bharatpur-7, Chitwan, Nepal',
            'address_ne', 'भरतपुर-७, चितवन, नेपाल',
            'reg_no', '7-1496',
            'pan_no', '302481477',
            'phone', '056-593288'
        ),
        'patient', jsonb_build_object(
            'uhid', v_patient.uhid,
            'full_name', v_patient.full_name,
            'title', v_patient.title,
            'mobile', v_patient.mobile,
            'gender', v_patient.gender,
            'dob', v_patient.dob,
            'age_years', v_patient.age_years,
            'age_months', v_patient.age_months,
            'age_days', v_patient.age_days,
            'address', v_patient.address
        ),
        'order', jsonb_build_object(
            'order_number', v_order.order_number,
            'bill_number', v_bill.bill_number,
            'registered_date_ad', v_order.order_date_ad,
            'registered_date_bs', v_order.order_date_bs,
            'collected_at', v_sample_dates->>'collected_at',
            'received_at', v_sample_dates->>'received_at',
            'reported_at', NOW(),
            'referring_doctor_name', COALESCE(v_bill.referring_doctor_name_snapshot, 'Self / Walk-in')
        ),
        'signatories', jsonb_build_object(
            'performed_by', jsonb_build_object(
                'id', v_performed_by.id,
                'full_name', v_performed_by.full_name,
                'qualification', v_performed_by.qualification,
                'professional_type', v_performed_by.professional_type,
                'registration_council', v_performed_by.registration_council,
                'registration_number', v_performed_by.registration_number,
                'signature_url', v_performed_by.signature_url
            ),
            'authorized_by', jsonb_build_object(
                'id', v_signed_by.id,
                'full_name', v_signed_by.full_name,
                'qualification', v_signed_by.qualification,
                'professional_type', v_signed_by.professional_type,
                'specialization', v_signed_by.specialization,
                'registration_council', v_signed_by.registration_council,
                'registration_number', v_signed_by.registration_number,
                'signature_url', v_signed_by.signature_url
            )
        ),
        'investigations', v_investigations,
        'meta', jsonb_build_object(
            'version', v_version,
            'is_amendment', v_is_amendment,
            'amendment_reason', p_amendment_reason,
            'amended_from_report_id', p_amended_from_report_id,
            'signed_at', NOW(),
            'signed_by_user_id', auth.uid()
        )
    );

    -- ------------------------------------------------------------------------
    -- 5. DETERMINISTIC SHA-256 INTEGRITY HASH
    -- ------------------------------------------------------------------------
    v_hash_input := v_order.order_number || '|v' || v_version::TEXT || '|' || v_snapshot::TEXT;
    v_integrity_hash := ENCODE(DIGEST(v_hash_input, 'sha256'), 'hex');

    -- ------------------------------------------------------------------------
    -- 6. INSERT DIAGNOSTIC REPORT
    -- ------------------------------------------------------------------------
    v_current_year := TO_CHAR(CURRENT_DATE, 'YYYY');
    v_report_number := 'REP-' || v_current_year || '-' || LPAD(NEXTVAL('report_seq')::TEXT, 5, '0');

    INSERT INTO public.diagnostic_reports (
        order_id,
        patient_id,
        report_number,
        version,
        is_amendment,
        amendment_reason,
        amended_from_report_id,
        status,
        integrity_hash,
        performed_by_personnel_id,
        performed_by_personnel_name,
        verified_by_personnel_id,
        verified_by_personnel_name,
        signed_by_personnel_id,
        signed_by_personnel_name,
        signed_at,
        pdf_storage_path,
        clinical_snapshot_json
    ) VALUES (
        p_order_id,
        v_order.patient_id,
        v_report_number,
        v_version,
        v_is_amendment,
        p_amendment_reason,
        p_amended_from_report_id,
        'SignedOff',
        v_integrity_hash,
        v_performed_by.id,
        v_performed_by.full_name,
        v_signed_by.id,
        v_signed_by.full_name,
        v_signed_by.id,
        v_signed_by.full_name,
        NOW(),
        'reports/' || p_order_id::TEXT || '/v' || v_version::TEXT || '/report.pdf',
        v_snapshot
    ) RETURNING id INTO v_report_id;

    -- ------------------------------------------------------------------------
    -- 7. UPDATE ORDER & RESULTS STATUS TO SIGNED OFF
    -- ------------------------------------------------------------------------
    UPDATE public.clinical_order_items
    SET status = 'SignedOff', updated_at = NOW()
    WHERE order_id = p_order_id;

    UPDATE public.test_results
    SET status = 'SignedOff',
        signed_off_by = auth.uid(),
        signed_off_name = v_signed_by.full_name,
        signed_off_at = NOW(),
        updated_at = NOW()
    WHERE order_item_id IN (
        SELECT id FROM public.clinical_order_items WHERE order_id = p_order_id
    );

    UPDATE public.clinical_orders
    SET status = 'SignedOff', updated_at = NOW()
    WHERE id = p_order_id;

    -- ------------------------------------------------------------------------
    -- 8. AUDIT LOGGING
    -- ------------------------------------------------------------------------
    INSERT INTO public.audit_logs (
        user_id,
        user_name,
        action,
        entity_type,
        entity_id,
        new_data
    ) VALUES (
        auth.uid(),
        v_signed_by.full_name,
        CASE WHEN v_is_amendment THEN 'REPORT_AMENDMENT_SIGNED' ELSE 'REPORT_SIGNED' END,
        'DiagnosticReport',
        v_report_number,
        jsonb_build_object(
            'report_id', v_report_id,
            'order_id', p_order_id,
            'order_number', v_order.order_number,
            'version', v_version,
            'integrity_hash', v_integrity_hash,
            'signed_by_personnel', v_signed_by.full_name,
            'performed_by_personnel', v_performed_by.full_name,
            'is_amendment', v_is_amendment,
            'amendment_reason', p_amendment_reason
        )
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'report_id', v_report_id,
        'report_number', v_report_number,
        'version', v_version,
        'integrity_hash', v_integrity_hash,
        'storage_path', 'reports/' || p_order_id::TEXT || '/v' || v_version::TEXT || '/report.pdf',
        'is_amendment', v_is_amendment,
        'snapshot', v_snapshot
    );
END;
$$;

REVOKE ALL ON FUNCTION public.sign_and_freeze_diagnostic_report(UUID, UUID, UUID, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sign_and_freeze_diagnostic_report(UUID, UUID, UUID, TEXT, UUID) TO authenticated;

-- ============================================================================
-- 4. REPORT ATTACH ARTIFACT HASH RPC
-- ============================================================================
CREATE OR REPLACE FUNCTION public.attach_report_artifact(
    p_report_id UUID,
    p_storage_path TEXT,
    p_sha256_hash VARCHAR(128)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    IF NOT (public.has_permission('can_sign_reports') OR public.has_permission('can_verify_results') OR public.is_super_admin()) THEN
        RAISE EXCEPTION 'Access Denied: Missing permissions to attach report artifact.';
    END IF;

    UPDATE public.diagnostic_reports
    SET pdf_storage_path = p_storage_path,
        integrity_hash = p_sha256_hash,
        updated_at = NOW()
    WHERE id = p_report_id;

    RETURN jsonb_build_object('success', TRUE, 'report_id', p_report_id);
END;
$$;

REVOKE ALL ON FUNCTION public.attach_report_artifact(UUID, TEXT, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.attach_report_artifact(UUID, TEXT, VARCHAR) TO authenticated;
