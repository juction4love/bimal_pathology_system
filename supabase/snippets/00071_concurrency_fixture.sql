\set ON_ERROR_STOP on
BEGIN;
ALTER TABLE public.diagnostic_reports ENABLE ALWAYS TRIGGER queue_signed_report_artifact_trigger;
ALTER TABLE public.report_pdf_artifacts ENABLE ALWAYS TRIGGER validate_report_pdf_artifact_identity_trigger;
SET LOCAL session_replication_role=replica;
INSERT INTO public.diagnostic_reports(
  id,order_id,patient_id,report_number,version,is_amendment,status,integrity_hash,
  performed_by_personnel_name,signed_at,clinical_snapshot_json
) VALUES(
  '71000000-0000-4000-8000-000000000009','71000000-0000-4000-8000-000000000109',
  '71000000-0000-4000-8000-000000000209','ACCEPT-00071-RACE',1,false,'SignedOff',repeat('e',64),
  'Synthetic Technician',now(),'{"meta":{"version":1}}'
);
SET LOCAL session_replication_role=origin;
ALTER TABLE public.diagnostic_reports ENABLE TRIGGER queue_signed_report_artifact_trigger;
ALTER TABLE public.report_pdf_artifacts ENABLE TRIGGER validate_report_pdf_artifact_identity_trigger;
INSERT INTO public.public_report_tokens(id,diagnostic_report_id,token_hash,expires_at,is_active)
VALUES('71000000-0000-4000-8000-000000000319','71000000-0000-4000-8000-000000000009',encode(extensions.digest(convert_to(repeat('Q',32),'UTF8'),'sha256'),'hex'),now()+interval '1 day',true);
INSERT INTO public.report_secure_link_presentations(report_token_id,public_url)
VALUES('71000000-0000-4000-8000-000000000319','https://lis.bimalpathology.com.np/r/'||repeat('Q',32));
COMMIT;
