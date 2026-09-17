-- Switch only newly finalized report notifications to the private authoritative
-- PDF delivery host. Historical tokens, URLs, and SMS rows remain unchanged.

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
        'Bimal Pathology: Your report is ready. Lab No: '||ordering.order_number||'. View report: '||p_public_url_base,
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

REVOKE ALL ON FUNCTION public.create_public_report_token(UUID,VARCHAR,INT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_public_report_token(UUID,VARCHAR,INT,TEXT) TO authenticated;
