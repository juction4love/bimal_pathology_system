-- Extend the existing immutable report-artifact pipeline without changing any
-- historical token, SMS row, report snapshot, or Clean Gateway contract.

ALTER TABLE public.report_secure_link_presentations
  DROP CONSTRAINT IF EXISTS report_secure_link_presentations_public_url_check;
ALTER TABLE public.report_secure_link_presentations
  ADD CONSTRAINT report_secure_link_presentations_public_url_check CHECK (
    public_url ~ '^https://(lis|dashboard)[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]+$'
    AND length(substring(public_url FROM '/r/([A-Za-z0-9_-]+)$')) BETWEEN 32 AND 256
  );

CREATE TABLE public.report_pdf_delivery_intents (
  diagnostic_report_id UUID PRIMARY KEY REFERENCES public.diagnostic_reports(id) ON DELETE RESTRICT,
  report_token_id UUID NOT NULL UNIQUE REFERENCES public.public_report_tokens(id) ON DELETE RESTRICT,
  public_url TEXT NOT NULL CHECK (
    public_url ~ '^https://dashboard[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]+$'
    AND length(substring(public_url FROM '/r/([A-Za-z0-9_-]+)$')) BETWEEN 32 AND 256
  ),
  status TEXT NOT NULL DEFAULT 'AwaitingArtifact' CHECK(status IN('AwaitingArtifact','Queued','Skipped')),
  queued_sms_id UUID UNIQUE REFERENCES public.sms_queue_items(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  queued_at TIMESTAMPTZ,
  CHECK ((status='Queued')=(queued_sms_id IS NOT NULL AND queued_at IS NOT NULL)),
  CHECK (status<>'Skipped' OR (queued_sms_id IS NULL AND queued_at IS NOT NULL))
);
ALTER TABLE public.report_pdf_delivery_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.report_pdf_delivery_intents FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.report_artifact_public_url(p_report_id UUID)
RETURNS TEXT LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE url TEXT;
BEGIN
  SELECT candidate.public_url INTO url
  FROM public.public_report_tokens token
  CROSS JOIN LATERAL (
    SELECT presentation.public_url,0 AS priority
    FROM public.report_secure_link_presentations presentation
    WHERE presentation.report_token_id=token.id
    UNION ALL
    SELECT substring(message.message_body FROM '(https://(lis|dashboard)[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]+)'),1
    FROM public.sms_queue_items message
    JOIN public.diagnostic_reports report ON report.id=message.diagnostic_report_id
    WHERE message.diagnostic_report_id=p_report_id AND message.sms_type='ReportReady'
      AND message.idempotency_key='REPORT_READY:'||p_report_id::TEXT||':'||report.version::TEXT
  ) candidate
  WHERE token.diagnostic_report_id=p_report_id AND token.is_active AND token.revoked_at IS NULL AND token.expires_at>NOW()
    AND candidate.public_url~'^https://(lis|dashboard)[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]+$'
    AND length(substring(candidate.public_url FROM '/r/([A-Za-z0-9_-]+)$')) BETWEEN 32 AND 256
    AND encode(extensions.digest(convert_to(substring(candidate.public_url FROM '/r/([A-Za-z0-9_-]+)$'),'UTF8'),'sha256'),'hex')=token.token_hash
  ORDER BY candidate.priority,token.created_at DESC LIMIT 1;
  RETURN url;
END $$;
REVOKE ALL ON FUNCTION public.report_artifact_public_url(UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.claim_report_pdf_artifact_v2(p_lease_seconds INT DEFAULT 300)
RETURNS TABLE(artifact_id UUID,report_id UUID,report_number VARCHAR,report_version INT,report_integrity_hash VARCHAR,
  snapshot_sha256 CHAR(64),snapshot JSONB,artifact_created_at TIMESTAMPTZ,lease_owner UUID,public_url TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE owner UUID:=gen_random_uuid();
BEGIN
  IF NOT public.is_report_artifact_worker() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_lease_seconds<60 OR p_lease_seconds>900 THEN RAISE EXCEPTION 'Invalid artifact lease.' USING ERRCODE='22023'; END IF;
  RETURN QUERY WITH candidate AS (
    SELECT a.id FROM public.report_pdf_artifacts a WHERE
      (a.generation_status IN('Pending','GenerationFailed','UploadFailed') OR
       (a.generation_status='Generating' AND a.lease_expires_at<=NOW())) AND a.attempt_count<5
      AND public.report_artifact_public_url(a.diagnostic_report_id) IS NOT NULL
    ORDER BY a.created_at,a.diagnostic_report_id,a.id LIMIT 1 FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE public.report_pdf_artifacts a SET generation_status='Generating',attempt_count=attempt_count+1,
      lease_owner=owner,lease_expires_at=NOW()+make_interval(secs=>p_lease_seconds),failure_code=NULL,updated_at=NOW()
    FROM candidate c WHERE a.id=c.id RETURNING a.*
  ) SELECT c.id,r.id,r.report_number,r.version,r.integrity_hash,c.frozen_snapshot_sha256,
      r.clinical_snapshot_json,c.created_at,owner,public.report_artifact_public_url(r.id)
    FROM claimed c JOIN public.diagnostic_reports r ON r.id=c.diagnostic_report_id
    WHERE r.status IN('SignedOff','Amended') AND r.version=c.report_version
      AND r.integrity_hash=c.report_integrity_hash
      AND encode(extensions.digest(r.clinical_snapshot_json::TEXT,'sha256'),'hex')=c.frozen_snapshot_sha256;
END $$;

CREATE FUNCTION public.complete_report_pdf_artifact_v2(p_artifact_id UUID,p_lease_owner UUID,p_ready BOOLEAN,
  p_pdf_sha256 TEXT DEFAULT NULL,p_byte_size BIGINT DEFAULT NULL,p_generator_name TEXT DEFAULT NULL,
  p_generator_version TEXT DEFAULT NULL,p_failure_code TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result JSONB; artifact public.report_pdf_artifacts%ROWTYPE; intent public.report_pdf_delivery_intents%ROWTYPE;
  report public.diagnostic_reports%ROWTYPE; patient public.patients%ROWTYPE; ordering public.clinical_orders%ROWTYPE;
  sms_id UUID; phone TEXT;
BEGIN
  IF NOT public.is_report_artifact_worker() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  result:=public.complete_report_pdf_artifact(p_artifact_id,p_lease_owner,p_ready,p_pdf_sha256,p_byte_size,p_generator_name,p_generator_version,p_failure_code);
  IF NOT p_ready THEN RETURN result; END IF;
  SELECT * INTO artifact FROM public.report_pdf_artifacts WHERE id=p_artifact_id;
  SELECT * INTO intent FROM public.report_pdf_delivery_intents
    WHERE diagnostic_report_id=artifact.diagnostic_report_id AND status='AwaitingArtifact' FOR UPDATE;
  IF NOT FOUND THEN RETURN result||jsonb_build_object('sms_queued',FALSE); END IF;
  SELECT * INTO report FROM public.diagnostic_reports WHERE id=artifact.diagnostic_report_id;
  SELECT * INTO patient FROM public.patients WHERE id=report.patient_id;
  SELECT * INTO ordering FROM public.clinical_orders WHERE id=report.order_id;
  phone:=regexp_replace(COALESCE(patient.mobile,''),'[^0-9]','','g');
  IF phone LIKE '977%' AND length(phone)=13 THEN phone:=substring(phone FROM 4); END IF;
  IF phone !~ '^(97|98)[0-9]{8}$' THEN
    UPDATE public.report_pdf_delivery_intents SET status='Skipped',queued_at=NOW()
      WHERE diagnostic_report_id=report.id;
    RETURN result||jsonb_build_object('sms_queued',FALSE,'sms_status','SMS skipped: invalid or missing Nepal mobile');
  END IF;
  INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,diagnostic_report_id)
  VALUES('ReportReady',phone,patient.full_name,
    'Bimal Pathology: Your report is ready. Lab No: '||ordering.order_number||'. View report: '||intent.public_url,
    'Pending','REPORT_READY:'||report.id::TEXT||':'||report.version::TEXT,report.id)
  ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO sms_id;
  IF sms_id IS NULL THEN SELECT id INTO sms_id FROM public.sms_queue_items
    WHERE idempotency_key='REPORT_READY:'||report.id::TEXT||':'||report.version::TEXT; END IF;
  IF sms_id IS NULL THEN RAISE EXCEPTION 'ReportReady delivery intent could not be materialized.' USING ERRCODE='55000'; END IF;
  UPDATE public.report_pdf_delivery_intents SET status='Queued',queued_sms_id=sms_id,queued_at=NOW()
    WHERE diagnostic_report_id=report.id;
  RETURN result||jsonb_build_object('sms_queued',TRUE);
END $$;

REVOKE ALL ON FUNCTION public.claim_report_pdf_artifact_v2(INT),public.complete_report_pdf_artifact_v2(UUID,UUID,BOOLEAN,TEXT,BIGINT,TEXT,TEXT,TEXT) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.claim_report_pdf_artifact_v2(INT),public.complete_report_pdf_artifact_v2(UUID,UUID,BOOLEAN,TEXT,BIGINT,TEXT,TEXT,TEXT) TO authenticated;

CREATE FUNCTION public.enqueue_missing_report_pdf_artifacts(p_limit INT DEFAULT 25)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE inserted_count INT;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_limit<1 OR p_limit>100 THEN RAISE EXCEPTION 'Invalid backfill limit.' USING ERRCODE='22023'; END IF;
  WITH candidates AS (
    SELECT r.* FROM public.diagnostic_reports r
    WHERE r.status IN('SignedOff','Amended') AND public.report_artifact_public_url(r.id) IS NOT NULL
      AND NOT EXISTS(SELECT 1 FROM public.report_pdf_artifacts a WHERE a.diagnostic_report_id=r.id AND a.report_version=r.version)
    ORDER BY r.signed_at,r.id LIMIT p_limit
  ) INSERT INTO public.report_pdf_artifacts(diagnostic_report_id,report_version,report_integrity_hash,frozen_snapshot_sha256)
    SELECT id,version,integrity_hash,encode(extensions.digest(clinical_snapshot_json::TEXT,'sha256'),'hex') FROM candidates
    ON CONFLICT(diagnostic_report_id,report_version) DO NOTHING;
  GET DIAGNOSTICS inserted_count=ROW_COUNT;
  RETURN inserted_count;
END $$;
REVOKE ALL ON FUNCTION public.enqueue_missing_report_pdf_artifacts(INT) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_missing_report_pdf_artifacts(INT) TO authenticated;
