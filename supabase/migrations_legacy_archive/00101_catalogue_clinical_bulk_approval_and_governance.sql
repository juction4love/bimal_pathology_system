-- Migration 00101: Catalogue Clinical Bulk Approval, Import/Export & Governance Dashboard
--
-- Clinical Safety Governance:
-- 1. Result-Type-Aware Clinical Readiness Verification
-- 2. Strict Panel Relationship Verification before Activation
-- 3. Governed Bulk Approval (fails closed if any selected test has missing prerequisites)
-- 4. Governed Bulk Activation (enables is_active, billing_enabled, clinical_reporting_enabled only for VALIDATED tests)
-- 5. Full Audit Logging and Version History
-- 6. Comprehensive Governance Dashboard Summary RPC

BEGIN;

-- 1. Result-Type-Aware Clinical Readiness Checker
CREATE OR REPLACE FUNCTION public.catalogue_check_test_readiness(p_test_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
  missing TEXT[] := ARRAY[]::TEXT[];
  blockers TEXT[] := ARRAY[]::TEXT[];
  p RECORD;
  c RECORD;
  has_numeric BOOLEAN := FALSE;
  has_ranges BOOLEAN := FALSE;
BEGIN
  SELECT * INTO v FROM public.tests WHERE id = p_test_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('found', FALSE, 'error', 'TEST_NOT_FOUND');
  END IF;

  -- 1. Basic Identity & Specimen
  IF btrim(COALESCE(v.code, '')) = '' THEN missing := array_append(missing, 'Test Code'); END IF;
  IF btrim(COALESCE(v.name, '')) = '' THEN missing := array_append(missing, 'Test Name'); END IF;
  IF v.reporting_type <> 'NoReporting' AND btrim(COALESCE(v.sample_type, '')) = '' THEN
    missing := array_append(missing, 'Specimen Type');
  END IF;
  IF v.reporting_type <> 'NoReporting' AND btrim(COALESCE(v.container, '')) = '' THEN
    missing := array_append(missing, 'Container');
  END IF;

  -- 2. Result-Type-Aware Checks
  FOR p IN SELECT * FROM public.parameters WHERE test_id = v.id AND is_active LOOP
    IF p.value_type = 'Numeric' THEN
      has_numeric := TRUE;
      IF btrim(COALESCE(p.unit, '')) = '' THEN
        missing := array_append(missing, 'Unit for parameter: ' || p.code);
      END IF;
      -- Check if reference range exists
      IF EXISTS(SELECT 1 FROM public.reference_ranges r WHERE r.parameter_id = p.id AND r.is_active) THEN
        has_ranges := TRUE;
      END IF;
    ELSIF p.value_type = 'Calculated' THEN
      IF btrim(COALESCE(p.formula, '')) = '' AND btrim(COALESCE(p.calculation_identifier, '')) = '' THEN
        missing := array_append(missing, 'Formula/Calculation Identifier for: ' || p.code);
      END IF;
      IF btrim(COALESCE(p.unit, '')) = '' THEN
        missing := array_append(missing, 'Unit for calculated parameter: ' || p.code);
      END IF;
    ELSIF p.value_type IN ('PositiveNegative', 'ReactiveNonReactive', 'DetectedNotDetected', 'Text') THEN
      -- Qualitative requires specimen & method
      IF btrim(COALESCE(v.method, '')) = '' THEN
        missing := array_append(missing, 'Analytical Method for qualitative test');
      END IF;
    ELSIF p.value_type = 'CultureAST' THEN
      IF btrim(COALESCE(v.sample_type, '')) = '' THEN
        missing := array_append(missing, 'Specimen for Culture/AST');
      END IF;
    END IF;
  END LOOP;

  -- 3. Panel Component Checks
  IF v.test_kind = 'Profile' OR v.test_type = 'Panel' THEN
    IF NOT EXISTS(SELECT 1 FROM public.catalogue_panel_components WHERE panel_test_id = v.id) THEN
      missing := array_append(missing, 'Panel Components (No child tests linked)');
    ELSE
      -- Check if child components are ready
      FOR c IN SELECT t.code, t.name, t.validation_status, t.is_active
               FROM public.catalogue_panel_components cpc
               JOIN public.tests t ON cpc.component_test_id = t.id
               WHERE cpc.panel_test_id = v.id LOOP
        IF c.validation_status <> 'VALIDATED' THEN
          blockers := array_append(blockers, 'Child test ' || c.code || ' is not validated');
        END IF;
        IF NOT c.is_active THEN
          blockers := array_append(blockers, 'Child test ' || c.code || ' is not active');
        END IF;
      END LOOP;
    END IF;
  END IF;

  -- Activation Blockers
  IF v.validation_status <> 'VALIDATED' THEN
    blockers := array_append(blockers, 'Test requires clinical validation and laboratory approval');
  END IF;
  IF cardinality(missing) > 0 THEN
    blockers := array_cat(blockers, missing);
  END IF;

  RETURN jsonb_build_object(
    'test_id', v.id,
    'code', v.code,
    'name', v.name,
    'test_kind', v.test_kind,
    'validation_status', v.validation_status,
    'is_active', v.is_active,
    'ready_for_approval', (cardinality(missing) = 0),
    'missing_fields', missing,
    'ready_for_activation', (cardinality(blockers) = 0),
    'activation_blockers', blockers,
    'has_pricing', (v.price_configured OR v.price_paisa > 0 OR v.allow_zero_price_billing),
    'has_method', (btrim(COALESCE(v.method, '')) <> ''),
    'has_ranges', has_ranges
  );
END $$;

-- 2. Bulk Submit Laboratory Approval RPC
CREATE OR REPLACE FUNCTION public.catalogue_bulk_submit_lab_approval(
  p_test_ids UUID[],
  p_analyzer_model TEXT,
  p_reagent_manufacturer TEXT,
  p_method TEXT,
  p_reference_range_source TEXT,
  p_critical_limit_source TEXT,
  p_effective_from DATE,
  p_approval_notes TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  t_id UUID;
  readiness JSONB;
  approved_count INT := 0;
  failed_tests JSONB := '[]'::JSONB;
  actor_id UUID;
  actor_name TEXT;
  new_version BIGINT;
BEGIN
  PERFORM public.catalogue_require_manager();
  actor_id := auth.uid();
  actor_name := public.catalogue_actor_name();

  IF p_test_ids IS NULL OR cardinality(p_test_ids) = 0 THEN
    RAISE EXCEPTION 'No tests provided for bulk approval.' USING ERRCODE='22023';
  END IF;

  -- First pass: Validate clinical readiness for ALL selected tests (fail closed)
  FOREACH t_id IN ARRAY p_test_ids LOOP
    readiness := public.catalogue_check_test_readiness(t_id);
    IF NOT (readiness->>'ready_for_approval')::BOOLEAN THEN
      failed_tests := failed_tests || jsonb_build_object(
        'test_id', t_id,
        'code', readiness->>'code',
        'missing', readiness->'missing_fields'
      );
    END IF;
  END LOOP;

  IF jsonb_array_length(failed_tests) > 0 THEN
    RAISE EXCEPTION 'Bulk approval blocked: % tests have missing clinical fields: %',
      jsonb_array_length(failed_tests), failed_tests::TEXT USING ERRCODE='23514';
  END IF;

  -- Second pass: Apply formal approval and transition to VALIDATED
  FOREACH t_id IN ARRAY p_test_ids LOOP
    SELECT COALESCE(MAX(version), 0) + 1 INTO new_version
    FROM public.catalogue_lab_approvals
    WHERE test_id = t_id;

    INSERT INTO public.catalogue_lab_approvals (
      test_id, approved_by, approved_by_name, approved_at,
      analyzer_model, reagent_manufacturer, method,
      reference_range_source, critical_limit_source,
      effective_from, version, approval_notes, approval_status
    ) VALUES (
      t_id, actor_id, actor_name, NOW(),
      btrim(p_analyzer_model), btrim(p_reagent_manufacturer), btrim(p_method),
      btrim(p_reference_range_source), btrim(p_critical_limit_source),
      COALESCE(p_effective_from, CURRENT_DATE), new_version, btrim(p_approval_notes), 'APPROVED'
    );

    UPDATE public.tests
    SET validation_status = 'VALIDATED',
        clinical_configuration_status = 'Configured',
        method = COALESCE(NULLIF(btrim(p_method), ''), method),
        configuration_notes = COALESCE(NULLIF(btrim(p_approval_notes), ''), configuration_notes),
        row_version = row_version + 1,
        updated_at = NOW()
    WHERE id = t_id;

    approved_count := approved_count + 1;
  END LOOP;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    actor_id, actor_name, 'CATALOGUE_BULK_LAB_APPROVED', 'Test',
    'BULK_' || approved_count::TEXT,
    jsonb_build_object('count', approved_count),
    jsonb_build_object('test_ids', p_test_ids, 'approved_by', actor_name)
  );

  RETURN jsonb_build_object('approved_count', approved_count, 'test_ids', p_test_ids);
END $$;

-- 3. Bulk Activation RPC
CREATE OR REPLACE FUNCTION public.catalogue_bulk_activate(
  p_test_ids UUID[]
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  t_id UUID;
  readiness JSONB;
  activated_count INT := 0;
  failed_tests JSONB := '[]'::JSONB;
  actor_id UUID;
  actor_name TEXT;
BEGIN
  PERFORM public.catalogue_require_manager();
  actor_id := auth.uid();
  actor_name := public.catalogue_actor_name();

  IF p_test_ids IS NULL OR cardinality(p_test_ids) = 0 THEN
    RAISE EXCEPTION 'No tests provided for bulk activation.' USING ERRCODE='22023';
  END IF;

  -- Validate readiness for all tests
  FOREACH t_id IN ARRAY p_test_ids LOOP
    readiness := public.catalogue_check_test_readiness(t_id);
    IF NOT (readiness->>'ready_for_activation')::BOOLEAN THEN
      failed_tests := failed_tests || jsonb_build_object(
        'test_id', t_id,
        'code', readiness->>'code',
        'blockers', readiness->'activation_blockers'
      );
    END IF;
  END LOOP;

  IF jsonb_array_length(failed_tests) > 0 THEN
    RAISE EXCEPTION 'Bulk activation blocked: % tests have activation blockers: %',
      jsonb_array_length(failed_tests), failed_tests::TEXT USING ERRCODE='23514';
  END IF;

  -- Apply activation
  FOREACH t_id IN ARRAY p_test_ids LOOP
    UPDATE public.tests
    SET lifecycle_status = 'Active',
        is_active = TRUE,
        billing_enabled = TRUE,
        clinical_reporting_enabled = TRUE,
        activated_at = NOW(),
        activated_by = actor_id,
        row_version = row_version + 1,
        updated_at = NOW()
    WHERE id = t_id;

    activated_count := activated_count + 1;
  END LOOP;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    actor_id, actor_name, 'CATALOGUE_BULK_ACTIVATED', 'Test',
    'BULK_' || activated_count::TEXT,
    jsonb_build_object('count', activated_count),
    jsonb_build_object('test_ids', p_test_ids)
  );

  RETURN jsonb_build_object('activated_count', activated_count, 'test_ids', p_test_ids);
END $$;

-- 4. Bulk CSV/Excel Lab Data Import RPC
CREATE OR REPLACE FUNCTION public.catalogue_bulk_import_lab_data(
  p_items JSONB
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  item JSONB;
  t_code TEXT;
  t_id UUID;
  param_id UUID;
  updated_count INT := 0;
  errs TEXT[] := ARRAY[]::TEXT[];
  price_val BIGINT;
  actor_id UUID;
  actor_name TEXT;
BEGIN
  PERFORM public.catalogue_require_manager();
  actor_id := auth.uid();
  actor_name := public.catalogue_actor_name();

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RETURN jsonb_build_object('updated_count', 0, 'errors', ARRAY['EMPTY_IMPORT_DATA']);
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    t_code := upper(btrim(COALESCE(item->>'test_code', '')));
    IF t_code = '' THEN
      errs := array_append(errs, 'Row missing test_code');
      CONTINUE;
    END IF;

    SELECT id INTO t_id FROM public.tests WHERE upper(code) = t_code;
    IF t_id IS NULL THEN
      errs := array_append(errs, 'Test code not found: ' || t_code);
      CONTINUE;
    END IF;

    -- Calculate price in paisa if price_npr is provided
    IF item->>'price_npr' IS NOT NULL AND btrim(item->>'price_npr') <> '' THEN
      price_val := round((item->>'price_npr')::numeric * 100);
    ELSE
      price_val := NULL;
    END IF;

    -- Update test metadata in DRAFT state
    UPDATE public.tests
    SET method = COALESCE(NULLIF(btrim(item->>'method'), ''), method),
        sample_type = COALESCE(NULLIF(btrim(item->>'specimen'), ''), sample_type),
        container = COALESCE(NULLIF(btrim(item->>'container'), ''), container),
        tat_hours = COALESCE(NULLIF(btrim(item->>'tat'), '')::int, tat_hours),
        price_paisa = COALESCE(price_val, price_paisa),
        price_configured = CASE WHEN price_val IS NOT NULL THEN TRUE ELSE price_configured END,
        configuration_notes = COALESCE(NULLIF(btrim(item->>'approval_notes'), ''), configuration_notes),
        updated_at = NOW()
    WHERE id = t_id;

    -- If parameter reference ranges are supplied, insert/update them
    IF (item->>'male_range' IS NOT NULL AND btrim(item->>'male_range') <> '')
       OR (item->>'female_range' IS NOT NULL AND btrim(item->>'female_range') <> '')
       OR (item->>'unit' IS NOT NULL AND btrim(item->>'unit') <> '') THEN

      -- Update parameter unit
      UPDATE public.parameters
      SET unit = COALESCE(NULLIF(btrim(item->>'unit'), ''), unit)
      WHERE test_id = t_id;

      SELECT id INTO param_id FROM public.parameters WHERE test_id = t_id LIMIT 1;
      IF param_id IS NOT NULL AND (item->>'male_range' IS NOT NULL OR item->>'female_range' IS NOT NULL) THEN
        -- Insert/update draft reference range
        INSERT INTO public.reference_ranges (
          parameter_id, gender, age_min_days, age_max_days,
          normal_text, critical_low, critical_high, method, unit,
          is_active, is_approved, lifecycle_status, validation_state
        ) VALUES (
          param_id, 'All', 0, 43800,
          COALESCE(item->>'male_range', item->>'female_range'),
          NULLIF(btrim(item->>'critical_low'), '')::numeric,
          NULLIF(btrim(item->>'critical_high'), '')::numeric,
          btrim(item->>'method'), btrim(item->>'unit'),
          TRUE, FALSE, 'Draft', 'Unclassified'
        ) ON CONFLICT DO NOTHING;
      END IF;
    END IF;

    updated_count := updated_count + 1;
  END LOOP;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    actor_id, actor_name, 'CATALOGUE_BULK_IMPORT_DATA', 'Test',
    'IMPORT_' || updated_count::TEXT,
    jsonb_build_object('count', updated_count),
    jsonb_build_object('updated_count', updated_count, 'errors', errs)
  );

  RETURN jsonb_build_object('updated_count', updated_count, 'errors', errs);
END $$;

-- 5. Governance Dashboard Summary Counters RPC
CREATE OR REPLACE FUNCTION public.catalogue_get_governance_summary()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  res JSONB;
BEGIN
  SELECT json_build_object(
    'total_tests', (SELECT count(*)::int FROM public.tests),
    'requires_validation_tests', (SELECT count(*)::int FROM public.tests WHERE validation_status = 'REQUIRES_VALIDATION'),
    'ready_for_approval_tests', (SELECT count(*)::int FROM public.tests WHERE validation_status = 'REQUIRES_VALIDATION' AND btrim(COALESCE(sample_type, '')) <> '' AND btrim(COALESCE(container, '')) <> ''),
    'validated_tests', (SELECT count(*)::int FROM public.tests WHERE validation_status = 'VALIDATED'),
    'active_tests', (SELECT count(*)::int FROM public.tests WHERE is_active = TRUE),
    'inactive_tests', (SELECT count(*)::int FROM public.tests WHERE is_active = FALSE),
    'missing_configuration_tests', (SELECT count(*)::int FROM public.tests WHERE btrim(COALESCE(sample_type, '')) = '' OR btrim(COALESCE(container, '')) = ''),
    'missing_pricing_tests', (SELECT count(*)::int FROM public.tests WHERE (price_paisa IS NULL OR price_paisa = 0) AND NOT allow_zero_price_billing),
    'missing_method_tests', (SELECT count(*)::int FROM public.tests WHERE btrim(COALESCE(method, '')) = '' AND reporting_type <> 'NoReporting'),
    'missing_range_tests', (SELECT count(*)::int FROM public.tests t WHERE t.reporting_type <> 'NoReporting' AND NOT EXISTS(
      SELECT 1 FROM public.parameters p JOIN public.reference_ranges r ON r.parameter_id = p.id WHERE p.test_id = t.id AND r.is_active
    )),
    'rejected_or_correction_tests', (SELECT count(*)::int FROM public.catalogue_lab_approvals WHERE approval_status = 'REVOKED')
  ) INTO res;

  RETURN res;
END $$;

-- 6. Grant Permissions
REVOKE ALL ON FUNCTION public.catalogue_check_test_readiness(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_check_test_readiness(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_bulk_submit_lab_approval(UUID[], TEXT, TEXT, TEXT, TEXT, TEXT, DATE, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_bulk_submit_lab_approval(UUID[], TEXT, TEXT, TEXT, TEXT, TEXT, DATE, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_bulk_activate(UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_bulk_activate(UUID[]) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_bulk_import_lab_data(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_bulk_import_lab_data(JSONB) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_get_governance_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_get_governance_summary() TO authenticated;

COMMIT;
