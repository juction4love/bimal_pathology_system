-- Ensure every future catalogue test mutation participates in readiness governance.
-- This migration intentionally performs no catalogue/business-row backfill.

CREATE OR REPLACE FUNCTION public.ensure_catalogue_test_readiness()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp AS $$
BEGIN
  INSERT INTO public.catalogue_service_readiness(test_id,state,decision_reason)
  VALUES(
    NEW.id,
    CASE
      WHEN NEW.lifecycle_status='Draft' THEN 'Draft'::public.catalogue_readiness_state_enum
      ELSE 'NeedsConfiguration'::public.catalogue_readiness_state_enum
    END,
    'Catalogue test entered readiness governance.'
  )
  ON CONFLICT(test_id) DO NOTHING;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS ensure_catalogue_test_readiness_trigger ON public.tests;
CREATE TRIGGER ensure_catalogue_test_readiness_trigger
AFTER INSERT OR UPDATE ON public.tests
FOR EACH ROW EXECUTE FUNCTION public.ensure_catalogue_test_readiness();

REVOKE ALL ON FUNCTION public.ensure_catalogue_test_readiness() FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION public.ensure_catalogue_test_readiness() IS 'Internal invariant trigger: future test creates/updates receive conservative readiness state without auto-approval.';

-- Readiness metadata must not make an otherwise never-used draft undeletable.
-- Reviewed configuration evidence remains immutable and therefore requires archive.
CREATE OR REPLACE FUNCTION public.catalogue_delete_test(p_test_id UUID,p_expected_version BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.tests%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.tests WHERE id=p_test_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
  IF EXISTS(SELECT 1 FROM public.bill_items WHERE test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.clinical_order_items WHERE test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.test_results r JOIN public.parameters p ON p.id=r.parameter_id WHERE p.test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.health_package_components WHERE test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.catalogue_profile_components WHERE profile_test_id=p_test_id OR component_test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.catalogue_panel_components WHERE component_test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.bill_package_components WHERE test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.bill_panel_components WHERE test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.catalogue_configuration_evidence WHERE test_id=p_test_id)
  THEN RAISE EXCEPTION 'Referenced tests or reviewed configurations cannot be deleted. Archive this test.' USING ERRCODE='23503'; END IF;
  DELETE FROM public.catalogue_rate_versions WHERE test_id=p_test_id;
  DELETE FROM public.catalogue_service_readiness WHERE test_id=p_test_id;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data)
  VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_TEST_DELETED','Test',p_test_id::TEXT,to_jsonb(v));
  DELETE FROM public.tests WHERE id=p_test_id;
END $$;
REVOKE ALL ON FUNCTION public.catalogue_delete_test(UUID,BIGINT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.catalogue_delete_test(UUID,BIGINT) TO authenticated;
