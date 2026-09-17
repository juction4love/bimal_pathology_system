-- Runtime acceptance assertions for the governed calculation engine.
-- No clinical data is created or mutated.
DO $$
DECLARE v NUMERIC; caught BOOLEAN;
BEGIN
  v:=public.evaluate_governed_formula('CBC_MCV','{"HCT":45,"RBC":5}'::jsonb);
  IF v<>90 THEN RAISE EXCEPTION 'CBC_MCV_RUNTIME_ASSERTION_FAILED'; END IF;
  v:=public.evaluate_governed_formula('CBC_MCH','{"HB":15,"RBC":5}'::jsonb);
  IF v<>30 THEN RAISE EXCEPTION 'CBC_MCH_RUNTIME_ASSERTION_FAILED'; END IF;
  v:=public.evaluate_governed_formula('CBC_MCHC','{"HB":15,"HCT":45}'::jsonb);
  IF v<>(100::numeric/3) THEN RAISE EXCEPTION 'CBC_MCHC_RUNTIME_ASSERTION_FAILED'; END IF;
  IF public.evaluate_governed_formula('CBC_ANC','{"WBC":8,"NEUT":60}'::jsonb)<>4.8
    OR public.evaluate_governed_formula('CBC_ALC','{"WBC":8,"LYMPH":30}'::jsonb)<>2.4
    OR public.evaluate_governed_formula('CBC_AEC','{"WBC":8,"EOS":5}'::jsonb)<>0.4
    OR public.evaluate_governed_formula('CBC_AMC','{"WBC":8,"MONO":4}'::jsonb)<>0.32
    OR public.evaluate_governed_formula('CBC_ABC','{"WBC":8,"BASO":1}'::jsonb)<>0.08
    OR public.evaluate_governed_formula('CBC_NLR','{"NEUT":60,"LYMPH":30}'::jsonb)<>2
  THEN RAISE EXCEPTION 'CBC_DIFFERENTIAL_RUNTIME_ASSERTION_FAILED'; END IF;

  IF public.normalize_clinical_calculation_input(8000,'/cumm','10^9/L')<>8
    OR public.normalize_clinical_calculation_input(5,'million/cumm','10^12/L')<>5
    OR public.normalize_clinical_calculation_input(15,'gm/dl','g/dL')<>15
  THEN RAISE EXCEPTION 'CALCULATION_UNIT_NORMALIZATION_ASSERTION_FAILED'; END IF;

  caught:=FALSE; BEGIN PERFORM public.evaluate_governed_formula('CBC_MCV','{"HCT":45,"RBC":0}'::jsonb);
    EXCEPTION WHEN division_by_zero THEN caught:=SQLERRM='CALCULATION_DIVISION_BY_ZERO'; END;
  IF NOT caught THEN RAISE EXCEPTION 'CALCULATION_ZERO_GUARD_ASSERTION_FAILED'; END IF;
  caught:=FALSE; BEGIN PERFORM public.evaluate_governed_formula('CBC_MCV','{"HCT":45}'::jsonb);
    EXCEPTION WHEN null_value_not_allowed THEN caught:=SQLERRM='CALCULATION_NULL_INPUT'; END;
  IF NOT caught THEN RAISE EXCEPTION 'CALCULATION_NULL_GUARD_ASSERTION_FAILED'; END IF;
  caught:=FALSE; BEGIN PERFORM public.normalize_clinical_calculation_input(8,'mg/dL','10^9/L');
    EXCEPTION WHEN invalid_parameter_value THEN caught:=SQLERRM='CALCULATION_UNIT_MISMATCH'; END;
  IF NOT caught THEN RAISE EXCEPTION 'CALCULATION_UNIT_GUARD_ASSERTION_FAILED'; END IF;

  IF (SELECT count(*) FROM public.clinical_calculation_formula_versions
      WHERE formula_identifier LIKE 'CBC_%' AND lifecycle_status='Candidate')<>9 THEN
    RAISE EXCEPTION 'CBC_CANDIDATE_VERSION_ASSERTION_FAILED';
  END IF;
  IF EXISTS(SELECT 1 FROM public.clinical_calculation_tolerance_versions) THEN
    RAISE EXCEPTION 'CALCULATION_TOLERANCE_MUST_NOT_BE_FABRICATED';
  END IF;
  IF EXISTS(SELECT 1 FROM public.tests WHERE code='CBC' AND clinical_reporting_enabled) THEN
    RAISE EXCEPTION 'CBC_MUST_REMAIN_CLINICALLY_DISABLED';
  END IF;
END $$;
