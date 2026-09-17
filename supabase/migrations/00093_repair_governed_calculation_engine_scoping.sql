-- ============================================================================
-- 00093_repair_governed_calculation_engine_scoping.sql
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Repair governed clinical calculation engine scoping and readiness check:
-- Decouple active approved formula execution from dynamic catalogue readiness
-- configuration counter to prevent calculation engine lockout on readiness updates.
-- ============================================================================

-- 1. Decouple approved calculation formula execution from dynamic readiness version counter.
CREATE OR REPLACE FUNCTION public.run_governed_order_item_calculations(p_order_item_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
 item public.clinical_order_items%ROWTYPE;
 ord public.clinical_orders%ROWTYPE;
 patient public.patients%ROWTYPE;
 def RECORD;
 inp RECORD;
 source RECORD;
 inputs JSONB;
 input_snapshot JSONB;
 raw_value NUMERIC;
 shown NUMERIC;
 output_result UUID;
 run_status TEXT;
 error_code TEXT;
 dependency_hash TEXT;
 missing JSONB;
 source_count INT;
BEGIN
 SELECT * INTO item FROM public.clinical_order_items WHERE id=p_order_item_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='CALCULATION_ORDER_ITEM_NOT_FOUND'; END IF;
 IF item.status='SignedOff' THEN RETURN; END IF;

 SELECT * INTO ord FROM public.clinical_orders WHERE id=item.order_id;
 SELECT * INTO patient FROM public.patients WHERE id=ord.patient_id;

 FOR def IN SELECT f.* FROM public.clinical_calculation_formula_versions f
   JOIN public.parameters op ON op.id=f.output_parameter_id
   WHERE f.lifecycle_status='Approved'
     AND f.scope_test_id=item.test_id
     AND op.test_id=item.test_id
     AND f.effective_from<=now()
     AND (f.effective_to IS NULL OR f.effective_to>now())
   ORDER BY f.execution_order,f.formula_identifier,f.formula_version
 LOOP
  inputs:='{}';
  input_snapshot:='[]';
  missing:='[]';
  run_status:='Calculated';
  error_code:=NULL;

  SELECT tr.id INTO output_result FROM public.test_results tr WHERE tr.order_item_id=item.id AND tr.parameter_id=def.output_parameter_id FOR UPDATE;
  IF output_result IS NULL THEN CONTINUE; END IF;
  UPDATE public.test_results SET numeric_value=NULL,display_value='Pending calculation',updated_at=now() WHERE id=output_result;

  FOR inp IN SELECT * FROM public.clinical_calculation_formula_inputs WHERE formula_version_id=def.id ORDER BY ordinal LOOP
   SELECT NULL::UUID id,NULL::NUMERIC numeric_value,NULL::TEXT unit,NULL::UUID parameter_id,NULL::UUID source_item_id,NULL::BIGINT source_revision INTO source;
   source_count:=0;

   IF inp.source_type='SAME_TEST_PARAMETER' THEN
    SELECT tr.id,tr.numeric_value,tr.unit::TEXT,p.id parameter_id,item.id source_item_id,item.result_revision source_revision
      INTO source FROM public.test_results tr JOIN public.parameters p ON p.id=tr.parameter_id
      WHERE tr.order_item_id=item.id AND p.id=inp.parameter_id;

   ELSIF inp.source_type='SAME_ORDER_CANONICAL_PARAMETER' THEN
    SELECT count(*) INTO source_count FROM public.test_results tr JOIN public.clinical_order_items oi ON oi.id=tr.order_item_id
      WHERE oi.order_id=item.order_id AND tr.parameter_id=inp.parameter_id AND tr.numeric_value IS NOT NULL;
    IF source_count>1 THEN
      RAISE EXCEPTION USING ERRCODE='21000',MESSAGE='CALCULATION_DEPENDENCY_AMBIGUOUS',DETAIL=jsonb_build_object('formula',def.formula_identifier,'input',inp.input_key)::TEXT;
    END IF;
    SELECT tr.id,tr.numeric_value,tr.unit::TEXT,tr.parameter_id,oi.id source_item_id,oi.result_revision source_revision
      INTO source FROM public.test_results tr JOIN public.clinical_order_items oi ON oi.id=tr.order_item_id
      WHERE oi.order_id=item.order_id AND tr.parameter_id=inp.parameter_id AND tr.numeric_value IS NOT NULL;

   ELSIF inp.source_type='PATIENT_DEMOGRAPHIC' THEN
    IF inp.source_identifier='AGE_YEARS' THEN
      source.numeric_value:=(CASE WHEN patient.dob IS NOT NULL THEN extract(year FROM age(ord.order_date_ad,patient.dob)) ELSE patient.age_years END)::NUMERIC;
      source.unit:='years'::TEXT;
    ELSIF inp.source_identifier='SEX_FEMALE' THEN
      source.numeric_value:=(CASE patient.gender WHEN 'Female' THEN 1 WHEN 'Male' THEN 0 ELSE NULL END)::NUMERIC;
      source.unit:='boolean'::TEXT;
    END IF;
    source.parameter_id:=NULL;
    source.id:=NULL;
    source.source_item_id:=NULL;
    source.source_revision:=0;

   ELSIF inp.source_type='FIXED_CONFIG_VALUE' THEN
    source.numeric_value:=NULLIF(inp.compatibility_rule->>'value','')::NUMERIC;
    source.unit:=inp.canonical_unit;
    source.source_revision:=0;
   END IF;

   IF source.numeric_value IS NULL THEN
    missing:=missing||jsonb_build_object('input_key',inp.input_key,'source_type',inp.source_type,'source_identifier',inp.source_identifier,'behavior',inp.missing_input_behavior);
    CONTINUE;
   END IF;

   raw_value:=public.normalize_clinical_calculation_input(source.numeric_value,source.unit,inp.canonical_unit);
   inputs:=jsonb_set(inputs,ARRAY[inp.input_key],to_jsonb(raw_value));
   input_snapshot:=input_snapshot||jsonb_build_object(
     'input_key',inp.input_key,
     'source_type',inp.source_type,
     'source_identifier',inp.source_identifier,
     'parameter_id',source.parameter_id,
     'result_id',source.id,
     'source_order_item_id',source.source_item_id,
     'source_revision',source.source_revision,
     'supplied_value',source.numeric_value,
     'supplied_unit',source.unit,
     'normalized_value',raw_value,
     'canonical_unit',inp.canonical_unit
   );
  END LOOP;

  dependency_hash:=encode(extensions.digest((input_snapshot||missing)::TEXT,'sha256'),'hex');

  IF jsonb_array_length(missing)>0 THEN
    run_status:='MissingInput';
    error_code:='CALCULATION_DEPENDENCY_MISSING';
  ELSE
   BEGIN
    raw_value:=public.evaluate_governed_formula(def.formula_key,inputs);
    shown:=round(raw_value,def.rounding_scale);
    UPDATE public.test_results SET numeric_value=shown,display_value=shown::TEXT,unit=def.output_unit,updated_at=now() WHERE id=output_result;
   EXCEPTION
    WHEN division_by_zero THEN
      run_status:='DivisionByZero';
      error_code:='CALCULATION_DIVISION_BY_ZERO';
      raw_value:=NULL;
      shown:=NULL;
    WHEN OTHERS THEN
      run_status:='InvalidInput';
      error_code:=SQLERRM;
      raw_value:=NULL;
      shown:=NULL;
   END;
  END IF;

  INSERT INTO public.clinical_calculation_runs(
    order_item_id,formula_version_id,output_result_id,source_result_revision,input_snapshot,
    calculated_raw_value,rounding_rule,displayed_value,output_unit,calculation_status,error_code,
    formula_snapshot,dependency_revision_hash
  )
  VALUES(
    item.id,def.id,output_result,item.result_revision,
    input_snapshot||jsonb_build_object('missing_dependencies',missing),
    raw_value,jsonb_build_object('mode',def.rounding_mode,'scale',def.rounding_scale),
    shown::TEXT,def.output_unit,run_status,error_code,
    jsonb_build_object('identifier',def.formula_identifier,'version',def.formula_version,'scope_test_id',def.scope_test_id,'expression',def.formula_expression,'definition_hash',def.definition_hash),
    dependency_hash
  )
  ON CONFLICT(order_item_id,formula_version_id,dependency_revision_hash) WHERE dependency_revision_hash IS NOT NULL DO NOTHING;
 END LOOP;
END $$;

-- 2. Decouple readiness validation from configuration_version snapshot.
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
    SELECT 1 FROM public.clinical_calculation_formula_versions f
    WHERE f.formula_identifier=p.calculation_identifier
      AND f.output_parameter_id=p.id
      AND f.scope_test_id=t.id
      AND f.lifecycle_status='Approved'
      AND f.rounding_scale IS NOT NULL
      AND f.rounding_mode IS NOT NULL
      AND NOT EXISTS(SELECT 1 FROM public.clinical_calculation_formula_inputs i WHERE i.formula_version_id=f.id AND (i.source_identifier IS NULL OR (i.source_type IN('SAME_TEST_PARAMETER','SAME_ORDER_CANONICAL_PARAMETER') AND i.parameter_id IS NULL)))
  )) THEN 'Incomplete'
  ELSE 'Ready' END::public.catalogue_result_readiness_enum
 FROM public.tests t LEFT JOIN public.catalogue_service_readiness r ON r.test_id=t.id WHERE t.id=p_test_id
$$;

-- 3. Ensure save_test_results runs authoritative calculation recomputations and verification gates.
CREATE OR REPLACE FUNCTION public.save_test_results(
  p_order_item_id UUID,
  p_results JSONB,
  p_target_status public.result_status_enum,
  p_amended_from_report_id UUID,
  p_amendment_reason TEXT,
  p_expected_revision BIGINT
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
 response JSONB;
 source_order UUID;
 dependent RECORD;
BEGIN
 response:=public.save_test_results_scoping_internal_00090(
   p_order_item_id,p_results,p_target_status,p_amended_from_report_id,p_amendment_reason,p_expected_revision
 );
 SELECT order_id INTO source_order FROM public.clinical_order_items WHERE id=p_order_item_id;
 PERFORM public.run_governed_order_item_calculations(p_order_item_id);

 IF p_target_status='Verified' AND EXISTS(
   SELECT 1 FROM public.clinical_calculation_formula_versions f
   LEFT JOIN LATERAL(
     SELECT r.calculation_status FROM public.clinical_calculation_runs r
     WHERE r.order_item_id=p_order_item_id AND r.formula_version_id=f.id
     ORDER BY r.calculated_at DESC LIMIT 1
   ) latest ON TRUE
   WHERE f.scope_test_id=(SELECT test_id FROM public.clinical_order_items WHERE id=p_order_item_id)
     AND f.lifecycle_status='Approved'
     AND COALESCE(latest.calculation_status,'MissingInput')<>'Calculated'
 ) THEN
   RAISE EXCEPTION 'CALCULATION_DEPENDENCIES_BLOCK_VERIFICATION' USING ERRCODE='23514';
 END IF;

 FOR dependent IN SELECT DISTINCT oi.id FROM public.clinical_order_items oi
   JOIN public.clinical_calculation_formula_versions f ON f.scope_test_id=oi.test_id AND f.lifecycle_status='Approved'
   JOIN public.clinical_calculation_formula_inputs i ON i.formula_version_id=f.id
   WHERE oi.order_id=source_order AND oi.id<>p_order_item_id AND oi.status NOT IN('Verified','SignedOff') AND i.source_type='SAME_ORDER_CANONICAL_PARAMETER'
     AND i.parameter_id IN(SELECT parameter_id FROM public.test_results WHERE order_item_id=p_order_item_id)
 LOOP
   PERFORM public.run_governed_order_item_calculations(dependent.id);
 END LOOP;

 RETURN response;
END $$;

REVOKE ALL ON FUNCTION public.save_test_results(UUID,JSONB,public.result_status_enum,UUID,TEXT,BIGINT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_test_results(UUID,JSONB,public.result_status_enum,UUID,TEXT,BIGINT) TO authenticated;
