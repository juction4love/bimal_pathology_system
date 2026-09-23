-- Exception-driven catalogue readiness. Forward-only from 00089.
-- No bill, order, sample, result, report, artifact, SMS, or snapshot rows are changed.

CREATE OR REPLACE FUNCTION public.ensure_catalogue_test_readiness()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp AS $$
DECLARE v_state public.catalogue_readiness_state_enum;
BEGIN
  v_state:=CASE
    WHEN NEW.lifecycle_status='Archived' OR NOT NEW.is_active THEN 'Draft'::public.catalogue_readiness_state_enum
    WHEN NEW.reporting_type='NoReporting' OR NEW.workflow_type='NoClinicalReport' THEN 'Approved'::public.catalogue_readiness_state_enum
    WHEN NOT NEW.workflow_supported THEN 'NeedsConfiguration'::public.catalogue_readiness_state_enum
    ELSE 'Approved'::public.catalogue_readiness_state_enum
  END;
  INSERT INTO public.catalogue_service_readiness(test_id,state,decision_reason,approved_at)
  VALUES(NEW.id,v_state,
    CASE WHEN v_state='Approved' THEN 'Ready by default; Lab Technician exception control applies.'
         WHEN v_state='NeedsConfiguration' THEN 'Reporting workflow is not currently supported.'
         ELSE 'Inactive catalogue item.' END,
    CASE WHEN v_state='Approved' THEN now() END)
  ON CONFLICT(test_id) DO NOTHING;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.ensure_catalogue_test_readiness() FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION public.ensure_catalogue_test_readiness() IS 'Internal invariant trigger: active supported tests are Ready by default; explicit readiness decisions are never overwritten.';

-- Preserve the mature persistence implementation, then adapt only the new-test
-- handoff. A basic standalone service receives one generic text result slot;
-- richer/qualitative/calculated structures remain explicit Technician work.
ALTER FUNCTION public.catalogue_save_test(JSONB,BIGINT) RENAME TO catalogue_save_test_conservative_00089;
REVOKE ALL ON FUNCTION public.catalogue_save_test_conservative_00089(JSONB,BIGINT) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.catalogue_save_test(p_test JSONB,p_expected_version BIGINT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result JSONB; v_test_id UUID; is_new BOOLEAN:=NOT (p_test ? 'id') OR NULLIF(p_test->>'id','') IS NULL; report_kind public.reporting_type_enum;
BEGIN
 PERFORM public.catalogue_require_manager();
 result:=public.catalogue_save_test_conservative_00089(p_test,p_expected_version);
 v_test_id:=(result->>'id')::UUID;
 IF NOT is_new THEN RETURN result; END IF;
 report_kind:=(p_test->>'reporting_type')::public.reporting_type_enum;
 IF report_kind<>'NoReporting' THEN
   INSERT INTO public.parameters(test_id,code,name,value_type,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status)
   VALUES(v_test_id,'RESULT','Result','Text',1,TRUE,TRUE,'Active','Configured');
 END IF;
 UPDATE public.tests SET is_active=TRUE,lifecycle_status='Active',billing_enabled=TRUE,
   clinical_reporting_enabled=(report_kind<>'NoReporting'),
   collection_required=(report_kind<>'NoReporting' AND (btrim(COALESCE(sample_type,''))<>'' OR btrim(COALESCE(container,''))<>'')),
   workflow_type=CASE WHEN report_kind='NoReporting' THEN 'NoClinicalReport'::public.clinical_workflow_type_enum ELSE workflow_type END,
   clinical_configuration_status='Configured',
   activated_at=now(),activated_by=auth.uid(),row_version=row_version+1,updated_at=now() WHERE id=v_test_id;
 UPDATE public.catalogue_service_readiness SET state='Approved',configuration_version=configuration_version+1,
   approved_by=auth.uid(),approved_at=now(),decision_reason=CASE WHEN report_kind='NoReporting'
     THEN 'Created as an intentional Non-Reportable Service.' ELSE 'Created Ready & Reportable by default.' END,updated_at=now()
 WHERE catalogue_service_readiness.test_id=v_test_id;
 RETURN jsonb_build_object('id',v_test_id,'missing','[]'::JSONB,'operational_status',CASE WHEN report_kind='NoReporting' THEN 'Non-Reportable Service' ELSE 'Ready & Reportable' END);
END $$;
REVOKE ALL ON FUNCTION public.catalogue_save_test(JSONB,BIGINT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.catalogue_save_test(JSONB,BIGINT) TO authenticated;

CREATE OR REPLACE FUNCTION public.catalogue_service_readiness_checklist(p_test_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE; r public.catalogue_service_readiness%ROWTYPE; classification TEXT;
 missing TEXT[]:=ARRAY[]::TEXT[]; parameter_count INT:=0; calculation_ready BOOLEAN:=TRUE; method_ready BOOLEAN:=TRUE;
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 SELECT * INTO t FROM public.tests WHERE id=p_test_id;
 SELECT * INTO r FROM public.catalogue_service_readiness WHERE test_id=p_test_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'CATALOGUE_SERVICE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 classification:=public.catalogue_classification(t);
 SELECT count(*) INTO parameter_count FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active';
 IF btrim(COALESCE(t.code,''))='' OR btrim(COALESCE(t.name,''))='' OR t.category_id IS NULL THEN missing:=array_append(missing,'Canonical identity/category is incomplete'); END IF;
 IF NOT t.is_active OR t.lifecycle_status<>'Active' THEN missing:=array_append(missing,'Service lifecycle is not Active'); END IF;
 IF classification='SpecialistWorkflow' THEN missing:=array_append(missing,'Reporting workflow requires Technician configuration');
 ELSIF classification<>'BillingOnly' THEN
   IF t.reporting_type NOT IN ('InHouse','OutsourceWithBimalReport') THEN missing:=array_append(missing,'A report-producing reporting type is required'); END IF;
   IF t.collection_required AND (btrim(COALESCE(t.sample_type,''))='' OR btrim(COALESCE(t.container,''))='') THEN missing:=array_append(missing,'Required specimen/container configuration is missing'); END IF;
   IF parameter_count=0 AND t.reporting_model<>'NarrativeDocument' THEN missing:=array_append(missing,'Required result structure is missing'); END IF;
   IF EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND (btrim(COALESCE(p.name,''))='' OR btrim(COALESCE(p.code,''))='')) THEN missing:=array_append(missing,'An active result parameter has no identity'); END IF;
   IF EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type IN ('Select','Boolean') AND (p.option_set_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.catalogue_option_values ov WHERE ov.option_set_id=p.option_set_id AND ov.is_active))) THEN missing:=array_append(missing,'A qualitative result vocabulary is missing'); END IF;
   IF EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type='Calculated' AND (p.calculation_identifier IS NULL OR NOT EXISTS(SELECT 1 FROM public.clinical_calculation_formula_versions f WHERE f.formula_identifier=p.calculation_identifier AND f.lifecycle_status='Approved' AND f.rounding_scale IS NOT NULL))) THEN calculation_ready:=FALSE; missing:=array_append(missing,'Approved calculation formula/rounding configuration is missing'); END IF;
   IF t.analyzer_configuration_required OR EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.method_validation_required) THEN
     method_ready:=EXISTS(SELECT 1 FROM public.test_analyzer_configurations c WHERE c.test_id=t.id AND c.lifecycle_status='Active' AND c.is_clinically_approved);
     IF NOT method_ready THEN missing:=array_append(missing,'Required analyzer/method configuration is missing'); END IF;
   END IF;
 END IF;
 RETURN jsonb_build_object('test_id',t.id,'code',t.code,'name',t.name,'classification',classification,
  'active',t.is_active AND t.lifecycle_status='Active','billable',t.billing_enabled,'reporting_type',t.reporting_type,
  'reporting_model',t.reporting_model,'workflow_type',t.workflow_type,'workflow_supported',t.workflow_supported,
  'clinical_reporting_enabled',t.clinical_reporting_enabled,'collection_required',t.collection_required,
  'specimen',t.sample_type,'container',t.container,'method',t.method,'test_row_version',t.row_version,
  'parameter_count',parameter_count,'calculation_ready',calculation_ready,'method_analyzer_ready',method_ready,
  'pricing_ready',TRUE,'missing_requirements',to_jsonb(missing),'ready_for_review',cardinality(missing)=0,
  'operational_status',CASE WHEN NOT t.is_active OR t.lifecycle_status<>'Active' THEN 'Inactive'
    WHEN r.state='Suspended' THEN 'Suspended' WHEN r.state='NeedsConfiguration' THEN 'Needs Attention'
    WHEN classification='BillingOnly' THEN 'Non-Reportable Service' WHEN t.clinical_reporting_enabled THEN 'Ready & Reportable'
    ELSE 'Needs Attention' END);
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_decide_readiness(p_test_id UUID,p_decision TEXT,p_reason TEXT,p_expected_version BIGINT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.catalogue_service_readiness%ROWTYPE; t public.tests%ROWTYPE; checklist JSONB; next_version BIGINT; target public.catalogue_readiness_state_enum; old_state JSONB;
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 IF p_decision NOT IN ('MarkReady','MarkReportable','NeedsConfiguration','Suspend','Reactivate','MarkNonReportable') THEN RAISE EXCEPTION 'CATALOGUE_DECISION_INVALID' USING ERRCODE='22023'; END IF;
 IF btrim(COALESCE(p_reason,''))='' THEN RAISE EXCEPTION 'A Technician decision reason is required.' USING ERRCODE='23514'; END IF;
 SELECT * INTO r FROM public.catalogue_service_readiness WHERE test_id=p_test_id FOR UPDATE;
 SELECT * INTO t FROM public.tests WHERE id=p_test_id FOR UPDATE;
 IF NOT FOUND OR r.test_id IS NULL THEN RAISE EXCEPTION 'CATALOGUE_SERVICE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF r.configuration_version<>p_expected_version THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
 IF NOT t.is_active OR t.lifecycle_status<>'Active' THEN RAISE EXCEPTION 'Inactive or archived services cannot be made operational.' USING ERRCODE='23514'; END IF;
 old_state:=jsonb_build_object('state',r.state,'reporting_type',t.reporting_type,'clinical_reporting_enabled',t.clinical_reporting_enabled);
 checklist:=public.catalogue_service_readiness_checklist(p_test_id); next_version:=r.configuration_version+1;
 IF p_decision IN ('MarkReady','MarkReportable','Reactivate') THEN
   IF cardinality(ARRAY(SELECT jsonb_array_elements_text(checklist->'missing_requirements')))<>0 THEN RAISE EXCEPTION 'CATALOGUE_REPORTING_INVARIANT_FAILED: %',checklist->'missing_requirements' USING ERRCODE='23514'; END IF;
   IF t.reporting_type='NoReporting' THEN UPDATE public.tests SET reporting_type='InHouse',workflow_type=CASE WHEN workflow_type='NoClinicalReport' THEN 'Routine' ELSE workflow_type END,billing_enabled=TRUE,clinical_reporting_enabled=TRUE,clinical_configuration_status='Configured',row_version=row_version+1,updated_at=now() WHERE id=p_test_id;
   ELSE UPDATE public.tests SET billing_enabled=TRUE,clinical_reporting_enabled=TRUE,clinical_configuration_status='Configured',row_version=row_version+1,updated_at=now() WHERE id=p_test_id; END IF;
   target:='Approved';
 ELSIF p_decision='MarkNonReportable' THEN
   target:='Approved'; UPDATE public.tests SET reporting_type='NoReporting',workflow_type='NoClinicalReport',collection_required=FALSE,billing_enabled=TRUE,clinical_reporting_enabled=FALSE,clinical_configuration_status='Configured',row_version=row_version+1,updated_at=now() WHERE id=p_test_id;
 ELSIF p_decision='Suspend' THEN target:='Suspended'; UPDATE public.tests SET billing_enabled=FALSE,clinical_reporting_enabled=FALSE,row_version=row_version+1,updated_at=now() WHERE id=p_test_id;
 ELSE target:='NeedsConfiguration'; UPDATE public.tests SET billing_enabled=FALSE,clinical_reporting_enabled=FALSE,clinical_configuration_status='Requires Clinical Validation',row_version=row_version+1,updated_at=now() WHERE id=p_test_id;
 END IF;
 UPDATE public.catalogue_service_readiness SET state=target,configuration_version=next_version,
  approved_by=CASE WHEN target='Approved' THEN auth.uid() END,approved_at=CASE WHEN target='Approved' THEN now() END,
  suspended_by=CASE WHEN target='Suspended' THEN auth.uid() END,suspended_at=CASE WHEN target='Suspended' THEN now() END,
  decision_reason=btrim(p_reason),updated_at=now() WHERE test_id=p_test_id;
 INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,previous_state,new_state,reason,actor_id,actor_role)
 VALUES(p_test_id,next_version,'Workflow',(CASE WHEN target='Approved' THEN 'Approved' ELSE 'Rejected' END)::public.catalogue_decision_status_enum,old_state,
  checklist||jsonb_build_object('decision',p_decision,'resulting_state',target),btrim(p_reason),auth.uid(),public.catalogue_readiness_actor_role());
 RETURN next_version;
END $$;
REVOKE ALL ON FUNCTION public.catalogue_decide_readiness(UUID,TEXT,TEXT,BIGINT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.catalogue_decide_readiness(UUID,TEXT,TEXT,BIGINT) TO authenticated;
COMMENT ON FUNCTION public.catalogue_decide_readiness(UUID,TEXT,TEXT,BIGINT) IS 'Server-authoritative Lab Technician/Super Admin exception control. No Administrator approval step.';

CREATE OR REPLACE FUNCTION public.catalogue_test_result_readiness(p_test_id UUID)
RETURNS public.catalogue_result_readiness_enum LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT CASE WHEN t.lifecycle_status='Archived' OR NOT t.is_active THEN 'Inactive'
  WHEN r.state='Suspended' OR r.state='NeedsConfiguration' THEN 'Incomplete'
  WHEN t.reporting_type='NoReporting' OR t.workflow_type='NoClinicalReport' THEN 'NoReporting'
  WHEN NOT t.workflow_supported THEN 'SpecialistWorkflow' WHEN t.reporting_model='NarrativeDocument' THEN 'DocumentWorkflow'
  WHEN NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active') THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND (btrim(COALESCE(p.name,''))='' OR btrim(COALESCE(p.code,''))='')) THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type IN ('Select','Boolean') AND (p.option_set_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.catalogue_option_values ov WHERE ov.option_set_id=p.option_set_id AND ov.is_active))) THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type='Calculated' AND p.calculation_identifier IS NULL) THEN 'Incomplete'
  ELSE 'Ready' END::public.catalogue_result_readiness_enum
 FROM public.tests t LEFT JOIN public.catalogue_service_readiness r ON r.test_id=t.id WHERE t.id=p_test_id
$$;

CREATE OR REPLACE FUNCTION public.catalogue_test_operational_label(p_test_id UUID)
RETURNS TEXT LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE;r public.catalogue_service_readiness%ROWTYPE;
BEGIN
 IF NOT public.is_active_user() THEN RETURN NULL; END IF;
 SELECT * INTO t FROM public.tests WHERE id=p_test_id;
 SELECT * INTO r FROM public.catalogue_service_readiness WHERE test_id=p_test_id;
 RETURN CASE WHEN NOT t.is_active OR t.lifecycle_status='Archived' THEN 'Inactive'
  WHEN r.state='Suspended' THEN 'Suspended' WHEN r.state='NeedsConfiguration' THEN 'Needs Attention'
  WHEN t.reporting_type='NoReporting' OR t.workflow_type='NoClinicalReport' THEN 'Non-Reportable Service'
  WHEN public.catalogue_test_result_readiness(t.id)='Ready' THEN 'Ready & Reportable' ELSE 'Needs Attention' END;
END $$;
REVOKE ALL ON FUNCTION public.catalogue_test_operational_label(UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.catalogue_test_operational_label(UUID) TO authenticated;

CREATE OR REPLACE VIEW public.catalogue_test_operational_state WITH (security_invoker=true) AS
SELECT t.id test_id,public.catalogue_test_result_readiness(t.id) readiness,
 public.catalogue_test_operational_label(t.id) operational_state
FROM public.tests t;
REVOKE ALL ON public.catalogue_test_operational_state FROM PUBLIC,anon;
GRANT SELECT ON public.catalogue_test_operational_state TO authenticated;

-- Controlled reconciliation: only the exact 00089 default blocker, with no human evidence.
-- Explicit suspension, non-reporting, inactive/archive, and reviewed decisions are untouched.
WITH candidates AS (
 SELECT r.test_id,r.configuration_version
 FROM public.catalogue_service_readiness r JOIN public.tests t ON t.id=r.test_id
 WHERE r.state='NeedsConfiguration' AND r.decision_reason='Catalogue test entered readiness governance.'
   AND t.is_active AND t.lifecycle_status='Active' AND t.workflow_supported
   AND t.reporting_type IN ('InHouse','OutsourceWithBimalReport')
   AND NOT EXISTS(SELECT 1 FROM public.catalogue_configuration_evidence e WHERE e.test_id=t.id)
), reconciled AS (
 UPDATE public.catalogue_service_readiness r SET state='Approved',configuration_version=r.configuration_version+1,
   approved_at=now(),decision_reason='00090 reconciliation: removed 00089 default blocker; no explicit operational decision existed.',updated_at=now()
 FROM candidates c WHERE r.test_id=c.test_id RETURNING r.test_id,r.configuration_version
)
INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,new_state,reason,actor_role)
SELECT test_id,configuration_version,'Workflow','Approved',jsonb_build_object('migration','00090','old_default_blocker_removed',TRUE),
 'Controlled migration reconciliation; explicit Technician decisions were excluded.','Migration 00090' FROM reconciled;

UPDATE public.tests t SET clinical_reporting_enabled=TRUE,clinical_configuration_status='Configured',row_version=row_version+1,updated_at=now()
WHERE t.is_active AND t.lifecycle_status='Active' AND t.workflow_supported AND t.reporting_type IN ('InHouse','OutsourceWithBimalReport')
 AND EXISTS(SELECT 1 FROM public.catalogue_service_readiness r WHERE r.test_id=t.id AND r.state='Approved' AND r.decision_reason='00090 reconciliation: removed 00089 default blocker; no explicit operational decision existed.');
