-- Production runtime contract corrections discovered by the systematic 00087
-- live-schema audit. No business rows are changed by this migration.

CREATE OR REPLACE FUNCTION public.search_patient_history(
  p_patient_id UUID,
  p_section TEXT,
  p_cursor_timestamp TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 25
)
RETURNS TABLE(item JSONB,sort_timestamp TIMESTAMPTZ,sort_id UUID)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_active_user() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF p_section='orders' THEN
  RETURN QUERY SELECT jsonb_build_object('id',o.id,'order_number',o.order_number,'status',o.status,'created_at',o.created_at,'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('test_name',i.test_name) ORDER BY i.created_at) FROM public.clinical_order_items i WHERE i.order_id=o.id),'[]'::JSONB)),o.created_at,o.id FROM public.clinical_orders o WHERE o.patient_id=p_patient_id AND(p_cursor_timestamp IS NULL OR(o.created_at,o.id)<(p_cursor_timestamp,p_cursor_id)) ORDER BY o.created_at DESC,o.id DESC LIMIT greatest(1,least(COALESCE(p_limit,25),51));
 ELSIF p_section='bills' THEN
  RETURN QUERY SELECT jsonb_build_object('id',b.id,'bill_number',b.bill_number,'bill_date',b.created_at,'gross_amount_paisa',b.gross_amount_paisa,'net_amount_paisa',b.net_amount_paisa,'paid_amount_paisa',b.paid_amount_paisa,'due_amount_paisa',b.due_amount_paisa,'payment_status',b.payment_status,'created_at',b.created_at,'clinical_orders',COALESCE((SELECT jsonb_agg(jsonb_build_object('order_number',o.order_number) ORDER BY o.created_at) FROM public.clinical_orders o WHERE o.bill_id=b.id),'[]'::JSONB),'payment_transactions',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',pt.id,'receipt_number',pt.receipt_number,'amount_paisa',pt.amount_paisa,'payment_mode',pt.payment_mode,'created_at',pt.created_at) ORDER BY pt.created_at) FROM public.payment_transactions pt WHERE pt.bill_id=b.id),'[]'::JSONB)),b.created_at,b.id FROM public.bills b WHERE b.patient_id=p_patient_id AND(p_cursor_timestamp IS NULL OR(b.created_at,b.id)<(p_cursor_timestamp,p_cursor_id)) ORDER BY b.created_at DESC,b.id DESC LIMIT greatest(1,least(COALESCE(p_limit,25),51));
 ELSIF p_section='reports' THEN
  RETURN QUERY SELECT jsonb_build_object('id',r.id,'report_number',r.report_number,'version',r.version,'is_amendment',r.is_amendment,'amendment_reason',r.amendment_reason,'status',r.status,'signed_at',r.signed_at,'integrity_hash',r.integrity_hash),r.signed_at,r.id FROM public.diagnostic_reports r WHERE r.patient_id=p_patient_id AND(p_cursor_timestamp IS NULL OR(r.signed_at,r.id)<(p_cursor_timestamp,p_cursor_id)) ORDER BY r.signed_at DESC,r.id DESC LIMIT greatest(1,least(COALESCE(p_limit,25),51));
 ELSE RAISE EXCEPTION 'Unknown patient history section.' USING ERRCODE='22023'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.search_patient_history(UUID,TEXT,TIMESTAMPTZ,UUID,INT) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.search_patient_history(UUID,TEXT,TIMESTAMPTZ,UUID,INT) TO authenticated;

CREATE OR REPLACE FUNCTION public.catalogue_delete_or_archive_rate(p_rate_id UUID,p_expected_version BIGINT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.catalogue_rate_versions%ROWTYPE; v_used BOOLEAN;
BEGIN
 PERFORM public.catalogue_require_manager();
 SELECT * INTO r FROM public.catalogue_rate_versions WHERE id=p_rate_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Rate not found.' USING ERRCODE='P0002'; END IF;
 IF r.row_version<>p_expected_version THEN RAISE EXCEPTION 'Rate changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.bill_panel_selections WHERE rate_version_id=r.id) INTO v_used;
 IF NOT v_used AND r.status='Draft' THEN
  DELETE FROM public.catalogue_rate_versions WHERE id=r.id;
  RETURN 'Deleted';
 END IF;
 UPDATE public.catalogue_rate_versions
 SET status=(CASE WHEN v_used THEN 'Inactive' ELSE 'Archived' END)::public.catalogue_rate_status_enum,
  effective_to=COALESCE(effective_to,now()),row_version=row_version+1,updated_at=now()
 WHERE id=r.id;
 RETURN CASE WHEN v_used THEN 'ArchivedUsedRate' ELSE 'Archived' END;
END $$;
REVOKE ALL ON FUNCTION public.catalogue_delete_or_archive_rate(UUID,BIGINT) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.catalogue_delete_or_archive_rate(UUID,BIGINT) TO authenticated;

CREATE OR REPLACE FUNCTION public.complete_report_pdf_artifact(p_artifact_id UUID,p_lease_owner UUID,p_ready BOOLEAN,
  p_pdf_sha256 TEXT DEFAULT NULL,p_byte_size BIGINT DEFAULT NULL,p_generator_name TEXT DEFAULT NULL,
  p_generator_version TEXT DEFAULT NULL,p_failure_code TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE a public.report_pdf_artifacts%ROWTYPE; key TEXT; next_status public.report_artifact_status_enum;
BEGIN
  IF NOT public.is_report_artifact_worker() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  SELECT * INTO a FROM public.report_pdf_artifacts WHERE id=p_artifact_id FOR UPDATE;
  IF NOT FOUND OR a.generation_status<>'Generating' OR a.lease_owner IS DISTINCT FROM p_lease_owner OR a.lease_expires_at<=NOW() THEN
    RAISE EXCEPTION 'Artifact lease is not owned by this attempt.' USING ERRCODE='55000';
  END IF;
  IF p_ready THEN
    IF p_pdf_sha256 !~ '^[0-9a-f]{64}$' OR p_byte_size IS NULL OR p_byte_size<=0 THEN RAISE EXCEPTION 'Invalid PDF evidence.' USING ERRCODE='22023'; END IF;
    key:=format('reports/%s/%s/v%s/%s.pdf',extract(year from a.created_at AT TIME ZONE 'UTC')::INT,a.diagnostic_report_id,a.report_version,p_pdf_sha256);
    next_status:='Ready';
    UPDATE public.report_pdf_artifacts SET generation_status=next_status,object_key=key,pdf_sha256=p_pdf_sha256,
      byte_size=p_byte_size,mime_type='application/pdf',generator_name=p_generator_name,generator_version=p_generator_version,
      generated_at=NOW(),lease_owner=NULL,lease_expires_at=NULL,updated_at=NOW() WHERE id=a.id;
  ELSE
    next_status:=(CASE WHEN p_failure_code='R2_UPLOAD_FAILED' THEN 'UploadFailed' ELSE 'GenerationFailed' END)::public.report_artifact_status_enum;
    UPDATE public.report_pdf_artifacts SET generation_status=next_status,failure_code=left(p_failure_code,100),
      lease_owner=NULL,lease_expires_at=NULL,updated_at=NOW() WHERE id=a.id;
  END IF;
  RETURN jsonb_build_object('status',next_status,'object_key',key);
END $$;
REVOKE ALL ON FUNCTION public.complete_report_pdf_artifact(UUID,UUID,BOOLEAN,TEXT,BIGINT,TEXT,TEXT,TEXT) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.complete_report_pdf_artifact(UUID,UUID,BOOLEAN,TEXT,BIGINT,TEXT,TEXT,TEXT) TO authenticated;

-- Catalogue readiness decisions are an operational catalogue responsibility.
-- The canonical manager guard admits an active Lab Technician with
-- can_manage_catalogue and retains the effective Super Admin bypass.
CREATE OR REPLACE FUNCTION public.catalogue_decide_readiness(
 p_test_id UUID,p_decision TEXT,p_reason TEXT,p_expected_version BIGINT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.catalogue_service_readiness%ROWTYPE; t public.tests%ROWTYPE; checklist JSONB; next_version BIGINT; target public.catalogue_readiness_state_enum;
BEGIN
 PERFORM public.catalogue_require_manager();
 IF p_decision NOT IN ('Approve','Reject','Suspend','Reactivate') THEN RAISE EXCEPTION 'CATALOGUE_DECISION_INVALID' USING ERRCODE='22023'; END IF;
 IF btrim(COALESCE(p_reason,''))='' THEN RAISE EXCEPTION 'Approval, rejection, and suspension require a reason.' USING ERRCODE='23514'; END IF;
 SELECT * INTO r FROM public.catalogue_service_readiness WHERE test_id=p_test_id FOR UPDATE;
 SELECT * INTO t FROM public.tests WHERE id=p_test_id FOR UPDATE;
 IF r.configuration_version<>p_expected_version THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
 checklist:=public.catalogue_service_readiness_checklist(p_test_id);
 next_version:=r.configuration_version+1;
 IF p_decision IN ('Approve','Reactivate') THEN
   IF r.state NOT IN ('ReadyForReview','Suspended') THEN RAISE EXCEPTION 'Service must be ReadyForReview or Suspended.' USING ERRCODE='23514'; END IF;
   IF NOT COALESCE((checklist->>'ready_for_review')::BOOLEAN,FALSE) THEN RAISE EXCEPTION 'CATALOGUE_NOT_READY: %',checklist->'missing_requirements' USING ERRCODE='23514'; END IF;
   IF checklist->>'classification' NOT IN ('InHouse','OutsourceWithBimalReport') THEN RAISE EXCEPTION 'Only supported clinical tests may be activated.' USING ERRCODE='23514'; END IF;
   target:='Approved';
   UPDATE public.tests SET clinical_reporting_enabled=TRUE,clinical_configuration_status='Configured',row_version=row_version+1,updated_at=now() WHERE id=p_test_id;
 ELSIF p_decision='Suspend' THEN
   target:='Suspended'; UPDATE public.tests SET clinical_reporting_enabled=FALSE,row_version=row_version+1,updated_at=now() WHERE id=p_test_id;
 ELSE
   target:='NeedsConfiguration'; UPDATE public.tests SET clinical_reporting_enabled=FALSE,clinical_configuration_status='Requires Clinical Validation',row_version=row_version+1,updated_at=now() WHERE id=p_test_id;
 END IF;
 UPDATE public.catalogue_service_readiness SET state=target,configuration_version=next_version,
   approved_by=CASE WHEN target='Approved' THEN auth.uid() END,approved_at=CASE WHEN target='Approved' THEN now() END,
   suspended_by=CASE WHEN target='Suspended' THEN auth.uid() END,suspended_at=CASE WHEN target='Suspended' THEN now() END,
   decision_reason=btrim(p_reason),updated_at=now() WHERE test_id=p_test_id;
 INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,new_state,reason,actor_id,actor_role)
 VALUES(p_test_id,next_version,'FinalApproval',CASE WHEN target='Approved' THEN 'Approved'::public.catalogue_decision_status_enum ELSE 'Rejected'::public.catalogue_decision_status_enum END,
   checklist||jsonb_build_object('decision',p_decision,'resulting_state',target),btrim(p_reason),auth.uid(),public.catalogue_readiness_actor_role());
 RETURN next_version;
END $$;
REVOKE ALL ON FUNCTION public.catalogue_decide_readiness(UUID,TEXT,TEXT,BIGINT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.catalogue_decide_readiness(UUID,TEXT,TEXT,BIGINT) TO authenticated;
COMMENT ON FUNCTION public.catalogue_decide_readiness(UUID,TEXT,TEXT,BIGINT) IS 'Catalogue-manager activation/suspension with clinical readiness checks, optimistic locking, and append-only evidence.';
