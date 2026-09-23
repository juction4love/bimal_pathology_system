-- Bimal Pathology LIS: governed server-authoritative calculation engine.
-- Prospective only. No historical result, report, snapshot, or range is rewritten.

DO $$ BEGIN
  CREATE TYPE public.parameter_clinical_class_enum AS ENUM
    ('Measured','Calculated','DerivedInterpretation','ReferencePolicy');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE public.parameters
  ADD COLUMN IF NOT EXISTS clinical_class public.parameter_clinical_class_enum NOT NULL DEFAULT 'Measured';

UPDATE public.parameters
SET clinical_class='Calculated'
WHERE value_type='Calculated' AND clinical_class='Measured';

COMMENT ON COLUMN public.parameters.clinical_class IS
'Measured includes analyzer and manually observed results. Calculated is server-produced only; DerivedInterpretation and ReferencePolicy require separately governed definitions.';

CREATE TABLE public.clinical_calculation_formula_versions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  formula_identifier TEXT NOT NULL,
  formula_version INTEGER NOT NULL CHECK (formula_version>0),
  formula_key TEXT NOT NULL,
  formula_expression TEXT NOT NULL,
  output_parameter_id UUID REFERENCES public.parameters(id) ON DELETE RESTRICT,
  output_parameter_code TEXT NOT NULL,
  output_unit TEXT NOT NULL,
  calculation_mode TEXT NOT NULL CHECK (calculation_mode IN ('Result','ConsistencyCheck','CandidateDerivedResult')),
  lifecycle_status TEXT NOT NULL DEFAULT 'Candidate' CHECK (lifecycle_status IN ('Candidate','Approved','Retired')),
  rounding_scale SMALLINT CHECK (rounding_scale BETWEEN 0 AND 12),
  rounding_mode TEXT CHECK (rounding_mode IS NULL OR rounding_mode IN ('HalfAwayFromZero')),
  effective_from TIMESTAMPTZ,
  effective_to TIMESTAMPTZ,
  approved_by UUID REFERENCES public.user_profiles(id),
  approved_at TIMESTAMPTZ,
  approval_reason TEXT,
  source_provenance TEXT NOT NULL,
  definition_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((lifecycle_status='Approved') =
    (approved_by IS NOT NULL AND approved_at IS NOT NULL AND effective_from IS NOT NULL
     AND rounding_scale IS NOT NULL AND rounding_mode IS NOT NULL)),
  UNIQUE(formula_identifier,formula_version),
  UNIQUE(definition_hash)
);

CREATE TABLE public.clinical_calculation_formula_inputs (
  formula_version_id UUID NOT NULL REFERENCES public.clinical_calculation_formula_versions(id) ON DELETE RESTRICT,
  input_key TEXT NOT NULL,
  parameter_id UUID REFERENCES public.parameters(id) ON DELETE RESTRICT,
  parameter_code TEXT NOT NULL,
  canonical_unit TEXT NOT NULL,
  ordinal SMALLINT NOT NULL CHECK (ordinal>0),
  PRIMARY KEY(formula_version_id,input_key),
  UNIQUE(formula_version_id,ordinal)
);

CREATE TABLE public.clinical_calculation_runs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_item_id UUID NOT NULL REFERENCES public.clinical_order_items(id) ON DELETE RESTRICT,
  formula_version_id UUID NOT NULL REFERENCES public.clinical_calculation_formula_versions(id) ON DELETE RESTRICT,
  output_result_id UUID REFERENCES public.test_results(id) ON DELETE RESTRICT,
  source_result_revision BIGINT NOT NULL CHECK (source_result_revision>=0),
  input_snapshot JSONB NOT NULL,
  calculated_raw_value NUMERIC,
  rounding_rule JSONB NOT NULL,
  displayed_value TEXT,
  output_unit TEXT NOT NULL,
  calculation_status TEXT NOT NULL CHECK (calculation_status IN ('Calculated','MissingInput','InvalidInput','UnitMismatch','DivisionByZero','Overflow')),
  error_code TEXT,
  formula_snapshot JSONB NOT NULL,
  calculated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(order_item_id,formula_version_id,source_result_revision)
);

CREATE TABLE public.clinical_calculation_tolerance_versions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  formula_version_id UUID NOT NULL REFERENCES public.clinical_calculation_formula_versions(id) ON DELETE RESTRICT,
  tolerance_kind TEXT NOT NULL CHECK (tolerance_kind IN ('Absolute','Percent')),
  tolerance_value NUMERIC NOT NULL CHECK (tolerance_value>=0),
  behavior TEXT NOT NULL CHECK (behavior IN ('Warning','Blocking')),
  version INTEGER NOT NULL CHECK (version>0),
  approved_by UUID NOT NULL REFERENCES public.user_profiles(id),
  approved_at TIMESTAMPTZ NOT NULL,
  effective_from TIMESTAMPTZ NOT NULL,
  effective_to TIMESTAMPTZ,
  reason TEXT NOT NULL,
  UNIQUE(formula_version_id,version)
);

CREATE TABLE public.clinical_calculation_consistency_checks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  calculation_run_id UUID NOT NULL UNIQUE REFERENCES public.clinical_calculation_runs(id) ON DELETE RESTRICT,
  measured_result_id UUID NOT NULL REFERENCES public.test_results(id) ON DELETE RESTRICT,
  measured_value NUMERIC NOT NULL,
  measured_unit TEXT NOT NULL,
  calculated_expected_value NUMERIC NOT NULL,
  calculated_unit TEXT NOT NULL,
  absolute_difference NUMERIC NOT NULL,
  percent_difference NUMERIC,
  tolerance_version_id UUID REFERENCES public.clinical_calculation_tolerance_versions(id) ON DELETE RESTRICT,
  disposition TEXT NOT NULL CHECK (disposition IN ('NotEvaluated','WithinTolerance','Warning','Blocked')),
  checked_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.report_calculation_provenance (
  report_id UUID NOT NULL REFERENCES public.diagnostic_reports(id) ON DELETE RESTRICT,
  calculation_run_id UUID NOT NULL REFERENCES public.clinical_calculation_runs(id) ON DELETE RESTRICT,
  report_version INTEGER NOT NULL,
  formula_snapshot JSONB NOT NULL,
  input_snapshot JSONB NOT NULL,
  calculated_raw_value NUMERIC,
  displayed_value TEXT,
  output_unit TEXT NOT NULL,
  calculation_status TEXT NOT NULL,
  provenance_hash TEXT NOT NULL,
  captured_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(report_id,calculation_run_id)
);

CREATE OR REPLACE FUNCTION public.normalize_clinical_calculation_input(
  p_value NUMERIC,p_supplied_unit TEXT,p_canonical_unit TEXT
) RETURNS NUMERIC LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=public,pg_temp AS $$
DECLARE supplied TEXT:=lower(regexp_replace(p_supplied_unit,'[[:space:]]','','g'));
        canonical TEXT:=lower(regexp_replace(p_canonical_unit,'[[:space:]]','','g'));
BEGIN
  IF p_value::TEXT IN ('Infinity','-Infinity','NaN') THEN
    RAISE EXCEPTION USING ERRCODE='22003',MESSAGE='CALCULATION_INVALID_INPUT';
  END IF;
  IF supplied=canonical THEN RETURN p_value; END IF;
  IF canonical='10^9/l' AND supplied IN ('×10³/mm³','x10^3/mm3','10^3/mm3','thousand/mm3') THEN RETURN p_value; END IF;
  IF canonical='10^9/l' AND supplied IN ('/cumm','/mm³','/mm3') THEN RETURN p_value/1000; END IF;
  IF canonical='10^12/l' AND supplied IN ('million/mm³','million/mm3','10^6/mm3') THEN RETURN p_value; END IF;
  IF canonical='10^12/l' AND supplied='million/cumm' THEN RETURN p_value; END IF;
  IF canonical='g/dl' AND supplied='gm/dl' THEN RETURN p_value; END IF;
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_UNIT_MISMATCH',
    DETAIL=jsonb_build_object('supplied_unit',p_supplied_unit,'required_unit',p_canonical_unit)::TEXT;
END $$;

CREATE OR REPLACE FUNCTION public.run_governed_order_item_calculations(p_order_item_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE item public.clinical_order_items%ROWTYPE; def RECORD; inp RECORD; source RECORD;
        inputs JSONB; input_snapshot JSONB; raw_value NUMERIC; shown NUMERIC; run_id UUID;
        output_result UUID; measured RECORD; tolerance RECORD; abs_diff NUMERIC; pct_diff NUMERIC;
BEGIN
  SELECT * INTO item FROM public.clinical_order_items WHERE id=p_order_item_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='CALCULATION_ORDER_ITEM_NOT_FOUND'; END IF;
  FOR def IN
    SELECT * FROM public.clinical_calculation_formula_versions
    WHERE lifecycle_status='Approved' AND effective_from<=now()
      AND (effective_to IS NULL OR effective_to>now()) ORDER BY formula_identifier,formula_version
  LOOP
    inputs:='{}'; input_snapshot:='[]';
    FOR inp IN SELECT * FROM public.clinical_calculation_formula_inputs
      WHERE formula_version_id=def.id ORDER BY ordinal
    LOOP
      SELECT tr.id,tr.numeric_value,tr.unit,p.id parameter_id INTO source
      FROM public.test_results tr JOIN public.parameters p ON p.id=tr.parameter_id
      WHERE tr.order_item_id=p_order_item_id AND p.code=inp.parameter_code;
      IF NOT FOUND OR source.numeric_value IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='22004',MESSAGE='CALCULATION_NULL_INPUT',
          DETAIL=jsonb_build_object('formula_identifier',def.formula_identifier,'input',inp.input_key)::TEXT;
      END IF;
      raw_value:=public.normalize_clinical_calculation_input(source.numeric_value,source.unit,inp.canonical_unit);
      inputs:=jsonb_set(inputs,ARRAY[inp.input_key],to_jsonb(raw_value));
      input_snapshot:=input_snapshot||jsonb_build_object('input_key',inp.input_key,
        'parameter_id',source.parameter_id,'result_id',source.id,'supplied_value',source.numeric_value,
        'supplied_unit',source.unit,'normalized_value',raw_value,'canonical_unit',inp.canonical_unit);
    END LOOP;
    raw_value:=public.evaluate_governed_formula(def.formula_key,inputs);
    shown:=round(raw_value,def.rounding_scale);

    output_result:=NULL;
    IF def.calculation_mode='Result' THEN
      SELECT tr.id INTO output_result FROM public.test_results tr
      JOIN public.parameters p ON p.id=tr.parameter_id
      WHERE tr.order_item_id=p_order_item_id AND p.id=def.output_parameter_id
        AND p.clinical_class='Calculated' FOR UPDATE;
      IF output_result IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_OUTPUT_NOT_CONFIGURED'; END IF;
      UPDATE public.test_results SET numeric_value=shown,display_value=shown::TEXT,unit=def.output_unit,updated_at=now()
      WHERE id=output_result;
    END IF;

    INSERT INTO public.clinical_calculation_runs(order_item_id,formula_version_id,output_result_id,
      source_result_revision,input_snapshot,calculated_raw_value,rounding_rule,displayed_value,
      output_unit,calculation_status,error_code,formula_snapshot)
    VALUES(p_order_item_id,def.id,output_result,item.result_revision,input_snapshot,raw_value,
      jsonb_build_object('mode',def.rounding_mode,'scale',def.rounding_scale),shown::TEXT,
      def.output_unit,'Calculated',NULL,jsonb_build_object('identifier',def.formula_identifier,
      'version',def.formula_version,'key',def.formula_key,'expression',def.formula_expression,
      'definition_hash',def.definition_hash))
    ON CONFLICT(order_item_id,formula_version_id,source_result_revision) DO NOTHING RETURNING id INTO run_id;

    IF def.calculation_mode='ConsistencyCheck' AND run_id IS NOT NULL THEN
      SELECT tr.id,tr.numeric_value,tr.unit INTO measured FROM public.test_results tr
      JOIN public.parameters p ON p.id=tr.parameter_id
      WHERE tr.order_item_id=p_order_item_id AND p.code=def.output_parameter_code
        AND tr.numeric_value IS NOT NULL;
      IF FOUND THEN
        abs_diff:=abs(public.normalize_clinical_calculation_input(measured.numeric_value,measured.unit,def.output_unit)-shown);
        pct_diff:=CASE WHEN shown=0 THEN NULL ELSE abs_diff/abs(shown)*100 END;
        SELECT * INTO tolerance FROM public.clinical_calculation_tolerance_versions
        WHERE formula_version_id=def.id AND effective_from<=now() AND (effective_to IS NULL OR effective_to>now())
        ORDER BY version DESC LIMIT 1;
        INSERT INTO public.clinical_calculation_consistency_checks(calculation_run_id,measured_result_id,
          measured_value,measured_unit,calculated_expected_value,calculated_unit,absolute_difference,
          percent_difference,tolerance_version_id,disposition)
        VALUES(run_id,measured.id,measured.numeric_value,measured.unit,shown,def.output_unit,abs_diff,pct_diff,
          tolerance.id,CASE WHEN tolerance.id IS NULL THEN 'NotEvaluated'
            WHEN (tolerance.tolerance_kind='Absolute' AND abs_diff<=tolerance.tolerance_value)
              OR (tolerance.tolerance_kind='Percent' AND pct_diff<=tolerance.tolerance_value) THEN 'WithinTolerance'
            WHEN tolerance.behavior='Blocking' THEN 'Blocked' ELSE 'Warning' END);
        IF tolerance.id IS NOT NULL AND tolerance.behavior='Blocking' AND
          ((tolerance.tolerance_kind='Absolute' AND abs_diff>tolerance.tolerance_value) OR
           (tolerance.tolerance_kind='Percent' AND pct_diff>tolerance.tolerance_value)) THEN
          RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_DISCREPANCY_BLOCKED';
        END IF;
      END IF;
    END IF;
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.evaluate_governed_formula(p_formula_key TEXT,p_inputs JSONB)
RETURNS NUMERIC LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=public,pg_temp AS $$
DECLARE a NUMERIC;b NUMERIC;result NUMERIC;
BEGIN
  IF jsonb_typeof(p_inputs)<>'object' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_INVALID_INPUT'; END IF;
  CASE p_formula_key
    WHEN 'CBC_MCV' THEN a:=NULLIF(p_inputs->>'HCT','')::NUMERIC;b:=NULLIF(p_inputs->>'RBC','')::NUMERIC; IF a IS NULL OR b IS NULL THEN RAISE EXCEPTION USING ERRCODE='22004',MESSAGE='CALCULATION_NULL_INPUT'; END IF; IF b=0 THEN RAISE EXCEPTION USING ERRCODE='22012',MESSAGE='CALCULATION_DIVISION_BY_ZERO'; END IF; result:=a*10/b;
    WHEN 'CBC_MCH' THEN a:=NULLIF(p_inputs->>'HB','')::NUMERIC;b:=NULLIF(p_inputs->>'RBC','')::NUMERIC; IF a IS NULL OR b IS NULL THEN RAISE EXCEPTION USING ERRCODE='22004',MESSAGE='CALCULATION_NULL_INPUT'; END IF; IF b=0 THEN RAISE EXCEPTION USING ERRCODE='22012',MESSAGE='CALCULATION_DIVISION_BY_ZERO'; END IF; result:=a*10/b;
    WHEN 'CBC_MCHC' THEN a:=NULLIF(p_inputs->>'HB','')::NUMERIC;b:=NULLIF(p_inputs->>'HCT','')::NUMERIC; IF a IS NULL OR b IS NULL THEN RAISE EXCEPTION USING ERRCODE='22004',MESSAGE='CALCULATION_NULL_INPUT'; END IF; IF b=0 THEN RAISE EXCEPTION USING ERRCODE='22012',MESSAGE='CALCULATION_DIVISION_BY_ZERO'; END IF; result:=a*100/b;
    WHEN 'CBC_ANC' THEN result:=(NULLIF(p_inputs->>'WBC','')::NUMERIC)*(NULLIF(p_inputs->>'NEUT','')::NUMERIC)/100;
    WHEN 'CBC_ALC' THEN result:=(NULLIF(p_inputs->>'WBC','')::NUMERIC)*(NULLIF(p_inputs->>'LYMPH','')::NUMERIC)/100;
    WHEN 'CBC_AEC' THEN result:=(NULLIF(p_inputs->>'WBC','')::NUMERIC)*(NULLIF(p_inputs->>'EOS','')::NUMERIC)/100;
    WHEN 'CBC_AMC' THEN result:=(NULLIF(p_inputs->>'WBC','')::NUMERIC)*(NULLIF(p_inputs->>'MONO','')::NUMERIC)/100;
    WHEN 'CBC_ABC' THEN result:=(NULLIF(p_inputs->>'WBC','')::NUMERIC)*(NULLIF(p_inputs->>'BASO','')::NUMERIC)/100;
    WHEN 'CBC_NLR' THEN a:=NULLIF(p_inputs->>'NEUT','')::NUMERIC;b:=NULLIF(p_inputs->>'LYMPH','')::NUMERIC; IF a IS NULL OR b IS NULL THEN RAISE EXCEPTION USING ERRCODE='22004',MESSAGE='CALCULATION_NULL_INPUT'; END IF; IF b=0 THEN RAISE EXCEPTION USING ERRCODE='22012',MESSAGE='CALCULATION_DIVISION_BY_ZERO'; END IF; result:=a/b;
    ELSE RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_FORMULA_NOT_IMPLEMENTED';
  END CASE;
  IF result IS NULL THEN RAISE EXCEPTION USING ERRCODE='22004',MESSAGE='CALCULATION_NULL_INPUT'; END IF;
  IF abs(result)>1e30 THEN RAISE EXCEPTION USING ERRCODE='22003',MESSAGE='CALCULATION_OVERFLOW'; END IF;
  RETURN result;
EXCEPTION WHEN invalid_text_representation THEN
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_INVALID_INPUT';
END $$;

CREATE OR REPLACE FUNCTION public.capture_report_calculation_provenance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  INSERT INTO public.report_calculation_provenance(
    report_id,calculation_run_id,report_version,formula_snapshot,input_snapshot,
    calculated_raw_value,displayed_value,output_unit,calculation_status,provenance_hash)
  SELECT NEW.id,r.id,NEW.version,r.formula_snapshot,r.input_snapshot,r.calculated_raw_value,
         r.displayed_value,r.output_unit,r.calculation_status,
         encode(extensions.digest(convert_to(jsonb_build_object('report_id',NEW.id,'report_version',NEW.version,
           'formula',r.formula_snapshot,'inputs',r.input_snapshot,'raw',r.calculated_raw_value,
           'display',r.displayed_value,'unit',r.output_unit,'status',r.calculation_status)::TEXT,'UTF8'),'sha256'),'hex')
  FROM public.clinical_calculation_runs r
  JOIN public.clinical_order_items coi ON coi.id=r.order_item_id
  WHERE coi.order_id=NEW.order_id;
  RETURN NEW;
END $$;

CREATE TRIGGER capture_report_calculation_provenance_trigger
AFTER INSERT ON public.diagnostic_reports FOR EACH ROW
EXECUTE FUNCTION public.capture_report_calculation_provenance();

-- Browser payloads may never author a server-calculated or derived value.
ALTER FUNCTION public.save_test_results(UUID,JSONB,public.result_status_enum,UUID,TEXT,BIGINT)
  RENAME TO save_test_results_revision_internal;
REVOKE ALL ON FUNCTION public.save_test_results_revision_internal(UUID,JSONB,public.result_status_enum,UUID,TEXT,BIGINT)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.save_test_results(
  p_order_item_id UUID,p_results JSONB,p_target_status public.result_status_enum,
  p_amended_from_report_id UUID,p_amendment_reason TEXT,p_expected_revision BIGINT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE response JSONB;
BEGIN
  IF EXISTS(
    SELECT 1 FROM jsonb_array_elements(p_results) r
    JOIN public.parameters p ON p.id=(r->>'parameter_id')::UUID
    WHERE p.clinical_class IN ('Calculated','DerivedInterpretation','ReferencePolicy')
  ) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='RESULT_SERVER_CALCULATION_REQUIRED';
  END IF;
  response:=public.save_test_results_revision_internal(p_order_item_id,p_results,p_target_status,
    p_amended_from_report_id,p_amendment_reason,p_expected_revision);
  -- Existing approved legacy calculations remain recomputed on the server.
  PERFORM public.recompute_order_item_calculated_results(p_order_item_id);
  PERFORM public.run_governed_order_item_calculations(p_order_item_id);
  RETURN response;
END $$;
REVOKE ALL ON FUNCTION public.save_test_results(UUID,JSONB,public.result_status_enum,UUID,TEXT,BIGINT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_test_results(UUID,JSONB,public.result_status_enum,UUID,TEXT,BIGINT) TO authenticated;

-- CBC definitions are governed candidates. No rounding/tolerance was supplied,
-- so this migration deliberately cannot make them Approved or reportable.
INSERT INTO public.clinical_calculation_formula_versions(
 formula_identifier,formula_version,formula_key,formula_expression,output_parameter_code,
 output_unit,calculation_mode,lifecycle_status,source_provenance,definition_hash)
VALUES
 ('CBC_MCV',1,'CBC_MCV','HCT * 10 / RBC','MCV','fL','ConsistencyCheck','Candidate','Operator-authorized formula; rounding and analyzer applicability pending',encode(extensions.digest('CBC_MCV|1|HCT*10/RBC|fL','sha256'),'hex')),
 ('CBC_MCH',1,'CBC_MCH','Hb * 10 / RBC','MCH','pg','ConsistencyCheck','Candidate','Operator-authorized formula; rounding and analyzer applicability pending',encode(extensions.digest('CBC_MCH|1|HB*10/RBC|pg','sha256'),'hex')),
 ('CBC_MCHC',1,'CBC_MCHC','Hb * 100 / HCT','MCHC','g/dL','ConsistencyCheck','Candidate','Operator-authorized formula; rounding and analyzer applicability pending',encode(extensions.digest('CBC_MCHC|1|HB*100/HCT|g/dL','sha256'),'hex')),
 ('CBC_ANC',1,'CBC_ANC','WBC * Neutrophil% / 100','ANC','10^9/L','CandidateDerivedResult','Candidate','Operator-authorized formula; CBC reporting inclusion and rounding pending',encode(extensions.digest('CBC_ANC|1|WBC*NEUT/100|10^9/L','sha256'),'hex')),
 ('CBC_ALC',1,'CBC_ALC','WBC * Lymphocyte% / 100','ALC','10^9/L','CandidateDerivedResult','Candidate','Operator-authorized formula; CBC reporting inclusion and rounding pending',encode(extensions.digest('CBC_ALC|1|WBC*LYMPH/100|10^9/L','sha256'),'hex')),
 ('CBC_AEC',1,'CBC_AEC','WBC * Eosinophil% / 100','AEC','10^9/L','CandidateDerivedResult','Candidate','Operator-authorized formula; CBC reporting inclusion and rounding pending',encode(extensions.digest('CBC_AEC|1|WBC*EOS/100|10^9/L','sha256'),'hex')),
 ('CBC_AMC',1,'CBC_AMC','WBC * Monocyte% / 100','AMC','10^9/L','CandidateDerivedResult','Candidate','Operator-authorized formula; CBC reporting inclusion and rounding pending',encode(extensions.digest('CBC_AMC|1|WBC*MONO/100|10^9/L','sha256'),'hex')),
 ('CBC_ABC',1,'CBC_ABC','WBC * Basophil% / 100','ABC','10^9/L','CandidateDerivedResult','Candidate','Operator-authorized formula; CBC reporting inclusion and rounding pending',encode(extensions.digest('CBC_ABC|1|WBC*BASO/100|10^9/L','sha256'),'hex')),
 ('CBC_NLR',1,'CBC_NLR','Neutrophil% / Lymphocyte%','NLR','ratio','CandidateDerivedResult','Candidate','Operator-authorized formula; CBC reporting inclusion and rounding pending',encode(extensions.digest('CBC_NLR|1|NEUT/LYMPH|ratio','sha256'),'hex'));

UPDATE public.clinical_calculation_formula_versions d SET output_parameter_id=p.id
FROM public.parameters p JOIN public.tests t ON t.id=p.test_id
WHERE t.code='CBC' AND p.code=d.output_parameter_code AND d.formula_identifier LIKE 'CBC_%';

WITH mappings(formula_identifier,input_key,parameter_code,canonical_unit,ordinal) AS (VALUES
 ('CBC_MCV','HCT','PCV','%',1),('CBC_MCV','RBC','RBC','10^12/L',2),
 ('CBC_MCH','HB','HB','g/dL',1),('CBC_MCH','RBC','RBC','10^12/L',2),
 ('CBC_MCHC','HB','HB','g/dL',1),('CBC_MCHC','HCT','PCV','%',2),
 ('CBC_ANC','WBC','TLC','10^9/L',1),('CBC_ANC','NEUT','NEUT','%',2),
 ('CBC_ALC','WBC','TLC','10^9/L',1),('CBC_ALC','LYMPH','LYMPH','%',2),
 ('CBC_AEC','WBC','TLC','10^9/L',1),('CBC_AEC','EOS','EOSIN','%',2),
 ('CBC_AMC','WBC','TLC','10^9/L',1),('CBC_AMC','MONO','MONO','%',2),
 ('CBC_ABC','WBC','TLC','10^9/L',1),('CBC_ABC','BASO','BASO','%',2),
 ('CBC_NLR','NEUT','NEUT','%',1),('CBC_NLR','LYMPH','LYMPH','%',2)
)
INSERT INTO public.clinical_calculation_formula_inputs(formula_version_id,input_key,parameter_id,parameter_code,canonical_unit,ordinal)
SELECT d.id,m.input_key,p.id,m.parameter_code,m.canonical_unit,m.ordinal
FROM mappings m JOIN public.clinical_calculation_formula_versions d ON d.formula_identifier=m.formula_identifier AND d.formula_version=1
LEFT JOIN public.tests t ON t.code='CBC'
LEFT JOIN public.parameters p ON p.test_id=t.id AND p.code=m.parameter_code;

-- Explicit safety blocks: these are not derivable by this engine.
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM public.clinical_calculation_formula_versions
    WHERE output_parameter_code IN ('RDW','MPV','PDW','P-LCR','PLCR','PT','INR')) THEN
    RAISE EXCEPTION 'CALCULATION_FORBIDDEN_OUTPUT_PRESENT';
  END IF;
END $$;

ALTER TABLE public.clinical_calculation_formula_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_calculation_formula_inputs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_calculation_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_calculation_tolerance_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_calculation_consistency_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_calculation_provenance ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.clinical_calculation_formula_versions,public.clinical_calculation_formula_inputs,
 public.clinical_calculation_runs,public.clinical_calculation_tolerance_versions,
 public.clinical_calculation_consistency_checks,public.report_calculation_provenance FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.clinical_calculation_formula_versions,public.clinical_calculation_formula_inputs,
 public.clinical_calculation_runs,public.clinical_calculation_consistency_checks,
 public.report_calculation_provenance TO authenticated;
REVOKE ALL ON FUNCTION public.normalize_clinical_calculation_input(NUMERIC,TEXT,TEXT),
 public.evaluate_governed_formula(TEXT,JSONB),public.run_governed_order_item_calculations(UUID),
 public.capture_report_calculation_provenance()
 FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON TABLE public.clinical_calculation_runs IS
'Immutable formula/input/output provenance. A measured analyzer result is never overwritten by a consistency-check calculation.';
COMMENT ON TABLE public.clinical_calculation_tolerance_versions IS
'Technical-authority approved discrepancy tolerances. Intentionally empty until explicitly approved.';
