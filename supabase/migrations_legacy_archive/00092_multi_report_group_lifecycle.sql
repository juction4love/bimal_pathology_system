-- Multi-investigation orders with frozen clinical report groups.
-- Existing whole-order reports remain legacy rows (report_group_id IS NULL).

ALTER TABLE public.tests
  ADD COLUMN report_group_key TEXT,
  ADD COLUMN report_group_title TEXT,
  ADD COLUMN report_section TEXT,
  ADD COLUMN report_group_sort_order INTEGER NOT NULL DEFAULT 500,
  ADD COLUMN specimen_requirement_key TEXT;

UPDATE public.tests t SET
  report_group_key = CASE
    WHEN t.code='CBC' THEN 'hematology'
    WHEN t.code IN ('LFT','KFT') THEN 'biochemistry'
    WHEN t.code='THYROID_PROFILE' THEN 'endocrinology'
    WHEN t.code='URINE_RE' THEN 'clinical_pathology'
    WHEN lower(coalesce(t.department,t.category,'')) ~ 'hemat' THEN 'hematology'
    WHEN lower(coalesce(t.department,t.category,'')) ~ 'thyroid|hormone|endocr' THEN 'endocrinology'
    WHEN lower(coalesce(t.department,t.category,'')) ~ 'urine|stool|clinical path' THEN 'clinical_pathology'
    WHEN lower(coalesce(t.department,t.category,'')) ~ 'micro|culture|bacter|fung' THEN 'microbiology'
    WHEN lower(coalesce(t.department,t.category,'')) ~ 'cyto|histo|pathology' THEN 'anatomic_pathology'
    ELSE 'biochemistry' END,
  report_group_title = CASE
    WHEN t.code='CBC' THEN 'Hematology'
    WHEN t.code IN ('LFT','KFT') THEN 'Biochemistry'
    WHEN t.code='THYROID_PROFILE' THEN 'Endocrinology'
    WHEN t.code='URINE_RE' THEN 'Clinical Pathology'
    WHEN lower(coalesce(t.department,t.category,'')) ~ 'hemat' THEN 'Hematology'
    WHEN lower(coalesce(t.department,t.category,'')) ~ 'thyroid|hormone|endocr' THEN 'Endocrinology'
    WHEN lower(coalesce(t.department,t.category,'')) ~ 'urine|stool|clinical path' THEN 'Clinical Pathology'
    WHEN lower(coalesce(t.department,t.category,'')) ~ 'micro|culture|bacter|fung' THEN 'Microbiology'
    WHEN lower(coalesce(t.department,t.category,'')) ~ 'cyto|histo|pathology' THEN 'Anatomic Pathology'
    ELSE 'Biochemistry' END,
  report_section = coalesce(nullif(t.department,''),nullif(t.category,''),'Laboratory'),
  report_group_sort_order = CASE
    WHEN t.code='CBC' OR lower(coalesce(t.department,t.category,'')) ~ 'hemat' THEN 100
    WHEN t.code IN ('LFT','KFT') THEN 200
    WHEN t.code='THYROID_PROFILE' THEN 300
    WHEN t.code='URINE_RE' THEN 400 ELSE 500 END,
  specimen_requirement_key = CASE WHEN NOT coalesce(t.collection_required,t.requires_sample_tracking,false)
    THEN 'NO_SAMPLE' ELSE upper(regexp_replace(trim(coalesce(t.sample_type,'UNSPECIFIED'))||'|'||trim(coalesce(t.container,'UNSPECIFIED')),'[^A-Za-z0-9]+','_','g')) END;

ALTER TABLE public.tests
  ALTER COLUMN report_group_key SET NOT NULL,
  ALTER COLUMN report_group_title SET NOT NULL,
  ALTER COLUMN report_section SET NOT NULL,
  ALTER COLUMN specimen_requirement_key SET NOT NULL,
  ALTER COLUMN report_group_key SET DEFAULT 'general_laboratory',
  ALTER COLUMN report_group_title SET DEFAULT 'General Laboratory',
  ALTER COLUMN report_section SET DEFAULT 'Laboratory',
  ALTER COLUMN specimen_requirement_key SET DEFAULT 'NO_SAMPLE',
  ADD CONSTRAINT tests_report_group_key_format CHECK(report_group_key ~ '^[a-z][a-z0-9_]{1,63}$'),
  ADD CONSTRAINT tests_specimen_requirement_key_format CHECK(specimen_requirement_key ~ '^[A-Z0-9_]{2,120}$');

CREATE OR REPLACE FUNCTION public.freeze_test_delivery_configuration() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NEW.report_group_key IS NULL OR NEW.report_group_key='' THEN NEW.report_group_key:='general_laboratory'; END IF;
 IF NEW.report_group_title IS NULL OR NEW.report_group_title='' THEN NEW.report_group_title:='General Laboratory'; END IF;
 IF NEW.report_section IS NULL OR NEW.report_section='' THEN NEW.report_section:=coalesce(nullif(NEW.department,''),nullif(NEW.category,''),'Laboratory'); END IF;
 NEW.specimen_requirement_key:=CASE WHEN NOT coalesce(NEW.collection_required,NEW.requires_sample_tracking,false) THEN 'NO_SAMPLE' ELSE upper(regexp_replace(trim(coalesce(NEW.sample_type,'UNSPECIFIED'))||'|'||trim(coalesce(NEW.container,'UNSPECIFIED')),'[^A-Za-z0-9]+','_','g')) END;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_freeze_test_delivery_configuration BEFORE INSERT OR UPDATE OF sample_type,container,collection_required,requires_sample_tracking,report_group_key,report_group_title,report_section ON public.tests FOR EACH ROW EXECUTE FUNCTION public.freeze_test_delivery_configuration();

CREATE TABLE public.clinical_report_groups(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.clinical_orders(id) ON DELETE RESTRICT,
  group_key TEXT NOT NULL,
  title TEXT NOT NULL,
  clinical_section TEXT NOT NULL,
  display_order INTEGER NOT NULL,
  lifecycle_state TEXT NOT NULL DEFAULT 'Pending' CHECK(lifecycle_state IN ('Pending','InProgress','ReadyToSign','Signed','Amended')),
  configuration_version BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  row_version BIGINT NOT NULL DEFAULT 1,
  UNIQUE(order_id,group_key)
);

CREATE TABLE public.clinical_report_group_items(
  report_group_id UUID NOT NULL REFERENCES public.clinical_report_groups(id) ON DELETE RESTRICT,
  order_item_id UUID NOT NULL UNIQUE REFERENCES public.clinical_order_items(id) ON DELETE RESTRICT,
  frozen_test_code TEXT NOT NULL,
  frozen_test_name TEXT NOT NULL,
  display_order INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID NOT NULL,
  PRIMARY KEY(report_group_id,order_item_id)
);

ALTER TABLE public.samples ADD COLUMN specimen_requirement_key TEXT;
UPDATE public.samples s SET specimen_requirement_key=coalesce((SELECT t.specimen_requirement_key FROM public.clinical_order_items oi JOIN public.tests t ON t.id=oi.test_id WHERE oi.sample_id=s.id ORDER BY oi.created_at LIMIT 1),upper(regexp_replace(trim(coalesce(s.specimen_type,'UNSPECIFIED'))||'|'||trim(coalesce(s.container_type,'UNSPECIFIED')),'[^A-Za-z0-9]+','_','g')));
ALTER TABLE public.samples ALTER COLUMN specimen_requirement_key SET NOT NULL;
CREATE INDEX idx_samples_order_requirement ON public.samples(order_id,specimen_requirement_key);
CREATE OR REPLACE FUNCTION public.freeze_sample_requirement_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN NEW.specimen_requirement_key:=coalesce(nullif(NEW.specimen_requirement_key,''),upper(regexp_replace(trim(coalesce(NEW.specimen_type,'UNSPECIFIED'))||'|'||trim(coalesce(NEW.container_type,'UNSPECIFIED')),'[^A-Za-z0-9]+','_','g'))); RETURN NEW; END $$;
CREATE TRIGGER trg_freeze_sample_requirement_identity BEFORE INSERT ON public.samples FOR EACH ROW EXECUTE FUNCTION public.freeze_sample_requirement_identity();

ALTER TABLE public.diagnostic_reports ADD COLUMN report_group_id UUID REFERENCES public.clinical_report_groups(id) ON DELETE RESTRICT;
ALTER TABLE public.clinical_orders DROP CONSTRAINT clinical_orders_status_check;
ALTER TABLE public.clinical_orders ADD CONSTRAINT clinical_orders_status_check CHECK(status IN ('Registered','InLab','InProgress','PartiallyCompleted','Completed','SignedOff','Pending','In Progress','Partially Reported','Fully Reported'));
ALTER TABLE public.diagnostic_reports DROP CONSTRAINT diagnostic_reports_order_version_unique;
CREATE UNIQUE INDEX uq_diagnostic_reports_legacy_version ON public.diagnostic_reports(order_id,version) WHERE report_group_id IS NULL;
CREATE UNIQUE INDEX uq_diagnostic_reports_group_version ON public.diagnostic_reports(order_id,report_group_id,version) WHERE report_group_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.materialize_report_group_item() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE; g UUID; actor UUID:=coalesce(auth.uid(),(SELECT created_by FROM public.bills b JOIN public.clinical_orders o ON o.bill_id=b.id WHERE o.id=NEW.order_id));
BEGIN
  SELECT * INTO t FROM public.tests WHERE id=NEW.test_id;
  IF NOT FOUND OR NOT coalesce(NEW.clinical_reporting_enabled,false) THEN RETURN NEW; END IF;
  INSERT INTO public.clinical_report_groups(order_id,group_key,title,clinical_section,display_order,configuration_version,created_by)
  VALUES(NEW.order_id,t.report_group_key,t.report_group_title,t.report_section,t.report_group_sort_order,t.row_version,actor)
  ON CONFLICT(order_id,group_key) DO UPDATE SET display_order=least(clinical_report_groups.display_order,excluded.display_order)
  RETURNING id INTO g;
  INSERT INTO public.clinical_report_group_items(report_group_id,order_item_id,frozen_test_code,frozen_test_name,display_order,created_by)
  VALUES(g,NEW.id,t.code,NEW.test_name,coalesce(t.display_order,0),actor) ON CONFLICT(order_item_id) DO NOTHING;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
  VALUES(actor,public.catalogue_actor_name(),'REPORT_GROUP_ITEM_FROZEN','ClinicalReportGroup',g::text,jsonb_build_object('order_item_id',NEW.id,'group_key',t.report_group_key,'test_code',t.code));
  RETURN NEW;
END $$;
CREATE TRIGGER trg_materialize_report_group_item AFTER INSERT ON public.clinical_order_items FOR EACH ROW EXECUTE FUNCTION public.materialize_report_group_item();

-- Local/synthetic orders that predate this migration receive the same deterministic freeze.
INSERT INTO public.clinical_report_groups(order_id,group_key,title,clinical_section,display_order,configuration_version,created_by)
SELECT oi.order_id,t.report_group_key,min(t.report_group_title),min(t.report_section),min(t.report_group_sort_order),max(t.row_version),coalesce(min(b.created_by::text)::uuid,min(p.id::text)::uuid)
FROM public.clinical_order_items oi JOIN public.tests t ON t.id=oi.test_id JOIN public.clinical_orders o ON o.id=oi.order_id JOIN public.bills b ON b.id=o.bill_id
LEFT JOIN public.user_profiles p ON p.is_active AND p.is_super_admin
WHERE oi.clinical_reporting_enabled GROUP BY oi.order_id,t.report_group_key ON CONFLICT DO NOTHING;
INSERT INTO public.clinical_report_group_items(report_group_id,order_item_id,frozen_test_code,frozen_test_name,display_order,created_by)
SELECT g.id,oi.id,t.code,oi.test_name,coalesce(t.display_order,0),g.created_by FROM public.clinical_order_items oi JOIN public.tests t ON t.id=oi.test_id JOIN public.clinical_report_groups g ON g.order_id=oi.order_id AND g.group_key=t.report_group_key WHERE oi.clinical_reporting_enabled ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.check_report_group_readiness(p_report_group_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE total_count INT; unverified INT; collection_blocked INT; critical_blocked INT; calculation_blocked INT; state TEXT;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_permission('can_enter_results') OR public.has_permission('can_verify_results') OR public.has_permission('can_sign_reports')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.clinical_report_groups WHERE id=p_report_group_id) THEN RAISE EXCEPTION 'Report group not found.' USING ERRCODE='P0002'; END IF;
 SELECT count(*),count(*) FILTER(WHERE oi.status NOT IN ('Verified','SignedOff') OR (oi.execution_route='OUTSOURCE' AND oi.outsource_state NOT IN ('Verified','Signed'))),
 count(*) FILTER(WHERE oi.collection_required AND (s.id IS NULL OR s.status<>'Received')),
 count(*) FILTER(WHERE EXISTS(SELECT 1 FROM public.test_results tr WHERE tr.order_item_id=oi.id AND tr.is_critical AND tr.critical_acknowledged_at IS NULL)),
 count(*) FILTER(WHERE EXISTS(SELECT 1 FROM public.test_results tr JOIN public.parameters p ON p.id=tr.parameter_id WHERE tr.order_item_id=oi.id AND p.value_type='Calculated' AND (tr.display_value IS NULL OR tr.display_value IN ('','Calculation Error'))))
 INTO total_count,unverified,collection_blocked,critical_blocked,calculation_blocked
 FROM public.clinical_report_group_items gi JOIN public.clinical_order_items oi ON oi.id=gi.order_item_id LEFT JOIN public.samples s ON s.id=oi.sample_id WHERE gi.report_group_id=p_report_group_id AND oi.clinical_reporting_enabled;
 state:=CASE WHEN unverified+collection_blocked+critical_blocked+calculation_blocked=0 AND total_count>0 THEN 'ReadyToSign' WHEN unverified<total_count THEN 'InProgress' ELSE 'Pending' END;
 UPDATE public.clinical_report_groups SET lifecycle_state=CASE WHEN lifecycle_state IN ('Signed','Amended') THEN lifecycle_state ELSE state END,updated_at=now(),row_version=row_version+1 WHERE id=p_report_group_id;
 RETURN jsonb_build_object('is_ready',total_count>0 AND unverified+collection_blocked+critical_blocked+calculation_blocked=0,'total_count',total_count,'unverified_count',unverified,'collection_blocked_count',collection_blocked,'unacknowledged_critical_count',critical_blocked,'calculation_blocked_count',calculation_blocked,'state',state);
END $$;

CREATE OR REPLACE VIEW public.order_report_group_workspace WITH (security_invoker=false) AS
SELECT g.id report_group_id,g.order_id,g.group_key,g.title,g.clinical_section,g.display_order,g.lifecycle_state,g.row_version,
 oi.id order_item_id,oi.test_id,gi.frozen_test_code,gi.frozen_test_name,gi.display_order item_display_order,oi.status result_state,oi.sample_id,s.status sample_state,
 r.id latest_report_id,r.version latest_report_version,r.status report_state,a.generation_status pdf_state
FROM public.clinical_report_groups g JOIN public.clinical_report_group_items gi ON gi.report_group_id=g.id JOIN public.clinical_order_items oi ON oi.id=gi.order_item_id
LEFT JOIN public.samples s ON s.id=oi.sample_id LEFT JOIN LATERAL(SELECT dr.* FROM public.diagnostic_reports dr WHERE dr.report_group_id=g.id ORDER BY dr.version DESC LIMIT 1) r ON true
LEFT JOIN public.report_pdf_artifacts a ON a.diagnostic_report_id=r.id AND a.report_version=r.version;

CREATE OR REPLACE FUNCTION public.derive_order_reporting_state(p_order_id UUID) RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT CASE WHEN count(*)=0 THEN 'Pending' WHEN bool_and(lifecycle_state IN ('Signed','Amended')) THEN 'Fully Reported' WHEN bool_or(lifecycle_state IN ('Signed','Amended')) THEN 'Partially Reported' WHEN bool_or(lifecycle_state IN ('InProgress','ReadyToSign')) THEN 'In Progress' ELSE 'Pending' END FROM public.clinical_report_groups WHERE order_id=p_order_id
$$;

CREATE OR REPLACE FUNCTION public.sign_report_group(p_report_group_id UUID,p_performed_by_id UUID,p_signed_by_id UUID DEFAULT NULL,p_amendment_reason TEXT DEFAULT NULL,p_amended_from_report_id UUID DEFAULT NULL) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE g public.clinical_report_groups%ROWTYPE; o public.clinical_orders%ROWTYPE; b public.bills%ROWTYPE; patient public.patients%ROWTYPE; performer public.reporting_personnel%ROWTYPE; signer public.reporting_personnel%ROWTYPE; parent public.diagnostic_reports%ROWTYPE; ready JSONB; investigations JSONB; snapshot JSONB; version_no INT; report_id UUID; report_no TEXT; integrity TEXT; is_amendment BOOLEAN:=p_amended_from_report_id IS NOT NULL; item RECORD;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_sign_reports') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 SELECT * INTO g FROM public.clinical_report_groups WHERE id=p_report_group_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Report group not found.' USING ERRCODE='P0002'; END IF;
 SELECT * INTO o FROM public.clinical_orders WHERE id=g.order_id; SELECT * INTO b FROM public.bills WHERE id=o.bill_id; SELECT * INTO patient FROM public.patients WHERE id=o.patient_id;
 SELECT * INTO performer FROM public.reporting_personnel WHERE id=p_performed_by_id AND is_active;
 IF NOT FOUND THEN RAISE EXCEPTION 'Active reporting personnel is required.' USING ERRCODE='23514'; END IF;
 IF p_signed_by_id IS NOT NULL THEN SELECT * INTO signer FROM public.reporting_personnel WHERE id=p_signed_by_id AND is_active AND can_sign_reports; IF NOT FOUND THEN RAISE EXCEPTION 'Active authorized signatory is required.' USING ERRCODE='23514'; END IF; END IF;
 ready:=public.check_report_group_readiness(g.id);
 IF NOT (ready->>'is_ready')::boolean THEN RAISE EXCEPTION 'Report group is not ready: %',ready USING ERRCODE='23514'; END IF;
 IF is_amendment THEN
   IF NOT public.has_permission('can_amend_reports') OR btrim(coalesce(p_amendment_reason,''))='' THEN RAISE EXCEPTION 'Amendment permission and reason are required.' USING ERRCODE='42501'; END IF;
   SELECT * INTO parent FROM public.diagnostic_reports WHERE id=p_amended_from_report_id AND report_group_id=g.id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Amendment parent is outside this report group.' USING ERRCODE='23514'; END IF;
   version_no:=parent.version+1; UPDATE public.diagnostic_reports SET status='Amended',updated_at=now() WHERE id=parent.id;
 ELSE
   IF EXISTS(SELECT 1 FROM public.diagnostic_reports WHERE report_group_id=g.id AND status='SignedOff') THEN RAISE EXCEPTION 'This report group is already signed.' USING ERRCODE='23505'; END IF;
   SELECT coalesce(max(version),0)+1 INTO version_no FROM public.diagnostic_reports WHERE report_group_id=g.id;
 END IF;
 FOR item IN SELECT oi.id FROM public.clinical_report_group_items gi JOIN public.clinical_order_items oi ON oi.id=gi.order_item_id WHERE gi.report_group_id=g.id LOOP PERFORM public.recompute_order_item_calculated_results(item.id); END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('order_item_id',x.order_item_id,'test_id',x.test_id,'test_name',x.test_name,'test_code',x.test_code,'department',x.department,'reporting_type',x.reporting_type,'execution_route',x.execution_route,'outsource_lab_name',x.outsource_lab_name,'outsource_external_reference',x.outsource_external_reference,'outsource_source_report_reference',x.outsource_source_report_reference,'outsource_method',x.outsource_method,'outsource_interpretation',x.outsource_interpretation,'outsource_result_payload',x.outsource_result_payload,'method',x.method,'interpretation_template',x.interpretation_template,'specimen_type',x.specimen_type,'container_type',x.container_type,'results',x.results) ORDER BY x.item_order),'[]'::jsonb)
 INTO investigations FROM (
   SELECT oi.id order_item_id,oi.test_id,gi.frozen_test_name test_name,gi.frozen_test_code test_code,oi.department,oi.reporting_type,oi.execution_route,oi.outsource_lab_name,oi.outsource_external_reference,oi.outsource_source_report_reference,oi.outsource_method,oi.outsource_interpretation,oi.outsource_result_payload,t.method,t.interpretation_template,oi.specimen_type,oi.container_type,gi.display_order item_order,
   coalesce(jsonb_agg(jsonb_build_object('parameter_id',tr.parameter_id,'code',p.code,'name',tr.parameter_name,'value_type',tr.value_type,'display_value',tr.display_value,'numeric_value',tr.numeric_value,'unit',tr.unit,'formula',p.formula,'flag',tr.flag,'is_critical',tr.is_critical,'reference_range',coalesce(case when tr.normal_min is not null and tr.normal_max is not null then tr.normal_min::text||' - '||tr.normal_max::text end,tr.normal_range_text,'Standard'),'normal_min',tr.normal_min,'normal_max',tr.normal_max,'critical_low',tr.critical_low,'critical_high',tr.critical_high) ORDER BY p.display_order) FILTER(WHERE tr.id IS NOT NULL),'[]'::jsonb) results
   FROM public.clinical_report_group_items gi JOIN public.clinical_order_items oi ON oi.id=gi.order_item_id JOIN public.tests t ON t.id=oi.test_id LEFT JOIN public.test_results tr ON tr.order_item_id=oi.id LEFT JOIN public.parameters p ON p.id=tr.parameter_id WHERE gi.report_group_id=g.id GROUP BY oi.id,gi.frozen_test_name,gi.frozen_test_code,t.method,t.interpretation_template,gi.display_order
 ) x;
 IF jsonb_array_length(investigations)=0 THEN RAISE EXCEPTION 'Report group contains no reportable investigations.' USING ERRCODE='23514'; END IF;
 snapshot:=jsonb_build_object('organization',jsonb_build_object('name_en','BIMAL PATHOLOGY & DIAGNOSTIC CENTER','name_ne','बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर','address_en','Bharatpur-7, Chitwan, Nepal','reg_no','7-1496','pan_no','302481477','phone','056-593288'),'patient',jsonb_build_object('uhid',patient.uhid,'full_name',patient.full_name,'title',patient.title,'mobile',patient.mobile,'gender',patient.gender,'dob',patient.dob,'age_years',patient.age_years,'age_months',patient.age_months,'age_days',patient.age_days,'address',patient.address),'order',jsonb_build_object('order_number',o.order_number,'bill_number',b.bill_number,'registered_date_ad',o.order_date_ad,'registered_date_bs',o.order_date_bs,'reported_at',now(),'referring_doctor_name',coalesce(b.referring_doctor_name_snapshot,'Self / Walk-in')),'report_group',jsonb_build_object('id',g.id,'key',g.group_key,'title',g.title,'clinical_section',g.clinical_section,'configuration_version',g.configuration_version),'signatories',jsonb_build_object('performed_by',jsonb_build_object('id',performer.id,'full_name',performer.full_name,'qualification',performer.qualification,'professional_type',performer.professional_type,'registration_council',performer.registration_council,'registration_number',performer.registration_number,'signature_url',performer.signature_url),'authorized_by',case when signer.id is null then null else jsonb_build_object('id',signer.id,'full_name',signer.full_name,'qualification',signer.qualification,'professional_type',signer.professional_type,'registration_council',signer.registration_council,'registration_number',signer.registration_number,'signature_url',signer.signature_url) end),'investigations',investigations,'meta',jsonb_build_object('version',version_no,'is_amendment',is_amendment,'amendment_reason',p_amendment_reason,'amended_from_report_id',p_amended_from_report_id,'signed_at',now(),'signed_by_user_id',auth.uid()));
 integrity:=encode(extensions.digest(convert_to(o.order_number||'|'||g.group_key||'|v'||version_no||'|'||snapshot::text,'UTF8'),'sha256'),'hex');
 report_no:='REP-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('report_seq')::text,5,'0');
 INSERT INTO public.diagnostic_reports(order_id,report_group_id,patient_id,report_number,version,is_amendment,amendment_reason,amended_from_report_id,status,integrity_hash,performed_by_personnel_id,performed_by_personnel_name,verified_by_personnel_id,verified_by_personnel_name,signed_by_personnel_id,signed_by_personnel_name,signed_at,pdf_storage_path,clinical_snapshot_json)
 VALUES(o.id,g.id,o.patient_id,report_no,version_no,is_amendment,p_amendment_reason,p_amended_from_report_id,'SignedOff',integrity,performer.id,performer.full_name,signer.id,signer.full_name,signer.id,signer.full_name,now(),'reports/'||o.id||'/'||g.group_key||'/v'||version_no||'/report.pdf',snapshot) RETURNING id INTO report_id;
 UPDATE public.clinical_order_items oi SET status='SignedOff',outsource_state=CASE WHEN oi.execution_route='OUTSOURCE' THEN 'Signed'::public.outsource_item_state_enum ELSE oi.outsource_state END,updated_at=now() FROM public.clinical_report_group_items gi WHERE gi.report_group_id=g.id AND gi.order_item_id=oi.id;
 UPDATE public.test_results tr SET status='SignedOff',signed_off_by=auth.uid(),signed_off_name=coalesce(signer.full_name,performer.full_name),signed_off_at=now(),updated_at=now() FROM public.clinical_report_group_items gi WHERE gi.report_group_id=g.id AND gi.order_item_id=tr.order_item_id;
 UPDATE public.clinical_report_groups SET lifecycle_state=CASE WHEN is_amendment THEN 'Amended' ELSE 'Signed' END,updated_at=now(),row_version=row_version+1 WHERE id=g.id;
 UPDATE public.clinical_orders SET status=public.derive_order_reporting_state(o.id),updated_at=now() WHERE id=o.id;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),performer.full_name,case when is_amendment then 'REPORT_GROUP_AMENDMENT_SIGNED' else 'REPORT_GROUP_SIGNED' end,'ClinicalReportGroup',g.id::text,jsonb_build_object('report_id',report_id,'order_id',o.id,'group_key',g.group_key,'version',version_no,'integrity_hash',integrity));
 RETURN jsonb_build_object('success',true,'report_id',report_id,'report_group_id',g.id,'report_group_key',g.group_key,'report_number',report_no,'version',version_no,'integrity_hash',integrity,'snapshot',snapshot,'order_reporting_state',public.derive_order_reporting_state(o.id));
END $$;

CREATE TABLE public.order_report_delivery_tokens(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),order_id UUID NOT NULL REFERENCES public.clinical_orders(id) ON DELETE RESTRICT,
 token_hash TEXT NOT NULL UNIQUE,expires_at TIMESTAMPTZ NOT NULL,created_by UUID NOT NULL,created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 is_active BOOLEAN NOT NULL DEFAULT true,revoked_at TIMESTAMPTZ,access_count BIGINT NOT NULL DEFAULT 0,last_accessed_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX uq_order_report_delivery_active ON public.order_report_delivery_tokens(order_id) WHERE is_active AND revoked_at IS NULL;
CREATE TABLE public.order_report_delivery_entitlements(
 order_token_id UUID NOT NULL REFERENCES public.order_report_delivery_tokens(id) ON DELETE RESTRICT,
 report_group_id UUID NOT NULL REFERENCES public.clinical_report_groups(id) ON DELETE RESTRICT,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),PRIMARY KEY(order_token_id,report_group_id)
);
CREATE TABLE public.order_report_notification_generations(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),order_id UUID NOT NULL REFERENCES public.clinical_orders(id) ON DELETE RESTRICT,
 generation INTEGER NOT NULL CHECK(generation>0),reason TEXT NOT NULL,requested_by UUID NOT NULL,created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 sms_queue_item_id UUID UNIQUE REFERENCES public.sms_queue_items(id) ON DELETE RESTRICT,UNIQUE(order_id,generation)
);

ALTER TABLE public.report_pdf_delivery_intents ALTER COLUMN report_token_id DROP NOT NULL;
ALTER TABLE public.report_pdf_delivery_intents ADD COLUMN order_token_id UUID REFERENCES public.order_report_delivery_tokens(id) ON DELETE RESTRICT;
ALTER TABLE public.report_pdf_delivery_intents DROP CONSTRAINT report_pdf_delivery_intents_public_url_check;
ALTER TABLE public.report_pdf_delivery_intents ADD CONSTRAINT report_pdf_delivery_intents_public_url_check CHECK(public_url ~ '^https://dashboard[.]bimalpathology[.]com[.]np/[ro]/[A-Za-z0-9_-]+$' AND length(substring(public_url FROM '/[ro]/([A-Za-z0-9_-]+)$')) BETWEEN 32 AND 256);
ALTER TABLE public.report_pdf_delivery_intents ADD CONSTRAINT report_pdf_delivery_token_exactly_one CHECK((report_token_id IS NOT NULL)::int+(order_token_id IS NOT NULL)::int=1);

CREATE OR REPLACE FUNCTION public.sign_and_queue_report_group(p_report_group_id UUID,p_performed_by_id UUID,p_signed_by_id UUID,p_amendment_reason TEXT,p_amended_from_report_id UUID,p_token_hash TEXT,p_order_public_url TEXT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE signed JSONB; report_id UUID; v_order_id UUID; token public.order_report_delivery_tokens%ROWTYPE;
BEGIN
 IF p_token_hash !~ '^[0-9a-f]{64}$' OR p_order_public_url !~ '^https://dashboard[.]bimalpathology[.]com[.]np/o/[A-Za-z0-9_-]+$' OR length(substring(p_order_public_url FROM '/o/([A-Za-z0-9_-]+)$')) NOT BETWEEN 32 AND 256 THEN RAISE EXCEPTION 'Invalid secure order delivery token.' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_report_group_id::text,0));
 signed:=public.sign_report_group(p_report_group_id,p_performed_by_id,p_signed_by_id,p_amendment_reason,p_amended_from_report_id);
 report_id:=(signed->>'report_id')::uuid; SELECT order_id INTO v_order_id FROM public.clinical_report_groups WHERE id=p_report_group_id;
 SELECT * INTO token FROM public.order_report_delivery_tokens WHERE order_id=v_order_id AND is_active AND revoked_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN
   INSERT INTO public.order_report_delivery_tokens(order_id,token_hash,expires_at,created_by) VALUES(v_order_id,p_token_hash,now()+interval '30 days',auth.uid()) RETURNING * INTO token;
   INSERT INTO public.order_report_delivery_entitlements(order_token_id,report_group_id) SELECT token.id,id FROM public.clinical_report_groups WHERE clinical_report_groups.order_id=v_order_id;
 ELSE
   -- The original opaque URL is retained only in guarded delivery intents; callers cannot replace the entitlement.
   SELECT public_url INTO p_order_public_url FROM public.report_pdf_delivery_intents WHERE order_token_id=token.id ORDER BY diagnostic_report_id LIMIT 1;
   IF p_order_public_url IS NULL THEN RAISE EXCEPTION 'Existing order entitlement has no recoverable delivery presentation.' USING ERRCODE='55000'; END IF;
 END IF;
 INSERT INTO public.report_pdf_delivery_intents(diagnostic_report_id,order_token_id,public_url) VALUES(report_id,token.id,p_order_public_url) ON CONFLICT(diagnostic_report_id) DO NOTHING;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'ORDER_REPORT_ENTITLEMENT_PROVISIONED','ClinicalReportGroup',p_report_group_id::text,jsonb_build_object('report_id',report_id,'order_id',v_order_id));
 RETURN signed||jsonb_build_object('delivery_mode','OrderPortal','sms_queued',false,'sms_status','Queued after PDF artifact is ready');
END $$;

CREATE OR REPLACE FUNCTION public.notify_updated_order_reports(p_order_id UUID,p_expected_generation INTEGER,p_reason TEXT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE current_generation INT; token public.order_report_delivery_tokens%ROWTYPE; report public.diagnostic_reports%ROWTYPE; patient public.patients%ROWTYPE; ordering public.clinical_orders%ROWTYPE; phone TEXT; sms_id UUID; next_generation INT;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_sign_reports') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF btrim(coalesce(p_reason,''))='' THEN RAISE EXCEPTION 'Notification reason is required.' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_order_id::text,91));
 SELECT coalesce(max(generation),0) INTO current_generation FROM public.order_report_notification_generations WHERE order_id=p_order_id;
 IF current_generation<>p_expected_generation THEN RAISE EXCEPTION 'Notification state changed. Refresh and retry.' USING ERRCODE='PT409'; END IF;
 SELECT * INTO token FROM public.order_report_delivery_tokens WHERE order_id=p_order_id AND is_active AND revoked_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order delivery entitlement is unavailable.' USING ERRCODE='23514'; END IF;
 SELECT dr.* INTO report FROM public.diagnostic_reports dr WHERE dr.order_id=p_order_id AND dr.report_group_id IS NOT NULL AND dr.status='SignedOff' ORDER BY dr.signed_at DESC LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'No finalized report is available.' USING ERRCODE='23514'; END IF;
 SELECT * INTO patient FROM public.patients WHERE id=report.patient_id; SELECT * INTO ordering FROM public.clinical_orders WHERE id=p_order_id;
 phone:=regexp_replace(coalesce(patient.mobile,''),'[^0-9]','','g'); IF phone LIKE '977%' AND length(phone)=13 THEN phone:=substring(phone FROM 4); END IF; IF phone !~ '^(97|98)[0-9]{8}$' THEN RAISE EXCEPTION 'Patient has no valid Nepal mobile.' USING ERRCODE='23514'; END IF;
 next_generation:=current_generation+1;
 INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,diagnostic_report_id) SELECT 'ReportReady',phone,patient.full_name,'Bimal Pathology: Updated reports are available. Lab No: '||ordering.order_number||'. View reports: '||i.public_url,'Pending','ORDER_REPORT_READY:'||p_order_id||':'||next_generation,report.id FROM public.report_pdf_delivery_intents i WHERE i.order_token_id=token.id ORDER BY i.queued_at NULLS LAST LIMIT 1 ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO sms_id;
 IF sms_id IS NULL THEN SELECT sms_queue_item_id INTO sms_id FROM public.order_report_notification_generations WHERE order_id=p_order_id AND generation=next_generation; END IF;
 INSERT INTO public.order_report_notification_generations(order_id,generation,reason,requested_by,sms_queue_item_id) VALUES(p_order_id,next_generation,btrim(p_reason),auth.uid(),sms_id) ON CONFLICT(order_id,generation) DO NOTHING;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'ORDER_REPORT_UPDATED_NOTIFICATION','ClinicalOrder',p_order_id::text,jsonb_build_object('generation',next_generation,'reason',btrim(p_reason)));
 RETURN jsonb_build_object('success',true,'generation',next_generation,'sms_queue_item_id',sms_id);
END $$;

CREATE OR REPLACE FUNCTION public.create_patient_bill_order_mixed_catalogue(p_patient_data JSONB,p_bill_data JSONB,p_items_data JSONB[],p_payment_data JSONB,p_idempotency_key TEXT,p_packages JSONB DEFAULT '[]',p_panel_service_id UUID DEFAULT NULL,p_expected_panel_version BIGINT DEFAULT NULL,p_agreed_panel_price_paisa BIGINT DEFAULT NULL) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE svc public.catalogue_panel_services%ROWTYPE; pnl public.catalogue_panels%ROWTYPE; response JSONB; bill_uuid UUID; selection_uuid UUID; component_snapshot JSONB; component_ids UUID[]; temporary_manual UUID[]:=ARRAY[]::uuid[]; temporary_zero UUID[]:=ARRAY[]::uuid[];
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF p_panel_service_id IS NULL THEN RETURN public.create_patient_bill_order_with_packages(p_patient_data,p_bill_data,p_items_data,p_payment_data,p_idempotency_key,p_packages); END IF;
 SELECT * INTO svc FROM public.catalogue_panel_services WHERE id=p_panel_service_id AND lifecycle_status='Active' FOR SHARE; IF NOT FOUND THEN RAISE EXCEPTION 'Panel service is inactive or missing.' USING ERRCODE='23503'; END IF;
 SELECT * INTO pnl FROM public.catalogue_panels WHERE id=svc.panel_id AND lifecycle_status='Active' FOR SHARE; IF NOT FOUND OR pnl.row_version<>p_expected_panel_version THEN RAISE EXCEPTION 'Panel definition changed. Refresh billing catalogue.' USING ERRCODE='PT409'; END IF;
 IF coalesce(p_agreed_panel_price_paisa,0)<=0 THEN RAISE EXCEPTION 'A positive bundled panel rate is required.' USING ERRCODE='23514'; END IF;
 SELECT jsonb_agg(jsonb_build_object('test_id',c.test_id,'test_code',c.test_code,'test_name',c.test_name,'display_order',c.display_order) ORDER BY c.display_order),array_agg(c.test_id ORDER BY c.test_id) INTO component_snapshot,component_ids FROM public.catalogue_panel_service_components(svc.id)c;
 IF component_ids IS NULL OR EXISTS(SELECT 1 FROM unnest(component_ids)x(id) WHERE NOT EXISTS(SELECT 1 FROM unnest(p_items_data)i WHERE (i->>'test_id')::uuid=x.id)) THEN RAISE EXCEPTION 'Panel component traceability is incomplete.' USING ERRCODE='23514'; END IF;
 PERFORM 1 FROM public.tests WHERE id=ANY(component_ids) ORDER BY id FOR UPDATE; SELECT coalesce(array_agg(id),ARRAY[]::uuid[]) INTO temporary_manual FROM public.tests WHERE id=ANY(component_ids) AND NOT allow_manual_price; SELECT coalesce(array_agg(id),ARRAY[]::uuid[]) INTO temporary_zero FROM public.tests WHERE id=ANY(component_ids) AND NOT allow_zero_price_billing;
 UPDATE public.tests SET allow_manual_price=true WHERE id=ANY(temporary_manual); UPDATE public.tests SET allow_zero_price_billing=true WHERE id=ANY(temporary_zero);
 response:=public.create_patient_bill_order_with_packages(p_patient_data,p_bill_data,p_items_data,p_payment_data,p_idempotency_key,p_packages); bill_uuid:=(response->>'bill_id')::uuid;
 UPDATE public.tests SET allow_manual_price=false WHERE id=ANY(temporary_manual); UPDATE public.tests SET allow_zero_price_billing=false WHERE id=ANY(temporary_zero);
 INSERT INTO public.bill_panel_selections(bill_id,panel_service_id,panel_id,service_code_snapshot,panel_name_snapshot,panel_price_paisa,rate_version_id,component_snapshot)
 SELECT bill_uuid,svc.id,pnl.id,svc.code,pnl.name,p_agreed_panel_price_paisa,r.id,component_snapshot FROM public.catalogue_rate_versions r WHERE r.panel_service_id=svc.id AND r.status='Active' ORDER BY r.effective_from DESC LIMIT 1 ON CONFLICT(bill_id,panel_service_id) DO NOTHING RETURNING id INTO selection_uuid;
 IF selection_uuid IS NULL THEN SELECT id INTO selection_uuid FROM public.bill_panel_selections WHERE bill_id=bill_uuid AND panel_service_id=svc.id; END IF;
 INSERT INTO public.bill_panel_components(bill_panel_selection_id,bill_item_id,test_id,display_order) SELECT selection_uuid,bi.id,bi.test_id,(x->>'display_order')::int FROM jsonb_array_elements(component_snapshot)x JOIN public.bill_items bi ON bi.bill_id=bill_uuid AND bi.test_id=(x->>'test_id')::uuid ON CONFLICT DO NOTHING;
 RETURN response||jsonb_build_object('panel_selection_id',selection_uuid,'panel_service_id',svc.id);
END $$;

CREATE OR REPLACE FUNCTION public.authorize_order_report_delivery(p_token_hash TEXT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE token public.order_report_delivery_tokens%ROWTYPE; payload JSONB;
BEGIN
 IF NOT public.is_report_artifact_worker() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 SELECT * INTO token FROM public.order_report_delivery_tokens WHERE token_hash=p_token_hash AND is_active AND revoked_at IS NULL AND expires_at>now() FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('authorized',false); END IF;
 UPDATE public.order_report_delivery_tokens SET access_count=access_count+1,last_accessed_at=now() WHERE id=token.id;
 SELECT jsonb_build_object('authorized',true,'order_id',token.order_id,'order_number',o.order_number,'reports',coalesce(jsonb_agg(jsonb_build_object('report_group_id',g.id,'group_key',g.group_key,'title',g.title,'state',g.lifecycle_state,'report_id',r.id,'version',r.version,'pdf_status',a.generation_status) ORDER BY g.display_order),'[]'::jsonb)) INTO payload
 FROM public.clinical_orders o JOIN public.order_report_delivery_entitlements e ON e.order_token_id=token.id JOIN public.clinical_report_groups g ON g.id=e.report_group_id
 LEFT JOIN LATERAL(SELECT dr.* FROM public.diagnostic_reports dr WHERE dr.report_group_id=g.id AND dr.status='SignedOff' ORDER BY dr.version DESC LIMIT 1) r ON true
 LEFT JOIN public.report_pdf_artifacts a ON a.diagnostic_report_id=r.id AND a.report_version=r.version WHERE o.id=token.order_id GROUP BY o.id;
 RETURN coalesce(payload,jsonb_build_object('authorized',false));
END $$;

CREATE OR REPLACE FUNCTION public.authorize_order_report_pdf_artifact(p_token_hash TEXT,p_report_id UUID) RETURNS JSONB
LANGUAGE sql SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT CASE WHEN NOT public.is_report_artifact_worker() THEN jsonb_build_object('authorized',false) ELSE coalesce((SELECT jsonb_build_object('authorized',true,'object_key',a.object_key,'sha256',a.pdf_sha256,'byte_size',a.byte_size,'report_id',r.id,'version',r.version) FROM public.order_report_delivery_tokens tok JOIN public.order_report_delivery_entitlements e ON e.order_token_id=tok.id JOIN public.diagnostic_reports r ON r.report_group_id=e.report_group_id AND r.id=p_report_id AND r.status='SignedOff' JOIN public.report_pdf_artifacts a ON a.diagnostic_report_id=r.id AND a.report_version=r.version AND a.generation_status='Ready' WHERE tok.token_hash=p_token_hash AND tok.is_active AND tok.revoked_at IS NULL AND tok.expires_at>now()),jsonb_build_object('authorized',false)) END
$$;

CREATE OR REPLACE FUNCTION public.report_artifact_public_url(p_report_id UUID) RETURNS TEXT
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE url TEXT;
BEGIN
 SELECT intent.public_url INTO url FROM public.report_pdf_delivery_intents intent JOIN public.order_report_delivery_tokens token ON token.id=intent.order_token_id
 WHERE intent.diagnostic_report_id=p_report_id AND token.is_active AND token.revoked_at IS NULL AND token.expires_at>now()
 AND intent.public_url~'^https://dashboard[.]bimalpathology[.]com[.]np/o/[A-Za-z0-9_-]+$' AND length(substring(intent.public_url FROM '/o/([A-Za-z0-9_-]+)$')) BETWEEN 32 AND 256
 AND encode(extensions.digest(convert_to(substring(intent.public_url FROM '/o/([A-Za-z0-9_-]+)$'),'UTF8'),'sha256'),'hex')=token.token_hash LIMIT 1;
 IF url IS NOT NULL THEN RETURN url; END IF;
 SELECT candidate.public_url INTO url FROM public.public_report_tokens token CROSS JOIN LATERAL(
   SELECT presentation.public_url,0 priority FROM public.report_secure_link_presentations presentation WHERE presentation.report_token_id=token.id
   UNION ALL SELECT substring(message.message_body FROM '(https://(lis|dashboard)[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]+)'),1 FROM public.sms_queue_items message JOIN public.diagnostic_reports report ON report.id=message.diagnostic_report_id WHERE message.diagnostic_report_id=p_report_id AND message.sms_type='ReportReady' AND message.idempotency_key='REPORT_READY:'||p_report_id::text||':'||report.version::text
 )candidate WHERE token.diagnostic_report_id=p_report_id AND token.is_active AND token.revoked_at IS NULL AND token.expires_at>now() AND candidate.public_url~'^https://(lis|dashboard)[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]+$' AND length(substring(candidate.public_url FROM '/r/([A-Za-z0-9_-]+)$')) BETWEEN 32 AND 256 AND encode(extensions.digest(convert_to(substring(candidate.public_url FROM '/r/([A-Za-z0-9_-]+)$'),'UTF8'),'sha256'),'hex')=token.token_hash ORDER BY candidate.priority,token.created_at DESC LIMIT 1;
 RETURN url;
END $$;

CREATE OR REPLACE FUNCTION public.complete_report_pdf_artifact_v2(p_artifact_id UUID,p_lease_owner UUID,p_ready BOOLEAN,p_pdf_sha256 TEXT DEFAULT NULL,p_byte_size BIGINT DEFAULT NULL,p_generator_name TEXT DEFAULT NULL,p_generator_version TEXT DEFAULT NULL,p_failure_code TEXT DEFAULT NULL) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result JSONB; artifact public.report_pdf_artifacts%ROWTYPE; intent public.report_pdf_delivery_intents%ROWTYPE; report public.diagnostic_reports%ROWTYPE; patient public.patients%ROWTYPE; ordering public.clinical_orders%ROWTYPE; sms_id UUID; phone TEXT; generation_id UUID;
BEGIN
 IF NOT public.is_report_artifact_worker() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 result:=public.complete_report_pdf_artifact(p_artifact_id,p_lease_owner,p_ready,p_pdf_sha256,p_byte_size,p_generator_name,p_generator_version,p_failure_code); IF NOT p_ready THEN RETURN result; END IF;
 SELECT * INTO artifact FROM public.report_pdf_artifacts WHERE id=p_artifact_id; SELECT * INTO intent FROM public.report_pdf_delivery_intents WHERE diagnostic_report_id=artifact.diagnostic_report_id AND status='AwaitingArtifact' FOR UPDATE;
 IF NOT FOUND THEN RETURN result||jsonb_build_object('sms_queued',false); END IF;
 SELECT * INTO report FROM public.diagnostic_reports WHERE id=artifact.diagnostic_report_id; SELECT * INTO patient FROM public.patients WHERE id=report.patient_id; SELECT * INTO ordering FROM public.clinical_orders WHERE id=report.order_id;
 IF intent.order_token_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.order_report_notification_generations WHERE order_id=report.order_id AND generation=1) THEN UPDATE public.report_pdf_delivery_intents SET status='Skipped',queued_at=now() WHERE diagnostic_report_id=report.id; RETURN result||jsonb_build_object('sms_queued',false,'sms_status','Order already notified'); END IF;
 phone:=regexp_replace(coalesce(patient.mobile,''),'[^0-9]','','g'); IF phone LIKE '977%' AND length(phone)=13 THEN phone:=substring(phone FROM 4); END IF;
 IF phone !~ '^(97|98)[0-9]{8}$' THEN UPDATE public.report_pdf_delivery_intents SET status='Skipped',queued_at=now() WHERE diagnostic_report_id=report.id; RETURN result||jsonb_build_object('sms_queued',false,'sms_status','SMS skipped: invalid or missing Nepal mobile'); END IF;
 INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,diagnostic_report_id) VALUES('ReportReady',phone,patient.full_name,'Bimal Pathology: Your report is ready. Lab No: '||ordering.order_number||'. View reports: '||intent.public_url,'Pending',CASE WHEN intent.order_token_id IS NULL THEN 'REPORT_READY:'||report.id||':'||report.version ELSE 'ORDER_REPORT_READY:'||report.order_id||':1' END,report.id) ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO sms_id;
 IF intent.order_token_id IS NOT NULL THEN INSERT INTO public.order_report_notification_generations(order_id,generation,reason,requested_by,sms_queue_item_id) VALUES(report.order_id,1,'First finalized PDF milestone',coalesce(report.signed_by_personnel_id,report.performed_by_personnel_id),sms_id) ON CONFLICT(order_id,generation) DO NOTHING RETURNING id INTO generation_id; END IF;
 UPDATE public.report_pdf_delivery_intents SET status=CASE WHEN sms_id IS NULL THEN 'Skipped' ELSE 'Queued' END,queued_sms_id=sms_id,queued_at=now() WHERE diagnostic_report_id=report.id;
 RETURN result||jsonb_build_object('sms_queued',sms_id IS NOT NULL);
END $$;

ALTER TABLE public.clinical_report_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_report_group_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_report_delivery_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_report_delivery_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_report_notification_generations ENABLE ROW LEVEL SECURITY;
CREATE POLICY report_groups_staff_read ON public.clinical_report_groups FOR SELECT TO authenticated USING(public.is_active_user());
CREATE POLICY report_group_items_staff_read ON public.clinical_report_group_items FOR SELECT TO authenticated USING(public.is_active_user());
REVOKE ALL ON public.clinical_report_groups,public.clinical_report_group_items FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON public.order_report_delivery_tokens,public.order_report_delivery_entitlements,public.order_report_notification_generations FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.clinical_report_groups,public.clinical_report_group_items,public.order_report_group_workspace TO authenticated;
REVOKE ALL ON FUNCTION public.check_report_group_readiness(UUID),public.derive_order_reporting_state(UUID),public.sign_report_group(UUID,UUID,UUID,TEXT,UUID),public.sign_and_queue_report_group(UUID,UUID,UUID,TEXT,UUID,TEXT,TEXT),public.notify_updated_order_reports(UUID,INTEGER,TEXT),public.authorize_order_report_delivery(TEXT),public.authorize_order_report_pdf_artifact(TEXT,UUID),public.create_patient_bill_order_mixed_catalogue(JSONB,JSONB,JSONB[],JSONB,TEXT,JSONB,UUID,BIGINT,BIGINT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.check_report_group_readiness(UUID),public.derive_order_reporting_state(UUID),public.sign_report_group(UUID,UUID,UUID,TEXT,UUID),public.sign_and_queue_report_group(UUID,UUID,UUID,TEXT,UUID,TEXT,TEXT),public.notify_updated_order_reports(UUID,INTEGER,TEXT),public.authorize_order_report_delivery(TEXT),public.authorize_order_report_pdf_artifact(TEXT,UUID),public.create_patient_bill_order_mixed_catalogue(JSONB,JSONB,JSONB[],JSONB,TEXT,JSONB,UUID,BIGINT,BIGINT) TO authenticated;

COMMENT ON TABLE public.clinical_report_groups IS 'Stable per-order clinical report lineages; legacy whole-order diagnostic reports remain ungrouped.';
COMMENT ON TABLE public.clinical_report_group_items IS 'Frozen order-item membership. Direct client mutation is denied.';
COMMENT ON COLUMN public.diagnostic_reports.report_group_id IS 'Null only for immutable historical whole-order reports.';

-- Governed internal/outsource execution is frozen per order item.  This extends
-- the existing outsource chain-of-custody model; it does not create a parallel
-- reporting engine.
CREATE TYPE public.clinical_execution_route_enum AS ENUM ('INTERNAL','OUTSOURCE');
CREATE TYPE public.outsource_item_state_enum AS ENUM (
  'AwaitingDispatch','Dispatched','AwaitingExternalResult','ResultReceived',
  'InternalReview','Verified','Signed','Rejected','RecollectionRequired',
  'Cancelled','UnableToPerform'
);

CREATE TABLE public.reference_laboratories(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE CHECK(code ~ '^[A-Z0-9_]{2,40}$'),
  name TEXT NOT NULL,
  external_code TEXT,
  contact_details TEXT,
  tat_hours INTEGER CHECK(tat_hours IS NULL OR tat_hours > 0),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  row_version BIGINT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.tests
  ADD COLUMN execution_route public.clinical_execution_route_enum NOT NULL DEFAULT 'INTERNAL',
  ADD COLUMN default_reference_laboratory_id UUID REFERENCES public.reference_laboratories(id) ON DELETE RESTRICT;

UPDATE public.tests SET execution_route='OUTSOURCE', requires_sample_tracking=TRUE
WHERE retired_duplicate_of IS NULL AND (
  code IN ('FNAC','FNAC_FINE_NEEDLE_ASPIRATION','PAP_SMEAR','IHC','HCV_RNA_QUANTITATIVE','GENETIC_TEST','HPLC',
           'SERUM_PROTEIN_ELECTROPHORESIS','DOUBLE_MARKER_MATERNAL_SCREEN_2_TESTS')
  OR upper(code) ~ '(^|_)PCR($|_)'
);
UPDATE public.tests SET report_group_key='molecular_outsource',report_group_title='Molecular / Outsource',report_section='Molecular Diagnostics',report_group_sort_order=600 WHERE code IN ('HCV_RNA_QUANTITATIVE','GENETIC_TEST') OR upper(code)~'(^|_)PCR($|_)';
UPDATE public.tests SET report_group_key='anatomic_pathology',report_group_title='Pathology / IHC',report_section='Anatomic Pathology',report_group_sort_order=700 WHERE code IN ('FNAC','FNAC_FINE_NEEDLE_ASPIRATION','PAP_SMEAR','IHC');

ALTER TABLE public.clinical_order_items
  ADD COLUMN execution_route public.clinical_execution_route_enum,
  ADD COLUMN reference_laboratory_id UUID REFERENCES public.reference_laboratories(id) ON DELETE RESTRICT,
  ADD COLUMN outsource_state public.outsource_item_state_enum,
  ADD COLUMN outsource_external_reference TEXT,
  ADD COLUMN outsource_source_report_reference TEXT,
  ADD COLUMN outsource_method TEXT,
  ADD COLUMN outsource_interpretation TEXT,
  ADD COLUMN outsource_result_payload JSONB,
  ADD COLUMN outsource_result_received_at TIMESTAMPTZ,
  ADD COLUMN outsource_result_received_by UUID,
  ADD COLUMN outsource_reviewed_at TIMESTAMPTZ,
  ADD COLUMN outsource_reviewed_by UUID;

UPDATE public.clinical_order_items oi SET
  execution_route=t.execution_route,
  outsource_state=CASE WHEN t.execution_route='OUTSOURCE' THEN 'AwaitingDispatch'::public.outsource_item_state_enum END,
  reference_laboratory_id=t.default_reference_laboratory_id
FROM public.tests t WHERE t.id=oi.test_id;
ALTER TABLE public.clinical_order_items ALTER COLUMN execution_route SET NOT NULL;

ALTER TABLE public.clinical_report_group_items
  ADD COLUMN execution_route public.clinical_execution_route_enum,
  ADD COLUMN frozen_reference_laboratory_id UUID REFERENCES public.reference_laboratories(id) ON DELETE RESTRICT;
UPDATE public.clinical_report_group_items gi SET execution_route=oi.execution_route,
 frozen_reference_laboratory_id=oi.reference_laboratory_id
FROM public.clinical_order_items oi WHERE oi.id=gi.order_item_id;
ALTER TABLE public.clinical_report_group_items ALTER COLUMN execution_route SET NOT NULL;

ALTER TABLE public.outsource_samples
  ADD COLUMN order_item_id UUID REFERENCES public.clinical_order_items(id) ON DELETE RESTRICT,
  ADD COLUMN reference_laboratory_id UUID REFERENCES public.reference_laboratories(id) ON DELETE RESTRICT,
  ADD COLUMN recollects_outsource_sample_id UUID REFERENCES public.outsource_samples(id) ON DELETE RESTRICT;
UPDATE public.outsource_samples os SET order_item_id=oi.id
FROM public.clinical_order_items oi WHERE oi.bill_item_id=os.bill_item_id AND os.order_item_id IS NULL;
CREATE UNIQUE INDEX uq_outsource_sample_current_item ON public.outsource_samples(order_item_id)
  WHERE status NOT IN ('Rejected','Cancelled','LostInTransit');

CREATE OR REPLACE FUNCTION public.freeze_order_item_execution_route() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE;
BEGIN
 SELECT * INTO t FROM public.tests WHERE id=NEW.test_id;
 NEW.execution_route:=t.execution_route;
 NEW.reference_laboratory_id:=t.default_reference_laboratory_id;
 NEW.outsource_state:=CASE WHEN t.execution_route='OUTSOURCE' THEN 'AwaitingDispatch'::public.outsource_item_state_enum ELSE NULL END;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_freeze_order_item_execution_route BEFORE INSERT ON public.clinical_order_items
FOR EACH ROW EXECUTE FUNCTION public.freeze_order_item_execution_route();

CREATE OR REPLACE FUNCTION public.link_outsource_tracker_to_order_item() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF NEW.execution_route='OUTSOURCE' THEN
  UPDATE public.outsource_samples SET order_item_id=NEW.id
  WHERE bill_item_id=NEW.bill_item_id AND order_item_id IS NULL;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_link_outsource_tracker_to_order_item AFTER INSERT ON public.clinical_order_items
FOR EACH ROW EXECUTE FUNCTION public.link_outsource_tracker_to_order_item();

CREATE OR REPLACE FUNCTION public.freeze_report_group_execution_route() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 SELECT execution_route,reference_laboratory_id INTO NEW.execution_route,NEW.frozen_reference_laboratory_id
 FROM public.clinical_order_items WHERE id=NEW.order_item_id;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_freeze_report_group_execution_route BEFORE INSERT ON public.clinical_report_group_items
FOR EACH ROW EXECUTE FUNCTION public.freeze_report_group_execution_route();

CREATE OR REPLACE FUNCTION public.configure_reference_laboratory(p_payload JSONB,p_expected_version BIGINT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.reference_laboratories%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_manage_outsource_tracking') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF nullif(p_payload->>'id','') IS NULL THEN
  INSERT INTO public.reference_laboratories(code,name,external_code,contact_details,tat_hours,is_active,created_by)
  VALUES(upper(btrim(p_payload->>'code')),btrim(p_payload->>'name'),nullif(btrim(p_payload->>'external_code'),''),nullif(btrim(p_payload->>'contact_details'),''),(p_payload->>'tat_hours')::int,coalesce((p_payload->>'is_active')::boolean,true),auth.uid()) RETURNING * INTO r;
 ELSE
  UPDATE public.reference_laboratories SET code=upper(btrim(p_payload->>'code')),name=btrim(p_payload->>'name'),external_code=nullif(btrim(p_payload->>'external_code'),''),contact_details=nullif(btrim(p_payload->>'contact_details'),''),tat_hours=(p_payload->>'tat_hours')::int,is_active=coalesce((p_payload->>'is_active')::boolean,is_active),row_version=row_version+1,updated_at=now()
  WHERE id=(p_payload->>'id')::uuid AND row_version=p_expected_version RETURNING * INTO r;
  IF NOT FOUND THEN RAISE EXCEPTION 'Reference laboratory changed. Refresh and retry.' USING ERRCODE='PT409'; END IF;
 END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'REFERENCE_LAB_CONFIGURED','ReferenceLaboratory',r.id::text,to_jsonb(r)-'contact_details');
 RETURN jsonb_build_object('id',r.id,'row_version',r.row_version);
END $$;

CREATE OR REPLACE FUNCTION public.transition_outsource_order_item(p_order_item_id UUID,p_to_state public.outsource_item_state_enum,p_destination_id UUID DEFAULT NULL,p_external_reference TEXT DEFAULT NULL,p_payload JSONB DEFAULT '{}'::jsonb,p_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE oi public.clinical_order_items%ROWTYPE; old_state public.outsource_item_state_enum; allowed BOOLEAN:=false; tracker public.outsource_samples%ROWTYPE; new_tracking TEXT;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_manage_outsource_tracking') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 SELECT * INTO oi FROM public.clinical_order_items WHERE id=p_order_item_id FOR UPDATE;
 IF NOT FOUND OR oi.execution_route<>'OUTSOURCE' THEN RAISE EXCEPTION 'Outsource order item not found.' USING ERRCODE='P0002'; END IF;
 old_state:=oi.outsource_state;
 allowed:=CASE
  WHEN old_state='AwaitingDispatch' AND p_to_state IN ('Dispatched','Rejected','Cancelled','UnableToPerform') THEN true
  WHEN old_state='Dispatched' AND p_to_state IN ('AwaitingExternalResult','ResultReceived','Rejected','RecollectionRequired','Cancelled','UnableToPerform') THEN true
  WHEN old_state='AwaitingExternalResult' AND p_to_state IN ('ResultReceived','Rejected','RecollectionRequired','Cancelled','UnableToPerform') THEN true
  WHEN old_state='ResultReceived' AND p_to_state='InternalReview' THEN true
  WHEN old_state='InternalReview' AND p_to_state='Verified' THEN true
  WHEN old_state='RecollectionRequired' AND p_to_state='Dispatched' THEN true
  WHEN old_state='Verified' AND p_to_state='Signed' THEN true ELSE false END;
 IF NOT allowed THEN RAISE EXCEPTION 'Invalid outsource transition: % to %',old_state,p_to_state USING ERRCODE='23514'; END IF;
 IF p_to_state='Dispatched' AND (p_destination_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.reference_laboratories WHERE id=p_destination_id AND is_active)) THEN RAISE EXCEPTION 'An active reference laboratory is required for dispatch.' USING ERRCODE='23514'; END IF;
 IF p_to_state='ResultReceived' AND coalesce(p_payload,'{}'::jsonb)='{}'::jsonb THEN RAISE EXCEPTION 'External result evidence is required.' USING ERRCODE='23514'; END IF;
 IF p_to_state='ResultReceived' AND (p_payload->>'result_type' NOT IN ('NUMERIC','QUALITATIVE','NARRATIVE','STRUCTURED') OR jsonb_typeof(p_payload->'results')<>'array' OR jsonb_array_length(p_payload->'results')=0 OR nullif(btrim(p_payload->>'source_report_reference'),'') IS NULL) THEN RAISE EXCEPTION 'Result type, structured result values, and source report reference are required.' USING ERRCODE='23514'; END IF;
 UPDATE public.clinical_order_items SET outsource_state=p_to_state,
  reference_laboratory_id=coalesce(p_destination_id,reference_laboratory_id),outsource_lab_name=coalesce((SELECT name FROM public.reference_laboratories WHERE id=p_destination_id),outsource_lab_name),
  outsource_external_reference=coalesce(nullif(p_external_reference,''),outsource_external_reference),
  outsource_source_report_reference=coalesce(nullif(p_payload->>'source_report_reference',''),outsource_source_report_reference),
  outsource_method=coalesce(nullif(p_payload->>'method',''),outsource_method),outsource_interpretation=coalesce(nullif(p_payload->>'interpretation',''),outsource_interpretation),
  outsource_result_payload=CASE WHEN p_to_state='ResultReceived' THEN p_payload ELSE outsource_result_payload END,
  outsource_result_received_at=CASE WHEN p_to_state='ResultReceived' THEN now() ELSE outsource_result_received_at END,
  outsource_result_received_by=CASE WHEN p_to_state='ResultReceived' THEN auth.uid() ELSE outsource_result_received_by END,
  outsource_reviewed_at=CASE WHEN p_to_state='InternalReview' THEN now() ELSE outsource_reviewed_at END,
  outsource_reviewed_by=CASE WHEN p_to_state='InternalReview' THEN auth.uid() ELSE outsource_reviewed_by END,
  status=CASE WHEN p_to_state='Verified' THEN 'Verified' ELSE status END,
  updated_at=now(),result_revision=result_revision+1 WHERE id=oi.id;
 IF p_to_state='ResultReceived' THEN
  UPDATE public.test_results tr SET display_value=nullif(v->>'display_value',''),numeric_value=CASE WHEN nullif(v->>'numeric_value','') IS NULL THEN NULL ELSE (v->>'numeric_value')::numeric END,text_value=nullif(v->>'text_value',''),status='SubmittedForVerification',updated_at=now()
  FROM jsonb_array_elements(p_payload->'results')v JOIN public.parameters p ON p.test_id=oi.test_id AND p.code=v->>'parameter_code' AND p.is_active
  WHERE tr.order_item_id=oi.id AND tr.parameter_id=p.id;
  IF NOT EXISTS(SELECT 1 FROM public.test_results WHERE order_item_id=oi.id AND nullif(btrim(display_value),'') IS NOT NULL) THEN RAISE EXCEPTION 'No external result matched the governed test structure.' USING ERRCODE='23514'; END IF;
 ELSIF p_to_state='Verified' THEN
  IF EXISTS(SELECT 1 FROM public.test_results tr JOIN public.parameters p ON p.id=tr.parameter_id WHERE tr.order_item_id=oi.id AND p.is_mandatory AND nullif(btrim(tr.display_value),'') IS NULL) THEN RAISE EXCEPTION 'Required external result fields are incomplete.' USING ERRCODE='23514'; END IF;
  UPDATE public.test_results SET status='Verified',verified_by=auth.uid(),verified_by_name=public.catalogue_actor_name(),verified_at=now(),updated_at=now() WHERE order_item_id=oi.id;
 END IF;
 SELECT * INTO tracker FROM public.outsource_samples WHERE order_item_id=oi.id AND status NOT IN ('Rejected','Cancelled','LostInTransit') ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
 IF FOUND AND p_to_state='Dispatched' THEN
  UPDATE public.outsource_samples SET status='DispatchedToReferenceLab',reference_laboratory_id=p_destination_id,reference_lab_name=(SELECT name FROM public.reference_laboratories WHERE id=p_destination_id),dispatched_at=now(),dispatched_by=auth.uid(),dispatched_by_name=public.catalogue_actor_name(),dispatch_notes=coalesce(p_reason,dispatch_notes),updated_at=now() WHERE id=tracker.id;
  INSERT INTO public.outsource_sample_events(outsource_sample_id,event_type,from_status,to_status,notes,meta,performed_by,performed_by_name) VALUES(tracker.id,'ORDER_ITEM_DISPATCH',tracker.status,'DispatchedToReferenceLab',p_reason,jsonb_build_object('destination_id',p_destination_id,'external_reference',p_external_reference),auth.uid(),public.catalogue_actor_name());
 ELSIF FOUND AND p_to_state='ResultReceived' THEN
  UPDATE public.outsource_samples SET status='ResultReceived',external_report_received=true,reference_lab_report_no=coalesce(nullif(p_payload->>'source_report_reference',''),reference_lab_report_no),result_received_at=now(),result_received_by=auth.uid(),result_received_by_name=public.catalogue_actor_name(),result_notes=coalesce(nullif(p_payload->>'interpretation',''),result_notes),updated_at=now() WHERE id=tracker.id;
  INSERT INTO public.outsource_sample_events(outsource_sample_id,event_type,from_status,to_status,notes,meta,performed_by,performed_by_name) VALUES(tracker.id,'ORDER_ITEM_EXTERNAL_RESULT',tracker.status,'ResultReceived',p_reason,jsonb_build_object('evidence_recorded',true),auth.uid(),public.catalogue_actor_name());
 ELSIF FOUND AND p_to_state='RecollectionRequired' THEN
  UPDATE public.outsource_samples SET status='Rejected',updated_at=now() WHERE id=tracker.id;
  INSERT INTO public.outsource_sample_events(outsource_sample_id,event_type,from_status,to_status,notes,meta,performed_by,performed_by_name) VALUES(tracker.id,'REFERENCE_LAB_REJECTION',tracker.status,'Rejected',p_reason,'{"recollection_required":true}'::jsonb,auth.uid(),public.catalogue_actor_name());
  new_tracking:='OUT-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('outsource_tracking_seq')::text,5,'0');
  INSERT INTO public.outsource_samples(tracking_number,bill_id,bill_item_id,patient_id,test_id,service_description,specimen_type,specimen_description,quantity_received,reference_lab_name,status,received_by,received_by_name,order_item_id,reference_laboratory_id,recollects_outsource_sample_id)
  VALUES(new_tracking,tracker.bill_id,tracker.bill_item_id,tracker.patient_id,tracker.test_id,tracker.service_description,tracker.specimen_type,'Recollection required: '||coalesce(p_reason,'reference laboratory rejection'),tracker.quantity_received,tracker.reference_lab_name,'ReceivedAtBimal',auth.uid(),public.catalogue_actor_name(),oi.id,tracker.reference_laboratory_id,tracker.id);
 END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'OUTSOURCE_ITEM_TRANSITION','ClinicalOrderItem',oi.id::text,jsonb_build_object('state',old_state),jsonb_build_object('state',p_to_state,'destination_id',coalesce(p_destination_id,oi.reference_laboratory_id),'external_reference',p_external_reference,'reason',p_reason));
 RETURN jsonb_build_object('success',true,'order_item_id',oi.id,'from_state',old_state,'to_state',p_to_state,'revision',oi.result_revision+1);
END $$;

ALTER TABLE public.reference_laboratories ENABLE ROW LEVEL SECURITY;
CREATE POLICY reference_labs_staff_read ON public.reference_laboratories FOR SELECT TO authenticated USING(public.is_active_user());
REVOKE ALL ON public.reference_laboratories FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.reference_laboratories TO authenticated;
REVOKE ALL ON FUNCTION public.configure_reference_laboratory(JSONB,BIGINT),public.transition_outsource_order_item(UUID,public.outsource_item_state_enum,UUID,TEXT,JSONB,TEXT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.configure_reference_laboratory(JSONB,BIGINT),public.transition_outsource_order_item(UUID,public.outsource_item_state_enum,UUID,TEXT,JSONB,TEXT) TO authenticated;

COMMENT ON COLUMN public.clinical_order_items.execution_route IS 'Frozen at order-item creation; later catalogue routing changes cannot alter history.';
COMMENT ON COLUMN public.clinical_report_group_items.execution_route IS 'Frozen report membership execution provenance.';

CREATE OR REPLACE VIEW public.order_report_group_workspace WITH (security_invoker=false) AS
SELECT g.id report_group_id,g.order_id,g.group_key,g.title,g.clinical_section,g.display_order,g.lifecycle_state,g.row_version,
 oi.id order_item_id,oi.test_id,gi.frozen_test_code,gi.frozen_test_name,gi.display_order item_display_order,oi.status result_state,oi.sample_id,s.status sample_state,
 r.id latest_report_id,r.version latest_report_version,r.status report_state,a.generation_status pdf_state,oi.execution_route,oi.outsource_state,oi.outsource_lab_name
FROM public.clinical_report_groups g JOIN public.clinical_report_group_items gi ON gi.report_group_id=g.id JOIN public.clinical_order_items oi ON oi.id=gi.order_item_id
LEFT JOIN public.samples s ON s.id=oi.sample_id LEFT JOIN LATERAL(SELECT dr.* FROM public.diagnostic_reports dr WHERE dr.report_group_id=g.id ORDER BY dr.version DESC LIMIT 1) r ON true
LEFT JOIN public.report_pdf_artifacts a ON a.diagnostic_report_id=r.id AND a.report_version=r.version;
