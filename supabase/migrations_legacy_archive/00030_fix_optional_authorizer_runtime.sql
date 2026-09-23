-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Migration 00030: Fix Optional Authorizer Runtime Record Dereference
-- Ensures calculated parameters (IBIL, GLOB, AG_RATIO, VLDL) are recomputed
-- and validated server-side from authoritative source values before sign-off.
-- Preserves exact existing function signature and JSONB return type.
-- ============================================================================

-- 1. Server-side function to recalculate and validate derived parameters for an order item
CREATE OR REPLACE FUNCTION public.recompute_order_item_calculated_results(
    p_order_item_id UUID
)
RETURNS VOID AS $$
DECLARE
    v_rec RECORD;
    v_val_map JSONB := '{}'::JSONB;
    v_tbil NUMERIC;
    v_dbil NUMERIC;
    v_tp NUMERIC;
    v_alb NUMERIC;
    v_glob NUMERIC;
    v_trig NUMERIC;
    v_calc_num NUMERIC;
    v_calc_disp TEXT;
BEGIN
    -- Build map of numeric values
    FOR v_rec IN (
        SELECT p.code, tr.numeric_value
        FROM public.test_results tr
        JOIN public.parameters p ON tr.parameter_id = p.id
        WHERE tr.order_item_id = p_order_item_id
          AND tr.numeric_value IS NOT NULL
    ) LOOP
        v_val_map := jsonb_set(v_val_map, ARRAY[v_rec.code], to_jsonb(v_rec.numeric_value));
    END LOOP;

    -- Extract common biochemistry values
    v_tbil := (v_val_map->>'TBIL')::NUMERIC;
    v_dbil := (v_val_map->>'DBIL')::NUMERIC;
    v_tp   := (v_val_map->>'TP')::NUMERIC;
    v_alb  := (v_val_map->>'ALB')::NUMERIC;
    v_trig := (v_val_map->>'TRIG')::NUMERIC;

    -- 1. Recalculate IBIL (Indirect Bilirubin = TBIL - DBIL)
    IF v_tbil IS NOT NULL AND v_dbil IS NOT NULL THEN
        v_calc_num := ROUND(v_tbil - v_dbil, 2);
        v_calc_disp := TO_CHAR(v_calc_num, 'FM999990.00');

        UPDATE public.test_results tr
        SET numeric_value = v_calc_num,
            display_value = v_calc_disp
        FROM public.parameters p
        WHERE tr.parameter_id = p.id
          AND tr.order_item_id = p_order_item_id
          AND p.code = 'IBIL'
          AND p.value_type = 'Calculated';
    END IF;

    -- 2. Recalculate GLOB (Globulin = TP - ALB)
    IF v_tp IS NOT NULL AND v_alb IS NOT NULL THEN
        v_glob := ROUND(v_tp - v_alb, 2);
        v_calc_disp := TO_CHAR(v_glob, 'FM999990.00');

        UPDATE public.test_results tr
        SET numeric_value = v_glob,
            display_value = v_calc_disp
        FROM public.parameters p
        WHERE tr.parameter_id = p.id
          AND tr.order_item_id = p_order_item_id
          AND p.code = 'GLOB'
          AND p.value_type = 'Calculated';

        -- Update local val map for downstream A:G ratio
        v_val_map := jsonb_set(v_val_map, '{GLOB}', to_jsonb(v_glob));
    ELSE
        SELECT numeric_value INTO v_glob
        FROM public.test_results tr
        JOIN public.parameters p ON tr.parameter_id = p.id
        WHERE tr.order_item_id = p_order_item_id AND p.code = 'GLOB';
    END IF;

    -- 3. Recalculate AG_RATIO (A:G Ratio = ALB / GLOB)
    IF v_alb IS NOT NULL AND v_glob IS NOT NULL THEN
        IF v_glob = 0 THEN
            UPDATE public.test_results tr
            SET numeric_value = NULL,
                display_value = 'Calculation Error'
            FROM public.parameters p
            WHERE tr.parameter_id = p.id
              AND tr.order_item_id = p_order_item_id
              AND p.code = 'AG_RATIO'
              AND p.value_type = 'Calculated';
        ELSE
            v_calc_num := ROUND(v_alb / v_glob, 2);
            v_calc_disp := TO_CHAR(v_calc_num, 'FM999990.00');

            UPDATE public.test_results tr
            SET numeric_value = v_calc_num,
                display_value = v_calc_disp
            FROM public.parameters p
            WHERE tr.parameter_id = p.id
              AND tr.order_item_id = p_order_item_id
              AND p.code = 'AG_RATIO'
              AND p.value_type = 'Calculated';
        END IF;
    END IF;

    -- 4. Recalculate VLDL (VLDL Cholesterol = TRIG / 5)
    IF v_trig IS NOT NULL THEN
        v_calc_num := ROUND(v_trig / 5.0, 2);
        v_calc_disp := TO_CHAR(v_calc_num, 'FM999990.00');

        UPDATE public.test_results tr
        SET numeric_value = v_calc_num,
            display_value = v_calc_disp
        FROM public.parameters p
        WHERE tr.parameter_id = p.id
          AND tr.order_item_id = p_order_item_id
          AND p.code = 'VLDL'
          AND p.value_type = 'Calculated';
    END IF;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 2. Update sign_and_freeze_diagnostic_report to recompute calculations before report snapshot creation
ALTER TABLE public.diagnostic_reports
    ALTER COLUMN verified_by_personnel_name DROP NOT NULL,
    ALTER COLUMN signed_by_personnel_name DROP NOT NULL;

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
    v_signed_by_id public.reporting_personnel.id%TYPE := NULL;
    v_signed_by_name public.reporting_personnel.full_name%TYPE := NULL;
    v_signed_by_qualification public.reporting_personnel.qualification%TYPE := NULL;
    v_signed_by_professional_type public.reporting_personnel.professional_type%TYPE := NULL;
    v_signed_by_specialization public.reporting_personnel.specialization%TYPE := NULL;
    v_signed_by_registration_council public.reporting_personnel.registration_council%TYPE := NULL;
    v_signed_by_registration_number public.reporting_personnel.registration_number%TYPE := NULL;
    v_signed_by_signature_url public.reporting_personnel.signature_url%TYPE := NULL;
    v_signed_by_is_active public.reporting_personnel.is_active%TYPE := NULL;
    v_signed_by_can_sign_reports public.reporting_personnel.can_sign_reports%TYPE := NULL;
    v_authorized_snapshot JSONB := NULL;
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

    -- A separate authorizing identity is optional. When supplied, it must
    -- still satisfy the existing active/authorized personnel gates.
    IF p_signed_by_id IS NOT NULL THEN
        IF p_signed_by_id = p_performed_by_id THEN
            RAISE EXCEPTION 'Authorizing signatory must be distinct from performed-by reporting personnel.';
        END IF;

        SELECT
            id,
            full_name,
            qualification,
            professional_type,
            specialization,
            registration_council,
            registration_number,
            signature_url,
            is_active,
            can_sign_reports
        INTO
            v_signed_by_id,
            v_signed_by_name,
            v_signed_by_qualification,
            v_signed_by_professional_type,
            v_signed_by_specialization,
            v_signed_by_registration_council,
            v_signed_by_registration_number,
            v_signed_by_signature_url,
            v_signed_by_is_active,
            v_signed_by_can_sign_reports
        FROM public.reporting_personnel
        WHERE id = p_signed_by_id;

        IF v_signed_by_id IS NULL THEN
            RAISE EXCEPTION 'Authorizing signatory ID % does not exist.', p_signed_by_id;
        END IF;

        IF v_signed_by_is_active IS NOT TRUE THEN
            RAISE EXCEPTION 'Signatory % is currently marked inactive.', v_signed_by_name;
        END IF;

        IF v_signed_by_can_sign_reports IS NOT TRUE THEN
            RAISE EXCEPTION 'Signatory % is not clinically authorized to sign reports (can_sign_reports = FALSE).', v_signed_by_name;
        END IF;

        v_authorized_snapshot := jsonb_build_object(
            'id', v_signed_by_id,
            'full_name', v_signed_by_name,
            'qualification', v_signed_by_qualification,
            'professional_type', v_signed_by_professional_type,
            'specialization', v_signed_by_specialization,
            'registration_council', v_signed_by_registration_council,
            'registration_number', v_signed_by_registration_number,
            'signature_url', v_signed_by_signature_url
        );
    END IF;

    -- Validate Performed By signatory
    SELECT * INTO v_performed_by
    FROM public.reporting_personnel
    WHERE id = p_performed_by_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reporting personnel (performed by) ID % does not exist.', p_performed_by_id;
    END IF;

    IF v_performed_by.is_active IS NOT TRUE THEN
        RAISE EXCEPTION 'Reporting personnel % is currently marked inactive.', v_performed_by.full_name;
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
    -- 3. SERVER-SIDE CALCULATION RECOMPUTATION & FETCH FULL METADATA
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
        -- Execute authoritative server-side recalculation of calculated parameters
        PERFORM public.recompute_order_item_calculated_results(v_item.id);

        v_results := '[]'::JSONB;

        FOR v_param IN (
            SELECT tr.*, p.code as param_code, p.display_order, p.formula
            FROM public.test_results tr
            JOIN public.parameters p ON tr.parameter_id = p.id
            WHERE tr.order_item_id = v_item.id
            ORDER BY p.display_order ASC
        ) LOOP
            -- Check for mathematical calculation error
            IF v_param.value_type = 'Calculated' AND v_param.display_value = 'Calculation Error' THEN
                RAISE EXCEPTION 'Cannot sign report: Calculated parameter % has a mathematical error (e.g. divide by zero)', v_param.parameter_name;
            END IF;

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
            'authorized_by', v_authorized_snapshot
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
    -- 5. DETERMINISTIC SHA-256 INTEGRITY HASH (Using schema-qualified pgcrypto)
    -- ------------------------------------------------------------------------
    v_hash_input := v_order.order_number || '|v' || v_version::TEXT || '|' || v_snapshot::TEXT;
    v_integrity_hash := ENCODE(
        extensions.digest(
            CONVERT_TO(v_hash_input, 'UTF8'),
            'sha256'
        ),
        'hex'
    );

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
        v_signed_by_id,
        v_signed_by_name,
        v_signed_by_id,
        v_signed_by_name,
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
        signed_off_name = v_signed_by_name,
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
        v_performed_by.full_name,
        CASE WHEN v_is_amendment THEN 'REPORT_AMENDMENT_SIGNED' ELSE 'REPORT_SIGNED' END,
        'DiagnosticReport',
        v_report_number,
        jsonb_build_object(
            'report_id', v_report_id,
            'order_id', p_order_id,
            'order_number', v_order.order_number,
            'version', v_version,
            'integrity_hash', v_integrity_hash,
            'signed_by_personnel', v_signed_by_name,
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

-- The insert-time guard continues to reject inactive performers and invalid
-- supplied signatories, while accurately allowing no separate authorizer.
CREATE OR REPLACE FUNCTION public.guard_diagnostic_report_personnel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.reporting_personnel
        WHERE id = NEW.performed_by_personnel_id AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'Performed-by reporting personnel must be active.';
    END IF;

    IF NEW.signed_by_personnel_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.reporting_personnel
        WHERE id = NEW.signed_by_personnel_id
          AND is_active = TRUE
          AND can_sign_reports = TRUE
    ) THEN
        RAISE EXCEPTION 'Authorizing reporting personnel must be active and eligible to sign.';
    END IF;

    RETURN NEW;
END;
$$;
