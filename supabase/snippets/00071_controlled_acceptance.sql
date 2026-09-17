\set ON_ERROR_STOP on
BEGIN;

-- Synthetic identifiers only. FK and unrelated diagnostic-report triggers are
-- bypassed for fixture creation; the 00071 queue and identity triggers remain active.
ALTER TABLE public.diagnostic_reports ENABLE ALWAYS TRIGGER queue_signed_report_artifact_trigger;
ALTER TABLE public.report_pdf_artifacts ENABLE ALWAYS TRIGGER validate_report_pdf_artifact_identity_trigger;
SET LOCAL session_replication_role = replica;

INSERT INTO public.diagnostic_reports(
  id,order_id,patient_id,report_number,version,is_amendment,status,integrity_hash,
  performed_by_personnel_name,signed_at,clinical_snapshot_json
) VALUES
 ('71000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000101','71000000-0000-4000-8000-000000000201','ACCEPT-00071-V1',1,false,'SignedOff',repeat('a',64),'Synthetic Technician',now(),'{"patient":{"name":"Synthetic A"},"meta":{"version":1}}'),
 ('71000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000102','71000000-0000-4000-8000-000000000202','ACCEPT-00071-STALE',1,false,'SignedOff',repeat('b',64),'Synthetic Technician',now(),'{"patient":{"name":"Synthetic B"},"meta":{"version":1}}'),
 ('71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000101','71000000-0000-4000-8000-000000000201','ACCEPT-00071-V2',2,true,'SignedOff',repeat('c',64),'Synthetic Technician',now(),'{"patient":{"name":"Synthetic A"},"meta":{"version":2,"is_amendment":true}}');

SET LOCAL session_replication_role = origin;
ALTER TABLE public.diagnostic_reports ENABLE TRIGGER queue_signed_report_artifact_trigger;
ALTER TABLE public.report_pdf_artifacts ENABLE TRIGGER validate_report_pdf_artifact_identity_trigger;

INSERT INTO public.public_report_tokens(id,diagnostic_report_id,token_hash,expires_at,is_active)
SELECT token_id,report_id,encode(extensions.digest(convert_to(raw_token,'UTF8'),'sha256'),'hex'),now()+interval '1 day',true
FROM (VALUES
 ('71000000-0000-4000-8000-000000000311'::uuid,'71000000-0000-4000-8000-000000000001'::uuid,repeat('A',32)),
 ('71000000-0000-4000-8000-000000000312'::uuid,'71000000-0000-4000-8000-000000000002'::uuid,repeat('B',32)),
 ('71000000-0000-4000-8000-000000000313'::uuid,'71000000-0000-4000-8000-000000000003'::uuid,repeat('C',32))
) fixture(token_id,report_id,raw_token);
INSERT INTO public.report_secure_link_presentations(report_token_id,public_url) VALUES
 ('71000000-0000-4000-8000-000000000311','https://lis.bimalpathology.com.np/r/'||repeat('A',32)),
 ('71000000-0000-4000-8000-000000000312','https://lis.bimalpathology.com.np/r/'||repeat('B',32)),
 ('71000000-0000-4000-8000-000000000313','https://lis.bimalpathology.com.np/r/'||repeat('C',32));

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.report_pdf_artifacts;
  IF n<>3 OR EXISTS(SELECT 1 FROM public.report_pdf_artifacts WHERE generation_status<>'Pending' OR attempt_count<>0) THEN
    RAISE EXCEPTION 'artifact registration/Pending acceptance failed';
  END IF;
  BEGIN
    INSERT INTO public.report_pdf_artifacts(diagnostic_report_id,report_version,report_integrity_hash,frozen_snapshot_sha256)
    SELECT diagnostic_report_id,report_version,report_integrity_hash,frozen_snapshot_sha256 FROM public.report_pdf_artifacts LIMIT 1;
    RAISE EXCEPTION 'duplicate artifact was accepted';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.report_pdf_artifacts(diagnostic_report_id,report_version,report_integrity_hash,frozen_snapshot_sha256)
    VALUES('71000000-0000-4000-8000-000000000001',2,repeat('a',64),repeat('a',64));
    RAISE EXCEPTION 'report/version mismatch was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.report_pdf_artifacts(diagnostic_report_id,report_version,report_integrity_hash,frozen_snapshot_sha256)
    VALUES('71000000-0000-4000-8000-000000000001',1,repeat('a',64),repeat('f',64));
    RAISE EXCEPTION 'frozen snapshot mismatch was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;

SELECT set_config('request.jwt.claim.role','service_role',true);
CREATE TEMP TABLE acceptance_claim AS
SELECT * FROM public.claim_report_pdf_artifact(300);

DO $$
DECLARE c record;
BEGIN
  SELECT * INTO c FROM acceptance_claim;
  IF c.artifact_id IS NULL OR c.report_id<>'71000000-0000-4000-8000-000000000001'::uuid THEN
    RAISE EXCEPTION 'initial claim failed';
  END IF;
  BEGIN
    PERFORM public.complete_report_pdf_artifact(c.artifact_id,gen_random_uuid(),false,NULL,NULL,'acceptance','1','PDF_GENERATION_FAILED');
    RAISE EXCEPTION 'wrong lease owner completed artifact';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  PERFORM public.complete_report_pdf_artifact(c.artifact_id,c.lease_owner,false,NULL,NULL,'acceptance','1','PDF_GENERATION_FAILED');
  IF (SELECT generation_status FROM public.report_pdf_artifacts WHERE id=c.artifact_id)<>'GenerationFailed' THEN
    RAISE EXCEPTION 'generation failure transition failed';
  END IF;
END $$;

TRUNCATE acceptance_claim;
INSERT INTO acceptance_claim SELECT * FROM public.claim_report_pdf_artifact(300);
DO $$
DECLARE c record;
BEGIN
  SELECT * INTO c FROM acceptance_claim;
  PERFORM public.complete_report_pdf_artifact(c.artifact_id,c.lease_owner,false,NULL,NULL,'acceptance','1','R2_UPLOAD_FAILED');
  IF (SELECT generation_status FROM public.report_pdf_artifacts WHERE id=c.artifact_id)<>'UploadFailed' THEN
    RAISE EXCEPTION 'upload failure transition failed';
  END IF;
END $$;

TRUNCATE acceptance_claim;
INSERT INTO acceptance_claim SELECT * FROM public.claim_report_pdf_artifact(300);
DO $$
DECLARE c record; result jsonb;
BEGIN
  SELECT * INTO c FROM acceptance_claim;
  result:=public.complete_report_pdf_artifact(c.artifact_id,c.lease_owner,true,repeat('d',64),12345,'acceptance-renderer','1.0',NULL);
  IF result->>'status'<>'Ready' OR (SELECT attempt_count FROM public.report_pdf_artifacts WHERE id=c.artifact_id)<>3 THEN
    RAISE EXCEPTION 'retry/Ready transition failed';
  END IF;
  BEGIN
    UPDATE public.report_pdf_artifacts SET byte_size=12346 WHERE id=c.artifact_id;
    RAISE EXCEPTION 'Ready update was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  BEGIN
    DELETE FROM public.report_pdf_artifacts WHERE id=c.artifact_id;
    RAISE EXCEPTION 'Ready delete was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
END $$;

-- Claim the stale-lease fixture, expire it, and prove a new owner can recover it.
TRUNCATE acceptance_claim;
INSERT INTO acceptance_claim SELECT * FROM public.claim_report_pdf_artifact(300);
UPDATE public.report_pdf_artifacts SET lease_expires_at=now()-interval '1 second'
WHERE id=(SELECT artifact_id FROM acceptance_claim);
CREATE TEMP TABLE recovered_claim AS SELECT * FROM public.claim_report_pdf_artifact(300);
DO $$
BEGIN
  IF (SELECT count(*) FROM recovered_claim)<>1
     OR (SELECT lease_owner FROM recovered_claim)=(SELECT lease_owner FROM acceptance_claim)
     OR (SELECT attempt_count FROM public.report_pdf_artifacts WHERE id=(SELECT artifact_id FROM recovered_claim))<>2 THEN
    RAISE EXCEPTION 'stale lease recovery failed';
  END IF;
END $$;

-- Token authorization is exercised against the Ready v1 artifact.
DELETE FROM public.report_secure_link_presentations WHERE report_token_id='71000000-0000-4000-8000-000000000311';
DELETE FROM public.public_report_tokens WHERE id='71000000-0000-4000-8000-000000000311';
INSERT INTO public.public_report_tokens(id,diagnostic_report_id,token_hash,expires_at,is_active)
VALUES('71000000-0000-4000-8000-000000000301','71000000-0000-4000-8000-000000000001',repeat('1',64),now()+interval '1 day',true);
DELETE FROM public.report_secure_link_presentations WHERE report_token_id='71000000-0000-4000-8000-000000000312';
DELETE FROM public.public_report_tokens WHERE id='71000000-0000-4000-8000-000000000312';
DO $$
DECLARE result jsonb;
BEGIN
  result:=public.authorize_report_pdf_artifact(repeat('1',64));
  IF NOT (result->>'authorized')::boolean OR result->>'object_key' IS NULL THEN RAISE EXCEPTION 'Ready token authorization failed'; END IF;
  UPDATE public.public_report_tokens SET expires_at=now()-interval '1 second' WHERE id='71000000-0000-4000-8000-000000000301';
  IF (public.authorize_report_pdf_artifact(repeat('1',64))->>'authorized')::boolean THEN RAISE EXCEPTION 'expired token authorized'; END IF;
  UPDATE public.public_report_tokens SET expires_at=now()+interval '1 day',revoked_at=now() WHERE id='71000000-0000-4000-8000-000000000301';
  IF (public.authorize_report_pdf_artifact(repeat('1',64))->>'authorized')::boolean THEN RAISE EXCEPTION 'revoked token authorized'; END IF;
  UPDATE public.public_report_tokens SET revoked_at=NULL,diagnostic_report_id='71000000-0000-4000-8000-000000000002' WHERE id='71000000-0000-4000-8000-000000000301';
  IF (public.authorize_report_pdf_artifact(repeat('1',64))->>'authorized')::boolean THEN RAISE EXCEPTION 'mismatched/non-Ready token authorized'; END IF;
END $$;

-- Direct table access and RPC invocation are denied outside service-role RPCs.
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN PERFORM count(*) FROM public.report_pdf_artifacts; RAISE EXCEPTION 'authenticated enumeration allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.claim_report_pdf_artifact(300); RAISE EXCEPTION 'authenticated claim allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE anon;
DO $$ BEGIN
  BEGIN PERFORM count(*) FROM public.report_pdf_artifacts; RAISE EXCEPTION 'anonymous enumeration allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.authorize_report_pdf_artifact(repeat('1',64)); RAISE EXCEPTION 'anonymous resolver allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$ BEGIN
  BEGIN UPDATE public.report_pdf_artifacts SET updated_at=now(); RAISE EXCEPTION 'service role direct update allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;

-- Amendment v2 is a distinct report and artifact; v1 remains Ready and unchanged.
DO $$
BEGIN
  IF (SELECT generation_status FROM public.report_pdf_artifacts WHERE diagnostic_report_id='71000000-0000-4000-8000-000000000001')<>'Ready'
     OR NOT EXISTS(SELECT 1 FROM public.report_pdf_artifacts WHERE diagnostic_report_id='71000000-0000-4000-8000-000000000003' AND report_version=2 AND generation_status<>'Ready') THEN
    RAISE EXCEPTION 'amendment/new-version isolation failed';
  END IF;
END $$;

SELECT jsonb_build_object(
  'passed',true,
  'registered',3,
  'ready_attempts',3,
  'stale_recovered',true,
  'rls_grants',true,
  'token_authorization',true,
  'amendment_isolation',true
) AS acceptance_result;

ROLLBACK;
