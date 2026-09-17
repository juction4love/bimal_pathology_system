\set ON_ERROR_STOP on
BEGIN;
SET LOCAL session_replication_role=replica;
INSERT INTO auth.users(id,email) VALUES
('25a1a656-5fde-4e3b-b6fe-053e79773bf9','admin-pdf-acceptance@invalid.local'),
('c0a51210-09b6-4684-9bbb-e241c84fe40e','worker-pdf-acceptance@invalid.local')
ON CONFLICT(id) DO NOTHING;
INSERT INTO public.user_profiles(id,email,full_name,is_active,is_super_admin)
VALUES('25a1a656-5fde-4e3b-b6fe-053e79773bf9','admin-pdf-acceptance@invalid.local','Synthetic Admin',TRUE,TRUE)
ON CONFLICT(id) DO NOTHING;
INSERT INTO public.user_roles(user_id,role_id)
SELECT '25a1a656-5fde-4e3b-b6fe-053e79773bf9',id FROM public.roles WHERE name='Administrator'
ON CONFLICT DO NOTHING;
INSERT INTO public.report_artifact_worker_identities(auth_user_id,worker_name,created_by)
VALUES('c0a51210-09b6-4684-9bbb-e241c84fe40e','PdfAcceptanceWorker','25a1a656-5fde-4e3b-b6fe-053e79773bf9')
ON CONFLICT(auth_user_id) DO NOTHING;
INSERT INTO public.patients(id,uhid,mobile,full_name,gender,address)
VALUES('84000000-0000-4000-8000-000000000001','PDF-ACCEPT-1','9800000000','Synthetic PDF Acceptance','Other','Synthetic');
INSERT INTO public.clinical_orders(id,bill_id,patient_id,order_number,order_date_bs,status)
VALUES('84000000-0000-4000-8000-000000000002','84000000-0000-4000-8000-000000000099','84000000-0000-4000-8000-000000000001','PDF-ORDER-1','2083-05-15','SignedOff');
INSERT INTO public.diagnostic_reports(id,order_id,patient_id,report_number,version,is_amendment,status,integrity_hash,performed_by_personnel_name,signed_at,clinical_snapshot_json)
VALUES('84000000-0000-4000-8000-000000000003','84000000-0000-4000-8000-000000000002','84000000-0000-4000-8000-000000000001','PDF-REPORT-0001',1,FALSE,'SignedOff',repeat('a',64),'Synthetic Operator',NOW(),'{"meta":{"version":1},"investigations":[]}'::jsonb);
SET LOCAL session_replication_role=origin;
INSERT INTO public.report_pdf_artifacts(diagnostic_report_id,report_version,report_integrity_hash,frozen_snapshot_sha256)
SELECT id,version,integrity_hash,encode(extensions.digest(clinical_snapshot_json::TEXT,'sha256'),'hex')
FROM public.diagnostic_reports WHERE id='84000000-0000-4000-8000-000000000003';

SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','25a1a656-5fde-4e3b-b6fe-053e79773bf9',true);
SELECT public.create_public_report_token(
  '84000000-0000-4000-8000-000000000003',
  encode(extensions.digest(convert_to(repeat('D',48),'UTF8'),'sha256'),'hex'),30,
  'https://dashboard.bimalpathology.com.np/r/'||repeat('D',48));

DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM public.sms_queue_items WHERE diagnostic_report_id='84000000-0000-4000-8000-000000000003') THEN
    RAISE EXCEPTION 'ReportReady became deliverable before PDF Ready';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.report_pdf_delivery_intents WHERE diagnostic_report_id='84000000-0000-4000-8000-000000000003' AND status='AwaitingArtifact') THEN
    RAISE EXCEPTION 'delivery intent missing';
  END IF;
END $$;

SELECT set_config('request.jwt.claim.sub','c0a51210-09b6-4684-9bbb-e241c84fe40e',true);
CREATE TEMP TABLE claimed AS SELECT * FROM public.claim_report_pdf_artifact_v2(300);
DO $$ DECLARE c RECORD; BEGIN
  SELECT * INTO c FROM claimed;
  IF c.report_number<>'PDF-REPORT-0001' OR c.public_url<>'https://dashboard.bimalpathology.com.np/r/'||repeat('D',48) THEN
    RAISE EXCEPTION 'claim omitted immutable report number or exact dashboard URL';
  END IF;
  PERFORM public.complete_report_pdf_artifact_v2(c.artifact_id,c.lease_owner,TRUE,repeat('b',64),12345,'acceptance','2.1.0',NULL);
END $$;

DO $$ BEGIN
  IF (SELECT generation_status FROM public.report_pdf_artifacts WHERE diagnostic_report_id='84000000-0000-4000-8000-000000000003')<>'Ready' THEN RAISE EXCEPTION 'artifact not Ready'; END IF;
  IF (SELECT count(*) FROM public.sms_queue_items WHERE diagnostic_report_id='84000000-0000-4000-8000-000000000003' AND status='Pending')<>1 THEN RAISE EXCEPTION 'exactly one delayed SMS was not materialized'; END IF;
  IF (SELECT status FROM public.report_pdf_delivery_intents WHERE diagnostic_report_id='84000000-0000-4000-8000-000000000003')<>'Queued' THEN RAISE EXCEPTION 'intent not queued'; END IF;
END $$;

SELECT public.complete_report_pdf_artifact_v2(artifact_id,lease_owner,TRUE,repeat('b',64),12345,'acceptance','2.1.0',NULL)
FROM claimed WHERE FALSE;

SET LOCAL ROLE anon;
DO $$ BEGIN
  BEGIN PERFORM public.claim_report_pdf_artifact_v2(300);RAISE EXCEPTION 'anon claim allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  BEGIN PERFORM public.authorize_report_pdf_artifact(repeat('a',64));RAISE EXCEPTION 'anon authorize allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;

SELECT jsonb_build_object('passed',TRUE,'report_number_contract',TRUE,'dashboard_token',TRUE,'sms_before_ready',0,'sms_after_ready',1,'anon_denials',2);
ROLLBACK;
