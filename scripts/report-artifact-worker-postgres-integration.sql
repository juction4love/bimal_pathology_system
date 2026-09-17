\set ON_ERROR_STOP on
BEGIN;
CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN,message TEXT) RETURNS VOID LANGUAGE plpgsql AS $$BEGIN IF value IS DISTINCT FROM TRUE THEN RAISE EXCEPTION '%',message;END IF;END$$;
SET LOCAL session_replication_role=replica;
INSERT INTO auth.users(id,email)VALUES
('93000000-0000-4000-8000-000000000001','artifact-worker@invalid.local'),
('93000000-0000-4000-8000-000000000002','gateway@invalid.local'),
('93000000-0000-4000-8000-000000000003','ordinary@invalid.local'),
('93000000-0000-4000-8000-000000000004','admin@invalid.local'),
('93000000-0000-4000-8000-000000000005','technician@invalid.local') ON CONFLICT(id)DO NOTHING;
INSERT INTO public.user_profiles(id,email,full_name,is_active,is_super_admin)VALUES
('93000000-0000-4000-8000-000000000003','ordinary@invalid.local','Ordinary',TRUE,FALSE),
('93000000-0000-4000-8000-000000000004','admin@invalid.local','Admin',TRUE,TRUE),
('93000000-0000-4000-8000-000000000005','technician@invalid.local','Technician',TRUE,FALSE) ON CONFLICT(id)DO NOTHING;
INSERT INTO public.user_roles(user_id,role_id)SELECT '93000000-0000-4000-8000-000000000005',id FROM public.roles WHERE code='technician' ON CONFLICT DO NOTHING;
INSERT INTO public.report_artifact_worker_identities(auth_user_id,worker_name,created_by)VALUES('93000000-0000-4000-8000-000000000001','AcceptanceWorker','93000000-0000-4000-8000-000000000004') ON CONFLICT(auth_user_id)DO NOTHING;
INSERT INTO public.sms_gateway_instances(instance_id,auth_user_id,hostname,gateway_version,provider_name,claiming_enabled,is_enabled)VALUES('93000000-0000-4000-8000-000000000010','93000000-0000-4000-8000-000000000002','acceptance-gateway','test','mock',FALSE,TRUE) ON CONFLICT DO NOTHING;
INSERT INTO public.patients(id,uhid,mobile,full_name,gender,address)VALUES('93000000-0000-4000-8000-000000000020','ART-1','9800000000','Synthetic','Other','Synthetic');
INSERT INTO public.clinical_orders(id,bill_id,patient_id,order_number,order_date_bs,status)VALUES('93000000-0000-4000-8000-000000000021','93000000-0000-4000-8000-000000000099','93000000-0000-4000-8000-000000000020','ART-ORDER','2083-05-15','SignedOff');
INSERT INTO public.diagnostic_reports(id,order_id,patient_id,report_number,version,is_amendment,status,integrity_hash,performed_by_personnel_name,signed_at,clinical_snapshot_json)VALUES('93000000-0000-4000-8000-000000000022','93000000-0000-4000-8000-000000000021','93000000-0000-4000-8000-000000000020','ART-REPORT',1,FALSE,'SignedOff',repeat('a',64),'Synthetic',NOW(),'{}');
INSERT INTO public.public_report_tokens(id,diagnostic_report_id,token_hash,expires_at,created_by,is_active)VALUES('93000000-0000-4000-8000-000000000023','93000000-0000-4000-8000-000000000022',encode(extensions.digest(convert_to(repeat('T',48),'UTF8'),'sha256'),'hex'),NOW()+INTERVAL'1 day','93000000-0000-4000-8000-000000000004',TRUE);
INSERT INTO public.report_secure_link_presentations(report_token_id,public_url)VALUES('93000000-0000-4000-8000-000000000023','https://dashboard.bimalpathology.com.np/r/'||repeat('T',48));
INSERT INTO public.report_pdf_artifacts(diagnostic_report_id,report_version,report_integrity_hash,frozen_snapshot_sha256,generation_status,object_key,pdf_sha256,byte_size,mime_type,generator_name,generator_version,generated_at)VALUES('93000000-0000-4000-8000-000000000022',1,repeat('a',64),encode(extensions.digest('{}'::jsonb::TEXT,'sha256'),'hex'),'Ready','reports/2026/93000000-0000-4000-8000-000000000022/v1/'||repeat('b',64)||'.pdf',repeat('b',64),12345,'application/pdf','acceptance','2.1.0',NOW());
INSERT INTO public.report_pdf_artifacts(id,diagnostic_report_id,report_version,report_integrity_hash,frozen_snapshot_sha256,generation_status,lease_owner,lease_expires_at)VALUES('93000000-0000-4000-8000-000000000024','93000000-0000-4000-8000-000000000022',2,repeat('a',64),encode(extensions.digest('{}'::jsonb::TEXT,'sha256'),'hex'),'Generating','93000000-0000-4000-8000-000000000025',NOW()+INTERVAL'5 minutes');
SET LOCAL session_replication_role=origin;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000001',true);
DO $$BEGIN BEGIN PERFORM public.is_report_artifact_worker();RAISE EXCEPTION'identity helper directly executable';EXCEPTION WHEN insufficient_privilege THEN NULL;END;END$$;
SELECT pg_temp.assert_true((public.get_report_pdf_delivery_acceptance_candidate()->>'available')::BOOLEAN,'Worker acceptance candidate unavailable');
SELECT pg_temp.assert_true((SELECT array_agg(key ORDER BY key)FROM jsonb_object_keys(public.get_report_pdf_delivery_acceptance_candidate())key)=ARRAY['available','byte_size','pdf_sha256','public_url','report_number','report_version'],'Acceptance metadata surface changed');
DO $$DECLARE result JSONB;BEGIN result:=public.complete_report_pdf_artifact_v2('93000000-0000-4000-8000-000000000024','93000000-0000-4000-8000-000000000025',FALSE,NULL,NULL,'acceptance','2.1.0','PDF_GENERATION_FAILED');PERFORM pg_temp.assert_true(result->>'status'='GenerationFailed','Artifact failure completion enum contract failed');END$$;
DO $$BEGIN BEGIN PERFORM count(*)FROM public.report_pdf_artifacts;RAISE EXCEPTION'direct artifact table read allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;END$$;
DO $$DECLARE uid UUID;BEGIN FOREACH uid IN ARRAY ARRAY['93000000-0000-4000-8000-000000000002'::UUID,'93000000-0000-4000-8000-000000000003'::UUID,'93000000-0000-4000-8000-000000000004'::UUID,'93000000-0000-4000-8000-000000000005'::UUID]LOOP PERFORM set_config('request.jwt.claim.sub',uid::TEXT,true);BEGIN PERFORM public.get_report_pdf_delivery_acceptance_candidate();RAISE EXCEPTION'non-worker acceptance allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;END LOOP;END$$;
SELECT set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000002',true);
SELECT pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM public.catalogue_test_operational_state),'Gateway catalogue visibility allowed');
SELECT set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000001',true);
SELECT pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM public.catalogue_test_operational_state),'Artifact Worker catalogue visibility allowed');
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$BEGIN BEGIN PERFORM public.get_report_pdf_delivery_acceptance_candidate();RAISE EXCEPTION'service_role acceptance allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;END$$;
RESET ROLE;
SELECT 'report artifact Worker PostgreSQL integration: PASS' AS result;
ROLLBACK;
