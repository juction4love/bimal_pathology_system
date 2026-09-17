-- Deferred 00071: immutable authoritative PDFs in a private object store.
-- Independent of deferred SMS migration 00070. No historical report is rewritten
-- or auto-backfilled. SMS/R2 ordering is a later, separately accepted migration.

DO $$ BEGIN
  CREATE TYPE public.report_artifact_status_enum AS ENUM ('Pending','Generating','GenerationFailed','UploadFailed','Ready');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE public.report_pdf_artifacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  diagnostic_report_id UUID NOT NULL REFERENCES public.diagnostic_reports(id) ON DELETE RESTRICT,
  report_version INT NOT NULL CHECK(report_version>0),
  report_integrity_hash VARCHAR(128) NOT NULL CHECK(report_integrity_hash~'^[0-9a-f]{64}$'),
  frozen_snapshot_sha256 CHAR(64) NOT NULL CHECK(frozen_snapshot_sha256~'^[0-9a-f]{64}$'),
  object_key TEXT CHECK(object_key IS NULL OR object_key~'^reports/[0-9]{4}/[0-9a-f-]{36}/v[0-9]+/[0-9a-f]{64}[.]pdf$'),
  pdf_sha256 CHAR(64) CHECK(pdf_sha256 IS NULL OR pdf_sha256~'^[0-9a-f]{64}$'),
  byte_size BIGINT CHECK(byte_size IS NULL OR byte_size>0),
  mime_type TEXT CHECK(mime_type IS NULL OR mime_type='application/pdf'),
  generation_status public.report_artifact_status_enum NOT NULL DEFAULT 'Pending',
  generator_name TEXT,
  generator_version TEXT,
  generated_at TIMESTAMPTZ,
  failure_code TEXT,
  attempt_count INT NOT NULL DEFAULT 0 CHECK(attempt_count>=0),
  lease_owner UUID,
  lease_expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(diagnostic_report_id,report_version),
  UNIQUE(object_key),
  UNIQUE(diagnostic_report_id,pdf_sha256),
  CHECK((generation_status='Ready')=(object_key IS NOT NULL AND pdf_sha256 IS NOT NULL AND byte_size IS NOT NULL AND mime_type='application/pdf' AND generated_at IS NOT NULL))
);

ALTER TABLE public.report_pdf_artifacts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.report_pdf_artifacts FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.report_pdf_artifacts FROM service_role;

CREATE INDEX report_pdf_artifacts_claim_idx
ON public.report_pdf_artifacts(created_at)
WHERE generation_status IN('Pending','Generating','GenerationFailed','UploadFailed') AND attempt_count<5;

CREATE FUNCTION public.validate_report_pdf_artifact_identity()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE report public.diagnostic_reports%ROWTYPE;
BEGIN
  SELECT * INTO report FROM public.diagnostic_reports WHERE id=NEW.diagnostic_report_id;
  IF NOT FOUND OR report.status NOT IN('SignedOff','Amended')
     OR report.version<>NEW.report_version
     OR report.integrity_hash<>NEW.report_integrity_hash
     OR encode(extensions.digest(report.clinical_snapshot_json::TEXT,'sha256'),'hex')<>NEW.frozen_snapshot_sha256 THEN
    RAISE EXCEPTION 'Report PDF artifact identity does not match the frozen signed report.' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.validate_report_pdf_artifact_identity() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER validate_report_pdf_artifact_identity_trigger
BEFORE INSERT ON public.report_pdf_artifacts
FOR EACH ROW EXECUTE FUNCTION public.validate_report_pdf_artifact_identity();

CREATE FUNCTION public.enforce_report_pdf_artifact_immutability()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'Report PDF artifacts are append-only.' USING ERRCODE='55000';
  END IF;
  IF OLD.generation_status='Ready' THEN
    IF NEW IS DISTINCT FROM OLD THEN
      RAISE EXCEPTION 'Ready report PDF artifacts are immutable.' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.diagnostic_report_id IS DISTINCT FROM OLD.diagnostic_report_id
     OR NEW.report_version IS DISTINCT FROM OLD.report_version
     OR NEW.report_integrity_hash IS DISTINCT FROM OLD.report_integrity_hash
     OR NEW.frozen_snapshot_sha256 IS DISTINCT FROM OLD.frozen_snapshot_sha256
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Signed report artifact identity is immutable.' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.enforce_report_pdf_artifact_immutability() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER enforce_report_pdf_artifact_immutability_trigger
BEFORE UPDATE OR DELETE ON public.report_pdf_artifacts
FOR EACH ROW EXECUTE FUNCTION public.enforce_report_pdf_artifact_immutability();

CREATE FUNCTION public.queue_signed_report_artifact()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF NEW.status IN('SignedOff','Amended') THEN
    INSERT INTO public.report_pdf_artifacts(diagnostic_report_id,report_version,report_integrity_hash,frozen_snapshot_sha256)
    VALUES(NEW.id,NEW.version,NEW.integrity_hash,encode(extensions.digest(NEW.clinical_snapshot_json::TEXT,'sha256'),'hex'))
    ON CONFLICT(diagnostic_report_id,report_version) DO NOTHING;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.queue_signed_report_artifact() FROM PUBLIC,anon,authenticated,service_role;

CREATE TRIGGER queue_signed_report_artifact_trigger AFTER INSERT ON public.diagnostic_reports
FOR EACH ROW EXECUTE FUNCTION public.queue_signed_report_artifact();

CREATE FUNCTION public.report_artifact_public_url(p_report_id UUID)
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
    SELECT substring(message.message_body FROM '(https://lis[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]+)'),1
    FROM public.sms_queue_items message
    JOIN public.diagnostic_reports report ON report.id=message.diagnostic_report_id
    WHERE message.diagnostic_report_id=p_report_id AND message.sms_type='ReportReady'
      AND message.idempotency_key='REPORT_READY:'||p_report_id::TEXT||':'||report.version::TEXT
  ) candidate
  WHERE token.diagnostic_report_id=p_report_id AND token.is_active AND token.revoked_at IS NULL AND token.expires_at>NOW()
    AND candidate.public_url~'^https://lis[.]bimalpathology[.]com[.]np/r/[A-Za-z0-9_-]+$'
    AND length(substring(candidate.public_url FROM '/r/([A-Za-z0-9_-]+)$')) BETWEEN 32 AND 256
    AND encode(extensions.digest(convert_to(substring(candidate.public_url FROM '/r/([A-Za-z0-9_-]+)$'),'UTF8'),'sha256'),'hex')=token.token_hash
  ORDER BY candidate.priority,token.created_at DESC LIMIT 1;
  RETURN url;
END $$;
REVOKE ALL ON FUNCTION public.report_artifact_public_url(UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.claim_report_pdf_artifact(p_lease_seconds INT DEFAULT 300)
RETURNS TABLE(artifact_id UUID,report_id UUID,report_version INT,report_integrity_hash VARCHAR,
  snapshot_sha256 CHAR(64),snapshot JSONB,artifact_created_at TIMESTAMPTZ,lease_owner UUID,public_url TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE owner UUID:=gen_random_uuid();
BEGIN
  IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
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
  ) SELECT c.id,r.id,r.version,r.integrity_hash,c.frozen_snapshot_sha256,r.clinical_snapshot_json,c.created_at,owner,
      public.report_artifact_public_url(r.id)
    FROM claimed c JOIN public.diagnostic_reports r ON r.id=c.diagnostic_report_id
    WHERE r.status IN('SignedOff','Amended') AND r.version=c.report_version
      AND r.integrity_hash=c.report_integrity_hash
      AND encode(extensions.digest(r.clinical_snapshot_json::TEXT,'sha256'),'hex')=c.frozen_snapshot_sha256;
END $$;

CREATE FUNCTION public.complete_report_pdf_artifact(p_artifact_id UUID,p_lease_owner UUID,p_ready BOOLEAN,
  p_pdf_sha256 TEXT DEFAULT NULL,p_byte_size BIGINT DEFAULT NULL,p_generator_name TEXT DEFAULT NULL,
  p_generator_version TEXT DEFAULT NULL,p_failure_code TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE a public.report_pdf_artifacts%ROWTYPE; key TEXT; next_status public.report_artifact_status_enum;
BEGIN
  IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
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
    next_status:=CASE WHEN p_failure_code='R2_UPLOAD_FAILED' THEN 'UploadFailed' ELSE 'GenerationFailed' END;
    UPDATE public.report_pdf_artifacts SET generation_status=next_status,failure_code=left(p_failure_code,100),
      lease_owner=NULL,lease_expires_at=NULL,updated_at=NOW() WHERE id=a.id;
  END IF;
  RETURN jsonb_build_object('status',next_status,'object_key',key);
END $$;

CREATE FUNCTION public.authorize_report_pdf_artifact(p_token_hash VARCHAR)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.public_report_tokens%ROWTYPE;a public.report_pdf_artifacts%ROWTYPE;
BEGIN
  IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  SELECT * INTO t FROM public.public_report_tokens WHERE token_hash=p_token_hash AND is_active AND revoked_at IS NULL AND expires_at>NOW();
  IF NOT FOUND THEN RETURN jsonb_build_object('authorized',FALSE); END IF;
  SELECT artifact.* INTO a
  FROM public.report_pdf_artifacts artifact
  JOIN public.diagnostic_reports report ON report.id=artifact.diagnostic_report_id
  WHERE artifact.diagnostic_report_id=t.diagnostic_report_id
    AND artifact.report_version=report.version
    AND artifact.report_integrity_hash=report.integrity_hash
    AND encode(extensions.digest(report.clinical_snapshot_json::TEXT,'sha256'),'hex')=artifact.frozen_snapshot_sha256
    AND report.status IN('SignedOff','Amended')
    AND artifact.generation_status='Ready';
  IF NOT FOUND THEN RETURN jsonb_build_object('authorized',FALSE,'reason','ARTIFACT_NOT_READY'); END IF;
  RETURN jsonb_build_object('authorized',TRUE,'object_key',a.object_key,'sha256',a.pdf_sha256,'byte_size',a.byte_size,'report_id',a.diagnostic_report_id,'version',a.report_version);
END $$;

REVOKE ALL ON FUNCTION public.claim_report_pdf_artifact(INT),public.complete_report_pdf_artifact(UUID,UUID,BOOLEAN,TEXT,BIGINT,TEXT,TEXT,TEXT),public.authorize_report_pdf_artifact(VARCHAR) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_report_pdf_artifact(INT),public.complete_report_pdf_artifact(UUID,UUID,BOOLEAN,TEXT,BIGINT,TEXT,TEXT,TEXT),public.authorize_report_pdf_artifact(VARCHAR) TO service_role;

-- Intentionally no SMS queue or dispatcher functions here. After 00070 and this
-- migration are independently accepted, a later forward migration may gate only
-- newly queued ReportReady messages on a Ready artifact. Existing Windows Gateway
-- behavior and historical SMS rows are unchanged by this migration.
