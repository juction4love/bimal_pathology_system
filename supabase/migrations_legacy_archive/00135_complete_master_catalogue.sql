-- Migration: 00135_rebuild_complete_catalogue_reporting.sql
-- Description: Clean rebuild and completion of reporting parameters, profile linkages, and result entry resolution for all 1,139 active catalogue investigations.
-- Safe, idempotent, and non-destructive to business and transaction data.

BEGIN;

-- ============================================================================
-- 1. Clean Archive of any Residual Dummy Structural Panel Rows
-- ============================================================================
UPDATE public.parameters
SET is_active = FALSE,
    lifecycle_status = 'Archived',
    updated_at = NOW()
WHERE is_active = TRUE
  AND (
    LOWER(COALESCE(unit, '')) = 'panel'
    OR LOWER(COALESCE(value_type::text, '')) IN ('panel', 'profile')
  );

-- ============================================================================
-- 2. Server-authoritative Result Entry Update for Direct and Profile Components
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

-- ============================================================================
-- 3. Link Panel Components for Profile Investigations (PRO-0010 to PRO-0025)
-- ============================================================================
DO $$
DECLARE
    v_panel_id UUID;
    v_comp_id UUID;
BEGIN
    -- PRO-0010: Fertility Female Profile
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0010';
    IF v_panel_id IS NOT NULL THEN
        DELETE FROM public.catalogue_panel_components WHERE panel_test_id = v_panel_id OR panel_id = v_panel_id;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0027'; -- FSH
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0028'; -- LH
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0029'; -- Estradiol (E2)
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0025'; -- Prolactin
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0001'; -- TSH
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 5, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0037'; -- AMH
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 6, TRUE, 'Measured'); END IF;
    END IF;

    -- PRO-0011: Fertility Male Profile
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0011';
    IF v_panel_id IS NOT NULL THEN
        DELETE FROM public.catalogue_panel_components WHERE panel_test_id = v_panel_id OR panel_id = v_panel_id;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0031'; -- Testosterone, Total
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0027'; -- FSH
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0028'; -- LH
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0025'; -- Prolactin
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured'); END IF;
    END IF;

    -- PRO-0012: PCOS Profile
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0012';
    IF v_panel_id IS NOT NULL THEN
        DELETE FROM public.catalogue_panel_components WHERE panel_test_id = v_panel_id OR panel_id = v_panel_id;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0028'; -- LH
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0027'; -- FSH
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0031'; -- Testosterone, Total
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0016'; -- DHEA-S
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0036'; -- 17-OH Progesterone
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 5, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0001'; -- TSH
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 6, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0025'; -- Prolactin
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 7, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0041'; -- Insulin, Fasting
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 8, TRUE, 'Measured'); END IF;
    END IF;

    -- PRO-0013: Anemia Profile
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0013';
    IF v_panel_id IS NOT NULL THEN
        DELETE FROM public.catalogue_panel_components WHERE panel_test_id = v_panel_id OR panel_id = v_panel_id;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'HEM-0001'; -- CBC
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'HEM-0023'; -- Reticulocyte Count
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0050'; -- Ferritin
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0045'; -- Iron
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0046'; -- TIBC
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 5, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0051'; -- Vitamin B12
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 6, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0052'; -- Folate
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 7, TRUE, 'Measured'); END IF;
    END IF;

    -- PRO-0015: Thrombophilia Profile
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0015';
    IF v_panel_id IS NOT NULL THEN
        DELETE FROM public.catalogue_panel_components WHERE panel_test_id = v_panel_id OR panel_id = v_panel_id;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'COA-0019'; -- Protein C Activity
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'COA-0020'; -- Protein S Activity
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'COA-0021'; -- Antithrombin III Activity
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'COA-0022'; -- Lupus Anticoagulant Screen
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'GEN-0024'; -- Factor V Leiden Mutation
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 5, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'GEN-0025'; -- Prothrombin G20210A Mutation
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 6, TRUE, 'Measured'); END IF;
    END IF;

    -- PRO-0016: TORCH Profile
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0016';
    IF v_panel_id IS NOT NULL THEN
        DELETE FROM public.catalogue_panel_components WHERE panel_test_id = v_panel_id OR panel_id = v_panel_id;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0030'; -- Toxoplasma IgM
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0031'; -- Toxoplasma IgG
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0032'; -- Rubella IgM
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0033'; -- Rubella IgG
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0034'; -- CMV IgM
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 5, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0035'; -- CMV IgG
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 6, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0036'; -- HSV-1 IgG
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 7, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0037'; -- HSV-2 IgG
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 8, TRUE, 'Measured'); END IF;
    END IF;

    -- PRO-0017: Hepatitis B Profile
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0017';
    IF v_panel_id IS NOT NULL THEN
        DELETE FROM public.catalogue_panel_components WHERE panel_test_id = v_panel_id OR panel_id = v_panel_id;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0004'; -- HBsAg
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0005'; -- Anti-HBs
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0006'; -- Anti-HBc Total
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0007'; -- Anti-HBc IgM
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0008'; -- HBeAg
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 5, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0009'; -- Anti-HBe
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 6, TRUE, 'Measured'); END IF;
    END IF;

    -- PRO-0018: Autoimmune Screen
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0018';
    IF v_panel_id IS NOT NULL THEN
        DELETE FROM public.catalogue_panel_components WHERE panel_test_id = v_panel_id OR panel_id = v_panel_id;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'IMM-0005'; -- ANA by IFA
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'IMM-0007'; -- Anti-dsDNA
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'IMM-0016'; -- C3 Complement
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'IMM-0017'; -- C4 Complement
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured'); END IF;
    END IF;

    -- PRO-0019: Rheumatology Profile
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0019';
    IF v_panel_id IS NOT NULL THEN
        DELETE FROM public.catalogue_panel_components WHERE panel_test_id = v_panel_id OR panel_id = v_panel_id;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'IMM-0002'; -- Rheumatoid Factor (RF)
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'IMM-0004'; -- Anti-CCP
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'IMM-0001'; -- CRP, Quantitative
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'HEM-0027'; -- ESR (Westergren)
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured'); END IF;
    END IF;

    -- PRO-0020: Multiple Myeloma Screen
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0020';
    IF v_panel_id IS NOT NULL THEN
        DELETE FROM public.catalogue_panel_components WHERE panel_test_id = v_panel_id OR panel_id = v_panel_id;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'IMM-0038'; -- Serum Protein Electrophoresis
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'IMM-0039'; -- Immunofixation Electrophoresis, Serum
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'IMM-0040'; -- Free Kappa Light Chain
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'IMM-0041'; -- Free Lambda Light Chain
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'IMM-0042'; -- Kappa/Lambda Ratio
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 5, TRUE, 'Calculated'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'TUM-0019'; -- Beta-2 Microglobulin
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 6, TRUE, 'Measured'); END IF;
    END IF;

    -- PRO-0021: Antenatal Basic Profile
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0021';
    IF v_panel_id IS NOT NULL THEN
        DELETE FROM public.catalogue_panel_components WHERE panel_test_id = v_panel_id OR panel_id = v_panel_id;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'HEM-0001'; -- CBC
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'HEM-0056'; -- Blood Group ABO
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'HEM-0057'; -- Rh(D) Typing
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0002'; -- Glucose, Random
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0004'; -- HBsAg
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 5, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0001'; -- HIV 1/2 Ag/Ab 4th Generation
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 6, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0026'; -- RPR
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 7, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'CLP-0001'; -- Urine Routine Examination (RE/ME)
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 8, TRUE, 'Measured'); END IF;
    END IF;

    -- PRO-0022: Preoperative Basic Profile
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0022';
    IF v_panel_id IS NOT NULL THEN
        DELETE FROM public.catalogue_panel_components WHERE panel_test_id = v_panel_id OR panel_id = v_panel_id;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'HEM-0001'; -- CBC
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'COA-0001'; -- PT / INR
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0010'; -- Creatinine
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0002'; -- Glucose, Random
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'HEM-0056'; -- Blood Group ABO
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 5, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'HEM-0057'; -- Rh(D) Typing
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 6, TRUE, 'Measured'); END IF;
    END IF;

    -- PRO-0023: Fever Panel - Basic
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0023';
    IF v_panel_id IS NOT NULL THEN
        DELETE FROM public.catalogue_panel_components WHERE panel_test_id = v_panel_id OR panel_id = v_panel_id;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'HEM-0001'; -- CBC
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'IMM-0001'; -- CRP, Quantitative
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0015'; -- Dengue NS1 Antigen
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0058'; -- Malaria Pf/Pv Antigen
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'SER-0089'; -- Scrub Typhus (FIA IgM/IgG)
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 5, TRUE, 'Measured'); END IF;
    END IF;

    -- PRO-0024: Hypertension Secondary Screen
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0024';
    IF v_panel_id IS NOT NULL THEN
        DELETE FROM public.catalogue_panel_components WHERE panel_test_id = v_panel_id OR panel_id = v_panel_id;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0037'; -- Sodium
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0038'; -- Potassium
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0010'; -- Creatinine
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0018'; -- Aldosterone
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0020'; -- Direct Renin
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 5, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0021'; -- Aldosterone/Renin Ratio
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 6, TRUE, 'Calculated'); END IF;
    END IF;

    -- PRO-0025: Pituitary Profile
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0025';
    IF v_panel_id IS NOT NULL THEN
        DELETE FROM public.catalogue_panel_components WHERE panel_test_id = v_panel_id OR panel_id = v_panel_id;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0025'; -- Prolactin
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0027'; -- FSH
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0028'; -- LH
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0001'; -- TSH
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0002'; -- Free T4 (FT4)
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 5, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0013'; -- Cortisol, 8 AM
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 6, TRUE, 'Measured'); END IF;
        
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0023'; -- IGF-1
        IF v_comp_id IS NOT NULL THEN INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role) VALUES (v_panel_id, v_panel_id, v_comp_id, 7, TRUE, 'Measured'); END IF;
    END IF;
END $$;

-- ============================================================================
-- 4. Operational Parameters for Active Specialized Tests
-- ============================================================================
DO $$
DECLARE
    v_test_id UUID;
BEGIN
    -- ALG-0049: Food Allergy Panel
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'ALG-0049';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.parameters (test_id, code, name, unit, value_type, display_order, is_mandatory, is_active, lifecycle_status, clinical_configuration_status)
        VALUES 
            (v_test_id, 'ALG-0049-01', 'Food Specific IgE Panel Result', 'kU/L', 'Text', 1, TRUE, TRUE, 'Active', 'Configured'),
            (v_test_id, 'ALG-0049-02', 'Allergen Sensitization Summary', NULL, 'Text', 2, FALSE, TRUE, 'Active', 'Configured')
        ON CONFLICT (test_id, code) DO UPDATE SET
            name = EXCLUDED.name, unit = EXCLUDED.unit, value_type = EXCLUDED.value_type,
            display_order = EXCLUDED.display_order, is_active = TRUE, lifecycle_status = 'Active';
    END IF;

    -- ALG-0050: Inhalant Allergy Panel
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'ALG-0050';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.parameters (test_id, code, name, unit, value_type, display_order, is_mandatory, is_active, lifecycle_status, clinical_configuration_status)
        VALUES 
            (v_test_id, 'ALG-0050-01', 'Inhalant Specific IgE Panel Result', 'kU/L', 'Text', 1, TRUE, TRUE, 'Active', 'Configured'),
            (v_test_id, 'ALG-0050-02', 'Inhalant Sensitization Summary', NULL, 'Text', 2, FALSE, TRUE, 'Active', 'Configured')
        ON CONFLICT (test_id, code) DO UPDATE SET
            name = EXCLUDED.name, unit = EXCLUDED.unit, value_type = EXCLUDED.value_type,
            display_order = EXCLUDED.display_order, is_active = TRUE, lifecycle_status = 'Active';
    END IF;

    -- ALG-0051: Pediatric Allergy Panel
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'ALG-0051';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.parameters (test_id, code, name, unit, value_type, display_order, is_mandatory, is_active, lifecycle_status, clinical_configuration_status)
        VALUES 
            (v_test_id, 'ALG-0051-01', 'Pediatric Specific IgE Panel Result', 'kU/L', 'Text', 1, TRUE, TRUE, 'Active', 'Configured'),
            (v_test_id, 'ALG-0051-02', 'Pediatric Sensitization Summary', NULL, 'Text', 2, FALSE, TRUE, 'Active', 'Configured')
        ON CONFLICT (test_id, code) DO UPDATE SET
            name = EXCLUDED.name, unit = EXCLUDED.unit, value_type = EXCLUDED.value_type,
            display_order = EXCLUDED.display_order, is_active = TRUE, lifecycle_status = 'Active';
    END IF;

    -- ALG-0052: Atopy Screen
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'ALG-0052';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.parameters (test_id, code, name, unit, value_type, display_order, is_mandatory, is_active, lifecycle_status, clinical_configuration_status)
        VALUES 
            (v_test_id, 'ALG-0052-01', 'Atopy Screen Specific IgE', 'kU/L', 'Text', 1, TRUE, TRUE, 'Active', 'Configured'),
            (v_test_id, 'ALG-0052-02', 'Clinical Interpretation', NULL, 'Text', 2, FALSE, TRUE, 'Active', 'Configured')
        ON CONFLICT (test_id, code) DO UPDATE SET
            name = EXCLUDED.name, unit = EXCLUDED.unit, value_type = EXCLUDED.value_type,
            display_order = EXCLUDED.display_order, is_active = TRUE, lifecycle_status = 'Active';
    END IF;

    -- IMM-0027: Lupus Anticoagulant Panel
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'IMM-0027';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.parameters (test_id, code, name, unit, value_type, display_order, is_mandatory, is_active, lifecycle_status, clinical_configuration_status)
        VALUES 
            (v_test_id, 'IMM-0027-01', 'dRVVT Screen Ratio', 'Ratio', 'Numeric', 1, TRUE, TRUE, 'Active', 'Configured'),
            (v_test_id, 'IMM-0027-02', 'dRVVT Confirm Ratio', 'Ratio', 'Numeric', 2, TRUE, TRUE, 'Active', 'Configured'),
            (v_test_id, 'IMM-0027-03', 'Normalized dRVVT Ratio', 'Ratio', 'Calculated', 3, TRUE, TRUE, 'Active', 'Configured'),
            (v_test_id, 'IMM-0027-04', 'Lupus Anticoagulant Interpretation', NULL, 'Text', 4, TRUE, TRUE, 'Active', 'Configured')
        ON CONFLICT (test_id, code) DO UPDATE SET
            name = EXCLUDED.name, unit = EXCLUDED.unit, value_type = EXCLUDED.value_type,
            display_order = EXCLUDED.display_order, is_active = TRUE, lifecycle_status = 'Active';
    END IF;

    -- SPC-0005: Amino Acid Profile, Plasma
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'SPC-0005';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.parameters (test_id, code, name, unit, value_type, display_order, is_mandatory, is_active, lifecycle_status, clinical_configuration_status)
        VALUES 
            (v_test_id, 'SPC-0005-01', 'Plasma Amino Acid Profile Screen', NULL, 'Text', 1, TRUE, TRUE, 'Active', 'Configured'),
            (v_test_id, 'SPC-0005-02', 'Diagnostic Impression & Metabolic Summary', NULL, 'Text', 2, FALSE, TRUE, 'Active', 'Configured')
        ON CONFLICT (test_id, code) DO UPDATE SET
            name = EXCLUDED.name, unit = EXCLUDED.unit, value_type = EXCLUDED.value_type,
            display_order = EXCLUDED.display_order, is_active = TRUE, lifecycle_status = 'Active';
    END IF;

    -- SPC-0006: Acylcarnitine Profile
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'SPC-0006';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.parameters (test_id, code, name, unit, value_type, display_order, is_mandatory, is_active, lifecycle_status, clinical_configuration_status)
        VALUES 
            (v_test_id, 'SPC-0006-01', 'Acylcarnitine Profile Screen', NULL, 'Text', 1, TRUE, TRUE, 'Active', 'Configured'),
            (v_test_id, 'SPC-0006-02', 'Diagnostic Impression & Referral Summary', NULL, 'Text', 2, FALSE, TRUE, 'Active', 'Configured')
        ON CONFLICT (test_id, code) DO UPDATE SET
            name = EXCLUDED.name, unit = EXCLUDED.unit, value_type = EXCLUDED.value_type,
            display_order = EXCLUDED.display_order, is_active = TRUE, lifecycle_status = 'Active';
    END IF;

END $$;

-- ============================================================================
-- 5. Canonical Category Normalization (Haematology -> Hematology)
-- ============================================================================
UPDATE public.tests
SET department = 'Hematology',
    updated_at = NOW()
WHERE department = 'Haematology';

UPDATE public.tests
SET category = 'Hematology'
WHERE category = 'Haematology';

COMMIT;
