-- Migration 00099: Catalogue Clinical Activation Governance
-- Enforce strict database-level clinical validation rules:
-- 1. REQUIRES_VALIDATION -> cannot be active or orderable (is_active=false, billing_enabled=false, clinical_reporting_enabled=false)
-- 2. VALIDATED -> eligible for operational activation
-- 3. ACTIVE -> implies clinical validation has been completed
-- 4. INACTIVE -> non-orderable

BEGIN;

-- 1. Reset all REQUIRES_VALIDATION tests to safe non-orderable/inactive baseline
UPDATE public.tests
SET is_active = FALSE,
    lifecycle_status = 'Draft',
    billing_enabled = FALSE,
    clinical_reporting_enabled = FALSE,
    updated_at = NOW()
WHERE validation_status = 'REQUIRES_VALIDATION' OR validation_status IS NULL;

-- Ensure default validation_status is REQUIRES_VALIDATION
ALTER TABLE public.tests ALTER COLUMN validation_status SET DEFAULT 'REQUIRES_VALIDATION';
UPDATE public.tests SET validation_status = 'REQUIRES_VALIDATION' WHERE validation_status IS NULL;

-- 2. Drop any conflicting constraints if they exist and create canonical constraints
ALTER TABLE public.tests DROP CONSTRAINT IF EXISTS chk_tests_validation_status;
ALTER TABLE public.tests DROP CONSTRAINT IF EXISTS chk_tests_active_requires_validated;
ALTER TABLE public.tests DROP CONSTRAINT IF EXISTS chk_tests_billing_requires_validated;
ALTER TABLE public.tests DROP CONSTRAINT IF EXISTS chk_tests_reporting_requires_validated;

ALTER TABLE public.tests
  ADD CONSTRAINT chk_tests_validation_status
    CHECK (validation_status IN ('REQUIRES_VALIDATION', 'VALIDATED')),
  ADD CONSTRAINT chk_tests_active_requires_validated
    CHECK (NOT (is_active AND validation_status = 'REQUIRES_VALIDATION')),
  ADD CONSTRAINT chk_tests_billing_requires_validated
    CHECK (NOT (billing_enabled AND validation_status = 'REQUIRES_VALIDATION')),
  ADD CONSTRAINT chk_tests_reporting_requires_validated
    CHECK (NOT (clinical_reporting_enabled AND validation_status = 'REQUIRES_VALIDATION'));

-- 3. Update catalogue_set_test_lifecycle to enforce clinical validation before activation
CREATE OR REPLACE FUNCTION public.catalogue_set_test_lifecycle(
  p_test_id UUID,
  p_status public.catalogue_lifecycle_enum,
  p_expected_version BIGINT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
  missing TEXT[];
BEGIN
  PERFORM public.catalogue_require_manager();
  SELECT * INTO v FROM public.tests WHERE id=p_test_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002';
  END IF;
  IF v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409';
  END IF;

  IF p_status = 'Active' THEN
    IF v.validation_status <> 'VALIDATED' THEN
      RAISE EXCEPTION 'Cannot activate test: clinical validation is required (current status: %).', v.validation_status USING ERRCODE='23514';
    END IF;
    missing := public.catalogue_test_missing_configuration(p_test_id);
    IF cardinality(missing) > 0 THEN
      RAISE EXCEPTION 'Cannot activate. Missing configuration: %', array_to_string(missing, ', ') USING ERRCODE='23514';
    END IF;
  END IF;

  UPDATE public.tests
  SET lifecycle_status = p_status,
      is_active = (p_status = 'Active'),
      row_version = row_version + 1,
      updated_at = NOW(),
      archived_at = CASE WHEN p_status = 'Archived' THEN NOW() ELSE NULL END,
      archived_by = CASE WHEN p_status = 'Archived' THEN auth.uid() ELSE NULL END,
      activated_at = CASE WHEN p_status = 'Active' THEN NOW() ELSE activated_at END,
      activated_by = CASE WHEN p_status = 'Active' THEN auth.uid() ELSE activated_by END
  WHERE id = p_test_id;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    auth.uid(),
    public.catalogue_actor_name(),
    'CATALOGUE_TEST_' || upper(p_status::TEXT),
    'Test',
    p_test_id::TEXT,
    to_jsonb(v),
    (SELECT to_jsonb(x) FROM public.tests x WHERE x.id = p_test_id)
  );

  RETURN jsonb_build_object('id', p_test_id, 'status', p_status, 'validation_status', v.validation_status);
END $$;

-- 4. RPC to validate a test clinically
CREATE OR REPLACE FUNCTION public.catalogue_validate_test(
  p_test_id UUID,
  p_notes TEXT DEFAULT NULL,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
  missing TEXT[];
  p RECORD;
BEGIN
  PERFORM public.catalogue_require_manager();
  SELECT * INTO v FROM public.tests WHERE id=p_test_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002';
  END IF;
  IF p_expected_version IS NOT NULL AND v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409';
  END IF;

  -- Verify basic clinical prerequisites
  IF btrim(COALESCE(v.sample_type, '')) = '' AND v.reporting_type <> 'NoReporting' THEN
    RAISE EXCEPTION 'Clinical validation requires a valid specimen type.' USING ERRCODE='23514';
  END IF;

  -- For calculated parameters, verify calculation definition exists
  FOR p IN SELECT * FROM public.parameters WHERE test_id = v.id AND is_active LOOP
    IF p.value_type = 'Calculated' AND (btrim(COALESCE(p.calculation_identifier, '')) = '' OR btrim(COALESCE(p.formula, '')) = '') THEN
      RAISE EXCEPTION 'Parameter % is marked Calculated but lacks formula or calculation identifier.', p.code USING ERRCODE='23514';
    END IF;
  END LOOP;

  UPDATE public.tests
  SET validation_status = 'VALIDATED',
      clinical_configuration_status = 'Configured',
      configuration_notes = COALESCE(NULLIF(btrim(p_notes), ''), configuration_notes),
      row_version = row_version + 1,
      updated_at = NOW()
  WHERE id = p_test_id;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    auth.uid(),
    public.catalogue_actor_name(),
    'CATALOGUE_TEST_CLINICALLY_VALIDATED',
    'Test',
    p_test_id::TEXT,
    to_jsonb(v),
    (SELECT to_jsonb(x) FROM public.tests x WHERE x.id = p_test_id)
  );

  RETURN jsonb_build_object('id', p_test_id, 'validation_status', 'VALIDATED');
END $$;

-- 5. RPC to invalidate a test (return to REQUIRES_VALIDATION)
CREATE OR REPLACE FUNCTION public.catalogue_invalidate_test(
  p_test_id UUID,
  p_reason TEXT DEFAULT NULL,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager();
  SELECT * INTO v FROM public.tests WHERE id=p_test_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002';
  END IF;
  IF p_expected_version IS NOT NULL AND v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409';
  END IF;

  UPDATE public.tests
  SET validation_status = 'REQUIRES_VALIDATION',
      clinical_configuration_status = 'Requires Clinical Validation',
      is_active = FALSE,
      lifecycle_status = 'Draft',
      billing_enabled = FALSE,
      clinical_reporting_enabled = FALSE,
      configuration_notes = COALESCE(NULLIF(btrim(p_reason), ''), configuration_notes),
      row_version = row_version + 1,
      updated_at = NOW()
  WHERE id = p_test_id;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    auth.uid(),
    public.catalogue_actor_name(),
    'CATALOGUE_TEST_INVALIDATED',
    'Test',
    p_test_id::TEXT,
    to_jsonb(v),
    (SELECT to_jsonb(x) FROM public.tests x WHERE x.id = p_test_id)
  );

  RETURN jsonb_build_object('id', p_test_id, 'validation_status', 'REQUIRES_VALIDATION', 'is_active', FALSE);
END $$;

-- 6. Update search_billable_catalogue to strictly require validation_status = 'VALIDATED' AND is_active = TRUE
CREATE OR REPLACE FUNCTION public.search_billable_catalogue(p_query TEXT, p_limit INT DEFAULT 20)
RETURNS TABLE(
  entity_type TEXT,
  entity_id UUID,
  code TEXT,
  name TEXT,
  short_name TEXT,
  category TEXT,
  specimen TEXT,
  container TEXT,
  price_paisa BIGINT,
  price_configured BOOLEAN,
  pricing_policy public.catalogue_pricing_policy_enum,
  allow_zero_price_billing BOOLEAN,
  reporting_type public.reporting_type_enum,
  rank_score INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
#variable_conflict use_column
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;

  RETURN QUERY WITH q AS (
    SELECT lower(btrim(COALESCE(p_query, ''))) value
  ),
  matches(entity_kind, item_id, item_code, item_name, item_short_name, item_category, item_specimen, item_container, item_price_paisa, item_price_configured, item_pricing_policy, item_zero_price, item_reporting_type, item_score) AS (
    SELECT
      'Test'::TEXT,
      t.id,
      t.code::TEXT,
      t.name::TEXT,
      t.short_name::TEXT,
      c.name::TEXT,
      t.sample_type::TEXT,
      t.container::TEXT,
      r.price_paisa,
      (r.id IS NOT NULL AND r.price_paisa IS NOT NULL),
      COALESCE(t.pricing_policy, 'Fixed'),
      t.allow_zero_price_billing,
      t.reporting_type,
      CASE
        WHEN lower(t.code) = q.value THEN 100
        WHEN lower(t.code) LIKE q.value || '%' THEN 90
        WHEN lower(t.name) LIKE q.value || '%' THEN 70
        ELSE 50
      END score
    FROM public.tests t
    CROSS JOIN q
    LEFT JOIN public.test_categories c ON c.id = t.category_id
    LEFT JOIN public.catalogue_rate_versions r ON r.test_id = t.id AND r.status = 'Active' AND (r.effective_to IS NULL OR r.effective_to > now())
    WHERE length(q.value) >= 2
      AND t.is_active = TRUE
      AND t.validation_status = 'VALIDATED'
      AND t.lifecycle_status = 'Active'
      AND (
        lower(t.code) LIKE '%' || q.value || '%'
        OR lower(t.name) LIKE '%' || q.value || '%'
        OR lower(COALESCE(t.short_name, '')) LIKE '%' || q.value || '%'
        OR EXISTS (
          SELECT 1 FROM public.test_aliases a
          WHERE a.test_id = t.id AND lower(a.alias_name) LIKE '%' || q.value || '%'
        )
      )

    UNION ALL

    SELECT
      'Package',
      p.id,
      p.code::TEXT,
      p.name::TEXT,
      NULL,
      'Health Packages',
      NULL,
      NULL,
      r.price_paisa,
      (r.id IS NOT NULL AND r.price_paisa IS NOT NULL),
      p.pricing_policy,
      FALSE,
      'NoReporting'::public.reporting_type_enum,
      CASE
        WHEN lower(p.code) = q.value THEN 100
        WHEN lower(p.code) LIKE q.value || '%' THEN 90
        WHEN lower(p.name) LIKE q.value || '%' THEN 70
        ELSE 50
      END
    FROM public.health_packages p
    CROSS JOIN q
    LEFT JOIN public.catalogue_rate_versions r ON r.package_id = p.id AND r.status = 'Active' AND (r.effective_to IS NULL OR r.effective_to > now())
    WHERE length(q.value) >= 2
      AND p.lifecycle_status = 'Active'
      AND (lower(p.code) LIKE '%' || q.value || '%' OR lower(p.name) LIKE '%' || q.value || '%')

    UNION ALL

    SELECT
      'Panel',
      ps.id,
      ps.code,
      ps.name,
      NULL,
      c.name,
      ps.specimen,
      ps.container,
      r.price_paisa,
      (r.id IS NOT NULL AND r.price_paisa IS NOT NULL),
      'Fixed'::public.catalogue_pricing_policy_enum,
      FALSE,
      ps.reporting_type,
      CASE
        WHEN lower(ps.code) = q.value THEN 100
        WHEN lower(ps.code) LIKE q.value || '%' THEN 90
        WHEN lower(ps.name) LIKE q.value || '%' THEN 70
        ELSE 50
      END
    FROM public.catalogue_panel_services ps
    JOIN public.test_categories c ON c.id = ps.category_id
    CROSS JOIN q
    LEFT JOIN public.catalogue_rate_versions r ON r.panel_service_id = ps.id AND r.status = 'Active' AND (r.effective_to IS NULL OR r.effective_to > now())
    WHERE length(q.value) >= 2
      AND ps.lifecycle_status = 'Active'
      AND (lower(ps.code) LIKE '%' || q.value || '%' OR lower(ps.name) LIKE '%' || q.value || '%')
  )
  SELECT
    m.entity_kind,
    m.item_id,
    m.item_code,
    m.item_name,
    m.item_short_name,
    m.item_category,
    m.item_specimen,
    m.item_container,
    m.item_price_paisa,
    m.item_price_configured,
    m.item_pricing_policy,
    m.item_zero_price,
    m.item_reporting_type,
    m.item_score
  FROM matches m
  ORDER BY m.item_score DESC, m.item_name
  LIMIT greatest(1, least(COALESCE(p_limit, 20), 50));
END $$;

-- 7. Update catalogue_test_operational_label to reflect validation status
CREATE OR REPLACE FUNCTION public.catalogue_test_operational_label(p_test_id UUID)
RETURNS TEXT LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  t public.tests%ROWTYPE;
  r public.catalogue_service_readiness%ROWTYPE;
BEGIN
  SELECT * INTO t FROM public.tests WHERE id=p_test_id;
  IF NOT FOUND THEN RETURN 'Unknown'; END IF;
  SELECT * INTO r FROM public.catalogue_service_readiness WHERE test_id=p_test_id;

  IF t.validation_status = 'REQUIRES_VALIDATION' THEN
    RETURN 'Requires Validation';
  END IF;
  IF NOT t.is_active OR t.lifecycle_status = 'Archived' THEN
    RETURN 'Inactive';
  END IF;
  IF r.state = 'Suspended' THEN
    RETURN 'Suspended';
  END IF;
  IF r.state = 'NeedsConfiguration' THEN
    RETURN 'Needs Attention';
  END IF;
  IF t.reporting_type = 'NoReporting' OR t.workflow_type = 'NoClinicalReport' THEN
    RETURN 'Non-Reportable Service';
  END IF;
  IF public.catalogue_test_result_readiness(t.id) = 'Ready' THEN
    RETURN 'Ready & Reportable';
  ELSE
    RETURN 'Needs Attention';
  END IF;
END $$;

-- 8. Grant execute privileges
REVOKE ALL ON FUNCTION public.catalogue_validate_test(UUID, TEXT, BIGINT) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.catalogue_invalidate_test(UUID, TEXT, BIGINT) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.catalogue_validate_test(UUID, TEXT, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_invalidate_test(UUID, TEXT, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_set_test_lifecycle(UUID, public.catalogue_lifecycle_enum, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_billable_catalogue(TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_test_operational_label(UUID) TO authenticated;

COMMIT;
