-- Authoritative operational gates and complete collection traceability.
-- Sample state never advances result, verification, or report state.

-- Existing legacy/default intervals remain usable as historical records but are
-- not sufficient for prospective clinical-reporting enablement.
UPDATE public.tests t SET clinical_reporting_enabled=FALSE
WHERE clinical_reporting_enabled AND EXISTS (
  SELECT 1 FROM public.parameters p
  WHERE p.test_id=t.id AND p.lifecycle_status='Active' AND p.is_active
    AND (p.clinical_configuration_status='Requires Clinical Validation'
      OR p.unit_validation_required OR p.range_validation_required OR p.method_validation_required
      OR (p.value_type IN ('Numeric','Calculated') AND NOT EXISTS (
        SELECT 1 FROM public.reference_ranges r WHERE r.parameter_id=p.id
          AND r.lifecycle_status='Active' AND r.is_active AND r.is_approved
          AND r.validation_state='ClinicallyValidated'))
      OR (p.value_type='Calculated' AND NOT EXISTS (
        SELECT 1 FROM public.catalogue_calculation_definitions d
        WHERE d.identifier=p.calculation_identifier AND d.parameter_code=p.code
          AND d.server_authoritative AND d.is_active)))
);

CREATE OR REPLACE FUNCTION public.catalogue_clinical_missing_configuration(p_test_id UUID) RETURNS TEXT[]
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE; missing TEXT[]:=ARRAY[]::TEXT[]; p RECORD;
BEGIN
  PERFORM public.catalogue_require_manager(); SELECT * INTO t FROM public.tests WHERE id=p_test_id;
  IF NOT FOUND THEN RETURN ARRAY['canonical identity']; END IF;
  IF NOT t.workflow_supported OR t.reporting_type='NoReporting' OR t.workflow_type IN ('MicrobiologyCulture','Cytology','Histopathology','Molecular','NoClinicalReport')
     OR t.clinical_configuration_status='Workflow Not Supported' THEN missing:=array_append(missing,'supported clinical workflow'); END IF;
  IF t.clinical_configuration_status='Requires Clinical Validation' THEN missing:=array_append(missing,'clinical validation approval'); END IF;
  IF btrim(COALESCE(t.sample_type,''))='' THEN missing:=array_append(missing,'specimen'); END IF;
  IF btrim(COALESCE(t.container,''))='' THEN missing:=array_append(missing,'container'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.parameters WHERE test_id=t.id AND lifecycle_status='Active' AND is_active) THEN missing:=array_append(missing,'at least one active parameter'); END IF;
  IF t.analyzer_configuration_required AND NOT EXISTS(
    SELECT 1 FROM public.test_analyzer_configurations c JOIN public.analyzers a ON a.id=c.analyzer_id
    WHERE c.test_id=t.id AND c.lifecycle_status='Active' AND c.is_clinically_approved
      AND c.validation_state='ClinicallyValidated' AND a.lifecycle_status='Active'
      AND c.effective_from<=CURRENT_DATE AND (c.effective_to IS NULL OR c.effective_to>=CURRENT_DATE)
  ) THEN missing:=array_append(missing,'active clinically validated analyzer configuration'); END IF;
  FOR p IN SELECT * FROM public.parameters WHERE test_id=t.id AND lifecycle_status='Active' AND is_active LOOP
    IF p.value_type IN ('Numeric','Calculated') AND btrim(COALESCE(p.unit,''))='' THEN missing:=array_append(missing,p.code||': unit'); END IF;
    IF p.clinical_configuration_status='Requires Clinical Validation' OR p.unit_validation_required OR p.range_validation_required OR p.method_validation_required THEN missing:=array_append(missing,p.code||': clinical validation'); END IF;
    IF p.value_type='Select' AND COALESCE(jsonb_array_length(p.options),0)=0 THEN missing:=array_append(missing,p.code||': select options'); END IF;
    IF p.value_type IN ('Numeric','Calculated') AND NOT EXISTS(SELECT 1 FROM public.reference_ranges r WHERE r.parameter_id=p.id AND r.lifecycle_status='Active' AND r.is_active AND r.is_approved AND r.validation_state='ClinicallyValidated') THEN missing:=array_append(missing,p.code||': clinically validated reference-range policy'); END IF;
    IF p.value_type='Calculated' AND NOT EXISTS(SELECT 1 FROM public.catalogue_calculation_definitions d WHERE d.identifier=p.calculation_identifier AND d.parameter_code=p.code AND d.server_authoritative AND d.is_active) THEN missing:=array_append(missing,p.code||': approved server-authoritative calculation'); END IF;
  END LOOP;
  RETURN missing;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_test_missing_configuration(p_test_id UUID) RETURNS TEXT[]
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE; missing TEXT[]:=ARRAY[]::TEXT[]; p RECORD;
BEGIN
  PERFORM public.catalogue_require_manager(); SELECT * INTO t FROM public.tests WHERE id=p_test_id;
  IF NOT FOUND THEN RETURN ARRAY['canonical identity']; END IF;
  IF btrim(COALESCE(t.code,''))='' THEN missing:=array_append(missing,'unique code'); END IF;
  IF btrim(COALESCE(t.name,''))='' THEN missing:=array_append(missing,'canonical name'); END IF;
  IF t.category_id IS NULL THEN missing:=array_append(missing,'category'); END IF;
  IF t.reporting_type IS NULL THEN missing:=array_append(missing,'reporting tier'); END IF;
  IF NOT t.workflow_supported OR t.clinical_configuration_status='Workflow Not Supported' THEN missing:=array_append(missing,'supported clinical workflow'); END IF;
  IF t.clinical_configuration_status='Requires Clinical Validation' THEN missing:=array_append(missing,'clinical validation approval'); END IF;
  IF NOT t.price_configured AND t.pricing_policy NOT IN ('PricePending','Manual') AND NOT t.allow_zero_price_billing THEN missing:=array_append(missing,'configured production price'); END IF;
  IF t.price_paisa=0 AND t.price_configured AND NOT t.allow_zero_price_billing THEN missing:=array_append(missing,'zero-price billing authorization'); END IF;
  IF t.reporting_type<>'NoReporting' AND btrim(COALESCE(t.sample_type,''))='' THEN missing:=array_append(missing,'specimen'); END IF;
  IF t.reporting_type<>'NoReporting' AND NOT EXISTS(SELECT 1 FROM public.parameters WHERE test_id=t.id AND lifecycle_status='Active' AND is_active) THEN missing:=array_append(missing,'at least one active parameter'); END IF;
  FOR p IN SELECT * FROM public.parameters WHERE test_id=t.id AND lifecycle_status='Active' AND is_active LOOP
    IF p.value_type IN ('Numeric','Calculated') AND btrim(COALESCE(p.unit,''))='' THEN missing:=array_append(missing,p.code||': unit'); END IF;
    IF p.clinical_configuration_status='Requires Clinical Validation' OR p.unit_validation_required OR p.range_validation_required OR p.method_validation_required THEN missing:=array_append(missing,p.code||': clinical validation'); END IF;
    IF p.value_type='Select' AND COALESCE(jsonb_array_length(p.options),0)=0 THEN missing:=array_append(missing,p.code||': select options'); END IF;
    IF p.value_type='Calculated' AND (btrim(COALESCE(p.calculation_identifier,''))='' OR btrim(COALESCE(p.formula,''))='' OR NOT EXISTS(SELECT 1 FROM public.catalogue_calculation_definitions d WHERE d.identifier=p.calculation_identifier AND d.parameter_code=p.code AND d.server_authoritative AND d.is_active)) THEN missing:=array_append(missing,p.code||': approved server-authoritative calculation configuration'); END IF;
    IF p.value_type IN ('Numeric','Calculated') AND NOT EXISTS(SELECT 1 FROM public.reference_ranges r WHERE r.parameter_id=p.id AND r.lifecycle_status='Active' AND r.is_active AND r.is_approved AND r.validation_state='ClinicallyValidated') THEN missing:=array_append(missing,p.code||': clinically validated reference-range policy'); END IF;
  END LOOP;
  IF t.billing_enabled AND NOT (t.price_configured OR t.pricing_policy IN ('Negotiable','PricePending','Manual')) THEN missing:=array_append(missing,'valid billing price policy'); END IF;
  IF t.billing_enabled AND t.price_paisa=0 AND t.price_configured AND t.pricing_policy='Fixed' AND NOT t.allow_zero_price_billing THEN missing:=array_append(missing,'zero-price billing authorization'); END IF;
  IF t.collection_required AND btrim(COALESCE(t.sample_type,''))='' THEN missing:=array_append(missing,'specimen'); END IF;
  IF t.collection_required AND btrim(COALESCE(t.container,''))='' THEN missing:=array_append(missing,'container'); END IF;
  IF t.clinical_reporting_enabled THEN missing:=missing||public.catalogue_clinical_missing_configuration(t.id); END IF;
  RETURN missing;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_set_test_operational_gates(
  p_test_id UUID,p_billing_enabled BOOLEAN,p_clinical_reporting_enabled BOOLEAN,
  p_collection_required BOOLEAN,p_expected_version BIGINT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE; missing TEXT[]; actor TEXT;
BEGIN
  PERFORM public.catalogue_require_manager(); SELECT * INTO t FROM public.tests WHERE id=p_test_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Test not found.' USING ERRCODE='P0002'; END IF;
  IF t.row_version<>p_expected_version THEN RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
  IF p_billing_enabled AND t.lifecycle_status<>'Active' THEN RAISE EXCEPTION 'Billing requires an active catalogue identity.' USING ERRCODE='23514'; END IF;
  IF p_billing_enabled AND NOT (t.price_configured OR t.pricing_policy IN ('Negotiable','PricePending','Manual')) THEN RAISE EXCEPTION 'Billing requires a valid pricing policy.' USING ERRCODE='23514'; END IF;
  IF p_billing_enabled AND t.price_paisa=0 AND t.price_configured AND t.pricing_policy='Fixed' AND NOT t.allow_zero_price_billing THEN RAISE EXCEPTION 'Zero-price billing requires explicit authorization.' USING ERRCODE='23514'; END IF;
  IF p_clinical_reporting_enabled AND NOT p_collection_required THEN RAISE EXCEPTION 'Clinical reporting requires collection traceability.' USING ERRCODE='23514'; END IF;
  IF p_collection_required AND (btrim(COALESCE(t.sample_type,''))='' OR btrim(COALESCE(t.container,''))='') THEN RAISE EXCEPTION 'Collected services require specimen and container.' USING ERRCODE='23514'; END IF;
  IF p_clinical_reporting_enabled THEN missing:=public.catalogue_clinical_missing_configuration(p_test_id); IF cardinality(missing)>0 THEN RAISE EXCEPTION 'Clinical reporting cannot be enabled. Missing: %',array_to_string(missing,', ') USING ERRCODE='23514'; END IF; END IF;
  UPDATE public.tests SET billing_enabled=p_billing_enabled,clinical_reporting_enabled=p_clinical_reporting_enabled,
    collection_required=p_collection_required,row_version=row_version+1,updated_at=NOW() WHERE id=p_test_id;
  actor:=public.catalogue_actor_name();
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data)
  VALUES(auth.uid(),actor,'CATALOGUE_OPERATIONAL_GATES_CHANGED','Test',p_test_id::TEXT,
    jsonb_build_object('billing_enabled',t.billing_enabled,'clinical_reporting_enabled',t.clinical_reporting_enabled,'collection_required',t.collection_required),
    jsonb_build_object('billing_enabled',p_billing_enabled,'clinical_reporting_enabled',p_clinical_reporting_enabled,'collection_required',p_collection_required));
  RETURN jsonb_build_object('id',p_test_id,'billing_enabled',p_billing_enabled,'clinical_reporting_enabled',p_clinical_reporting_enabled,'collection_required',p_collection_required);
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_save_analyzer(p_analyzer JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE a public.analyzers%ROWTYPE; result_id UUID; old_row JSONB;
BEGIN
  PERFORM public.catalogue_require_manager();
  IF btrim(COALESCE(p_analyzer->>'code',''))='' OR btrim(COALESCE(p_analyzer->>'name',''))='' THEN RAISE EXCEPTION 'Analyzer code and name are required.' USING ERRCODE='22023'; END IF;
  IF NULLIF(p_analyzer->>'id','') IS NOT NULL THEN
    SELECT * INTO a FROM public.analyzers WHERE id=(p_analyzer->>'id')::UUID FOR UPDATE;
    IF NOT FOUND OR a.row_version<>p_expected_version THEN RAISE EXCEPTION 'Analyzer changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; old_row:=to_jsonb(a);result_id:=a.id;
    UPDATE public.analyzers SET code=upper(btrim(p_analyzer->>'code')),name=btrim(p_analyzer->>'name'),manufacturer=NULLIF(btrim(p_analyzer->>'manufacturer'),''),model=NULLIF(btrim(p_analyzer->>'model'),''),serial_number=NULLIF(btrim(p_analyzer->>'serial_number'),''),laboratory_location=NULLIF(btrim(p_analyzer->>'laboratory_location'),''),lifecycle_status=COALESCE((p_analyzer->>'lifecycle_status')::public.analyzer_lifecycle_enum,lifecycle_status),row_version=row_version+1,updated_at=NOW() WHERE id=result_id;
  ELSE INSERT INTO public.analyzers(code,name,manufacturer,model,serial_number,laboratory_location) VALUES(upper(btrim(p_analyzer->>'code')),btrim(p_analyzer->>'name'),NULLIF(btrim(p_analyzer->>'manufacturer'),''),NULLIF(btrim(p_analyzer->>'model'),''),NULLIF(btrim(p_analyzer->>'serial_number'),''),NULLIF(btrim(p_analyzer->>'laboratory_location'),'')) RETURNING id INTO result_id; END IF;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'ANALYZER_SAVED','Analyzer',result_id::TEXT,old_row,(SELECT to_jsonb(x) FROM public.analyzers x WHERE x.id=result_id)); RETURN result_id;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_save_test_analyzer_configuration(p_configuration JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE c public.test_analyzer_configurations%ROWTYPE; result_id UUID; old_row JSONB; approved BOOLEAN;
BEGIN
  PERFORM public.catalogue_require_manager(); approved:=COALESCE((p_configuration->>'is_clinically_approved')::BOOLEAN,FALSE);
  IF btrim(COALESCE(p_configuration->>'method',''))='' OR btrim(COALESCE(p_configuration->>'configuration_version',''))='' THEN RAISE EXCEPTION 'Method and configuration version are required.' USING ERRCODE='22023'; END IF;
  IF NULLIF(p_configuration->>'parameter_id','') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.parameters WHERE id=(p_configuration->>'parameter_id')::UUID AND test_id=(p_configuration->>'test_id')::UUID) THEN RAISE EXCEPTION 'Analyzer parameter must belong to the configured test.' USING ERRCODE='23503'; END IF;
  IF approved AND (COALESCE(p_configuration->>'validation_state','Unclassified')<>'ClinicallyValidated' OR btrim(COALESCE(p_configuration->>'validation_source',''))='') THEN RAISE EXCEPTION 'Clinical approval requires validated provenance.' USING ERRCODE='23514'; END IF;
  IF NULLIF(p_configuration->>'id','') IS NOT NULL THEN
    SELECT * INTO c FROM public.test_analyzer_configurations WHERE id=(p_configuration->>'id')::UUID FOR UPDATE;
    IF NOT FOUND OR c.row_version<>p_expected_version THEN RAISE EXCEPTION 'Analyzer configuration changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; old_row:=to_jsonb(c);result_id:=c.id;
    UPDATE public.test_analyzer_configurations SET test_id=(p_configuration->>'test_id')::UUID,parameter_id=NULLIF(p_configuration->>'parameter_id','')::UUID,analyzer_id=(p_configuration->>'analyzer_id')::UUID,method=btrim(p_configuration->>'method'),assay_identifier=NULLIF(btrim(p_configuration->>'assay_identifier'),''),configuration_version=btrim(p_configuration->>'configuration_version'),effective_from=COALESCE((p_configuration->>'effective_from')::DATE,CURRENT_DATE),effective_to=NULLIF(p_configuration->>'effective_to','')::DATE,validation_state=COALESCE((p_configuration->>'validation_state')::public.reference_range_validation_state_enum,'Unclassified'),validation_source=NULLIF(btrim(p_configuration->>'validation_source'),''),is_clinically_approved=approved,approved_by=CASE WHEN approved THEN auth.uid() END,approved_at=CASE WHEN approved THEN NOW() END,lifecycle_status=COALESCE((p_configuration->>'lifecycle_status')::public.analyzer_lifecycle_enum,lifecycle_status),row_version=row_version+1,updated_at=NOW() WHERE id=result_id;
  ELSE INSERT INTO public.test_analyzer_configurations(test_id,parameter_id,analyzer_id,method,assay_identifier,configuration_version,effective_from,effective_to,validation_state,validation_source,is_clinically_approved,approved_by,approved_at,lifecycle_status) VALUES((p_configuration->>'test_id')::UUID,NULLIF(p_configuration->>'parameter_id','')::UUID,(p_configuration->>'analyzer_id')::UUID,btrim(p_configuration->>'method'),NULLIF(btrim(p_configuration->>'assay_identifier'),''),btrim(p_configuration->>'configuration_version'),COALESCE((p_configuration->>'effective_from')::DATE,CURRENT_DATE),NULLIF(p_configuration->>'effective_to','')::DATE,COALESCE((p_configuration->>'validation_state')::public.reference_range_validation_state_enum,'Unclassified'),NULLIF(btrim(p_configuration->>'validation_source'),''),approved,CASE WHEN approved THEN auth.uid() END,CASE WHEN approved THEN NOW() END,COALESCE((p_configuration->>'lifecycle_status')::public.analyzer_lifecycle_enum,'Draft')) RETURNING id INTO result_id; END IF;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'TEST_ANALYZER_CONFIGURATION_SAVED','TestAnalyzerConfiguration',result_id::TEXT,old_row,(SELECT to_jsonb(x) FROM public.test_analyzer_configurations x WHERE x.id=result_id)); RETURN result_id;
END $$;

CREATE OR REPLACE FUNCTION public.ensure_bill_collection_traceability(p_bill_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE b public.bills%ROWTYPE; o public.clinical_orders%ROWTYPE; x RECORD; s_id UUID; key TEXT; sample_map JSONB:='{}'; actor_name TEXT; created_samples INT:=0; created_items INT:=0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  SELECT * INTO b FROM public.bills WHERE id=p_bill_id FOR SHARE; IF NOT FOUND THEN RAISE EXCEPTION 'Bill not found.' USING ERRCODE='P0002'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.bill_items bi JOIN public.tests t ON t.id=bi.test_id WHERE bi.bill_id=b.id AND (t.collection_required OR t.clinical_reporting_enabled)) THEN RETURN jsonb_build_object('order_id',NULL,'order_number',NULL,'samples_created',0,'items_created',0); END IF;
  SELECT * INTO o FROM public.clinical_orders WHERE bill_id=b.id ORDER BY created_at LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN INSERT INTO public.clinical_orders(order_number,bill_id,patient_id,order_date_ad,order_date_bs,status) VALUES('ALLOCATE-BPDC',b.id,b.patient_id,CURRENT_DATE,to_char(CURRENT_DATE,'YYYY-MM-DD'),'Registered') RETURNING * INTO o; END IF;
  SELECT COALESCE(full_name,'Billing Staff') INTO actor_name FROM public.user_profiles WHERE id=auth.uid();
  FOR x IN SELECT bi.id bill_item_id,t.* FROM public.bill_items bi JOIN public.tests t ON t.id=bi.test_id WHERE bi.bill_id=b.id AND (t.collection_required OR t.clinical_reporting_enabled) ORDER BY bi.created_at LOOP
    IF btrim(COALESCE(x.sample_type,''))='' OR btrim(COALESCE(x.container,''))='' THEN RAISE EXCEPTION 'Collected service % requires specimen and container.',x.code USING ERRCODE='23514'; END IF;
    SELECT sample_id INTO s_id FROM public.clinical_order_items WHERE bill_item_id=x.bill_item_id;
    IF s_id IS NULL THEN
      key:=x.sample_type||'::'||x.container;
      IF sample_map ? key THEN s_id:=(sample_map->>key)::UUID; ELSE
        SELECT id INTO s_id FROM public.samples WHERE order_id=o.id AND specimen_type=x.sample_type AND container_type=x.container ORDER BY created_at LIMIT 1;
        IF s_id IS NULL THEN INSERT INTO public.samples(barcode,order_id,patient_id,specimen_type,container_type,status) VALUES('SMP-'||to_char(CURRENT_DATE,'YYYY')||'-'||lpad(nextval('sample_seq')::TEXT,5,'0'),o.id,b.patient_id,x.sample_type,x.container,'Pending') RETURNING id INTO s_id; created_samples:=created_samples+1; END IF;
        sample_map:=jsonb_set(sample_map,ARRAY[key],to_jsonb(s_id::TEXT));
      END IF;
      INSERT INTO public.clinical_order_items(order_id,bill_item_id,test_id,test_name,department,reporting_type,outsource_lab_name,specimen_type,container_type,status,sample_id,workflow_type,clinical_reporting_enabled,collection_required)
      VALUES(o.id,x.bill_item_id,x.id,x.name,x.department,x.reporting_type,x.outsource_lab_name,x.sample_type,x.container,'Pending',s_id,x.workflow_type,x.clinical_reporting_enabled,x.collection_required); created_items:=created_items+1;
    ELSE UPDATE public.clinical_order_items SET workflow_type=x.workflow_type,clinical_reporting_enabled=x.clinical_reporting_enabled,collection_required=x.collection_required WHERE bill_item_id=x.bill_item_id; END IF;
  END LOOP;
  DELETE FROM public.test_results tr USING public.clinical_order_items oi WHERE tr.order_item_id=oi.id AND oi.order_id=o.id AND NOT oi.clinical_reporting_enabled;
  INSERT INTO public.sample_lifecycle_events(sample_id,from_status,to_status,reason,performed_by,performed_by_name,timestamp)
  SELECT s.id,s.status,s.status,'Sample accession created during bill finalization',auth.uid(),COALESCE(actor_name,'Billing Staff'),s.created_at FROM public.samples s WHERE s.order_id=o.id AND NOT EXISTS(SELECT 1 FROM public.sample_lifecycle_events e WHERE e.sample_id=s.id);
  RETURN jsonb_build_object('order_id',o.id,'order_number',o.order_number,'samples_created',created_samples,'items_created',created_items);
END $$;

-- Block every result write for collection-only/no-clinical-reporting order items.
CREATE OR REPLACE FUNCTION public.guard_clinical_result_write() RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.clinical_order_items WHERE id=NEW.order_item_id AND clinical_reporting_enabled) THEN RAISE EXCEPTION 'Clinical reporting is disabled for this order item.' USING ERRCODE='55000'; END IF; RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS guard_clinical_result_write_trigger ON public.test_results;
CREATE TRIGGER guard_clinical_result_write_trigger BEFORE INSERT OR UPDATE ON public.test_results FOR EACH ROW EXECUTE FUNCTION public.guard_clinical_result_write();

-- Amend the existing authoritative readiness/snapshot functions in place.
DO $report_gate_patch$ DECLARE sig REGPROCEDURE; def TEXT; fixed TEXT; BEGIN
  FOREACH sig IN ARRAY ARRAY['public.check_order_report_readiness(uuid)'::REGPROCEDURE,'public.sign_and_freeze_diagnostic_report(uuid,uuid,uuid,text,uuid)'::REGPROCEDURE] LOOP
    SELECT pg_get_functiondef(sig) INTO def;
    IF position('coi.clinical_reporting_enabled = true' IN lower(def))=0 THEN
      fixed:=replace(def,E'AND coi.reporting_type IN (''InHouse'', ''OutsourceWithBimalReport'')',E'AND coi.reporting_type IN (''InHouse'', ''OutsourceWithBimalReport'')\n          AND coi.clinical_reporting_enabled = TRUE');
      IF fixed=def THEN RAISE EXCEPTION 'Report gate patch did not match %',sig; END IF; EXECUTE fixed;
    END IF;
  END LOOP;
END $report_gate_patch$;

CREATE OR REPLACE FUNCTION public.catalogue_expand_package(p_package_id UUID) RETURNS TABLE(package_id UUID,package_code TEXT,package_name TEXT,package_price_paisa BIGINT,test_id UUID,test_code TEXT,test_name TEXT,display_order INT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.health_packages p WHERE p.id=p_package_id AND p.lifecycle_status='Active') THEN RAISE EXCEPTION 'Package is unavailable.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM public.health_package_components c JOIN public.tests t ON t.id=c.test_id WHERE c.package_id=p_package_id AND (t.lifecycle_status<>'Active' OR NOT t.is_active OR NOT t.billing_enabled)) THEN RAISE EXCEPTION 'Package contains a disabled component.' USING ERRCODE='23514'; END IF;
 RETURN QUERY SELECT p.id,p.code::TEXT,p.name::TEXT,p.price_paisa,t.id,t.code::TEXT,t.name::TEXT,c.display_order FROM public.health_packages p JOIN public.health_package_components c ON c.package_id=p.id JOIN public.tests t ON t.id=c.test_id WHERE p.id=p_package_id AND p.lifecycle_status='Active' AND t.lifecycle_status='Active' AND t.is_active AND t.billing_enabled ORDER BY c.display_order;
END $$;

CREATE OR REPLACE FUNCTION public.search_billable_catalogue(p_query TEXT,p_limit INT DEFAULT 20) RETURNS TABLE(entity_type TEXT,entity_id UUID,code TEXT,name TEXT,short_name TEXT,category TEXT,specimen TEXT,container TEXT,price_paisa BIGINT,price_configured BOOLEAN,pricing_policy public.catalogue_pricing_policy_enum,allow_zero_price_billing BOOLEAN,reporting_type public.reporting_type_enum,rank_score INT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 RETURN QUERY WITH q AS(SELECT lower(btrim(COALESCE(p_query,''))) value),m AS(
 SELECT 'Test'::TEXT,t.id,t.code::TEXT,t.name::TEXT,t.short_name::TEXT,t.category::TEXT,t.sample_type::TEXT,t.container::TEXT,t.price_paisa,t.price_configured,t.pricing_policy,t.allow_zero_price_billing,t.reporting_type,CASE WHEN lower(t.code)=q.value THEN 100 WHEN lower(t.code) LIKE q.value||'%' THEN 90 WHEN lower(COALESCE(t.short_name,'')) LIKE q.value||'%' THEN 85 WHEN q.value=ANY(t.search_aliases) THEN 82 WHEN lower(t.name) LIKE q.value||'%' THEN 75 ELSE 60 END AS rank_score FROM public.tests t,q WHERE length(q.value)>=2 AND t.lifecycle_status='Active' AND t.is_active AND t.billing_enabled AND (lower(t.code) LIKE '%'||q.value||'%' OR lower(t.name) LIKE '%'||q.value||'%' OR lower(COALESCE(t.short_name,'')) LIKE '%'||q.value||'%' OR EXISTS(SELECT 1 FROM unnest(t.search_aliases)a WHERE a LIKE '%'||q.value||'%'))
 UNION ALL SELECT 'Package',p.id,p.code::TEXT,p.name::TEXT,NULL,'Health Packages',NULL,NULL,p.price_paisa,TRUE,p.pricing_policy,FALSE,'NoReporting'::public.reporting_type_enum,CASE WHEN lower(p.code)=q.value THEN 100 WHEN lower(p.code) LIKE q.value||'%' THEN 90 ELSE 60 END FROM public.health_packages p,q WHERE length(q.value)>=2 AND p.lifecycle_status='Active' AND NOT EXISTS(SELECT 1 FROM public.health_package_components c JOIN public.tests t ON t.id=c.test_id WHERE c.package_id=p.id AND NOT t.billing_enabled) AND (lower(p.code) LIKE '%'||q.value||'%' OR lower(p.name) LIKE '%'||q.value||'%' OR EXISTS(SELECT 1 FROM unnest(p.search_aliases)a WHERE a LIKE '%'||q.value||'%')))
 SELECT m.* FROM m ORDER BY m.rank_score DESC,m.name LIMIT greatest(1,least(COALESCE(p_limit,20),50)); END $$;

-- Replace the existing authoritative package-aware entrypoint in place. This is
-- the same signature and transaction boundary introduced in 00050.
CREATE OR REPLACE FUNCTION public.create_patient_bill_order_with_packages(p_patient_data JSONB,p_bill_data JSONB,p_items_data JSONB[],p_payment_data JSONB,p_idempotency_key TEXT,p_packages JSONB DEFAULT '[]') RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE response JSONB; bill_uuid UUID; pkg JSONB; component UUID; selection_uuid UUID; expected_ids UUID[]; supplied_ids UUID[]:=ARRAY(SELECT DISTINCT (x->>'test_id')::UUID FROM unnest(p_items_data)x); package_seen UUID[]:=ARRAY[]::UUID[]; temporary_manual_price_ids UUID[]:=ARRAY[]::UUID[]; package_row public.health_packages%ROWTYPE; agreed_price BIGINT; component_price_sum BIGINT;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF cardinality(p_items_data)<>cardinality(supplied_ids) THEN RAISE EXCEPTION 'A canonical test/profile may be selected only once.' USING ERRCODE='23505'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(p_items_data)item LEFT JOIN public.tests t ON t.id=(item->>'test_id')::UUID WHERE t.id IS NULL OR t.lifecycle_status<>'Active' OR NOT t.is_active OR NOT t.billing_enabled) THEN RAISE EXCEPTION 'Only active, billing-enabled catalogue services may be billed.' USING ERRCODE='23514'; END IF;
 FOR pkg IN SELECT * FROM jsonb_array_elements(COALESCE(p_packages,'[]')) LOOP
  SELECT * INTO package_row FROM public.health_packages WHERE id=(pkg->>'package_id')::UUID AND lifecycle_status='Active' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Only active packages may be billed.' USING ERRCODE='23514'; END IF;
  SELECT array_agg(c.test_id ORDER BY c.display_order) INTO expected_ids FROM public.health_package_components c JOIN public.tests t ON t.id=c.test_id WHERE c.package_id=package_row.id AND t.lifecycle_status='Active' AND t.is_active AND t.billing_enabled;
  IF expected_ids IS NULL OR expected_ids<>ARRAY(SELECT x::UUID FROM jsonb_array_elements_text(pkg->'component_ids')x) THEN RAISE EXCEPTION 'Package definition changed or contains a disabled component. Refresh billing catalogue.' USING ERRCODE='PT409'; END IF;
  agreed_price:=(pkg->>'agreed_price_paisa')::BIGINT;
  IF agreed_price<=0 THEN RAISE EXCEPTION 'A package requires an explicit positive agreed price.' USING ERRCODE='23514'; END IF;
  IF package_row.pricing_policy='Fixed' AND agreed_price<>package_row.price_paisa THEN RAISE EXCEPTION 'A fixed package price cannot be overridden.' USING ERRCODE='42501'; END IF;
  FOREACH component IN ARRAY expected_ids LOOP IF component=ANY(package_seen) THEN RAISE EXCEPTION 'A component test may be expanded only once.' USING ERRCODE='23505'; END IF; IF NOT component=ANY(supplied_ids) THEN RAISE EXCEPTION 'Package component is missing from bill items.' USING ERRCODE='23514'; END IF; package_seen:=array_append(package_seen,component); END LOOP;
  SELECT COALESCE(sum((item->>'unit_price_paisa')::BIGINT),0) INTO component_price_sum FROM unnest(p_items_data)item WHERE (item->>'test_id')::UUID=ANY(expected_ids);
  IF component_price_sum<>agreed_price THEN RAISE EXCEPTION 'Package component prices must equal the agreed package price.' USING ERRCODE='23514'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM unnest(p_items_data)item JOIN public.tests t ON t.id=(item->>'test_id')::UUID WHERE NOT t.id=ANY(package_seen) AND COALESCE((item->>'unit_price_paisa')::BIGINT,t.price_paisa)=0 AND (NOT t.allow_zero_price_billing OR NOT COALESCE((item->>'zero_price_acknowledged')::BOOLEAN,FALSE))) THEN RAISE EXCEPTION 'Zero-price billing requires catalogue authorization and explicit operator acknowledgement.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(p_items_data)item JOIN public.tests t ON t.id=(item->>'test_id')::UUID WHERE NOT t.id=ANY(package_seen) AND NOT t.price_configured AND t.pricing_policy NOT IN ('PricePending','Manual')) THEN RAISE EXCEPTION 'A configured catalogue price is required for this pricing policy.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(p_items_data)item JOIN public.tests t ON t.id=(item->>'test_id')::UUID WHERE t.pricing_policy='Fixed' AND NOT t.id=ANY(package_seen) AND COALESCE((item->>'unit_price_paisa')::BIGINT,-1)<>t.price_paisa) THEN RAISE EXCEPTION 'Fixed catalogue prices cannot be overridden during billing.' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(p_items_data)item JOIN public.tests t ON t.id=(item->>'test_id')::UUID WHERE NOT t.id=ANY(package_seen) AND t.pricing_policy IN ('Negotiable','PricePending','Manual') AND ((item->>'unit_price_paisa') IS NULL OR (item->>'unit_price_paisa')::BIGINT<0)) THEN RAISE EXCEPTION 'Negotiable, pending, and manual items require a valid agreed rate.' USING ERRCODE='23514'; END IF;
 IF cardinality(package_seen)>0 THEN
  PERFORM 1 FROM public.tests t WHERE t.id=ANY(package_seen) ORDER BY t.id FOR UPDATE;
  SELECT COALESCE(array_agg(t.id ORDER BY t.id),ARRAY[]::UUID[]) INTO temporary_manual_price_ids FROM public.tests t WHERE t.id=ANY(package_seen) AND NOT t.allow_manual_price;
  IF cardinality(temporary_manual_price_ids)>0 THEN UPDATE public.tests SET allow_manual_price=TRUE WHERE id=ANY(temporary_manual_price_ids); END IF;
 END IF;
 response:=public.create_patient_bill_and_order(p_patient_data,p_bill_data,p_items_data,p_payment_data,p_idempotency_key); bill_uuid:=(response->>'bill_id')::UUID;
 IF cardinality(temporary_manual_price_ids)>0 THEN UPDATE public.tests SET allow_manual_price=FALSE WHERE id=ANY(temporary_manual_price_ids); END IF;
 FOR pkg IN SELECT * FROM jsonb_array_elements(COALESCE(p_packages,'[]')) LOOP
  INSERT INTO public.bill_package_selections(bill_id,package_id,package_code_snapshot,package_name_snapshot,package_price_paisa)
  SELECT bill_uuid,p.id,p.code,p.name,(pkg->>'agreed_price_paisa')::BIGINT FROM public.health_packages p WHERE p.id=(pkg->>'package_id')::UUID ON CONFLICT(bill_id,package_id) DO NOTHING RETURNING id INTO selection_uuid;
  IF selection_uuid IS NOT NULL THEN INSERT INTO public.bill_package_components(bill_package_selection_id,bill_item_id,test_id) SELECT selection_uuid,bi.id,bi.test_id FROM public.bill_items bi WHERE bi.bill_id=bill_uuid AND bi.test_id=ANY(ARRAY(SELECT x::UUID FROM jsonb_array_elements_text(pkg->'component_ids')x)); END IF;
 END LOOP;
 response:=response||public.ensure_bill_collection_traceability(bill_uuid);
 RETURN response||jsonb_build_object('packages_recorded',jsonb_array_length(COALESCE(p_packages,'[]')));
END $$;

-- Existing sample lifecycle RPC remains authoritative; no sample transition updates results/reports.
REVOKE ALL ON FUNCTION public.catalogue_clinical_missing_configuration(UUID),public.catalogue_set_test_operational_gates(UUID,BOOLEAN,BOOLEAN,BOOLEAN,BIGINT),public.catalogue_save_analyzer(JSONB,BIGINT),public.catalogue_save_test_analyzer_configuration(JSONB,BIGINT),public.ensure_bill_collection_traceability(UUID) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_clinical_missing_configuration(UUID),public.catalogue_set_test_operational_gates(UUID,BOOLEAN,BOOLEAN,BOOLEAN,BIGINT),public.catalogue_save_analyzer(JSONB,BIGINT),public.catalogue_save_test_analyzer_configuration(JSONB,BIGINT) TO authenticated;
REVOKE ALL ON FUNCTION public.guard_clinical_result_write() FROM PUBLIC,anon,authenticated;
