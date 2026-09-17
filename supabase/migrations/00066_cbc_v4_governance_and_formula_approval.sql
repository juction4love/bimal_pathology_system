-- CBC V4 immutable source evidence and formula/reporting-mode governance.
-- No range is approved/materialized and CBC remains clinically disabled.

ALTER TABLE public.clinical_source_items
  DROP CONSTRAINT clinical_source_items_source_classification_check;
ALTER TABLE public.clinical_source_items
  ADD CONSTRAINT clinical_source_items_source_classification_check CHECK (source_classification IN (
    'AuthorizedExplicitApplicability','AuthorizedUnspecifiedAge','AuthorizedSexSpecificAgeBoundsMissing',
    'AuthorizedContextDependent','AuthorizedApproximateReviewRequired','SourceVersionChanged','SeparateCandidateParameter'
  ));

INSERT INTO public.clinical_source_imports(
  id,source_version,source_name,source_sha256,source_received_on,provenance)
VALUES('61000000-0000-0000-0000-000000000004','CBC-V4',
  'Bimal Pathology operator-authorized CBC clinical dataset V4',
  '36a4a65fa6c56c53b80c9f65de0dc3fa137113724d4c7194a92211e36315e64f',
  '2026-08-28','Operator-authorized V4 source evidence; no silent supersession or clinical validation');

WITH data(key,name,value,unit,context,note,param_code,normalized,class,conflict) AS (VALUES
 ('HB_M_10_100','Hemoglobin — Male age 10–100 years','13–17','g/dL','Male; age 10–100 years','Normalized as [10 years,100 years inclusive]; exact year/day materialization remains a technical decision','HB','{"normal_min":13,"normal_max":17,"unit":"g/dL","gender":"Male","source_age_from":"P10Y","source_age_to":"P100Y","boundary_model":"[P10Y,P100Y]"}'::jsonb,'AuthorizedExplicitApplicability','CBC.HB'),
 ('HB_F_10_100','Hemoglobin — Female age 10–100 years','12–15','g/dL','Female; age 10–100 years','Normalized as [10 years,100 years inclusive]; exact year/day materialization remains a technical decision','HB','{"normal_min":12,"normal_max":15,"unit":"g/dL","gender":"Female","source_age_from":"P10Y","source_age_to":"P100Y","boundary_model":"[P10Y,P100Y]"}'::jsonb,'AuthorizedExplicitApplicability','CBC.HB'),
 ('HB_0_21D','Hemoglobin — age 0–21 days','17–23','g/dL','All sex; age 0–21 days','Deterministic half-open normalization [0 days,21 days); day 21 belongs only to the successor interval','HB','{"normal_min":17,"normal_max":23,"unit":"g/dL","gender":"All","source_age_from":"P0D","source_age_to":"P21D","boundary_model":"[P0D,P21D)"}'::jsonb,'AuthorizedExplicitApplicability','CBC.HB'),
 ('HB_21D_10Y','Hemoglobin — age 21 days–10 years','11.2–16.5','g/dL','All sex; age 21 days–10 years','Deterministic half-open normalization [21 days,10 years); age 10 years belongs only to sex-specific successor intervals','HB','{"normal_min":11.2,"normal_max":16.5,"unit":"g/dL","gender":"All","source_age_from":"P21D","source_age_to":"P10Y","boundary_model":"[P21D,P10Y)"}'::jsonb,'AuthorizedExplicitApplicability','CBC.HB'),
 ('PCV_M','PCV/HCT — Male','41–53','%','Male; age unspecified','Age applicability remains incomplete','PCV','{"normal_min":41,"normal_max":53,"unit":"%","gender":"Male"}'::jsonb,'AuthorizedSexSpecificAgeBoundsMissing','CBC.PCV'),
 ('PCV_F','PCV/HCT — Female','36–46','%','Female; age unspecified','Age applicability remains incomplete','PCV','{"normal_min":36,"normal_max":46,"unit":"%","gender":"Female"}'::jsonb,'AuthorizedSexSpecificAgeBoundsMissing','CBC.PCV'),
 ('TLC','TLC/WBC','4.0–11.0','×10³/mm³','Age/sex unspecified','V1/V2/V3 upper bound was 10.0','TLC','{"normal_min":4000,"normal_max":11000,"unit":"/cumm","conversion":"multiply supplied bounds by 1000; 1 mm3 = 1 cumm"}'::jsonb,'SourceVersionChanged','CBC.TLC'),
 ('PLT','Platelet Count','150–400','×10³/mm³','Age/sex unspecified','V1/V2 supplied upper 350; V3 contained both 350 and 400','PLT','{"normal_min":150000,"normal_max":400000,"unit":"/cumm","conversion":"multiply supplied bounds by 1000; 1 mm3 = 1 cumm"}'::jsonb,'SourceVersionChanged','CBC.PLT'),
 ('ESR','ESR','0–10','mm/hr','Age/sex/method unspecified','Method and applicability remain incomplete','ESR','{"normal_min":0,"normal_max":10,"unit":"mm/hr"}'::jsonb,'AuthorizedContextDependent','CBC.ESR'),
 ('NEUT','Neutrophils','40–70','%','Age/sex unspecified','Age applicability remains incomplete','NEUT','{"normal_min":40,"normal_max":70,"unit":"%"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.NEUT'),
 ('LYMPH','Lymphocytes','20–40','%','Age/sex unspecified','Age applicability remains incomplete','LYMPH','{"normal_min":20,"normal_max":40,"unit":"%"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.LYMPH'),
 ('MONO','Monocytes','2–10','%','Age/sex unspecified','Age applicability remains incomplete','MONO','{"normal_min":2,"normal_max":10,"unit":"%"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.MONO'),
 ('EOSIN','Eosinophils','2–6','%','Age/sex unspecified','Age applicability remains incomplete','EOSIN','{"normal_min":2,"normal_max":6,"unit":"%"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.EOSIN'),
 ('BASO','Basophils','0–1','%','Age/sex unspecified','Age applicability remains incomplete','BASO','{"normal_min":0,"normal_max":1,"unit":"%"}'::jsonb,'AuthorizedUnspecifiedAge','CBC.BASO')
)
INSERT INTO public.clinical_source_items(import_id,source_key,canonical_parameter,supplied_value,supplied_unit,
 supplied_context,source_note,target_test_code,target_parameter_code,normalized_representation,source_classification,conflict_key)
SELECT '61000000-0000-0000-0000-000000000004',key,name,value,unit,context,note,
 CASE WHEN key='ESR' THEN 'ESR' ELSE 'CBC' END,param_code,normalized,class,conflict FROM data;

DO $$ BEGIN
  CREATE TYPE public.calculation_reporting_mode_enum AS ENUM
    ('Measured','Calculated','MeasuredWithCalculatedConsistencyCheck');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE public.parameters ADD COLUMN calculation_reporting_mode public.calculation_reporting_mode_enum
  NOT NULL DEFAULT 'Measured';
UPDATE public.parameters SET calculation_reporting_mode='Calculated' WHERE clinical_class='Calculated';

CREATE OR REPLACE FUNCTION public.catalogue_approve_calculation_formula(
 p_formula_id UUID,p_expected_identifier TEXT,p_expected_version INTEGER,p_rounding_scale SMALLINT,
 p_effective_from TIMESTAMPTZ,p_reason TEXT
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE d public.clinical_calculation_formula_versions%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager();
  SELECT * INTO d FROM public.clinical_calculation_formula_versions WHERE id=p_formula_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Formula candidate not found.' USING ERRCODE='P0002'; END IF;
  IF d.formula_identifier<>p_expected_identifier OR d.formula_version<>p_expected_version THEN
    RAISE EXCEPTION 'Formula version changed. Reload latest.' USING ERRCODE='PT409';
  END IF;
  IF d.lifecycle_status<>'Candidate' OR p_rounding_scale IS NULL OR p_rounding_scale<0 OR p_rounding_scale>12
     OR p_effective_from IS NULL OR length(btrim(COALESCE(p_reason,'')))<5 THEN
    RAISE EXCEPTION 'Formula approval requires Candidate state, explicit rounding, effective date and reason.' USING ERRCODE='23514';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.clinical_calculation_formula_inputs WHERE formula_version_id=d.id AND parameter_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Formula inputs are not mapped to catalogue parameter IDs.' USING ERRCODE='23514';
  END IF;
  UPDATE public.clinical_calculation_formula_versions SET lifecycle_status='Approved',rounding_scale=p_rounding_scale,
    rounding_mode='HalfAwayFromZero',effective_from=p_effective_from,approved_by=auth.uid(),approved_at=now(),approval_reason=btrim(p_reason)
  WHERE id=d.id;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
  VALUES(auth.uid(),public.catalogue_actor_name(),'CALCULATION_FORMULA_APPROVED','CalculationFormulaVersion',d.id::text,
    jsonb_build_object('identifier',d.formula_identifier,'version',d.formula_version,'rounding_scale',p_rounding_scale,
      'rounding_mode','HalfAwayFromZero','effective_from',p_effective_from,'reason',btrim(p_reason)));
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_set_parameter_calculation_reporting_mode(
 p_parameter_id UUID,p_mode public.calculation_reporting_mode_enum,p_reason TEXT
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.parameters%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager();
  SELECT * INTO p FROM public.parameters WHERE id=p_parameter_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Parameter not found.' USING ERRCODE='P0002'; END IF;
  IF length(btrim(COALESCE(p_reason,'')))<5 THEN RAISE EXCEPTION 'Reporting-mode reason is required.' USING ERRCODE='23514'; END IF;
  IF p_mode='Calculated' AND NOT EXISTS(SELECT 1 FROM public.clinical_calculation_formula_versions d
      WHERE d.output_parameter_id=p.id AND d.calculation_mode='Result' AND d.lifecycle_status='Approved') THEN
    RAISE EXCEPTION 'Calculated reporting requires an approved Result formula version.' USING ERRCODE='23514';
  END IF;
  IF p_mode='MeasuredWithCalculatedConsistencyCheck' AND NOT EXISTS(SELECT 1 FROM public.clinical_calculation_formula_versions d
      WHERE d.output_parameter_id=p.id AND d.calculation_mode='ConsistencyCheck' AND d.lifecycle_status='Approved') THEN
    RAISE EXCEPTION 'Consistency-check reporting requires an approved formula version.' USING ERRCODE='23514';
  END IF;
  UPDATE public.parameters SET calculation_reporting_mode=p_mode,row_version=row_version+1,updated_at=now() WHERE id=p.id;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data)
  VALUES(auth.uid(),public.catalogue_actor_name(),'PARAMETER_CALCULATION_REPORTING_MODE_CHANGED','Parameter',p.id::text,
    jsonb_build_object('mode',p.calculation_reporting_mode),jsonb_build_object('mode',p_mode,'reason',btrim(p_reason)));
END $$;

CREATE OR REPLACE VIEW public.cbc_source_version_conflict_matrix WITH (security_invoker=true) AS
SELECT s.conflict_key,s.canonical_parameter,i.source_version,s.source_key,s.supplied_value,s.supplied_unit,
 s.supplied_context,s.source_classification,s.review_state,s.normalized_representation,
 d.action selected_action,d.reason,d.status decision_status,d.approved_by
FROM public.clinical_source_items s JOIN public.clinical_source_imports i ON i.id=s.import_id
LEFT JOIN LATERAL (SELECT x.* FROM public.clinical_source_decisions x WHERE x.source_item_id=s.id
 ORDER BY x.decision_version DESC LIMIT 1) d ON true
WHERE i.source_version IN ('CBC-V1','CBC-V2','CBC-V3','CBC-V4')
ORDER BY s.conflict_key,i.source_version,s.source_key;
GRANT SELECT ON public.cbc_source_version_conflict_matrix TO authenticated;

CREATE OR REPLACE FUNCTION public.catalogue_cbc_v4_completeness()
RETURNS TABLE(parameter_code TEXT,selected_source_candidate TEXT,age_coverage TEXT,sex_coverage TEXT,
 method_analyzer_status TEXT,formula_status TEXT,conflict_status TEXT,technical_decision_required TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public.catalogue_require_manager();
  RETURN QUERY
  WITH required(code) AS (VALUES ('HB'),('TLC'),('NEUT'),('LYMPH'),('EOSIN'),('MONO'),('BASO'),('RBC'),('PCV'),('MCV'),('MCH'),('MCHC'),('RDW'),('PLT')),
  v4 AS (SELECT target_parameter_code code,string_agg(supplied_value||' '||coalesce(supplied_unit,''),'; ' ORDER BY source_key) candidate,
    bool_and(source_classification='AuthorizedExplicitApplicability') explicit_applicability,
    bool_or(source_classification='SourceVersionChanged') conflict
    FROM public.clinical_source_items s JOIN public.clinical_source_imports i ON i.id=s.import_id
    WHERE i.source_version='CBC-V4' AND target_test_code='CBC' GROUP BY target_parameter_code),
  formula AS (SELECT output_parameter_code code,string_agg(formula_identifier||' v'||formula_version||' '||lifecycle_status,', ') status
    FROM public.clinical_calculation_formula_versions WHERE formula_identifier LIKE 'CBC_%' GROUP BY output_parameter_code)
  SELECT r.code,coalesce(v4.candidate,'No V4 candidate'),
    CASE WHEN r.code='HB' THEN 'V4 intervals explicit; year/day materialization decision pending'
         WHEN v4.code IS NULL THEN 'Not supplied by V4' ELSE 'Age unspecified/incomplete' END,
    CASE WHEN r.code IN ('HB','PCV') THEN 'Sex-specific where supplied; pediatric Hb All'
         WHEN v4.code IS NULL THEN 'Not supplied by V4' ELSE 'Sex unspecified' END,
    'Technical method/analyzer applicability decision required',coalesce(formula.status,'Measured; no formula'),
    CASE WHEN v4.conflict THEN 'Source conflict requires selection' WHEN v4.code IS NULL THEN 'V1–V3 evidence retained' ELSE 'No changed numeric conflict identified in V4' END,
    CASE WHEN r.code='HB' THEN 'Select V4 policy; materialize non-overlapping age-day bounds; method/analyzer; critical-limit review'
         WHEN r.code IN ('MCV','MCH','MCHC') THEN 'Select source/applicability and Measured vs consistency-check mode; approve rounding if formula used'
         WHEN r.code IN ('RBC','RDW') THEN 'V4 missing: select/correct older source applicability'
         WHEN v4.conflict THEN 'Select source version; complete applicability; method/analyzer; critical-limit review'
         ELSE 'Complete applicability; method/analyzer; critical-limit review' END
  FROM required r LEFT JOIN v4 ON v4.code=r.code LEFT JOIN formula ON formula.code=r.code
  ORDER BY array_position(ARRAY['HB','TLC','NEUT','LYMPH','EOSIN','MONO','BASO','RBC','PCV','MCV','MCH','MCHC','RDW','PLT'],r.code);
END $$;

REVOKE ALL ON FUNCTION public.catalogue_approve_calculation_formula(UUID,TEXT,INTEGER,SMALLINT,TIMESTAMPTZ,TEXT),
 public.catalogue_set_parameter_calculation_reporting_mode(UUID,public.calculation_reporting_mode_enum,TEXT),
 public.catalogue_cbc_v4_completeness() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_approve_calculation_formula(UUID,TEXT,INTEGER,SMALLINT,TIMESTAMPTZ,TEXT),
 public.catalogue_set_parameter_calculation_reporting_mode(UUID,public.calculation_reporting_mode_enum,TEXT),
 public.catalogue_cbc_v4_completeness() TO authenticated;

DO $$ DECLARE n INT; BEGIN
 SELECT count(*) INTO n FROM public.clinical_source_items s JOIN public.clinical_source_imports i ON i.id=s.import_id WHERE i.source_version='CBC-V4';
 IF n<>14 THEN RAISE EXCEPTION 'CBC V4 expected 14 immutable items, found %',n; END IF;
 IF EXISTS(SELECT 1 FROM public.tests WHERE code='CBC' AND clinical_reporting_enabled) THEN RAISE EXCEPTION 'CBC must remain clinically disabled pending technical decisions.'; END IF;
END $$;
