-- Bimal Pathology LIS: canonical 248-test catalogue and test-scoped calculation governance.
-- Prospective configuration only. Historical bills, results, reports and snapshots are untouched.

-- ---------------------------------------------------------------------------
-- 1. Extend the existing calculation registry; do not create a parallel engine.
-- ---------------------------------------------------------------------------
ALTER TABLE public.clinical_calculation_formula_versions
  ADD COLUMN scope_test_id UUID REFERENCES public.tests(id) ON DELETE RESTRICT,
  ADD COLUMN catalogue_configuration_version BIGINT,
  ADD COLUMN execution_order SMALLINT NOT NULL DEFAULT 100;
ALTER TABLE public.clinical_calculation_formula_versions
  ADD CONSTRAINT calculation_formula_scope_complete CHECK (
    lifecycle_status<>'Approved' OR (scope_test_id IS NOT NULL AND catalogue_configuration_version IS NOT NULL)
  ) NOT VALID;

ALTER TABLE public.clinical_calculation_formula_inputs
  ADD COLUMN source_type TEXT NOT NULL DEFAULT 'SAME_TEST_PARAMETER',
  ADD COLUMN source_identifier TEXT,
  ADD COLUMN is_required BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN compatibility_rule JSONB NOT NULL DEFAULT '{}'::JSONB,
  ADD COLUMN missing_input_behavior TEXT NOT NULL DEFAULT 'BLOCK_CALCULATION';
ALTER TABLE public.clinical_calculation_formula_inputs
  ADD CONSTRAINT calculation_input_source_type_check CHECK(source_type IN
    ('SAME_TEST_PARAMETER','SAME_ORDER_CANONICAL_PARAMETER','PATIENT_DEMOGRAPHIC','FIXED_CONFIG_VALUE','APPROVED_CONTEXT_VALUE')),
  ADD CONSTRAINT calculation_input_missing_behavior_check CHECK(missing_input_behavior IN
    ('BLOCK_CALCULATION','OPTIONAL_NULL')),
  ADD CONSTRAINT calculation_input_source_identifier_check CHECK(btrim(COALESCE(source_identifier,parameter_code))<>'');

UPDATE public.clinical_calculation_formula_inputs
SET source_identifier=parameter_code WHERE source_identifier IS NULL;

ALTER TABLE public.clinical_calculation_runs
  ADD COLUMN IF NOT EXISTS dependency_revision_hash TEXT;
ALTER TABLE public.clinical_calculation_runs DROP CONSTRAINT clinical_calculation_runs_order_item_id_formula_version_id__key;
CREATE UNIQUE INDEX IF NOT EXISTS clinical_calculation_run_dependency_unique
  ON public.clinical_calculation_runs(order_item_id,formula_version_id,dependency_revision_hash)
  WHERE dependency_revision_hash IS NOT NULL;

CREATE OR REPLACE FUNCTION public.evaluate_governed_formula(p_formula_key TEXT,p_inputs JSONB)
RETURNS NUMERIC LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=public,pg_temp AS $$
DECLARE a NUMERIC;b NUMERIC;c NUMERIC;sex_factor NUMERIC;kappa NUMERIC;alpha NUMERIC;result NUMERIC;
BEGIN
 IF jsonb_typeof(p_inputs)<>'object' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_INVALID_INPUT'; END IF;
 CASE p_formula_key
  WHEN 'CBC_MCV' THEN a:=NULLIF(p_inputs->>'HCT','')::NUMERIC;b:=NULLIF(p_inputs->>'RBC','')::NUMERIC;IF b=0 THEN RAISE division_by_zero;END IF;result:=a*10/b;
  WHEN 'CBC_MCH' THEN a:=NULLIF(p_inputs->>'HB','')::NUMERIC;b:=NULLIF(p_inputs->>'RBC','')::NUMERIC;IF b=0 THEN RAISE division_by_zero;END IF;result:=a*10/b;
  WHEN 'CBC_MCHC' THEN a:=NULLIF(p_inputs->>'HB','')::NUMERIC;b:=NULLIF(p_inputs->>'HCT','')::NUMERIC;IF b=0 THEN RAISE division_by_zero;END IF;result:=a*100/b;
  WHEN 'ABS_ANC' THEN result:=(NULLIF(p_inputs->>'TLC','')::NUMERIC)*(NULLIF(p_inputs->>'NEUT','')::NUMERIC)/100;
  WHEN 'ABS_ALC' THEN result:=(NULLIF(p_inputs->>'TLC','')::NUMERIC)*(NULLIF(p_inputs->>'LYMPH','')::NUMERIC)/100;
  WHEN 'ABS_AEC' THEN result:=(NULLIF(p_inputs->>'TLC','')::NUMERIC)*(NULLIF(p_inputs->>'EOS','')::NUMERIC)/100;
  WHEN 'ABS_AMC' THEN result:=(NULLIF(p_inputs->>'TLC','')::NUMERIC)*(NULLIF(p_inputs->>'MONO','')::NUMERIC)/100;
  WHEN 'ABS_ABC' THEN result:=(NULLIF(p_inputs->>'TLC','')::NUMERIC)*(NULLIF(p_inputs->>'BASO','')::NUMERIC)/100;
  WHEN 'CBC_ANC' THEN result:=(NULLIF(p_inputs->>'WBC','')::NUMERIC)*(NULLIF(p_inputs->>'NEUT','')::NUMERIC)/100;
  WHEN 'CBC_ALC' THEN result:=(NULLIF(p_inputs->>'WBC','')::NUMERIC)*(NULLIF(p_inputs->>'LYMPH','')::NUMERIC)/100;
  WHEN 'CBC_AEC' THEN result:=(NULLIF(p_inputs->>'WBC','')::NUMERIC)*(NULLIF(p_inputs->>'EOS','')::NUMERIC)/100;
  WHEN 'CBC_AMC' THEN result:=(NULLIF(p_inputs->>'WBC','')::NUMERIC)*(NULLIF(p_inputs->>'MONO','')::NUMERIC)/100;
  WHEN 'CBC_ABC' THEN result:=(NULLIF(p_inputs->>'WBC','')::NUMERIC)*(NULLIF(p_inputs->>'BASO','')::NUMERIC)/100;
  WHEN 'CBC_NLR' THEN a:=NULLIF(p_inputs->>'NEUT','')::NUMERIC;b:=NULLIF(p_inputs->>'LYMPH','')::NUMERIC;IF b=0 THEN RAISE division_by_zero;END IF;result:=a/b;
  WHEN 'BILIRUBIN_INDIRECT' THEN a:=NULLIF(p_inputs->>'TOTAL','')::NUMERIC;b:=NULLIF(p_inputs->>'DIRECT','')::NUMERIC;IF b>a THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_DIRECT_BILIRUBIN_EXCEEDS_TOTAL';END IF;result:=a-b;
  WHEN 'GLOBULIN' THEN result:=NULLIF(p_inputs->>'TOTAL_PROTEIN','')::NUMERIC-NULLIF(p_inputs->>'ALBUMIN','')::NUMERIC;
  WHEN 'AG_RATIO' THEN a:=NULLIF(p_inputs->>'ALBUMIN','')::NUMERIC;b:=NULLIF(p_inputs->>'GLOBULIN','')::NUMERIC;IF b=0 THEN RAISE division_by_zero;END IF;result:=a/b;
  WHEN 'VLDL' THEN result:=NULLIF(p_inputs->>'TRIGLYCERIDES','')::NUMERIC/5;
  WHEN 'CHOL_HDL_RATIO' THEN a:=NULLIF(p_inputs->>'CHOLESTEROL','')::NUMERIC;b:=NULLIF(p_inputs->>'HDL','')::NUMERIC;IF b=0 THEN RAISE division_by_zero;END IF;result:=a/b;
  WHEN 'NON_HDL' THEN result:=NULLIF(p_inputs->>'CHOLESTEROL','')::NUMERIC-NULLIF(p_inputs->>'HDL','')::NUMERIC;
  WHEN 'INR' THEN a:=NULLIF(p_inputs->>'PATIENT_PT','')::NUMERIC;b:=NULLIF(p_inputs->>'MEAN_NORMAL_PT','')::NUMERIC;c:=NULLIF(p_inputs->>'ISI','')::NUMERIC;IF b=0 THEN RAISE division_by_zero;END IF;result:=power(a/b,c);
  WHEN 'EGFR_CKD_EPI_2021' THEN
    a:=NULLIF(p_inputs->>'CREATININE','')::NUMERIC;b:=NULLIF(p_inputs->>'AGE_YEARS','')::NUMERIC;sex_factor:=NULLIF(p_inputs->>'SEX_FEMALE','')::NUMERIC;
    IF sex_factor NOT IN(0,1) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_UNSUPPORTED_DEMOGRAPHIC';END IF;
    kappa:=CASE WHEN sex_factor=1 THEN 0.7 ELSE 0.9 END;alpha:=CASE WHEN sex_factor=1 THEN -0.241 ELSE -0.302 END;
    result:=142*power(least(a/kappa,1),alpha)*power(greatest(a/kappa,1),-1.200)*power(0.9938,b)*CASE WHEN sex_factor=1 THEN 1.012 ELSE 1 END;
  ELSE RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_FORMULA_NOT_IMPLEMENTED';
 END CASE;
 IF result IS NULL THEN RAISE EXCEPTION USING ERRCODE='22004',MESSAGE='CALCULATION_NULL_INPUT';END IF;
 IF abs(result)>1e30 THEN RAISE EXCEPTION USING ERRCODE='22003',MESSAGE='CALCULATION_OVERFLOW';END IF;
 RETURN result;
EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='CALCULATION_INVALID_INPUT';
END $$;

-- Only formulas attached to the current ordered test are enumerated. Each input
-- is resolved by declared source type and identifier; no implicit code lookup.
CREATE OR REPLACE FUNCTION public.run_governed_order_item_calculations(p_order_item_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE item public.clinical_order_items%ROWTYPE;ord public.clinical_orders%ROWTYPE;patient public.patients%ROWTYPE;
 def RECORD;inp RECORD;source RECORD;inputs JSONB;input_snapshot JSONB;raw_value NUMERIC;shown NUMERIC;
 output_result UUID;run_status TEXT;error_code TEXT;dependency_hash TEXT;missing JSONB;source_count INT;
BEGIN
 SELECT * INTO item FROM public.clinical_order_items WHERE id=p_order_item_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='CALCULATION_ORDER_ITEM_NOT_FOUND';END IF;
 IF item.status='SignedOff' THEN RETURN;END IF;
 SELECT * INTO ord FROM public.clinical_orders WHERE id=item.order_id;
 SELECT * INTO patient FROM public.patients WHERE id=ord.patient_id;
 FOR def IN SELECT f.* FROM public.clinical_calculation_formula_versions f
   JOIN public.parameters op ON op.id=f.output_parameter_id
   WHERE f.lifecycle_status='Approved' AND f.scope_test_id=item.test_id AND op.test_id=item.test_id
     AND f.effective_from<=now() AND (f.effective_to IS NULL OR f.effective_to>now())
     AND f.catalogue_configuration_version=(SELECT configuration_version FROM public.catalogue_service_readiness WHERE test_id=item.test_id)
   ORDER BY f.execution_order,f.formula_identifier,f.formula_version
 LOOP
  inputs:='{}';input_snapshot:='[]';missing:='[]';run_status:='Calculated';error_code:=NULL;
  SELECT tr.id INTO output_result FROM public.test_results tr WHERE tr.order_item_id=item.id AND tr.parameter_id=def.output_parameter_id FOR UPDATE;
  IF output_result IS NULL THEN CONTINUE;END IF;
  UPDATE public.test_results SET numeric_value=NULL,display_value='Pending calculation',updated_at=now() WHERE id=output_result;
  FOR inp IN SELECT * FROM public.clinical_calculation_formula_inputs WHERE formula_version_id=def.id ORDER BY ordinal LOOP
   SELECT NULL::UUID id,NULL::NUMERIC numeric_value,NULL::TEXT unit,NULL::UUID parameter_id,NULL::UUID source_item_id,NULL::BIGINT source_revision INTO source;source_count:=0;
   IF inp.source_type='SAME_TEST_PARAMETER' THEN
    SELECT tr.id,tr.numeric_value,tr.unit::TEXT,p.id parameter_id,item.id source_item_id,item.result_revision source_revision
      INTO source FROM public.test_results tr JOIN public.parameters p ON p.id=tr.parameter_id
      WHERE tr.order_item_id=item.id AND p.id=inp.parameter_id;
   ELSIF inp.source_type='SAME_ORDER_CANONICAL_PARAMETER' THEN
    SELECT count(*) INTO source_count FROM public.test_results tr JOIN public.clinical_order_items oi ON oi.id=tr.order_item_id
      WHERE oi.order_id=item.order_id AND tr.parameter_id=inp.parameter_id AND tr.numeric_value IS NOT NULL;
    IF source_count>1 THEN RAISE EXCEPTION USING ERRCODE='21000',MESSAGE='CALCULATION_DEPENDENCY_AMBIGUOUS',DETAIL=jsonb_build_object('formula',def.formula_identifier,'input',inp.input_key)::TEXT;END IF;
    SELECT tr.id,tr.numeric_value,tr.unit::TEXT,tr.parameter_id,oi.id source_item_id,oi.result_revision source_revision
      INTO source FROM public.test_results tr JOIN public.clinical_order_items oi ON oi.id=tr.order_item_id
      WHERE oi.order_id=item.order_id AND tr.parameter_id=inp.parameter_id AND tr.numeric_value IS NOT NULL;
   ELSIF inp.source_type='PATIENT_DEMOGRAPHIC' THEN
    IF inp.source_identifier='AGE_YEARS' THEN source.numeric_value:=(CASE WHEN patient.dob IS NOT NULL THEN extract(year FROM age(ord.order_date_ad,patient.dob)) ELSE patient.age_years END)::NUMERIC;source.unit:='years'::TEXT;
    ELSIF inp.source_identifier='SEX_FEMALE' THEN source.numeric_value:=(CASE patient.gender WHEN 'Female' THEN 1 WHEN 'Male' THEN 0 ELSE NULL END)::NUMERIC;source.unit:='boolean'::TEXT;END IF;
    source.parameter_id:=NULL;source.id:=NULL;source.source_item_id:=NULL;source.source_revision:=0;
   ELSIF inp.source_type='FIXED_CONFIG_VALUE' THEN source.numeric_value:=NULLIF(inp.compatibility_rule->>'value','')::NUMERIC;source.unit:=inp.canonical_unit;source.source_revision:=0;
   END IF;
   IF source.numeric_value IS NULL THEN missing:=missing||jsonb_build_object('input_key',inp.input_key,'source_type',inp.source_type,'source_identifier',inp.source_identifier,'behavior',inp.missing_input_behavior);CONTINUE;END IF;
   raw_value:=public.normalize_clinical_calculation_input(source.numeric_value,source.unit,inp.canonical_unit);
   inputs:=jsonb_set(inputs,ARRAY[inp.input_key],to_jsonb(raw_value));
   input_snapshot:=input_snapshot||jsonb_build_object('input_key',inp.input_key,'source_type',inp.source_type,'source_identifier',inp.source_identifier,'parameter_id',source.parameter_id,'result_id',source.id,'source_order_item_id',source.source_item_id,'source_revision',source.source_revision,'supplied_value',source.numeric_value,'supplied_unit',source.unit,'normalized_value',raw_value,'canonical_unit',inp.canonical_unit);
  END LOOP;
  dependency_hash:=encode(extensions.digest((input_snapshot||missing)::TEXT,'sha256'),'hex');
  IF jsonb_array_length(missing)>0 THEN run_status:='MissingInput';error_code:='CALCULATION_DEPENDENCY_MISSING';
  ELSE
   BEGIN raw_value:=public.evaluate_governed_formula(def.formula_key,inputs);shown:=round(raw_value,def.rounding_scale);
    UPDATE public.test_results SET numeric_value=shown,display_value=shown::TEXT,unit=def.output_unit,updated_at=now() WHERE id=output_result;
   EXCEPTION WHEN division_by_zero THEN run_status:='DivisionByZero';error_code:='CALCULATION_DIVISION_BY_ZERO';raw_value:=NULL;shown:=NULL;
    WHEN OTHERS THEN run_status:='InvalidInput';error_code:=SQLERRM;raw_value:=NULL;shown:=NULL;
   END;
  END IF;
  INSERT INTO public.clinical_calculation_runs(order_item_id,formula_version_id,output_result_id,source_result_revision,input_snapshot,calculated_raw_value,rounding_rule,displayed_value,output_unit,calculation_status,error_code,formula_snapshot,dependency_revision_hash)
  VALUES(item.id,def.id,output_result,item.result_revision,input_snapshot||jsonb_build_object('missing_dependencies',missing),raw_value,jsonb_build_object('mode',def.rounding_mode,'scale',def.rounding_scale),shown::TEXT,def.output_unit,run_status,error_code,jsonb_build_object('identifier',def.formula_identifier,'version',def.formula_version,'scope_test_id',def.scope_test_id,'expression',def.formula_expression,'definition_hash',def.definition_hash),dependency_hash)
  ON CONFLICT(order_item_id,formula_version_id,dependency_revision_hash) WHERE dependency_revision_hash IS NOT NULL DO NOTHING;
 END LOOP;
END $$;

-- Legacy hard-coded calculations are superseded by the scoped governed registry.
CREATE OR REPLACE FUNCTION public.recompute_order_item_calculated_results(p_order_item_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN RETURN; END $$;

-- Recompute the edited item and only explicitly scoped dependent items in the same order.
ALTER FUNCTION public.save_test_results(UUID,JSONB,public.result_status_enum,UUID,TEXT,BIGINT)
 RENAME TO save_test_results_scoping_internal_00090;
REVOKE ALL ON FUNCTION public.save_test_results_scoping_internal_00090(UUID,JSONB,public.result_status_enum,UUID,TEXT,BIGINT) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.save_test_results(p_order_item_id UUID,p_results JSONB,p_target_status public.result_status_enum,p_amended_from_report_id UUID,p_amendment_reason TEXT,p_expected_revision BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE response JSONB;source_order UUID;dependent RECORD;
BEGIN
 response:=public.save_test_results_scoping_internal_00090(p_order_item_id,p_results,p_target_status,p_amended_from_report_id,p_amendment_reason,p_expected_revision);
 SELECT order_id INTO source_order FROM public.clinical_order_items WHERE id=p_order_item_id;
 PERFORM public.run_governed_order_item_calculations(p_order_item_id);
 IF p_target_status='Verified' AND EXISTS(
   SELECT 1 FROM public.clinical_calculation_formula_versions f
   LEFT JOIN LATERAL(SELECT r.calculation_status FROM public.clinical_calculation_runs r WHERE r.order_item_id=p_order_item_id AND r.formula_version_id=f.id ORDER BY r.calculated_at DESC LIMIT 1) latest ON TRUE
   WHERE f.scope_test_id=(SELECT test_id FROM public.clinical_order_items WHERE id=p_order_item_id) AND f.lifecycle_status='Approved' AND COALESCE(latest.calculation_status,'MissingInput')<>'Calculated'
 ) THEN RAISE EXCEPTION 'CALCULATION_DEPENDENCIES_BLOCK_VERIFICATION' USING ERRCODE='23514';END IF;
 FOR dependent IN SELECT DISTINCT oi.id FROM public.clinical_order_items oi
  JOIN public.clinical_calculation_formula_versions f ON f.scope_test_id=oi.test_id AND f.lifecycle_status='Approved'
  JOIN public.clinical_calculation_formula_inputs i ON i.formula_version_id=f.id
  WHERE oi.order_id=source_order AND oi.id<>p_order_item_id AND oi.status NOT IN('Verified','SignedOff') AND i.source_type='SAME_ORDER_CANONICAL_PARAMETER'
    AND i.parameter_id IN(SELECT parameter_id FROM public.test_results WHERE order_item_id=p_order_item_id)
 LOOP PERFORM public.run_governed_order_item_calculations(dependent.id);END LOOP;
 RETURN response;
END $$;
REVOKE ALL ON FUNCTION public.save_test_results(UUID,JSONB,public.result_status_enum,UUID,TEXT,BIGINT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_test_results(UUID,JSONB,public.result_status_enum,UUID,TEXT,BIGINT) TO authenticated;

-- Migration approvals are immutable deployment provenance, not impersonated users.
ALTER TABLE public.clinical_calculation_formula_versions ADD COLUMN approval_authority TEXT NOT NULL DEFAULT 'User';
ALTER TABLE public.clinical_calculation_formula_versions DROP CONSTRAINT clinical_calculation_formula_versions_check;
ALTER TABLE public.clinical_calculation_formula_versions ADD CONSTRAINT clinical_calculation_formula_versions_approval_check CHECK (
 (lifecycle_status='Approved') = (approved_at IS NOT NULL AND effective_from IS NOT NULL AND rounding_scale IS NOT NULL AND rounding_mode IS NOT NULL
  AND ((approval_authority='User' AND approved_by IS NOT NULL) OR (approval_authority='Migration 00091' AND approved_by IS NULL)))
);

-- ---------------------------------------------------------------------------
-- 2. Canonical identity accounting and specialist result structures.
-- ---------------------------------------------------------------------------
ALTER TABLE public.tests ADD COLUMN retired_duplicate_of UUID REFERENCES public.tests(id) ON DELETE RESTRICT;
ALTER TABLE public.tests ADD COLUMN retirement_reason TEXT;
ALTER TABLE public.tests ADD CONSTRAINT tests_retirement_complete CHECK((retired_duplicate_of IS NULL AND retirement_reason IS NULL) OR (retired_duplicate_of IS NOT NULL AND btrim(retirement_reason)<>''));

-- Hosted production contains this legacy identity; pristine replay does not.
INSERT INTO public.tests(code,name,short_name,department,category,reporting_type,price_paisa,sample_type,container,tat_hours,is_active,display_order,allow_manual_price,description,test_kind,lifecycle_status,category_id,price_configured,clinical_configuration_status,workflow_supported,pricing_policy,billing_enabled,clinical_reporting_enabled,collection_required,workflow_type,reporting_model,catalogue_approved)
SELECT 'BETA HCG','Beta HCG (retired alias)','Beta HCG',department,category,'InHouse',0,sample_type,container,tat_hours,FALSE,display_order,TRUE,'Legacy spelling retained for historical compatibility.',test_kind,'Draft',category_id,FALSE,'Configured',TRUE,'PricePending',FALSE,FALSE,FALSE,'Routine',reporting_model,FALSE
FROM public.tests WHERE code='BETA_HCG' ON CONFLICT(code) DO NOTHING;

WITH aliases(alias_code,survivor_code,reason) AS (VALUES
 ('LIPID','LIPID_PROFILE','Canonical profile'),('RFT','KFT','Canonical profile'),('BETA HCG','BETA_HCG','Canonical code'),
 ('ESR_WESTERGREN','ESR','Canonical Westergren identity'),('ESR_WINTROBE','ESR','Alternative method not separately offered'),
 ('WIDAL','WIDAL_SLIDE','Canonical structured slide method'),('WIDAL_TUBE_METHOD','WIDAL_SLIDE','Alternative method not separately offered'),
 ('DLC_3PART','DLC','Canonical differential'),('AEC','ABS_DLC','Canonical calculated absolute differential'),('ANC','ABS_DLC','Canonical calculated absolute differential'))
UPDATE public.tests a SET retired_duplicate_of=s.id,retirement_reason=x.reason,is_active=FALSE,lifecycle_status='Archived',billing_enabled=FALSE,clinical_reporting_enabled=FALSE,collection_required=FALSE,archived_at=COALESCE(a.archived_at,now()),row_version=a.row_version+1,updated_at=now()
FROM aliases x JOIN public.tests s ON s.code=x.survivor_code WHERE a.code=x.alias_code;

CREATE TEMP TABLE specialist_00091(test_code TEXT,code TEXT,name TEXT,value_type public.parameter_value_type_enum,unit TEXT,display_order INT) ON COMMIT DROP;
INSERT INTO specialist_00091 VALUES
 ('AFB','MICROSCOPY','Structured microscopy','Text',NULL,1),('AFB','INTERPRETATION','Interpretation','Text',NULL,2),
 ('SKIN_SMEAR_FOR_AFB','MICROSCOPY','Structured microscopy','Text',NULL,1),('SKIN_SMEAR_FOR_AFB','INTERPRETATION','Interpretation','Text',NULL,2),
 ('FUNGAL_SCRAPING_SMEAR','MICROSCOPY','Fungal elements microscopy','Text',NULL,1),('FUNGAL_SCRAPING_SMEAR','INTERPRETATION','Interpretation','Text',NULL,2),
 ('GRAM_S_STAIN','MICROSCOPY','Gram smear morphotypes','Text',NULL,1),('GRAM_S_STAIN','INTERPRETATION','Interpretation','Text',NULL,2),
 ('CULTURE_AND_SENSITIVITY','SPECIMEN','Specimen','Text',NULL,1),('CULTURE_AND_SENSITIVITY','MICROSCOPY','Microscopy','Text',NULL,2),('CULTURE_AND_SENSITIVITY','GROWTH','Culture / growth','Text',NULL,3),('CULTURE_AND_SENSITIVITY','ORGANISM','Organism','Text',NULL,4),('CULTURE_AND_SENSITIVITY','AST','Governed AST','Text',NULL,5),('CULTURE_AND_SENSITIVITY','INTERPRETATION','Interpretation','Text',NULL,6),
 ('FNAC_FINE_NEEDLE_ASPIRATION','CLINICAL_HISTORY','Clinical history','Text',NULL,1),('FNAC_FINE_NEEDLE_ASPIRATION','SITE','Site','Text',NULL,2),('FNAC_FINE_NEEDLE_ASPIRATION','GROSS','Gross appearance','Text',NULL,3),('FNAC_FINE_NEEDLE_ASPIRATION','MICROSCOPY','Microscopy','Text',NULL,4),('FNAC_FINE_NEEDLE_ASPIRATION','IMPRESSION','Pathologist impression','Text',NULL,5),
 ('PAP_SMEAR','ADEQUACY','Specimen adequacy','Text',NULL,1),('PAP_SMEAR','BETHESDA','Bethesda category','Text',NULL,2),('PAP_SMEAR','MICROSCOPY','Microscopy','Text',NULL,3),('PAP_SMEAR','IMPRESSION','Impression','Text',NULL,4),
 ('IHC','SPECIMEN_BLOCK','Specimen / block','Text',NULL,1),('IHC','ANTIBODY_PANEL','Antibody panel','Text',NULL,2),('IHC','STAINING_RESULT','Staining / result','Text',NULL,3),('IHC','INTERPRETATION','Interpretation','Text',NULL,4),('IHC','SOURCE_LAB','Source laboratory','Text',NULL,5),
 ('SEMEN_EXAMINATION','PHYSICAL','Physical examination','Text',NULL,1),('SEMEN_EXAMINATION','VOLUME','Volume','Numeric','mL',2),('SEMEN_EXAMINATION','COUNT','Sperm count','Numeric','million/mL',3),('SEMEN_EXAMINATION','MOTILITY','Motility','Text',NULL,4),('SEMEN_EXAMINATION','MORPHOLOGY','Morphology','Text',NULL,5),('SEMEN_EXAMINATION','MICROSCOPY','Microscopy','Text',NULL,6),('SEMEN_EXAMINATION','INTERPRETATION','Interpretation','Text',NULL,7),
 ('FLUID_EXAMINATION','FLUID_SITE','Fluid / site','Text',NULL,1),('FLUID_EXAMINATION','APPEARANCE','Appearance','Text',NULL,2),('FLUID_EXAMINATION','CELLS','Cells','Numeric','/cumm',3),('FLUID_EXAMINATION','DIFFERENTIAL','Differential','Text',NULL,4),('FLUID_EXAMINATION','CHEMISTRY','Relevant chemistry','Text',NULL,5),('FLUID_EXAMINATION','INTERPRETATION','Interpretation','Text',NULL,6),
 ('HCV_RNA_QUANTITATIVE','VALUE','HCV RNA value','Numeric','IU/mL',1),('HCV_RNA_QUANTITATIVE','METHOD','Method','Text',NULL,2),('HCV_RNA_QUANTITATIVE','INTERPRETATION','Interpretation','Text',NULL,3),('HCV_RNA_QUANTITATIVE','SOURCE_LAB','Source laboratory','Text',NULL,4),
 ('GENETIC_TEST','SPECIMEN','Specimen','Text',NULL,1),('GENETIC_TEST','ASSAY','Assay','Text',NULL,2),('GENETIC_TEST','VARIANT','Detected result / variant','Text',NULL,3),('GENETIC_TEST','INTERPRETATION','Interpretation','Text',NULL,4),('GENETIC_TEST','SOURCE_LAB','Source laboratory','Text',NULL,5),
 ('SERUM_PROTEIN_ELECTROPHORESIS','ALBUMIN','Albumin','Numeric','%',1),('SERUM_PROTEIN_ELECTROPHORESIS','ALPHA_1','Alpha-1','Numeric','%',2),('SERUM_PROTEIN_ELECTROPHORESIS','ALPHA_2','Alpha-2','Numeric','%',3),('SERUM_PROTEIN_ELECTROPHORESIS','BETA','Beta','Numeric','%',4),('SERUM_PROTEIN_ELECTROPHORESIS','GAMMA','Gamma','Numeric','%',5),('SERUM_PROTEIN_ELECTROPHORESIS','M_SPIKE','M-spike','Numeric','g/dL',6),('SERUM_PROTEIN_ELECTROPHORESIS','INTERPRETATION','Interpretation','Text',NULL,7);
INSERT INTO public.parameters(test_id,code,name,value_type,unit,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,clinical_class)
SELECT t.id,s.code,s.name,s.value_type,s.unit,s.display_order,TRUE,TRUE,'Active','Configured','Measured' FROM specialist_00091 s JOIN public.tests t ON t.code=s.test_code
ON CONFLICT(test_id,code) DO UPDATE SET name=EXCLUDED.name,value_type=EXCLUDED.value_type,unit=EXCLUDED.unit,display_order=EXCLUDED.display_order,is_active=TRUE,lifecycle_status='Active',clinical_configuration_status='Configured',row_version=public.parameters.row_version+1,updated_at=now();

-- Unsupported optional derived outputs are manual or excluded; no formula is invented.
UPDATE public.parameters p SET value_type='Numeric',clinical_class='Measured',calculation_identifier=NULL,formula=NULL,formula_dependencies=ARRAY[]::TEXT[],row_version=p.row_version+1,updated_at=now()
FROM public.tests t WHERE p.test_id=t.id AND p.is_active AND ((t.code='ABG' AND p.code='HCO3') OR (t.code='LUPUS_ANTICOAGULANT_DRVVT' AND p.code='DRVVT_RATIO') OR (t.code='MICROALBUMIN_CREATININE_RATIO_URINE_RANDOM' AND p.code='ACR') OR (t.code='MICROALBUMIN_URINE_24_HOURS' AND p.code='ALBUMIN_EXCRETION') OR (t.code='IRON_PROFILE' AND p.code='TRANSFERRIN_SAT'));
UPDATE public.parameters p SET is_active=FALSE,lifecycle_status='Archived',archived_at=now(),row_version=p.row_version+1,updated_at=now()
FROM public.tests t WHERE p.test_id=t.id AND p.is_active AND ((t.code='KFT' AND p.code IN('EGFR_CATEGORY','UREA_CREAT_RATIO','BUN_CREAT_RATIO')) OR (t.code='LFT' AND p.code='SGOT_SGPT_RATIO') OR (t.code='LIPID_PROFILE' AND p.code IN('LDL_HDL_RATIO','TG_HDL_RATIO')));

-- ABS_DLC outputs are calculated and read-only. Inputs remain explicitly external.
UPDATE public.parameters p SET value_type='Calculated',clinical_class='Calculated',unit='/µL',decimal_precision=0,row_version=p.row_version+1,updated_at=now()
FROM public.tests t WHERE p.test_id=t.id AND t.code='ABS_DLC' AND p.code IN('ANC','ALC','AMC','AEC','ABC');

-- Every other survivor needs an explicit report slot; this is only a last-mile
-- structural fallback for genuine narrative identities with no supplied fields.
INSERT INTO public.parameters(test_id,code,name,value_type,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,clinical_class)
SELECT t.id,'RESULT','Result','Text',1,TRUE,TRUE,'Active','Configured','Measured' FROM public.tests t
WHERE t.retired_duplicate_of IS NULL AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active')
ON CONFLICT(test_id,code) DO UPDATE SET is_active=TRUE,lifecycle_status='Active',clinical_configuration_status='Configured',row_version=public.parameters.row_version+1,updated_at=now();

UPDATE public.tests SET is_active=TRUE,lifecycle_status='Active',reporting_type=CASE WHEN reporting_type='OutsourceWithBimalReport' THEN reporting_type ELSE 'InHouse'::public.reporting_type_enum END,billing_enabled=TRUE,clinical_reporting_enabled=TRUE,workflow_supported=TRUE,clinical_configuration_status='Configured',catalogue_approved=TRUE,workflow_type=CASE WHEN reporting_model='MicrobiologyWorkflow' THEN 'MicrobiologyCulture'::public.clinical_workflow_type_enum WHEN reporting_model='CytologyWorkflow' THEN 'Cytology'::public.clinical_workflow_type_enum WHEN reporting_model='MolecularWorkflow' THEN 'Molecular'::public.clinical_workflow_type_enum WHEN reporting_type='OutsourceWithBimalReport' THEN 'Outsource'::public.clinical_workflow_type_enum ELSE 'Routine'::public.clinical_workflow_type_enum END,collection_required=(btrim(COALESCE(sample_type,''))<>'' AND lower(COALESCE(container,''))<>'not applicable'),activated_at=COALESCE(activated_at,now()),row_version=row_version+1,updated_at=now() WHERE retired_duplicate_of IS NULL;
INSERT INTO public.catalogue_service_readiness(test_id,state,configuration_version,approved_at,decision_reason)
SELECT id,'Approved',1,now(),'00091 final canonical catalogue: Ready & Reportable.' FROM public.tests WHERE retired_duplicate_of IS NULL
ON CONFLICT(test_id) DO UPDATE SET state='Approved',configuration_version=public.catalogue_service_readiness.configuration_version+1,approved_at=now(),suspended_at=NULL,suspended_by=NULL,decision_reason='00091 final canonical catalogue: Ready & Reportable.',updated_at=now();
UPDATE public.catalogue_service_readiness r SET state='Draft',configuration_version=r.configuration_version+1,approved_at=NULL,approved_by=NULL,suspended_at=NULL,suspended_by=NULL,decision_reason='00091 RETIRED_DUPLICATE: historical identity unavailable for new use.',updated_at=now() FROM public.tests t WHERE r.test_id=t.id AND t.retired_duplicate_of IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 3. Exact operator-approved formula versions and explicit dependencies.
-- ---------------------------------------------------------------------------
INSERT INTO public.parameters(test_id,code,name,value_type,unit,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,clinical_class)
SELECT t.id,'ISI','ISI Value','Numeric','Ratio',8,TRUE,TRUE,'Active','Configured','Measured' FROM public.tests t WHERE t.code='COAG_PROFILE'
ON CONFLICT(test_id,code) DO UPDATE SET value_type='Numeric',unit='Ratio',is_active=TRUE,lifecycle_status='Active',clinical_configuration_status='Configured',row_version=public.parameters.row_version+1,updated_at=now();
UPDATE public.parameters p SET unit='Ratio',row_version=p.row_version+1,updated_at=now() FROM public.tests t WHERE p.test_id=t.id AND t.code='PT_INR' AND p.code='ISI';

CREATE TEMP TABLE formula_scope_00091(test_code TEXT,output_code TEXT,identifier TEXT,formula_key TEXT,expression TEXT,output_unit TEXT,rounding_scale SMALLINT,execution_order SMALLINT) ON COMMIT DROP;
INSERT INTO formula_scope_00091 VALUES
 ('ABS_DLC','ANC','ABS_DLC_ANC_V1','ABS_ANC','TLC * Neutrophil% / 100','/µL',0,10),
 ('ABS_DLC','ALC','ABS_DLC_ALC_V1','ABS_ALC','TLC * Lymphocyte% / 100','/µL',0,10),
 ('ABS_DLC','AMC','ABS_DLC_AMC_V1','ABS_AMC','TLC * Monocyte% / 100','/µL',0,10),
 ('ABS_DLC','AEC','ABS_DLC_AEC_V1','ABS_AEC','TLC * Eosinophil% / 100','/µL',0,10),
 ('ABS_DLC','ABC','ABS_DLC_ABC_V1','ABS_ABC','TLC * Basophil% / 100','/µL',0,10),
 ('BILIRUBIN_TD','INDIRECT_BILIRUBIN','BILIRUBIN_TD_INDIRECT_V1','BILIRUBIN_INDIRECT','Total Bilirubin - Direct Bilirubin','mg/dL',2,10),
 ('LFT','IBIL','LFT_INDIRECT_BILIRUBIN_V1','BILIRUBIN_INDIRECT','Total Bilirubin - Direct Bilirubin','mg/dL',2,10),
 ('LFT','GLOB','LFT_GLOBULIN_V1','GLOBULIN','Total Protein - Albumin','g/dL',2,20),
 ('LFT','AG_RATIO','LFT_AG_RATIO_V1','AG_RATIO','Albumin / Globulin','ratio',2,30),
 ('LIPID_PROFILE','VLDL','LIPID_VLDL_V1','VLDL','Triglycerides / 5','mg/dL',1,10),
 ('LIPID_PROFILE','TC_HDL_RATIO','LIPID_CHOL_HDL_RATIO_V1','CHOL_HDL_RATIO','Total Cholesterol / HDL','ratio',2,10),
 ('LIPID_PROFILE','NON_HDL','LIPID_NON_HDL_V1','NON_HDL','Total Cholesterol - HDL','mg/dL',1,10),
 ('PT_INR','INR','PT_INR_V1','INR','(Patient PT / Mean Normal PT)^ISI','Ratio',2,10),
 ('COAG_PROFILE','INR','COAG_PROFILE_INR_V1','INR','(Patient PT / Mean Normal PT)^ISI','Ratio',2,10),
 ('EGFR','EGFR_RESULT','EGFR_CKD_EPI_2021_V1','EGFR_CKD_EPI_2021','CKD-EPI 2021','mL/min/1.73m²',0,10),
 ('KFT','EGFR','KFT_EGFR_CKD_EPI_2021_V1','EGFR_CKD_EPI_2021','CKD-EPI 2021','mL/min/1.73m²',0,10);

INSERT INTO public.clinical_calculation_formula_versions(formula_identifier,formula_version,formula_key,formula_expression,output_parameter_id,output_parameter_code,output_unit,calculation_mode,lifecycle_status,rounding_scale,rounding_mode,effective_from,approved_at,approval_reason,approval_authority,source_provenance,definition_hash,scope_test_id,catalogue_configuration_version,execution_order)
SELECT s.identifier,1,s.formula_key,s.expression,p.id,p.code,s.output_unit,'Result','Approved',s.rounding_scale,'HalfAwayFromZero',now(),now(),'Operator-approved canonical catalogue formula.','Migration 00091','Operator-approved canonical catalogue master supplied in final catalogue task.',encode(extensions.digest(s.identifier||'|1|'||s.expression||'|'||s.output_unit||'|'||s.rounding_scale,'sha256'),'hex'),t.id,r.configuration_version,s.execution_order
FROM formula_scope_00091 s JOIN public.tests t ON t.code=s.test_code JOIN public.parameters p ON p.test_id=t.id AND p.code=s.output_code JOIN public.catalogue_service_readiness r ON r.test_id=t.id
ON CONFLICT(formula_identifier,formula_version) DO UPDATE SET formula_key=EXCLUDED.formula_key,formula_expression=EXCLUDED.formula_expression,output_parameter_id=EXCLUDED.output_parameter_id,output_parameter_code=EXCLUDED.output_parameter_code,output_unit=EXCLUDED.output_unit,calculation_mode='Result',lifecycle_status='Approved',rounding_scale=EXCLUDED.rounding_scale,rounding_mode='HalfAwayFromZero',effective_from=EXCLUDED.effective_from,effective_to=NULL,approved_by=NULL,approved_at=EXCLUDED.approved_at,approval_reason=EXCLUDED.approval_reason,approval_authority='Migration 00091',source_provenance=EXCLUDED.source_provenance,scope_test_id=EXCLUDED.scope_test_id,catalogue_configuration_version=EXCLUDED.catalogue_configuration_version,execution_order=EXCLUDED.execution_order;

CREATE TEMP TABLE formula_input_00091(identifier TEXT,input_key TEXT,source_type TEXT,source_test_code TEXT,source_parameter_code TEXT,source_identifier TEXT,canonical_unit TEXT,ordinal SMALLINT,compatibility JSONB) ON COMMIT DROP;
INSERT INTO formula_input_00091 VALUES
 ('ABS_DLC_ANC_V1','TLC','SAME_ORDER_CANONICAL_PARAMETER','TLC','TLC_VAL','TLC.TLC_VAL','/cumm',1,'{"same_order":true}'::jsonb),('ABS_DLC_ANC_V1','NEUT','SAME_ORDER_CANONICAL_PARAMETER','DLC','NEUT_VAL','DLC.NEUT_VAL','%',2,'{"same_order":true}'::jsonb),
 ('ABS_DLC_ALC_V1','TLC','SAME_ORDER_CANONICAL_PARAMETER','TLC','TLC_VAL','TLC.TLC_VAL','/cumm',1,'{"same_order":true}'::jsonb),('ABS_DLC_ALC_V1','LYMPH','SAME_ORDER_CANONICAL_PARAMETER','DLC','LYMPH_VAL','DLC.LYMPH_VAL','%',2,'{"same_order":true}'::jsonb),
 ('ABS_DLC_AMC_V1','TLC','SAME_ORDER_CANONICAL_PARAMETER','TLC','TLC_VAL','TLC.TLC_VAL','/cumm',1,'{"same_order":true}'::jsonb),('ABS_DLC_AMC_V1','MONO','SAME_ORDER_CANONICAL_PARAMETER','DLC','MONO_VAL','DLC.MONO_VAL','%',2,'{"same_order":true}'::jsonb),
 ('ABS_DLC_AEC_V1','TLC','SAME_ORDER_CANONICAL_PARAMETER','TLC','TLC_VAL','TLC.TLC_VAL','/cumm',1,'{"same_order":true}'::jsonb),('ABS_DLC_AEC_V1','EOS','SAME_ORDER_CANONICAL_PARAMETER','DLC','EOSIN_VAL','DLC.EOSIN_VAL','%',2,'{"same_order":true}'::jsonb),
 ('ABS_DLC_ABC_V1','TLC','SAME_ORDER_CANONICAL_PARAMETER','TLC','TLC_VAL','TLC.TLC_VAL','/cumm',1,'{"same_order":true}'::jsonb),('ABS_DLC_ABC_V1','BASO','SAME_ORDER_CANONICAL_PARAMETER','DLC','BASO_VAL','DLC.BASO_VAL','%',2,'{"same_order":true}'::jsonb),
 ('BILIRUBIN_TD_INDIRECT_V1','TOTAL','SAME_TEST_PARAMETER','BILIRUBIN_TD','TOTAL_BILIRUBIN','BILIRUBIN_TD.TOTAL_BILIRUBIN','mg/dL',1,'{}'),('BILIRUBIN_TD_INDIRECT_V1','DIRECT','SAME_TEST_PARAMETER','BILIRUBIN_TD','DIRECT_BILIRUBIN','BILIRUBIN_TD.DIRECT_BILIRUBIN','mg/dL',2,'{}'),
 ('LFT_INDIRECT_BILIRUBIN_V1','TOTAL','SAME_TEST_PARAMETER','LFT','TBIL','LFT.TBIL','mg/dL',1,'{}'),('LFT_INDIRECT_BILIRUBIN_V1','DIRECT','SAME_TEST_PARAMETER','LFT','DBIL','LFT.DBIL','mg/dL',2,'{}'),
 ('LFT_GLOBULIN_V1','TOTAL_PROTEIN','SAME_TEST_PARAMETER','LFT','TP','LFT.TP','g/dL',1,'{}'),('LFT_GLOBULIN_V1','ALBUMIN','SAME_TEST_PARAMETER','LFT','ALB','LFT.ALB','g/dL',2,'{}'),
 ('LFT_AG_RATIO_V1','ALBUMIN','SAME_TEST_PARAMETER','LFT','ALB','LFT.ALB','g/dL',1,'{}'),('LFT_AG_RATIO_V1','GLOBULIN','SAME_TEST_PARAMETER','LFT','GLOB','LFT.GLOB','g/dL',2,'{}'),
 ('LIPID_VLDL_V1','TRIGLYCERIDES','SAME_TEST_PARAMETER','LIPID_PROFILE','TRIG','LIPID_PROFILE.TRIG','mg/dL',1,'{}'),
 ('LIPID_CHOL_HDL_RATIO_V1','CHOLESTEROL','SAME_TEST_PARAMETER','LIPID_PROFILE','CHOL','LIPID_PROFILE.CHOL','mg/dL',1,'{}'),('LIPID_CHOL_HDL_RATIO_V1','HDL','SAME_TEST_PARAMETER','LIPID_PROFILE','HDL','LIPID_PROFILE.HDL','mg/dL',2,'{}'),
 ('LIPID_NON_HDL_V1','CHOLESTEROL','SAME_TEST_PARAMETER','LIPID_PROFILE','CHOL','LIPID_PROFILE.CHOL','mg/dL',1,'{}'),('LIPID_NON_HDL_V1','HDL','SAME_TEST_PARAMETER','LIPID_PROFILE','HDL','LIPID_PROFILE.HDL','mg/dL',2,'{}'),
 ('PT_INR_V1','PATIENT_PT','SAME_TEST_PARAMETER','PT_INR','PATIENT_PT','PT_INR.PATIENT_PT','Seconds',1,'{}'),('PT_INR_V1','MEAN_NORMAL_PT','SAME_TEST_PARAMETER','PT_INR','CONTROL_TIME','PT_INR.CONTROL_TIME','Seconds',2,'{}'),('PT_INR_V1','ISI','SAME_TEST_PARAMETER','PT_INR','ISI','PT_INR.ISI','Ratio',3,'{}'),
 ('COAG_PROFILE_INR_V1','PATIENT_PT','SAME_TEST_PARAMETER','COAG_PROFILE','PT','COAG_PROFILE.PT','Seconds',1,'{}'),('COAG_PROFILE_INR_V1','MEAN_NORMAL_PT','SAME_TEST_PARAMETER','COAG_PROFILE','PT_CONTROL','COAG_PROFILE.PT_CONTROL','Seconds',2,'{}'),('COAG_PROFILE_INR_V1','ISI','SAME_TEST_PARAMETER','COAG_PROFILE','ISI','COAG_PROFILE.ISI','Ratio',3,'{}'),
 ('EGFR_CKD_EPI_2021_V1','CREATININE','SAME_ORDER_CANONICAL_PARAMETER','CREATININE','CREAT_VAL','CREATININE.CREAT_VAL','mg/dL',1,'{"same_order":true}'),('EGFR_CKD_EPI_2021_V1','AGE_YEARS','PATIENT_DEMOGRAPHIC',NULL,NULL,'AGE_YEARS','years',2,'{"authority":"patients.dob or patients.age_years","date":"clinical_orders.order_date_ad"}'),('EGFR_CKD_EPI_2021_V1','SEX_FEMALE','PATIENT_DEMOGRAPHIC',NULL,NULL,'SEX_FEMALE','boolean',3,'{"supported":["Male","Female"]}'),
 ('KFT_EGFR_CKD_EPI_2021_V1','CREATININE','SAME_TEST_PARAMETER','KFT','CREAT','KFT.CREAT','mg/dL',1,'{}'),('KFT_EGFR_CKD_EPI_2021_V1','AGE_YEARS','PATIENT_DEMOGRAPHIC',NULL,NULL,'AGE_YEARS','years',2,'{"authority":"patients.dob or patients.age_years","date":"clinical_orders.order_date_ad"}'),('KFT_EGFR_CKD_EPI_2021_V1','SEX_FEMALE','PATIENT_DEMOGRAPHIC',NULL,NULL,'SEX_FEMALE','boolean',3,'{"supported":["Male","Female"]}');

DELETE FROM public.clinical_calculation_formula_inputs i USING public.clinical_calculation_formula_versions f WHERE i.formula_version_id=f.id AND f.formula_identifier IN(SELECT identifier FROM formula_scope_00091);
INSERT INTO public.clinical_calculation_formula_inputs(formula_version_id,input_key,parameter_id,parameter_code,canonical_unit,ordinal,source_type,source_identifier,is_required,compatibility_rule,missing_input_behavior)
SELECT f.id,i.input_key,p.id,COALESCE(i.source_parameter_code,i.source_identifier),i.canonical_unit,i.ordinal,i.source_type,i.source_identifier,TRUE,i.compatibility,'BLOCK_CALCULATION'
FROM formula_input_00091 i JOIN public.clinical_calculation_formula_versions f ON f.formula_identifier=i.identifier AND f.formula_version=1
LEFT JOIN public.tests st ON st.code=i.source_test_code LEFT JOIN public.parameters p ON p.test_id=st.id AND p.code=i.source_parameter_code;

UPDATE public.parameters p SET calculation_identifier=s.identifier,formula=s.expression,formula_dependencies=ARRAY(SELECT i.source_identifier FROM formula_input_00091 i WHERE i.identifier=s.identifier ORDER BY i.ordinal),clinical_class='Calculated',value_type='Calculated',row_version=p.row_version+1,updated_at=now()
FROM formula_scope_00091 s JOIN public.tests t ON t.code=s.test_code WHERE p.test_id=t.id AND p.code=s.output_code;

ALTER TABLE public.clinical_calculation_formula_versions VALIDATE CONSTRAINT calculation_formula_scope_complete;

CREATE OR REPLACE FUNCTION public.catalogue_test_result_readiness(p_test_id UUID)
RETURNS public.catalogue_result_readiness_enum LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT CASE WHEN t.lifecycle_status='Archived' OR NOT t.is_active THEN 'Inactive'
  WHEN r.state IN('Suspended','NeedsConfiguration') THEN 'Incomplete'
  WHEN t.reporting_type='NoReporting' OR t.workflow_type='NoClinicalReport' THEN 'NoReporting'
  WHEN NOT t.workflow_supported THEN 'SpecialistWorkflow'
  WHEN NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active') THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND (btrim(COALESCE(p.name,''))='' OR btrim(COALESCE(p.code,''))='')) THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type IN('Select','Boolean') AND (p.option_set_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.catalogue_option_values ov WHERE ov.option_set_id=p.option_set_id AND ov.is_active))) THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type='Calculated' AND NOT EXISTS(
    SELECT 1 FROM public.clinical_calculation_formula_versions f WHERE f.formula_identifier=p.calculation_identifier AND f.output_parameter_id=p.id AND f.scope_test_id=t.id AND f.lifecycle_status='Approved' AND f.catalogue_configuration_version=r.configuration_version AND f.rounding_scale IS NOT NULL AND f.rounding_mode IS NOT NULL
      AND NOT EXISTS(SELECT 1 FROM public.clinical_calculation_formula_inputs i WHERE i.formula_version_id=f.id AND (i.source_identifier IS NULL OR (i.source_type IN('SAME_TEST_PARAMETER','SAME_ORDER_CANONICAL_PARAMETER') AND i.parameter_id IS NULL)))
  )) THEN 'Incomplete'
  ELSE 'Ready' END::public.catalogue_result_readiness_enum
 FROM public.tests t LEFT JOIN public.catalogue_service_readiness r ON r.test_id=t.id WHERE t.id=p_test_id
$$;

CREATE OR REPLACE FUNCTION public.catalogue_test_operational_label(p_test_id UUID)
RETURNS TEXT LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE;r public.catalogue_service_readiness%ROWTYPE;
BEGIN
 IF NOT public.is_active_user() THEN RETURN NULL;END IF;
 SELECT * INTO t FROM public.tests WHERE id=p_test_id;SELECT * INTO r FROM public.catalogue_service_readiness WHERE test_id=p_test_id;
 RETURN CASE WHEN t.retired_duplicate_of IS NOT NULL THEN 'Inactive / Retired' WHEN NOT t.is_active OR t.lifecycle_status='Archived' THEN 'Inactive'
  WHEN r.state='Suspended' THEN 'Suspended' WHEN r.state='NeedsConfiguration' THEN 'Needs Attention'
  WHEN t.reporting_type='NoReporting' OR t.workflow_type='NoClinicalReport' THEN 'Non-Reportable Service'
  WHEN public.catalogue_test_result_readiness(t.id)='Ready' THEN 'Ready & Reportable' ELSE 'Needs Attention' END;
END $$;
REVOKE ALL ON FUNCTION public.catalogue_test_operational_label(UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.catalogue_test_operational_label(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.calculation_dependency_blockers(p_order_item_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT public.is_active_user() THEN RAISE EXCEPTION 'Inactive or anonymous users cannot view calculation dependencies.' USING ERRCODE='42501';END IF;
 RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('parameter_code',p.code,'parameter_name',p.name,'formula_identifier',f.formula_identifier,'status',r.calculation_status,'error_code',r.error_code,'missing_dependencies',COALESCE(r.input_snapshot->'missing_dependencies','[]'::jsonb)) ORDER BY p.display_order)
 FROM public.clinical_calculation_formula_versions f JOIN public.parameters p ON p.id=f.output_parameter_id
 LEFT JOIN LATERAL(SELECT x.* FROM public.clinical_calculation_runs x WHERE x.order_item_id=p_order_item_id AND x.formula_version_id=f.id ORDER BY x.calculated_at DESC LIMIT 1) r ON TRUE
 WHERE f.scope_test_id=(SELECT test_id FROM public.clinical_order_items WHERE id=p_order_item_id) AND f.lifecycle_status='Approved' AND (r.id IS NULL OR r.calculation_status<>'Calculated')),'[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.calculation_dependency_blockers(UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.calculation_dependency_blockers(UUID) TO authenticated;

-- Append existing immutable evidence when a protected owner exists. Fresh replay
-- remains deterministic without fabricating an application user.
DO $$ DECLARE actor UUID;BEGIN
 SELECT id INTO actor FROM public.user_profiles WHERE is_super_admin ORDER BY created_at LIMIT 1;
 IF actor IS NOT NULL THEN
  INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,new_state,source_metadata,reason,actor_id,actor_role)
  SELECT t.id,r.configuration_version,'FinalApproval','Approved',jsonb_build_object('state',CASE WHEN t.retired_duplicate_of IS NULL THEN 'Ready & Reportable' ELSE 'Inactive / Retired' END,'retired_duplicate_of',t.retired_duplicate_of),jsonb_build_object('migration','00091','canonical_total',248),'Final canonical catalogue configuration; historical records unchanged.',actor,'Migration 00091'
  FROM public.tests t JOIN public.catalogue_service_readiness r ON r.test_id=t.id;
 END IF;
END $$;

DO $$ DECLARE total_count INT;ready_count INT;retired_count INT;suspended_count INT;nonreporting_count INT;attention_count INT;ungoverned_count INT;bad_scope_count INT;
BEGIN
 SELECT count(*),count(*) FILTER(WHERE t.retired_duplicate_of IS NULL AND public.catalogue_test_result_readiness(t.id)='Ready'),count(*) FILTER(WHERE t.retired_duplicate_of IS NOT NULL),count(*) FILTER(WHERE r.state='Suspended'),count(*) FILTER(WHERE t.retired_duplicate_of IS NULL AND (t.reporting_type='NoReporting' OR NOT t.clinical_reporting_enabled)),count(*) FILTER(WHERE t.retired_duplicate_of IS NULL AND public.catalogue_test_result_readiness(t.id)<>'Ready')
 INTO total_count,ready_count,retired_count,suspended_count,nonreporting_count,attention_count FROM public.tests t JOIN public.catalogue_service_readiness r ON r.test_id=t.id;
 SELECT count(*) INTO ungoverned_count FROM public.parameters p JOIN public.tests t ON t.id=p.test_id WHERE t.retired_duplicate_of IS NULL AND p.is_active AND p.lifecycle_status='Active' AND p.value_type='Calculated' AND NOT EXISTS(SELECT 1 FROM public.clinical_calculation_formula_versions f WHERE f.output_parameter_id=p.id AND f.formula_identifier=p.calculation_identifier AND f.scope_test_id=t.id AND f.lifecycle_status='Approved');
 SELECT count(*) INTO bad_scope_count FROM public.clinical_calculation_formula_versions f JOIN public.parameters p ON p.id=f.output_parameter_id WHERE f.lifecycle_status='Approved' AND (f.scope_test_id IS NULL OR p.test_id<>f.scope_test_id OR EXISTS(SELECT 1 FROM public.clinical_calculation_formula_inputs i WHERE i.formula_version_id=f.id AND i.source_type IN('SAME_TEST_PARAMETER','SAME_ORDER_CANONICAL_PARAMETER') AND i.parameter_id IS NULL));
 IF total_count<>248 OR ready_count<>238 OR retired_count<>10 OR suspended_count<>0 OR nonreporting_count<>0 OR attention_count<>0 OR ungoverned_count<>0 OR bad_scope_count<>0 THEN
  RAISE EXCEPTION '00091 authoritative assertion failed total=% ready=% retired=% suspended=% nonreporting=% attention=% ungoverned=% bad_scope=%',total_count,ready_count,retired_count,suspended_count,nonreporting_count,attention_count,ungoverned_count,bad_scope_count;
 END IF;
END $$;

COMMENT ON COLUMN public.clinical_calculation_formula_versions.scope_test_id IS 'Explicit ordered test/profile scope; the runner never enumerates this formula outside that scope.';
COMMENT ON COLUMN public.clinical_calculation_formula_inputs.source_type IS 'Governed dependency source. SAME_ORDER never searches outside the current clinical order.';
