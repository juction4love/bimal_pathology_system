-- Migration 00104: Operational Orderability & Clinical Reporting Guards
--
-- State Model:
-- REQUIRES_VALIDATION -> ORDERABLE / CONFIGURABLE -> PENDING_APPROVAL -> VALIDATED -> REPORTABLE
--
-- Clinical Safety Governance:
-- 1. All 1,122 tests remain operational and orderable (is_active = TRUE, billing_enabled = TRUE).
-- 2. Unvalidated tests may be ordered, billed, accessioned, accept result entry, and accept equipment configuration.
-- 3. Unvalidated tests must NOT allow final clinical verification, sign-off, or final report generation.
-- 4. Result entry configuration is saved as configuration_status = 'PENDING_APPROVAL'.
-- 5. Technicians cannot self-approve without explicit clinical approval authority.
-- 6. Final verification and report sign-off strictly require validation_status = 'VALIDATED'.
-- 7. Panel reporting waits until every reportable component is clinically validated.

BEGIN;

-- 1. Add configuration_status column to tests
ALTER TABLE public.tests
  ADD COLUMN IF NOT EXISTS configuration_status TEXT DEFAULT 'PENDING_APPROVAL'
  CHECK (configuration_status IN ('PENDING_APPROVAL', 'CONFIGURED', 'REQUIRES_CONFIGURATION', 'VALIDATED'));

-- 2. Drop constraints that previously blocked ordering/billing for unvalidated tests
ALTER TABLE public.tests DROP CONSTRAINT IF EXISTS chk_tests_active_requires_validated;
ALTER TABLE public.tests DROP CONSTRAINT IF EXISTS chk_tests_billing_requires_validated;
ALTER TABLE public.tests DROP CONSTRAINT IF EXISTS chk_tests_reporting_requires_validated;

-- 3. Enforce that only final clinical reporting requires validation
ALTER TABLE public.tests
  ADD CONSTRAINT chk_tests_reporting_requires_validated
    CHECK (NOT (clinical_reporting_enabled AND validation_status = 'REQUIRES_VALIDATION'));

-- 4. Set all tests to be operational, orderable, and billable while maintaining REQUIRES_VALIDATION
UPDATE public.tests
SET is_active = TRUE,
    billing_enabled = TRUE,
    lifecycle_status = 'Active',
    clinical_reporting_enabled = FALSE,
    configuration_status = 'PENDING_APPROVAL',
    updated_at = NOW()
WHERE validation_status = 'REQUIRES_VALIDATION';

-- 5. RPC to submit pending clinical configuration during Result Entry or Technical Workflow
CREATE OR REPLACE FUNCTION public.catalogue_submit_pending_configuration(
  p_test_id UUID,
  p_analyzer_model TEXT DEFAULT NULL,
  p_reagent_manufacturer TEXT DEFAULT NULL,
  p_method TEXT DEFAULT NULL,
  p_unit TEXT DEFAULT NULL,
  p_normal_min NUMERIC DEFAULT NULL,
  p_normal_max NUMERIC DEFAULT NULL,
  p_critical_low NUMERIC DEFAULT NULL,
  p_critical_high NUMERIC DEFAULT NULL,
  p_normal_text TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
  v_param public.parameters%ROWTYPE;
  actor_id UUID;
  actor_name TEXT;
  can_approve BOOLEAN := FALSE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE='42501';
  END IF;

  IF NOT (
    public.has_permission('can_enter_results') OR
    public.has_permission('can_verify_results') OR
    public.has_permission('can_manage_catalogue') OR
    public.has_permission('can_configure_catalogue_technical')
  ) THEN
    RAISE EXCEPTION 'Permission denied to configure laboratory test parameters.' USING ERRCODE='42501';
  END IF;

  actor_id := auth.uid();
  actor_name := public.catalogue_actor_name();
  can_approve := public.has_permission('can_manage_catalogue');

  SELECT * INTO v FROM public.tests WHERE id = p_test_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002';
  END IF;

  -- Update test method, configuration_notes, and configuration_status
  UPDATE public.tests
  SET method = COALESCE(NULLIF(btrim(p_method), ''), method),
      configuration_status = CASE WHEN can_approve THEN 'CONFIGURED' ELSE 'PENDING_APPROVAL' END,
      configuration_notes = COALESCE(NULLIF(btrim(p_notes), ''), configuration_notes),
      updated_at = NOW()
  WHERE id = p_test_id;

  -- If parameter exists, update unit and draft range
  FOR v_param IN SELECT * FROM public.parameters WHERE test_id = p_test_id AND is_active LOOP
    IF p_unit IS NOT NULL AND btrim(p_unit) <> '' THEN
      UPDATE public.parameters SET unit = p_unit, updated_at = NOW() WHERE id = v_param.id;
    END IF;

    -- Add or update draft unapproved reference range
    IF p_normal_min IS NOT NULL OR p_normal_max IS NOT NULL OR p_normal_text IS NOT NULL THEN
      INSERT INTO public.reference_ranges (
        parameter_id,
        gender,
        age_min_days,
        age_max_days,
        normal_min,
        normal_max,
        critical_low,
        critical_high,
        normal_text,
        unit,
        method,
        is_active,
        is_approved
      ) VALUES (
        v_param.id,
        'All',
        0,
        43800,
        p_normal_min,
        p_normal_max,
        p_critical_low,
        p_critical_high,
        p_normal_text,
        COALESCE(p_unit, v_param.unit),
        COALESCE(p_method, v.method),
        TRUE,
        can_approve
      );
    END IF;
  END LOOP;

  -- Audit log
  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    actor_id,
    actor_name,
    'CATALOGUE_PENDING_CONFIG_SUBMIT',
    'Test',
    p_test_id::TEXT,
    to_jsonb(v),
    (SELECT to_jsonb(x) FROM public.tests x WHERE x.id = p_test_id)
  );

  RETURN jsonb_build_object(
    'test_id', p_test_id,
    'configuration_status', CASE WHEN can_approve THEN 'CONFIGURED' ELSE 'PENDING_APPROVAL' END,
    'validation_status', v.validation_status,
    'message', CASE WHEN can_approve THEN 'Configuration saved.' ELSE 'Configuration saved as PENDING_APPROVAL awaiting formal lab sign-off.' END
  );
END $$;

-- 6. Guard Server-Authoritative Result Verification against unvalidated tests
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
    v_test public.tests%ROWTYPE;
    v_parent public.diagnostic_reports%ROWTYPE;
    v_result JSONB;
    v_parameter public.parameters%ROWTYPE;
    v_existing public.test_results%ROWTYPE;
    v_user_name TEXT;
    v_is_amendment BOOLEAN := FALSE;
    v_count INT := 0;
    v_item_status TEXT;
    v_unval_comp RECORD;
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
    SELECT * INTO v_test FROM public.tests WHERE id = v_item.test_id;

    -- Strict Clinical Guard: Verification requires formal clinical validation
    IF p_target_status = 'Verified' THEN
        IF v_test.validation_status <> 'VALIDATED' THEN
            RAISE EXCEPTION 'Cannot verify results: Test % (%) has not received formal clinical validation. Save as Draft while awaiting clinical approval.', v_test.name, v_test.code USING ERRCODE = '23514';
        END IF;

        -- For panels, all child component tests must be validated
        IF v_test.test_kind = 'Profile' THEN
            FOR v_unval_comp IN
                SELECT t.code, t.name
                FROM public.catalogue_panel_components cpc
                JOIN public.tests t ON cpc.component_test_id = t.id
                WHERE cpc.panel_test_id = v_test.id AND t.validation_status <> 'VALIDATED'
            LOOP
                RAISE EXCEPTION 'Cannot verify panel: Component test % (%) is not clinically validated.', v_unval_comp.name, v_unval_comp.code USING ERRCODE = '23514';
            END LOOP;
        END IF;
    END IF;

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
        WHERE order_item_id = p_order_item_id
          AND parameter_id = v_parameter.id
        FOR UPDATE;

        IF FOUND THEN
            UPDATE public.test_results
            SET display_value = COALESCE(v_result->>'display_value', ''),
                numeric_value = CASE
                    WHEN v_parameter.value_type = 'Numeric' AND NULLIF(btrim(COALESCE(v_result->>'display_value', '')), '') IS NOT NULL
                    THEN (v_result->>'display_value')::NUMERIC
                    ELSE NULL
                END,
                text_value = CASE
                    WHEN v_parameter.value_type <> 'Numeric'
                    THEN v_result->>'display_value'
                    ELSE NULL
                END,
                flag = COALESCE((v_result->>'flag')::public.result_flag_enum, 'Normal'),
                is_critical = COALESCE((v_result->>'is_critical')::BOOLEAN, FALSE),
                critical_acknowledged = COALESCE((v_result->>'critical_acknowledged')::BOOLEAN, FALSE),
                status = p_target_status,
                entered_by = CASE WHEN p_target_status IN ('Draft', 'SubmittedForVerification') THEN auth.uid() ELSE entered_by END,
                entered_by_name = CASE WHEN p_target_status IN ('Draft', 'SubmittedForVerification') THEN v_user_name ELSE entered_by_name END,
                entered_at = CASE WHEN p_target_status IN ('Draft', 'SubmittedForVerification') THEN NOW() ELSE entered_at END,
                verified_by = CASE WHEN p_target_status = 'Verified' THEN auth.uid() ELSE verified_by END,
                verified_by_name = CASE WHEN p_target_status = 'Verified' THEN v_user_name ELSE verified_by_name END,
                verified_at = CASE WHEN p_target_status = 'Verified' THEN NOW() ELSE verified_at END,
                updated_at = NOW()
            WHERE id = v_existing.id;
        ELSE
            INSERT INTO public.test_results (
                order_item_id,
                parameter_id,
                parameter_name,
                unit,
                display_value,
                numeric_value,
                text_value,
                flag,
                is_critical,
                critical_acknowledged,
                status,
                entered_by,
                entered_by_name,
                entered_at,
                verified_by,
                verified_by_name,
                verified_at
            ) VALUES (
                p_order_item_id,
                v_parameter.id,
                v_parameter.name,
                v_parameter.unit,
                COALESCE(v_result->>'display_value', ''),
                CASE
                    WHEN v_parameter.value_type = 'Numeric' AND NULLIF(btrim(COALESCE(v_result->>'display_value', '')), '') IS NOT NULL
                    THEN (v_result->>'display_value')::NUMERIC
                    ELSE NULL
                END,
                CASE
                    WHEN v_parameter.value_type <> 'Numeric'
                    THEN v_result->>'display_value'
                    ELSE NULL
                END,
                COALESCE((v_result->>'flag')::public.result_flag_enum, 'Normal'),
                COALESCE((v_result->>'is_critical')::BOOLEAN, FALSE),
                COALESCE((v_result->>'critical_acknowledged')::BOOLEAN, FALSE),
                p_target_status,
                auth.uid(),
                v_user_name,
                NOW(),
                CASE WHEN p_target_status = 'Verified' THEN auth.uid() ELSE NULL END,
                CASE WHEN p_target_status = 'Verified' THEN v_user_name ELSE NULL END,
                CASE WHEN p_target_status = 'Verified' THEN NOW() ELSE NULL END
            );
        END IF;
        v_count := v_count + 1;
    END LOOP;

    -- Update parent order item status
    v_item_status := CASE
        WHEN p_target_status = 'Verified' THEN 'Verified'
        WHEN p_target_status = 'SubmittedForVerification' THEN 'SubmittedForVerification'
        WHEN p_target_status = 'ReturnedForCorrection' THEN 'ReturnedForCorrection'
        ELSE 'Draft'
    END;

    UPDATE public.clinical_order_items
    SET status = v_item_status::public.result_status_enum,
        updated_at = NOW()
    WHERE id = p_order_item_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'order_item_id', p_order_item_id,
        'status', v_item_status,
        'results_saved', v_count
    );
END $$;

-- 7. Guard Report Readiness & Signoff
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
    v_unval_items JSONB := '[]'::JSONB;
    v_unack_critical_count INT := 0;
    v_unack_critical_items JSONB := '[]'::JSONB;
    v_is_ready BOOLEAN := FALSE;
    v_item RECORD;
    v_res RECORD;
BEGIN
    FOR v_item IN (
        SELECT coi.id, coi.test_name, coi.department, coi.reporting_type, coi.status, t.validation_status, t.code AS test_code
        FROM public.clinical_order_items coi
        JOIN public.tests t ON coi.test_id = t.id
        WHERE coi.order_id = p_order_id
          AND coi.reporting_type IN ('InHouse', 'OutsourceWithBimalReport')
    ) LOOP
        v_reportable_count := v_reportable_count + 1;

        -- Check validation status
        IF v_item.validation_status <> 'VALIDATED' THEN
            v_unval_items := v_unval_items || jsonb_build_object(
                'order_item_id', v_item.id,
                'test_code', v_item.test_code,
                'test_name', v_item.test_name,
                'validation_status', v_item.validation_status,
                'reason', 'Test requires formal clinical validation and lab approval before report release'
            );
        END IF;

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

    -- Check critical panic values
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
            'flag', v_res.flag
        );
    END LOOP;

    v_is_ready := (
        v_reportable_count > 0 AND
        v_verified_count = v_reportable_count AND
        v_unack_critical_count = 0 AND
        jsonb_array_length(v_unval_items) = 0
    );

    RETURN jsonb_build_object(
        'is_ready', v_is_ready,
        'reportable_count', v_reportable_count,
        'verified_count', v_verified_count,
        'unverified_count', jsonb_array_length(v_unverified_items),
        'unverified_items', v_unverified_items,
        'unvalidated_count', jsonb_array_length(v_unval_items),
        'unvalidated_items', v_unval_items,
        'unacknowledged_critical_count', v_unack_critical_count,
        'unacknowledged_critical_items', v_unack_critical_items
    );
END $$;

REVOKE ALL ON FUNCTION public.catalogue_submit_pending_configuration(UUID, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_submit_pending_configuration(UUID, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TEXT) TO authenticated;

COMMIT;
