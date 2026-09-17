-- Forward-only hardening for calculation/formula evidence introduced in 00063.
CREATE OR REPLACE FUNCTION public.guard_immutable_calculation_evidence()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='CALCULATION_EVIDENCE_IMMUTABLE';
END $$;

CREATE TRIGGER clinical_calculation_runs_immutable
BEFORE UPDATE OR DELETE ON public.clinical_calculation_runs FOR EACH ROW
EXECUTE FUNCTION public.guard_immutable_calculation_evidence();
CREATE TRIGGER clinical_calculation_checks_immutable
BEFORE UPDATE OR DELETE ON public.clinical_calculation_consistency_checks FOR EACH ROW
EXECUTE FUNCTION public.guard_immutable_calculation_evidence();
CREATE TRIGGER report_calculation_provenance_immutable
BEFORE UPDATE OR DELETE ON public.report_calculation_provenance FOR EACH ROW
EXECUTE FUNCTION public.guard_immutable_calculation_evidence();

CREATE OR REPLACE FUNCTION public.guard_formula_version_rewrite()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF OLD.lifecycle_status='Approved' OR EXISTS(
    SELECT 1 FROM public.clinical_calculation_runs WHERE formula_version_id=OLD.id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='CALCULATION_FORMULA_VERSION_IMMUTABLE';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER clinical_calculation_formula_version_rewrite_guard
BEFORE UPDATE OR DELETE ON public.clinical_calculation_formula_versions FOR EACH ROW
EXECUTE FUNCTION public.guard_formula_version_rewrite();

REVOKE ALL ON FUNCTION public.guard_immutable_calculation_evidence(),
 public.guard_formula_version_rewrite() FROM PUBLIC,anon,authenticated,service_role;
