-- Temporary Nepal Telecom URL-free SMS policy. Function bodies only; no table/schema changes.
-- Keep historical SMS records and all secure link presentations/intents for QR/web access.
-- No patient SMS language preference exists; use the neutral English notification.
BEGIN;

-- Replaces create_public_report_token from 00084_gate_reportready_on_authoritative_pdf.sql; only SMS text changes.
CREATE OR REPLACE FUNCTION public.create_public_report_token(
  p_report_id UUID,p_token_hash VARCHAR(128),p_expiry_days INT DEFAULT 30,p_public_url_base TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE report public.diagnostic_reports%ROWTYPE; existing public.public_report_tokens%ROWTYPE;
  patient public.patients%ROWTYPE; ordering public.clinical_orders%ROWTYPE;
  token_id UUID; v_expires_at TIMESTAMPTZ; raw_token TEXT; delivery_host TEXT;
  phone TEXT; sms_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE='42501'; END IF;
  IF NOT(public.has_permission('can_sign_reports') OR public.is_super_admin()) THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;
  SELECT * INTO report FROM public.diagnostic_reports WHERE id=p_report_id FOR UPDATE;
  IF NOT FOUND OR report.status NOT IN('SignedOff','Amended') THEN
    RAISE EXCEPTION 'A signed or amended report is required.' USING ERRCODE='22023';
  END IF;
  UPDATE public.public_report_tokens token SET is_active=FALSE,updated_at=NOW()
    WHERE token.diagnostic_report_id=p_report_id AND token.is_active
      AND (token.revoked_at IS NOT NULL OR token.expires_at<=NOW());
  SELECT * INTO existing FROM public.public_report_tokens
    WHERE diagnostic_report_id=p_report_id AND is_active AND revoked_at IS NULL AND expires_at>NOW()
    ORDER BY created_at LIMIT 1 FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object('success',TRUE,'token_id',existing.id,'expires_at',existing.expires_at,
      'report_number',report.report_number,'sms_queued',FALSE,'sms_status','Existing report link retained',
      'idempotency_replay',TRUE);
  END IF;
  raw_token:=substring(p_public_url_base FROM '/r/([A-Za-z0-9_-]+)$');
  delivery_host:=substring(p_public_url_base FROM '^https://(lis|dashboard)[.]bimalpathology[.]com[.]np/r/');
  IF delivery_host IS NULL OR raw_token IS NULL OR length(raw_token) NOT BETWEEN 32 AND 256
     OR p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$'
     OR encode(extensions.digest(convert_to(raw_token,'UTF8'),'sha256'),'hex')<>p_token_hash THEN
    RAISE EXCEPTION 'A valid approved production report token is required.' USING ERRCODE='22023';
  END IF;
  v_expires_at:=NOW()+(greatest(1,least(COALESCE(p_expiry_days,30),90))||' days')::INTERVAL;
  INSERT INTO public.public_report_tokens(diagnostic_report_id,token_hash,expires_at,created_by,is_active)
    VALUES(p_report_id,p_token_hash,v_expires_at,auth.uid(),TRUE) RETURNING id INTO token_id;
  INSERT INTO public.report_secure_link_presentations(report_token_id,public_url)
    VALUES(token_id,p_public_url_base);
  IF delivery_host='dashboard' THEN
    INSERT INTO public.report_pdf_delivery_intents(diagnostic_report_id,report_token_id,public_url)
      VALUES(p_report_id,token_id,p_public_url_base);
  ELSE
    -- Compatibility path for the currently deployed head-00080 frontend. It is
    -- retired by deploying the coordinated frontend after PDF acceptance.
    SELECT * INTO patient FROM public.patients WHERE id=report.patient_id;
    SELECT * INTO ordering FROM public.clinical_orders WHERE id=report.order_id;
    phone:=regexp_replace(COALESCE(patient.mobile,''),'[^0-9]','','g');
    IF phone LIKE '977%' AND length(phone)=13 THEN phone:=substring(phone FROM 4); END IF;
    IF phone~'^(97|98)[0-9]{8}$' THEN
      INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,diagnostic_report_id)
      VALUES('ReportReady',phone,patient.full_name,
        'Bimal Pathology: Your laboratory report is ready. Please collect it from the lab or contact 056-593288. Thank you.',
        'Pending','REPORT_READY:'||report.id::TEXT||':'||report.version::TEXT,report.id)
      ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO sms_id;
    END IF;
  END IF;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
    VALUES(auth.uid(),'Authorized Signatory','PUBLIC_REPORT_TOKEN_CREATED','DiagnosticReport',report.report_number,
      jsonb_build_object('report_id',p_report_id,'token_id',token_id,'expires_at',v_expires_at,
        'delivery_host',delivery_host||'.bimalpathology.com.np',
        'delivery_state',CASE WHEN delivery_host='dashboard' THEN 'AwaitingArtifact' ELSE 'LegacyImmediate' END));
  RETURN jsonb_build_object('success',TRUE,'token_id',token_id,'expires_at',v_expires_at,
    'report_number',report.report_number,'sms_queued',sms_id IS NOT NULL,
    'sms_status',CASE WHEN delivery_host='dashboard' THEN 'Awaiting authoritative PDF'
      WHEN sms_id IS NOT NULL THEN 'Report notification queued' ELSE 'SMS skipped: invalid or missing Nepal mobile' END,
    'idempotency_replay',FALSE);
END $$;

-- Replaces notify_updated_order_reports from 00092_multi_report_group_lifecycle.sql; only SMS text changes.
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
 INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,diagnostic_report_id) SELECT 'ReportReady',phone,patient.full_name,'Bimal Pathology: Your laboratory report is ready. Please collect it from the lab or contact 056-593288. Thank you.','Pending','ORDER_REPORT_READY:'||p_order_id||':'||next_generation,report.id FROM public.report_pdf_delivery_intents i WHERE i.order_token_id=token.id ORDER BY i.queued_at NULLS LAST LIMIT 1 ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO sms_id;
 IF sms_id IS NULL THEN SELECT sms_queue_item_id INTO sms_id FROM public.order_report_notification_generations WHERE order_id=p_order_id AND generation=next_generation; END IF;
 INSERT INTO public.order_report_notification_generations(order_id,generation,reason,requested_by,sms_queue_item_id) VALUES(p_order_id,next_generation,btrim(p_reason),auth.uid(),sms_id) ON CONFLICT(order_id,generation) DO NOTHING;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'ORDER_REPORT_UPDATED_NOTIFICATION','ClinicalOrder',p_order_id::text,jsonb_build_object('generation',next_generation,'reason',btrim(p_reason)));
 RETURN jsonb_build_object('success',true,'generation',next_generation,'sms_queue_item_id',sms_id);
END $$;

-- Replaces complete_report_pdf_artifact_v2 from 00092_multi_report_group_lifecycle.sql; only SMS text changes.
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
 INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,diagnostic_report_id) VALUES('ReportReady',phone,patient.full_name,'Bimal Pathology: Your laboratory report is ready. Please collect it from the lab or contact 056-593288. Thank you.','Pending',CASE WHEN intent.order_token_id IS NULL THEN 'REPORT_READY:'||report.id||':'||report.version ELSE 'ORDER_REPORT_READY:'||report.order_id||':1' END,report.id) ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO sms_id;
 IF intent.order_token_id IS NOT NULL THEN INSERT INTO public.order_report_notification_generations(order_id,generation,reason,requested_by,sms_queue_item_id) VALUES(report.order_id,1,'First finalized PDF milestone',coalesce(report.signed_by_personnel_id,report.performed_by_personnel_id),sms_id) ON CONFLICT(order_id,generation) DO NOTHING RETURNING id INTO generation_id; END IF;
 UPDATE public.report_pdf_delivery_intents SET status=CASE WHEN sms_id IS NULL THEN 'Skipped' ELSE 'Queued' END,queued_sms_id=sms_id,queued_at=now() WHERE diagnostic_report_id=report.id;
 RETURN result||jsonb_build_object('sms_queued',sms_id IS NOT NULL);
END $$;

-- Allow the central content guard to persist a permanent rejection and safe audit entry.
CREATE OR REPLACE FUNCTION public.reject_sms_gateway_v2_local_validation(
  p_instance_id UUID,p_sms_id UUID,p_worker_id UUID,p_error_code TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE changed INT;
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  IF p_error_code NOT IN ('INVALID_NEPAL_MOBILE','EMPTY_MESSAGE','SEGMENT_LIMIT_EXCEEDED','SMS_URL_BLOCKED') THEN
    RAISE EXCEPTION 'Unsupported local validation code.' USING ERRCODE='22023';
  END IF;
  UPDATE public.sms_queue_items SET status='DeadLetter',retry_count=LEAST(retry_count+1,max_attempts),
    error_message=p_error_code,error_classification='PermanentGatewayValidationFailure',final_state_at=now(),
    lease_owner=NULL,lease_instance_id=NULL,lease_expires_at=NULL,updated_at=now()
  WHERE id=p_sms_id AND status='Processing' AND lease_owner=p_worker_id AND lease_instance_id=p_instance_id
    AND lease_expires_at>now() AND provider_call_started_at IS NULL;
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>1 THEN RAISE EXCEPTION 'SMS lease was lost or provider call already started.' USING ERRCODE='40001'; END IF;
  INSERT INTO public.audit_logs(action,entity_type,entity_id,new_data)
  VALUES('SMS_FAILED','SmsQueueItem',p_sms_id::TEXT,
    jsonb_build_object('status','DeadLetter','classification','PermanentGatewayValidationFailure',
      'error_code',p_error_code,'gateway_instance_id',p_instance_id));
  RETURN TRUE;
END $$;

COMMIT;
