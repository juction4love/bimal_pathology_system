-- Migration 00116: Remove Catalogue Readiness & Clinical Validation Workflow Blocks
-- Business Decision: Lab Technician / Administrator operationally decide what to process, verify, sign, and report.
-- Removes validation_status, REQUIRES_VALIDATION, and clinical_reporting_enabled blocks from routine LIS workflow.

BEGIN;

-- 1. Drop constraints that block ordering, billing, or reporting on unvalidated tests
ALTER TABLE public.tests DROP CONSTRAINT IF EXISTS chk_tests_reporting_requires_validated;
ALTER TABLE public.tests DROP CONSTRAINT IF EXISTS chk_tests_active_requires_validated;
ALTER TABLE public.tests DROP CONSTRAINT IF EXISTS chk_tests_billing_requires_validated;

-- 2. Open all reportable investigations (InHouse and OutsourceWithBimalReport)
UPDATE public.tests
SET clinical_reporting_enabled = TRUE,
    is_active = TRUE,
    billing_enabled = TRUE
WHERE reporting_type IN ('InHouse', 'OutsourceWithBimalReport');

UPDATE public.clinical_order_items
SET clinical_reporting_enabled = TRUE
WHERE reporting_type IN ('InHouse', 'OutsourceWithBimalReport');

-- 3. Update result write guard trigger: allow result entry for all reportable investigations
CREATE OR REPLACE FUNCTION public.guard_clinical_result_write() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF NOT EXISTS(
    SELECT 1 FROM public.clinical_order_items
    WHERE id = NEW.order_item_id
      AND reporting_type IN ('InHouse', 'OutsourceWithBimalReport')
  ) THEN
    RAISE EXCEPTION 'Clinical reporting is not supported for billing-only items.' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END $$;

-- 4. Server-authoritative Result Entry & Verification (no validation_status block)
CREATE OR REPLACE FUNCTION public.save_test_results_unversioned_internal(
    p_order_item_id UUID,
    p_results JSONB,
    p_target_status public.result_status_enum,
    p_amended_from_report_id UUID DEFAULT NULL,
    p_amendment_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_item public.clinical_order_items%ROWTYPE;
    v_order public.clinical_orders%ROWTYPE;
    v_parent public.diagnostic_reports%ROWTYPE;
    v_result JSONB;
    v_parameter public.parameters%ROWTYPE;
    v_existing public.test_results%ROWTYPE;
    v_user_name TEXT;
    v_is_amendment BOOLEAN := FALSE;
    v_count INT := 0;
    v_item_status TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF jsonb_typeof(p_results) <> 'array' OR jsonb_array_length(p_results) = 0 THEN
        RAISE EXCEPTION 'At least one result is required.' USING ERRCODE = '22023';
    END IF;
    IF p_target_status NOT IN ('Draft', 'SubmittedForVerification', 'ReturnedForCorrection', 'Verified') THEN
        RAISE EXCEPTION 'Unsupported result workflow state.' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_item FROM public.clinical_order_items
    WHERE id = p_order_item_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Result work item was not found.' USING ERRCODE = 'P0002';
    END IF;
    SELECT * INTO v_order FROM public.clinical_orders WHERE id = v_item.order_id FOR UPDATE;

    IF p_amended_from_report_id IS NOT NULL THEN
        SELECT * INTO v_parent FROM public.diagnostic_reports
        WHERE id = p_amended_from_report_id AND order_id = v_item.order_id
          AND status IN ('SignedOff', 'Amended');
        IF NOT FOUND OR NULLIF(btrim(p_amendment_reason), '') IS NULL
           OR NOT public.has_permission('can_amend_reports') THEN
            RAISE EXCEPTION 'A valid authorized amendment and reason are required.' USING ERRCODE = '42501';
        END IF;
        v_is_amendment := TRUE;
    END IF;

    IF p_target_status IN ('Draft', 'SubmittedForVerification')
       AND NOT (public.has_permission('can_enter_results') OR public.has_permission('can_verify_results')) THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;
    IF p_target_status IN ('ReturnedForCorrection', 'Verified')
       AND NOT public.has_permission('can_verify_results') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;
    IF v_item.status = 'SignedOff' AND NOT v_is_amendment THEN
        RAISE EXCEPTION 'This result can no longer be modified.' USING ERRCODE = '55000';
    END IF;

    IF p_target_status = 'ReturnedForCorrection'
       AND NOT EXISTS (SELECT 1 FROM public.test_results WHERE order_item_id = p_order_item_id AND status IN ('SubmittedForVerification', 'Verified')) THEN
        RAISE EXCEPTION 'Only submitted results may be returned for correction.' USING ERRCODE = '55000';
    END IF;

    IF p_target_status = 'Verified' AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_results) r
        WHERE COALESCE((r->>'is_critical')::BOOLEAN, FALSE)
          AND NOT COALESCE((r->>'critical_acknowledged')::BOOLEAN, FALSE)
    ) THEN
        RAISE EXCEPTION 'Critical results must be acknowledged before verification.' USING ERRCODE = '55000';
    END IF;

    SELECT COALESCE(full_name, 'Lab Staff') INTO v_user_name
    FROM public.user_profiles WHERE id = auth.uid();

    FOR v_result IN SELECT value FROM jsonb_array_elements(p_results)
    LOOP
        SELECT p.* INTO v_parameter
        FROM public.parameters p
        WHERE p.id = (v_result->>'parameter_id')::UUID
          AND p.test_id = v_item.test_id
          AND p.is_active = TRUE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'A submitted parameter is not valid for this investigation.' USING ERRCODE = '22023';
        END IF;

        SELECT * INTO v_existing FROM public.test_results
        WHERE order_item_id = p_order_item_id AND parameter_id = v_parameter.id
        FOR UPDATE;
        IF FOUND AND v_existing.status = 'SignedOff' AND NOT v_is_amendment THEN
            RAISE EXCEPTION 'This result can no longer be modified.' USING ERRCODE = '55000';
        END IF;

        INSERT INTO public.test_results(
            order_item_id, parameter_id, parameter_name, unit, value_type,
            numeric_value, text_value, display_value, flag, is_critical,
            critical_acknowledged, critical_acknowledged_by, critical_acknowledged_at,
            normal_range_text, normal_min, normal_max, critical_low, critical_high,
            status, entered_by, entered_by_name, entered_at,
            verified_by, verified_by_name, verified_at, updated_at
        ) VALUES (
            p_order_item_id, v_parameter.id, v_parameter.name, v_parameter.unit, v_parameter.value_type,
            NULLIF(v_result->>'numeric_value', '')::NUMERIC,
            NULLIF(v_result->>'text_value', ''), COALESCE(v_result->>'display_value', ''),
            COALESCE((v_result->>'flag')::public.result_flag_enum, 'Normal'),
            COALESCE((v_result->>'is_critical')::BOOLEAN, FALSE),
            COALESCE((v_result->>'critical_acknowledged')::BOOLEAN, FALSE),
            CASE WHEN COALESCE((v_result->>'critical_acknowledged')::BOOLEAN, FALSE) THEN auth.uid() ELSE NULL END,
            CASE WHEN COALESCE((v_result->>'critical_acknowledged')::BOOLEAN, FALSE) THEN NOW() ELSE NULL END,
            NULLIF(v_result->>'normal_range_text', ''), NULLIF(v_result->>'normal_min', '')::NUMERIC,
            NULLIF(v_result->>'normal_max', '')::NUMERIC, NULLIF(v_result->>'critical_low', '')::NUMERIC,
            NULLIF(v_result->>'critical_high', '')::NUMERIC, p_target_status,
            COALESCE(v_existing.entered_by, auth.uid()),
            COALESCE(v_existing.entered_by_name, v_user_name),
            COALESCE(v_existing.entered_at, NOW()),
            CASE WHEN p_target_status = 'Verified' THEN auth.uid() ELSE NULL END,
            CASE WHEN p_target_status = 'Verified' THEN v_user_name ELSE NULL END,
            CASE WHEN p_target_status = 'Verified' THEN NOW() ELSE NULL END,
            NOW()
        )
        ON CONFLICT (order_item_id, parameter_id) DO UPDATE SET
            parameter_name = EXCLUDED.parameter_name, unit = EXCLUDED.unit, value_type = EXCLUDED.value_type,
            numeric_value = EXCLUDED.numeric_value, text_value = EXCLUDED.text_value,
            display_value = EXCLUDED.display_value, flag = EXCLUDED.flag,
            is_critical = EXCLUDED.is_critical, critical_acknowledged = EXCLUDED.critical_acknowledged,
            critical_acknowledged_by = EXCLUDED.critical_acknowledged_by,
            critical_acknowledged_at = EXCLUDED.critical_acknowledged_at,
            normal_range_text = EXCLUDED.normal_range_text, normal_min = EXCLUDED.normal_min,
            normal_max = EXCLUDED.normal_max, critical_low = EXCLUDED.critical_low,
            critical_high = EXCLUDED.critical_high, status = EXCLUDED.status,
            entered_by = COALESCE(public.test_results.entered_by, EXCLUDED.entered_by),
            entered_by_name = COALESCE(public.test_results.entered_by_name, EXCLUDED.entered_by_name),
            entered_at = COALESCE(public.test_results.entered_at, EXCLUDED.entered_at),
            verified_by = EXCLUDED.verified_by, verified_by_name = EXCLUDED.verified_by_name,
            verified_at = EXCLUDED.verified_at, signed_off_by = NULL, signed_off_name = NULL,
            signed_off_at = NULL, updated_at = NOW();
        v_count := v_count + 1;
    END LOOP;

    v_item_status := CASE WHEN p_target_status = 'Verified' THEN 'Verified' ELSE 'ResultDrafted' END;
    UPDATE public.clinical_order_items SET status = v_item_status, updated_at = NOW()
    WHERE id = p_order_item_id;
    IF v_order.status = 'SignedOff' AND v_is_amendment THEN
        UPDATE public.clinical_orders SET status = 'InProgress', updated_at = NOW() WHERE id = v_order.id;
    END IF;

    INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES (
        auth.uid(), v_user_name,
        CASE p_target_status WHEN 'Verified' THEN 'RESULTS_VERIFIED'
          WHEN 'SubmittedForVerification' THEN 'RESULTS_SUBMITTED'
          WHEN 'ReturnedForCorrection' THEN 'RESULTS_RETURNED' ELSE 'RESULTS_SAVED' END,
        'ClinicalOrderItem', p_order_item_id::TEXT,
        jsonb_strip_nulls(jsonb_build_object(
            'status', p_target_status, 'result_count', v_count,
            'amended_from_report_id', p_amended_from_report_id,
            'amendment_reason_recorded', CASE WHEN v_is_amendment THEN TRUE ELSE NULL END
        ))
    );

    RETURN jsonb_build_object('success', TRUE, 'status', p_target_status, 'result_count', v_count);
END;
$$;

-- 5. Diagnostic Report Readiness Check (no validation_status block)
CREATE OR REPLACE FUNCTION public.check_order_report_readiness(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_reportable_count INT := 0;
    v_verified_count INT := 0;
    v_unverified_items JSONB := '[]'::JSONB;
    v_unack_critical_count INT := 0;
    v_unack_critical_items JSONB := '[]'::JSONB;
    v_is_ready BOOLEAN := FALSE;
    v_item RECORD;
    v_res RECORD;
BEGIN
    FOR v_item IN (
        SELECT coi.id, coi.test_name, coi.department, coi.reporting_type, coi.status, t.code AS test_code
        FROM public.clinical_order_items coi
        JOIN public.tests t ON coi.test_id = t.id
        WHERE coi.order_id = p_order_id
          AND coi.reporting_type IN ('InHouse', 'OutsourceWithBimalReport')
    ) LOOP
        v_reportable_count := v_reportable_count + 1;

        IF v_item.status IN ('Verified', 'SignedOff') THEN
            v_verified_count := v_verified_count + 1;
        ELSE
            v_unverified_items := v_unverified_items || jsonb_build_object(
                'order_item_id', v_item.id,
                'test_name', v_item.test_name,
                'department', v_item.department,
                'status', v_item.status
            );
        END IF;
    END LOOP;

    -- Check critical panic values
    FOR v_res IN (
        SELECT tr.id, tr.parameter_name, tr.display_value, tr.unit, tr.flag, tr.critical_acknowledged, coi.test_name
        FROM public.test_results tr
        JOIN public.clinical_order_items coi ON tr.order_item_id = coi.id
        WHERE coi.order_id = p_order_id
          AND (tr.is_critical = TRUE OR tr.flag IN ('CriticalLow', 'CriticalHigh'))
          AND tr.critical_acknowledged = FALSE
    ) LOOP
        v_unack_critical_count := v_unack_critical_count + 1;
        v_unack_critical_items := v_unack_critical_items || jsonb_build_object(
            'result_id', v_res.id,
            'test_name', v_res.test_name,
            'parameter_name', v_res.parameter_name,
            'display_value', v_res.display_value,
            'flag', v_res.flag
        );
    END LOOP;

    v_is_ready := (
        v_reportable_count > 0 AND
        v_verified_count = v_reportable_count AND
        v_unack_critical_count = 0
    );

    RETURN jsonb_build_object(
        'is_ready', v_is_ready,
        'reportable_count', v_reportable_count,
        'verified_count', v_verified_count,
        'unverified_count', jsonb_array_length(v_unverified_items),
        'unverified_items', v_unverified_items,
        'unvalidated_count', 0,
        'unvalidated_items', '[]'::JSONB,
        'unacknowledged_critical_count', v_unack_critical_count,
        'unacknowledged_critical_items', v_unack_critical_items
    );
END $$;

-- 6. Report Group Materialization: automatically freeze report group for all reportable tests
CREATE OR REPLACE FUNCTION public.materialize_report_group_item() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE; g UUID; actor UUID:=coalesce(auth.uid(),(SELECT created_by FROM public.bills b JOIN public.clinical_orders o ON o.bill_id=b.id WHERE o.id=NEW.order_id));
BEGIN
  SELECT * INTO t FROM public.tests WHERE id=NEW.test_id;
  IF NOT FOUND OR NEW.reporting_type = 'NoReporting' THEN RETURN NEW; END IF;
  INSERT INTO public.clinical_report_groups(order_id,group_key,title,clinical_section,display_order,configuration_version,created_by)
  VALUES(NEW.order_id,COALESCE(NULLIF(t.report_group_key,''),'general_laboratory'),COALESCE(NULLIF(t.report_group_title,''),'General Laboratory'),COALESCE(NULLIF(t.report_section,''),'Laboratory'),COALESCE(t.report_group_sort_order,500),COALESCE(t.row_version,1),actor)
  ON CONFLICT(order_id,group_key) DO UPDATE SET display_order=least(clinical_report_groups.display_order,excluded.display_order)
  RETURNING id INTO g;
  INSERT INTO public.clinical_report_group_items(report_group_id,order_item_id,frozen_test_code,frozen_test_name,display_order,created_by)
  VALUES(g,NEW.id,COALESCE(t.code,NEW.test_name),NEW.test_name,coalesce(t.display_order,0),actor) ON CONFLICT(order_item_id) DO NOTHING;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
  VALUES(actor,public.catalogue_actor_name(),'REPORT_GROUP_ITEM_FROZEN','ClinicalReportGroup',g::text,jsonb_build_object('order_item_id',NEW.id,'group_key',COALESCE(t.report_group_key,'general_laboratory'),'test_code',t.code));
  RETURN NEW;
END $$;

-- 7. Report Group Readiness: evaluate report group items without clinical_reporting_enabled filter
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
 FROM public.clinical_report_group_items gi JOIN public.clinical_order_items oi ON oi.id=gi.order_item_id LEFT JOIN public.samples s ON s.id=oi.sample_id
 WHERE gi.report_group_id=p_report_group_id AND oi.reporting_type IN ('InHouse', 'OutsourceWithBimalReport');
 state:=CASE WHEN unverified+collection_blocked+critical_blocked+calculation_blocked=0 AND total_count>0 THEN 'ReadyToSign' WHEN unverified<total_count THEN 'InProgress' ELSE 'Pending' END;
 UPDATE public.clinical_report_groups SET lifecycle_state=CASE WHEN lifecycle_state IN ('Signed','Amended') THEN lifecycle_state ELSE state END,updated_at=now(),row_version=row_version+1 WHERE id=p_report_group_id;
 RETURN jsonb_build_object('is_ready',total_count>0 AND unverified+collection_blocked+critical_blocked+calculation_blocked=0,'total_count',total_count,'unverified_count',unverified,'collection_blocked_count',collection_blocked,'unacknowledged_critical_count',critical_blocked,'calculation_blocked_count',calculation_blocked,'state',state);
END $$;

-- 8. Worklist Search: Show all reportable investigations (InHouse, OutsourceWithBimalReport)
CREATE OR REPLACE FUNCTION public.search_laboratory_worklist(
  p_search TEXT DEFAULT NULL,
  p_department TEXT DEFAULT NULL,
  p_sample_status TEXT DEFAULT NULL,
  p_order_date DATE DEFAULT NULL,
  p_view TEXT DEFAULT 'All',
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 50
)
RETURNS TABLE(item JSONB)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path=public,pg_temp
AS $$
DECLARE
  term TEXT:=NULLIF(btrim(p_search),'');
  escaped_term TEXT;
BEGIN
  IF p_limit<1 OR p_limit>100 THEN
    RAISE EXCEPTION 'Invalid worklist page size.' USING ERRCODE='22023';
  END IF;
  IF (p_cursor_created_at IS NULL)<>(p_cursor_id IS NULL) THEN
    RAISE EXCEPTION 'Incomplete worklist cursor.' USING ERRCODE='22023';
  END IF;
  IF p_view NOT IN ('All','Pending','ToVerify','Verified','Signed') THEN
    RAISE EXCEPTION 'Invalid worklist view.' USING ERRCODE='22023';
  END IF;
  escaped_term:=replace(replace(replace(lower(term),'\','\\'),'%','\%'),'_','\_');

  RETURN QUERY
  SELECT jsonb_build_object(
    'id',coi.id,
    'order_id',coi.order_id,
    'test_id',coi.test_id,
    'test_name',coi.test_name,
    'department',coi.department,
    'reporting_type',coi.reporting_type,
    'outsource_lab_name',coi.outsource_lab_name,
    'status',coi.status,
    'created_at',coi.created_at,
    'order',jsonb_build_object(
      'id',o.id,'order_number',o.order_number,'order_date_ad',o.order_date_ad,
      'order_date_bs',o.order_date_bs,'patient',jsonb_build_object(
        'uhid',p.uhid,'full_name',p.full_name,'gender',p.gender,'age_years',p.age_years
      )
    ),
    'sample',CASE WHEN s.id IS NULL THEN NULL ELSE jsonb_build_object(
      'barcode',s.barcode,'status',s.status,'specimen_type',s.specimen_type,
      'container_type',s.container_type
    ) END,
    'results',COALESCE(result_set.results,'[]'::JSONB),
    'report',report_row.report
  )
  FROM public.clinical_order_items coi
  JOIN public.clinical_orders o ON o.id=coi.order_id
  JOIN public.patients p ON p.id=o.patient_id
  LEFT JOIN public.samples s ON s.id=coi.sample_id
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(jsonb_build_object(
      'id',tr.id,'flag',tr.flag,'is_critical',tr.is_critical,'status',tr.status
    ) ORDER BY tr.id) AS results
    FROM public.test_results tr WHERE tr.order_item_id=coi.id
  ) result_set ON TRUE
  LEFT JOIN LATERAL (
    SELECT jsonb_build_object('id',r.id,'report_number',r.report_number,'version',r.version,'status',r.status) AS report
    FROM public.diagnostic_reports r WHERE r.order_id=coi.order_id
    ORDER BY r.version DESC,r.created_at DESC,r.id DESC LIMIT 1
  ) report_row ON TRUE
  WHERE coi.reporting_type IN ('InHouse','OutsourceWithBimalReport')
    AND (p_cursor_created_at IS NULL OR (coi.created_at,coi.id)<(p_cursor_created_at,p_cursor_id))
    AND (p_department IS NULL OR p_department='' OR coi.department=p_department)
    AND (p_sample_status IS NULL OR p_sample_status='' OR s.status::TEXT=p_sample_status)
    AND (p_order_date IS NULL OR o.order_date_ad=p_order_date)
    AND (
      p_view='All'
      OR (p_view='Pending' AND coi.status IN ('SampleReceived','ResultDrafted'))
      OR (p_view='ToVerify' AND coi.status NOT IN ('Verified','SignedOff') AND EXISTS(
        SELECT 1 FROM public.test_results pending_result
        WHERE pending_result.order_item_id=coi.id AND pending_result.status='SubmittedForVerification'
      ))
      OR (p_view='Verified' AND coi.status='Verified' AND report_row.report IS NULL)
      OR (p_view='Signed' AND (coi.status='SignedOff' OR report_row.report IS NOT NULL))
    )
    AND (
      term IS NULL
      OR (term~*'^BPDC-[0-9]{8}$' AND o.order_number=upper(term))
      OR (term!~*'^BPDC-[0-9]{8}$' AND (
        lower(p.full_name) LIKE '%'||escaped_term||'%' ESCAPE '\'
        OR lower(p.uhid) LIKE '%'||escaped_term||'%' ESCAPE '\'
        OR lower(o.order_number) LIKE '%'||escaped_term||'%' ESCAPE '\'
        OR lower(COALESCE(s.barcode,'')) LIKE '%'||escaped_term||'%' ESCAPE '\'
        OR lower(coi.test_name) LIKE '%'||escaped_term||'%' ESCAPE '\'
      ))
    )
  ORDER BY coi.created_at DESC,coi.id DESC
  LIMIT p_limit+1;
END;
$$;

-- 9. Ensure Bill Collection Traceability: create clinical order items and samples for all reportable tests
CREATE OR REPLACE FUNCTION public.ensure_bill_collection_traceability(p_bill_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE b public.bills%ROWTYPE; o public.clinical_orders%ROWTYPE; x RECORD; s_id UUID; key TEXT; sample_map JSONB:='{}'; actor_name TEXT; created_samples INT:=0; created_items INT:=0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  SELECT * INTO b FROM public.bills WHERE id=p_bill_id FOR SHARE; IF NOT FOUND THEN RAISE EXCEPTION 'Bill not found.' USING ERRCODE='P0002'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.bill_items bi JOIN public.tests t ON t.id=bi.test_id WHERE bi.bill_id=b.id AND (t.collection_required OR t.reporting_type IN ('InHouse','OutsourceWithBimalReport'))) THEN RETURN jsonb_build_object('order_id',NULL,'order_number',NULL,'samples_created',0,'items_created',0); END IF;
  SELECT * INTO o FROM public.clinical_orders WHERE bill_id=b.id ORDER BY created_at LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN INSERT INTO public.clinical_orders(order_number,bill_id,patient_id,order_date_ad,order_date_bs,status) VALUES('ALLOCATE-BPDC',b.id,b.patient_id,CURRENT_DATE,to_char(CURRENT_DATE,'YYYY-MM-DD'),'Registered') RETURNING * INTO o; END IF;
  SELECT COALESCE(full_name,'Billing Staff') INTO actor_name FROM public.user_profiles WHERE id=auth.uid();
  FOR x IN SELECT bi.id bill_item_id,t.* FROM public.bill_items bi JOIN public.tests t ON t.id=bi.test_id WHERE bi.bill_id=b.id AND (t.collection_required OR t.reporting_type IN ('InHouse','OutsourceWithBimalReport')) ORDER BY bi.created_at LOOP
    SELECT sample_id INTO s_id FROM public.clinical_order_items WHERE bill_item_id=x.bill_item_id;
    IF s_id IS NULL THEN
      key:=COALESCE(NULLIF(btrim(x.sample_type),''),'Blood')||'::'||COALESCE(NULLIF(btrim(x.container),''),'EDTA');
      IF sample_map ? key THEN s_id:=(sample_map->>key)::UUID; ELSE
        SELECT id INTO s_id FROM public.samples WHERE order_id=o.id AND specimen_type=COALESCE(NULLIF(btrim(x.sample_type),''),'Blood') AND container_type=COALESCE(NULLIF(btrim(x.container),''),'EDTA') ORDER BY created_at LIMIT 1;
        IF s_id IS NULL THEN INSERT INTO public.samples(barcode,order_id,patient_id,specimen_type,container_type,status) VALUES('SMP-'||to_char(CURRENT_DATE,'YYYY')||'-'||lpad(nextval('sample_seq')::TEXT,5,'0'),o.id,b.patient_id,COALESCE(NULLIF(btrim(x.sample_type),''),'Blood'),COALESCE(NULLIF(btrim(x.container),''),'EDTA'),'Pending') RETURNING id INTO s_id; created_samples:=created_samples+1; END IF;
        sample_map:=jsonb_set(sample_map,ARRAY[key],to_jsonb(s_id::TEXT));
      END IF;
      INSERT INTO public.clinical_order_items(order_id,bill_item_id,test_id,test_name,department,reporting_type,outsource_lab_name,specimen_type,container_type,status,sample_id,workflow_type,clinical_reporting_enabled,collection_required)
      VALUES(o.id,x.bill_item_id,x.id,x.name,x.department,x.reporting_type,x.outsource_lab_name,COALESCE(NULLIF(btrim(x.sample_type),''),'Blood'),COALESCE(NULLIF(btrim(x.container),''),'EDTA'),'Pending',s_id,x.workflow_type,TRUE,COALESCE(x.collection_required,TRUE)); created_items:=created_items+1;
    ELSE UPDATE public.clinical_order_items SET workflow_type=x.workflow_type,clinical_reporting_enabled=TRUE,collection_required=COALESCE(x.collection_required,TRUE) WHERE bill_item_id=x.bill_item_id; END IF;
  END LOOP;
  INSERT INTO public.sample_lifecycle_events(sample_id,from_status,to_status,reason,performed_by,performed_by_name,timestamp)
  SELECT s.id,s.status,s.status,'Sample accession created during bill finalization',auth.uid(),COALESCE(actor_name,'Billing Staff'),s.created_at FROM public.samples s WHERE s.order_id=o.id AND NOT EXISTS(SELECT 1 FROM public.sample_lifecycle_events e WHERE e.sample_id=s.id);
  RETURN jsonb_build_object('order_id',o.id,'order_number',o.order_number,'samples_created',created_samples,'items_created',created_items);
END $$;

-- 10. Search Billable Catalogue: allow all active catalogue items without validation_status gate
CREATE OR REPLACE FUNCTION public.search_billable_catalogue(p_query TEXT, p_limit INT DEFAULT 20)
RETURNS TABLE(
  entity_type TEXT,
  entity_id UUID,
  code TEXT,
  name TEXT,
  short_name TEXT,
  category TEXT,
  specimen TEXT,
  container TEXT,
  price_paisa BIGINT,
  price_configured BOOLEAN,
  pricing_policy public.catalogue_pricing_policy_enum,
  allow_zero_price_billing BOOLEAN,
  reporting_type public.reporting_type_enum,
  rank_score INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
#variable_conflict use_column
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;

  RETURN QUERY WITH q AS (
    SELECT lower(btrim(COALESCE(p_query, ''))) value
  ),
  matches(entity_kind, item_id, item_code, item_name, item_short_name, item_category, item_specimen, item_container, item_price_paisa, item_price_configured, item_pricing_policy, item_zero_price, item_reporting_type, item_score) AS (
    SELECT
      'Test'::TEXT,
      t.id,
      t.code::TEXT,
      t.name::TEXT,
      t.short_name::TEXT,
      c.name::TEXT,
      t.sample_type::TEXT,
      t.container::TEXT,
      r.price_paisa,
      (r.id IS NOT NULL AND r.price_paisa IS NOT NULL),
      COALESCE(t.pricing_policy, 'Fixed'),
      t.allow_zero_price_billing,
      t.reporting_type,
      CASE
        WHEN lower(t.code) = q.value THEN 100
        WHEN lower(t.code) LIKE q.value || '%' THEN 90
        WHEN lower(t.name) LIKE q.value || '%' THEN 70
        ELSE 50
      END score
    FROM public.tests t
    CROSS JOIN q
    LEFT JOIN public.test_categories c ON c.id = t.category_id
    LEFT JOIN public.catalogue_rate_versions r ON r.test_id = t.id AND r.status = 'Active' AND (r.effective_to IS NULL OR r.effective_to > now())
    WHERE length(q.value) >= 2
      AND t.is_active = TRUE
      AND t.lifecycle_status = 'Active'
      AND (
        lower(t.code) LIKE '%' || q.value || '%'
        OR lower(t.name) LIKE '%' || q.value || '%'
        OR lower(COALESCE(t.short_name, '')) LIKE '%' || q.value || '%'
        OR EXISTS (
          SELECT 1 FROM public.test_aliases a
          WHERE a.test_id = t.id AND lower(a.alias_name) LIKE '%' || q.value || '%'
        )
      )

    UNION ALL

    SELECT
      'Package',
      p.id,
      p.code::TEXT,
      p.name::TEXT,
      NULL,
      'Health Packages',
      NULL,
      NULL,
      r.price_paisa,
      (r.id IS NOT NULL AND r.price_paisa IS NOT NULL),
      p.pricing_policy,
      FALSE,
      'NoReporting'::public.reporting_type_enum,
      CASE
        WHEN lower(p.code) = q.value THEN 100
        WHEN lower(p.code) LIKE q.value || '%' THEN 90
        WHEN lower(p.name) LIKE q.value || '%' THEN 70
        ELSE 50
      END
    FROM public.health_packages p
    CROSS JOIN q
    LEFT JOIN public.catalogue_rate_versions r ON r.package_id = p.id AND r.status = 'Active' AND (r.effective_to IS NULL OR r.effective_to > now())
    WHERE length(q.value) >= 2
      AND p.lifecycle_status = 'Active'
      AND (lower(p.code) LIKE '%' || q.value || '%' OR lower(p.name) LIKE '%' || q.value || '%')

    UNION ALL

    SELECT
      'Panel',
      ps.id,
      ps.code,
      ps.name,
      NULL,
      c.name,
      ps.specimen,
      ps.container,
      r.price_paisa,
      (r.id IS NOT NULL AND r.price_paisa IS NOT NULL),
      'Fixed'::public.catalogue_pricing_policy_enum,
      FALSE,
      ps.reporting_type,
      CASE
        WHEN lower(ps.code) = q.value THEN 100
        WHEN lower(ps.code) LIKE q.value || '%' THEN 90
        WHEN lower(ps.name) LIKE q.value || '%' THEN 70
        ELSE 50
      END
    FROM public.catalogue_panel_services ps
    JOIN public.test_categories c ON c.id = ps.category_id
    CROSS JOIN q
    LEFT JOIN public.catalogue_rate_versions r ON r.panel_service_id = ps.id AND r.status = 'Active' AND (r.effective_to IS NULL OR r.effective_to > now())
    WHERE length(q.value) >= 2
      AND ps.lifecycle_status = 'Active'
      AND (lower(ps.code) LIKE '%' || q.value || '%' OR lower(ps.name) LIKE '%' || q.value || '%')
  )
  SELECT
    m.entity_kind,
    m.item_id,
    m.item_code,
    m.item_name,
    m.item_short_name,
    m.item_category,
    m.item_specimen,
    m.item_container,
    m.item_price_paisa,
    m.item_price_configured,
    m.item_pricing_policy,
    m.item_zero_price,
    m.item_reporting_type,
    m.item_score
  FROM matches m
  ORDER BY m.item_score DESC, m.item_name
  LIMIT greatest(1, least(COALESCE(p_limit, 20), 50));
END $$;

-- 11. Catalogue Set Test Lifecycle: allow activating test without validation_status blocking
CREATE OR REPLACE FUNCTION public.catalogue_set_test_lifecycle(
  p_test_id UUID,
  p_status public.catalogue_lifecycle_enum,
  p_expected_version BIGINT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager();
  SELECT * INTO v FROM public.tests WHERE id=p_test_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002';
  END IF;
  IF v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409';
  END IF;

  UPDATE public.tests
  SET lifecycle_status = p_status,
      is_active = (p_status = 'Active'),
      billing_enabled = CASE WHEN p_status = 'Active' THEN TRUE ELSE billing_enabled END,
      clinical_reporting_enabled = CASE WHEN p_status = 'Active' AND reporting_type IN ('InHouse', 'OutsourceWithBimalReport') THEN TRUE ELSE clinical_reporting_enabled END,
      row_version = row_version + 1,
      updated_at = NOW(),
      archived_at = CASE WHEN p_status = 'Archived' THEN NOW() ELSE NULL END,
      archived_by = CASE WHEN p_status = 'Archived' THEN auth.uid() ELSE NULL END,
      activated_at = CASE WHEN p_status = 'Active' THEN NOW() ELSE activated_at END,
      activated_by = CASE WHEN p_status = 'Active' THEN auth.uid() ELSE activated_by END
  WHERE id = p_test_id;

  INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    auth.uid(),
    public.catalogue_actor_name(),
    'CATALOGUE_TEST_' || upper(p_status::TEXT),
    'Test',
    p_test_id::TEXT,
    to_jsonb(v),
    (SELECT to_jsonb(x) FROM public.tests x WHERE x.id = p_test_id)
  );

  RETURN jsonb_build_object('id', p_test_id, 'status', p_status, 'validation_status', v.validation_status);
END $$;

-- 12. Create Patient Bill Order with Panel Service: allow panel billing without blocking on readiness
CREATE OR REPLACE FUNCTION public.create_patient_bill_order_with_panel_service(
  p_patient_data JSONB,
  p_bill_data JSONB,
  p_payment_data JSONB,
  p_idempotency_key TEXT,
  p_panel_service_id UUID,
  p_expected_panel_version BIGINT,
  p_agreed_panel_price_paisa BIGINT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  svc public.catalogue_panel_services%ROWTYPE;
  rate public.catalogue_rate_versions%ROWTYPE;
  items JSONB[];
  response JSONB;
  bill_uuid UUID;
  selection_uuid UUID;
  component_snapshot JSONB;
  component_ids UUID[];
  manual_ids UUID[]:=ARRAY[]::UUID[];
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_agreed_panel_price_paisa IS NULL OR p_agreed_panel_price_paisa<=0 THEN RAISE EXCEPTION 'A panel requires a positive agreed price.' USING ERRCODE='23514'; END IF;
  SELECT * INTO svc FROM public.catalogue_panel_services WHERE id=p_panel_service_id AND lifecycle_status='Active' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Panel service is inactive or missing.' USING ERRCODE='23503'; END IF;
  IF svc.row_version<>p_expected_panel_version THEN RAISE EXCEPTION 'Panel definition changed. Refresh billing catalogue.' USING ERRCODE='PT409'; END IF;
  SELECT * INTO rate FROM public.catalogue_rate_versions WHERE panel_service_id=svc.id AND status='Active' AND price_paisa IS NOT NULL AND COALESCE(effective_from,now())<=now() AND(effective_to IS NULL OR effective_to>now()) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'A panel catalogue default must be active before billing.' USING ERRCODE='23514'; END IF;
  
  SELECT array_agg(jsonb_build_object('test_id',c.test_id,'unit_price_paisa',CASE WHEN c.display_order=x.min_ord THEN p_agreed_panel_price_paisa ELSE 0 END,'manual_price_paisa',CASE WHEN c.display_order=x.min_ord THEN p_agreed_panel_price_paisa ELSE 0 END,'discount_paisa',0,'zero_price_acknowledged',TRUE) ORDER BY c.display_order),
    jsonb_agg(jsonb_build_object('test_id',c.test_id,'test_code',c.test_code,'test_name',c.test_name,'display_order',c.display_order) ORDER BY c.display_order),array_agg(c.test_id ORDER BY c.test_id)
  INTO items,component_snapshot,component_ids FROM public.catalogue_panel_service_components(svc.id)c CROSS JOIN(SELECT min(display_order)min_ord FROM public.catalogue_panel_service_components(svc.id))x;
  IF items IS NULL THEN RAISE EXCEPTION 'Panel has no canonical component tests.' USING ERRCODE='23514'; END IF;
  PERFORM 1 FROM public.tests WHERE id=ANY(component_ids) ORDER BY id FOR UPDATE;
  SELECT COALESCE(array_agg(id ORDER BY id),ARRAY[]::UUID[]) INTO manual_ids FROM public.tests WHERE id=ANY(component_ids) AND NOT allow_manual_price;
  UPDATE public.tests SET allow_manual_price=TRUE WHERE id=ANY(manual_ids);
  response:=public.create_patient_bill_and_order(p_patient_data,p_bill_data,items,p_payment_data,p_idempotency_key); bill_uuid:=(response->>'bill_id')::UUID;
  UPDATE public.bill_items bi SET catalogue_price_paisa_snapshot=t.price_paisa FROM public.tests t WHERE bi.bill_id=bill_uuid AND bi.test_id=t.id;
  UPDATE public.tests SET allow_manual_price=FALSE WHERE id=ANY(manual_ids);
  INSERT INTO public.bill_panel_selections(bill_id,panel_service_id,panel_id,service_code_snapshot,panel_name_snapshot,panel_price_paisa,catalogue_panel_price_paisa,rate_version_id,component_snapshot)
  VALUES(bill_uuid,svc.id,svc.panel_id,svc.code,svc.name,p_agreed_panel_price_paisa,rate.price_paisa,rate.id,component_snapshot)
  ON CONFLICT(bill_id,panel_service_id) DO NOTHING RETURNING id INTO selection_uuid;
  IF selection_uuid IS NULL THEN
    SELECT id INTO selection_uuid FROM public.bill_panel_selections WHERE bill_id=bill_uuid AND panel_service_id=svc.id;
  ELSE
    INSERT INTO public.bill_panel_components(bill_panel_selection_id,bill_item_id,test_id,display_order)
    SELECT selection_uuid,bi.id,bi.test_id,(x->>'display_order')::INT
    FROM jsonb_array_elements(component_snapshot)x
    JOIN public.bill_items bi ON bi.bill_id=bill_uuid AND bi.test_id=(x->>'test_id')::UUID;
  END IF;
  RETURN response||jsonb_build_object('panel_selection_id',selection_uuid,'panel_service_id',svc.id,'panel_code',svc.code,'components_recorded',cardinality(items));
END $$;

-- 13. Grant execute privileges
GRANT EXECUTE ON FUNCTION public.search_billable_catalogue(TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_set_test_lifecycle(UUID, public.catalogue_lifecycle_enum, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_order_with_panel_service(JSONB, JSONB, JSONB, TEXT, UUID, BIGINT, BIGINT) TO authenticated;

COMMIT;

