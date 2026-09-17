-- Migration 00100: Catalogue Clinical Laboratory Approval Workflow & Reversion
--
-- Clinical Safety Governance:
-- 1. Software-seeded / generic reference intervals and prices are NOT lab approvals.
-- 2. All 36 previously auto-seeded tests are reverted to:
--    validation_status = 'REQUIRES_VALIDATION', is_active = FALSE, billing_enabled = FALSE, clinical_reporting_enabled = FALSE.
-- 3. All configuration data is preserved as PROPOSED / DRAFT for clinical review.
-- 4. A formal Laboratory Approval Workflow is established requiring explicit clinical leadership approval metadata.

BEGIN;

-- 1. Create table for formal Laboratory Clinical Approvals
CREATE TABLE IF NOT EXISTS public.catalogue_lab_approvals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
  approved_by UUID REFERENCES public.user_profiles(id),
  approved_by_name TEXT NOT NULL,
  approved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  analyzer_model TEXT,
  reagent_manufacturer TEXT,
  method TEXT,
  reference_range_source TEXT,
  critical_limit_source TEXT,
  effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
  version BIGINT NOT NULL DEFAULT 1,
  approval_notes TEXT,
  approval_status TEXT NOT NULL DEFAULT 'APPROVED' CHECK (approval_status IN ('APPROVED', 'REVOKED', 'SUPERSEDED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_catalogue_lab_approvals_test_id ON public.catalogue_lab_approvals(test_id);

ALTER TABLE public.catalogue_lab_approvals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS catalogue_lab_approvals_select ON public.catalogue_lab_approvals;
CREATE POLICY catalogue_lab_approvals_select ON public.catalogue_lab_approvals
  FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS catalogue_lab_approvals_insert ON public.catalogue_lab_approvals;
CREATE POLICY catalogue_lab_approvals_insert ON public.catalogue_lab_approvals
  FOR INSERT TO authenticated WITH CHECK (
    public.has_permission('can_manage_catalogue')
  );

-- 2. Revert all 36 previously auto-seeded tests to safe unapproved DRAFT baseline
UPDATE public.tests
SET validation_status = 'REQUIRES_VALIDATION',
    clinical_configuration_status = 'Requires Clinical Validation',
    lifecycle_status = 'Draft',
    is_active = FALSE,
    billing_enabled = FALSE,
    clinical_reporting_enabled = FALSE,
    updated_at = NOW()
WHERE validation_status = 'VALIDATED' OR is_active = TRUE;

-- 3. Canonical naming clarity for Thyroid Profile (PRO-0004)
UPDATE public.tests
SET name = 'Thyroid Profile (FT3, FT4, TSH)',
    short_name = 'TFT (Free)',
    description = 'Canonical Free Thyroid Profile evaluating FT3, FT4, and TSH.',
    search_aliases = ARRAY['tft', 'thyroid profile', 'ft3 ft4 tsh', 'free thyroid panel', 'thyroid function test']
WHERE code = 'PRO-0004';

-- 4. Governed RPC for submitting formal Laboratory Approval
CREATE OR REPLACE FUNCTION public.catalogue_submit_lab_approval(
  p_test_id UUID,
  p_analyzer_model TEXT,
  p_reagent_manufacturer TEXT,
  p_method TEXT,
  p_reference_range_source TEXT,
  p_critical_limit_source TEXT,
  p_effective_from DATE,
  p_approval_notes TEXT,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
  actor_id UUID;
  actor_name TEXT;
  new_version BIGINT;
BEGIN
  PERFORM public.catalogue_require_manager();
  actor_id := auth.uid();
  actor_name := public.catalogue_actor_name();

  SELECT * INTO v FROM public.tests WHERE id = p_test_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002';
  END IF;

  IF p_expected_version IS NOT NULL AND v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409';
  END IF;

  -- Validate required approval metadata
  IF btrim(COALESCE(p_reference_range_source, '')) = '' AND v.test_kind IN ('Single', 'Component') AND v.reporting_type <> 'NoReporting' THEN
    RAISE EXCEPTION 'Laboratory approval requires a documented reference range source/clinical policy.' USING ERRCODE='23514';
  END IF;

  SELECT COALESCE(MAX(version), 0) + 1 INTO new_version
  FROM public.catalogue_lab_approvals
  WHERE test_id = p_test_id;

  -- Insert formal approval record
  INSERT INTO public.catalogue_lab_approvals (
    test_id, approved_by, approved_by_name, approved_at,
    analyzer_model, reagent_manufacturer, method,
    reference_range_source, critical_limit_source,
    effective_from, version, approval_notes, approval_status
  ) VALUES (
    p_test_id, actor_id, actor_name, NOW(),
    btrim(p_analyzer_model), btrim(p_reagent_manufacturer), COALESCE(btrim(p_method), v.method),
    btrim(p_reference_range_source), btrim(p_critical_limit_source),
    COALESCE(p_effective_from, CURRENT_DATE), new_version, btrim(p_approval_notes), 'APPROVED'
  );

  -- Update test validation state to VALIDATED
  UPDATE public.tests
  SET validation_status = 'VALIDATED',
      clinical_configuration_status = 'Configured',
      method = COALESCE(NULLIF(btrim(p_method), ''), method),
      configuration_notes = COALESCE(NULLIF(btrim(p_approval_notes), ''), configuration_notes),
      row_version = row_version + 1,
      updated_at = NOW()
  WHERE id = p_test_id;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    actor_id,
    actor_name,
    'CATALOGUE_TEST_LAB_APPROVED',
    'Test',
    p_test_id::TEXT,
    to_jsonb(v),
    (SELECT to_jsonb(x) FROM public.tests x WHERE x.id = p_test_id)
  );

  RETURN jsonb_build_object(
    'id', p_test_id,
    'validation_status', 'VALIDATED',
    'approval_version', new_version,
    'approved_by_name', actor_name
  );
END $$;

-- 5. Governed RPC to revert test configuration to Proposed / Unapproved
CREATE OR REPLACE FUNCTION public.catalogue_revert_to_proposed(
  p_test_id UUID,
  p_reason TEXT DEFAULT NULL,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
  actor_id UUID;
  actor_name TEXT;
BEGIN
  PERFORM public.catalogue_require_manager();
  actor_id := auth.uid();
  actor_name := public.catalogue_actor_name();

  SELECT * INTO v FROM public.tests WHERE id = p_test_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002';
  END IF;

  IF p_expected_version IS NOT NULL AND v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409';
  END IF;

  -- Mark active approvals as superseded/revoked
  UPDATE public.catalogue_lab_approvals
  SET approval_status = 'REVOKED'
  WHERE test_id = p_test_id AND approval_status = 'APPROVED';

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
    actor_id,
    actor_name,
    'CATALOGUE_TEST_REVERTED_TO_PROPOSED',
    'Test',
    p_test_id::TEXT,
    to_jsonb(v),
    (SELECT to_jsonb(x) FROM public.tests x WHERE x.id = p_test_id)
  );

  RETURN jsonb_build_object('id', p_test_id, 'validation_status', 'REQUIRES_VALIDATION');
END $$;

COMMIT;
