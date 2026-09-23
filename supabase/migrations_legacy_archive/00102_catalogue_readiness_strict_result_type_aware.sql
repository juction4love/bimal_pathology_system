-- Migration 00102: Strict Result-Type-Aware Clinical Readiness Governance
--
-- 1. Strict Result-Type-Aware Readiness: Numeric tests require configured reference ranges before approval
-- 2. Non-numeric tests (Qualitative, Culture/AST, Narrative, Molecular) require only clinically applicable fields
-- 3. Governance summary counter "ready_for_approval_tests" strictly matches catalogue_check_test_readiness()

BEGIN;

-- 1. Result-Type-Aware Clinical Readiness Function
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
  param_count INT := 0;
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

  -- 2. Result-Type-Aware Parameter & Range Checks
  FOR p IN SELECT * FROM public.parameters WHERE test_id = v.id AND is_active LOOP
    param_count := param_count + 1;
    IF p.value_type = 'Numeric' THEN
      has_numeric := TRUE;
      IF btrim(COALESCE(p.unit, '')) = '' THEN
        missing := array_append(missing, 'Unit for numeric parameter: ' || p.code);
      END IF;
      -- Strict check: Numeric tests MUST have configured reference ranges to be ready for approval
      IF EXISTS(SELECT 1 FROM public.reference_ranges r WHERE r.parameter_id = p.id AND r.is_active) THEN
        has_ranges := TRUE;
      ELSE
        missing := array_append(missing, 'Reference range for numeric parameter: ' || p.code);
      END IF;
    ELSIF p.value_type = 'Calculated' THEN
      IF btrim(COALESCE(p.formula, '')) = '' AND btrim(COALESCE(p.calculation_identifier, '')) = '' THEN
        missing := array_append(missing, 'Formula/Calculation Identifier for: ' || p.code);
      END IF;
      IF btrim(COALESCE(p.unit, '')) = '' THEN
        missing := array_append(missing, 'Unit for calculated parameter: ' || p.code);
      END IF;
    ELSIF p.value_type IN ('PositiveNegative', 'ReactiveNonReactive', 'DetectedNotDetected', 'Text') THEN
      -- Qualitative requires analytical method
      IF btrim(COALESCE(v.method, '')) = '' THEN
        missing := array_append(missing, 'Analytical Method for qualitative test');
      END IF;
    ELSIF p.value_type = 'CultureAST' THEN
      IF btrim(COALESCE(v.sample_type, '')) = '' THEN
        missing := array_append(missing, 'Specimen for Culture/AST');
      END IF;
    END IF;
  END LOOP;

  -- If not a panel and not NoReporting, ensure at least one parameter or method is defined
  IF v.test_kind <> 'Profile' AND v.reporting_type <> 'NoReporting' AND param_count = 0 THEN
    IF btrim(COALESCE(v.method, '')) = '' THEN
      missing := array_append(missing, 'Result structure or analytical method');
    END IF;
  END IF;

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

-- 2. Governance Dashboard Summary Counters RPC driven strictly by readiness logic
CREATE OR REPLACE FUNCTION public.catalogue_get_governance_summary()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  res JSONB;
BEGIN
  SELECT json_build_object(
    'total_tests', (SELECT count(*)::int FROM public.tests),
    'requires_validation_tests', (SELECT count(*)::int FROM public.tests WHERE validation_status = 'REQUIRES_VALIDATION'),
    'ready_for_approval_tests', (
      SELECT count(*)::int
      FROM public.tests t
      WHERE t.validation_status = 'REQUIRES_VALIDATION'
        AND (public.catalogue_check_test_readiness(t.id)->>'ready_for_approval')::boolean = TRUE
    ),
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

REVOKE ALL ON FUNCTION public.catalogue_check_test_readiness(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_check_test_readiness(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_get_governance_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_get_governance_summary() TO authenticated;

COMMIT;
