\set ON_ERROR_STOP on
BEGIN;
TRUNCATE public.sms_queue_items;

DO $$ BEGIN
 IF public.normalize_nepal_sms_mobile('98 5506-5327')<>'9855065327' OR public.normalize_nepal_sms_mobile('+9779855065327')<>'9855065327' OR public.normalize_nepal_sms_mobile('9779855065327')<>'9855065327' THEN RAISE EXCEPTION 'MOBILE_NORMALIZATION_FAILED'; END IF;
 BEGIN PERFORM public.normalize_nepal_sms_mobile('invalid98'); RAISE EXCEPTION 'INVALID_MOBILE_ACCEPTED'; EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
END $$;

INSERT INTO public.sms_queue_items(id,sms_type,recipient_phone,recipient_name,message_body,idempotency_key)
VALUES
 ('91000000-0000-0000-0000-000000000001','BillRegistration','+9779855065327','Acceptance','Bimal Pathology: Payment of NPR 400.00 received for Lab No: BPDC-TEST-1. Thank you.','PAYMENT_CONFIRMATION:91000000-0000-0000-0000-000000000001'),
 ('91000000-0000-0000-0000-000000000002','ReportReady','9779855065327','Acceptance','Bimal Pathology: Your report is ready. Lab No: BPDC-TEST-2. View report: https://lis.bimalpathology.com.np/r/opaque_acceptance_token_000000000000','REPORT_READY:91000000-0000-0000-0000-000000000002:1');

DO $$ BEGIN
 BEGIN INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,idempotency_key) VALUES('BillRegistration','9855065327','Duplicate','duplicate','PAYMENT_CONFIRMATION:91000000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'DUPLICATE_IDEMPOTENCY_ACCEPTED'; EXCEPTION WHEN unique_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM public.sms_queue_items WHERE recipient_phone<>'9855065327') THEN RAISE EXCEPTION 'QUEUE_MOBILE_NOT_NORMALIZED'; END IF;
END $$;

DO $$ DECLARE a RECORD;b RECORD;BEGIN
 SELECT * INTO a FROM public.claim_next_sms_gateway_item('92000000-0000-0000-0000-000000000001',300);
 SELECT * INTO b FROM public.claim_next_sms_gateway_item('92000000-0000-0000-0000-000000000002',300);
 IF a.id IS NULL OR b.id IS NULL OR a.id=b.id THEN RAISE EXCEPTION 'CONCURRENT_CLAIM_FAILED'; END IF;
 IF NOT public.mark_sms_provider_call_started(a.id,'92000000-0000-0000-0000-000000000001') THEN RAISE EXCEPTION 'PROVIDER_MARK_FAILED'; END IF;
 BEGIN PERFORM public.complete_sms_gateway_item(a.id,'92000000-0000-0000-0000-000000000099',TRUE,'wrong',NULL,'200',NULL,NULL,FALSE); RAISE EXCEPTION 'WRONG_LEASE_ACCEPTED'; EXCEPTION WHEN serialization_failure THEN NULL; END;
 PERFORM public.complete_sms_gateway_item(a.id,'92000000-0000-0000-0000-000000000001',TRUE,'provider-accepted-1','{"response":"Success"}'::jsonb,'200',NULL,NULL,FALSE);
 IF NOT public.mark_sms_provider_call_started(b.id,'92000000-0000-0000-0000-000000000002') THEN RAISE EXCEPTION 'SECOND_PROVIDER_MARK_FAILED'; END IF;
 PERFORM public.complete_sms_gateway_item(b.id,'92000000-0000-0000-0000-000000000002',FALSE,NULL,'{"response":"Temporary"}'::jsonb,'503','Temporary provider error','RetryableProviderFailure',TRUE);
 IF (SELECT status FROM public.sms_queue_items WHERE id=a.id)<>'Sent' OR (SELECT status FROM public.sms_queue_items WHERE id=b.id)<>'Failed' THEN RAISE EXCEPTION 'COMPLETION_STATE_FAILED'; END IF;
END $$;

INSERT INTO auth.users(id,aud,role,email,created_at,updated_at,is_anonymous) VALUES('93000000-0000-0000-0000-000000000001','authenticated','authenticated','sms-admin@example.invalid',NOW(),NOW(),FALSE);
UPDATE public.user_profiles SET full_name='SMS Acceptance Admin',is_active=TRUE,is_super_admin=TRUE WHERE id='93000000-0000-0000-0000-000000000001';
SELECT set_config('request.jwt.claim.sub','93000000-0000-0000-0000-000000000001',true);
DO $$ DECLARE failed_id UUID;BEGIN
 SELECT id INTO failed_id FROM public.sms_queue_items WHERE status='Failed';
 PERFORM public.retry_sms_delivery(failed_id,'Authorized isolated acceptance retry');
 IF (SELECT status FROM public.sms_queue_items WHERE id=failed_id)<>'Pending' OR (SELECT retry_count FROM public.sms_queue_items WHERE id=failed_id)<>0 THEN RAISE EXCEPTION 'MANUAL_RETRY_FAILED'; END IF;
 BEGIN PERFORM public.retry_sms_delivery((SELECT id FROM public.sms_queue_items WHERE status='Sent'),'Must be refused'); RAISE EXCEPTION 'SENT_RETRY_ACCEPTED'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
END $$;

DELETE FROM public.sms_queue_items WHERE status<>'Sent';

INSERT INTO public.sms_queue_items(id,sms_type,recipient_phone,recipient_name,message_body,idempotency_key) VALUES
 ('91000000-0000-0000-0000-000000000003','BillRegistration','9855065327','Lease pre-call','pre-call','PAYMENT_CONFIRMATION:lease-pre-call'),
 ('91000000-0000-0000-0000-000000000004','ReportReady','9855065327','Lease post-call','post-call','REPORT_READY:lease-post-call:1');
SELECT * FROM public.claim_next_sms_gateway_item('92000000-0000-0000-0000-000000000003',60);
UPDATE public.sms_queue_items SET lease_expires_at=NOW()-INTERVAL '1 second' WHERE lease_owner='92000000-0000-0000-0000-000000000003';
SELECT public.recover_stale_sms_gateway_items(60);
UPDATE public.sms_queue_items SET scheduled_at=NOW()+INTERVAL '1 day' WHERE error_classification='LeaseExpiredBeforeProviderCall';
SELECT * FROM public.claim_next_sms_gateway_item('92000000-0000-0000-0000-000000000004',60);
SELECT public.mark_sms_provider_call_started(id,'92000000-0000-0000-0000-000000000004') FROM public.sms_queue_items WHERE lease_owner='92000000-0000-0000-0000-000000000004';
UPDATE public.sms_queue_items SET lease_expires_at=NOW()-INTERVAL '1 second' WHERE lease_owner='92000000-0000-0000-0000-000000000004';
SELECT public.recover_stale_sms_gateway_items(60);

DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.sms_queue_items WHERE error_classification='LeaseExpiredBeforeProviderCall' AND status='Pending') THEN RAISE EXCEPTION 'SAFE_STALE_RECOVERY_FAILED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.sms_queue_items WHERE error_classification='ProviderOutcomeUnknown' AND status='DeadLetter') THEN RAISE EXCEPTION 'UNKNOWN_OUTCOME_NOT_QUARANTINED'; END IF;
 IF has_function_privilege('anon','public.claim_next_sms_gateway_item(uuid,integer)','EXECUTE') OR has_function_privilege('authenticated','public.complete_sms_gateway_item(uuid,uuid,boolean,text,jsonb,text,text,text,boolean)','EXECUTE') THEN RAISE EXCEPTION 'GATEWAY_RPC_PRIVILEGE_LEAK'; END IF;
 IF has_table_privilege('authenticated','public.sms_queue_items','SELECT,INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'SMS_TABLE_BROWSER_PRIVILEGE_LEAK'; END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.sms_queue_items'::regclass) THEN RAISE EXCEPTION 'SMS_RLS_DISABLED'; END IF;
 IF (SELECT count(*) FROM public.sms_queue_items WHERE idempotency_key='PAYMENT_CONFIRMATION:91000000-0000-0000-0000-000000000001')<>1 THEN RAISE EXCEPTION 'IDEMPOTENCY_COUNT_FAILED'; END IF;
END $$;

SELECT jsonb_build_object('pass',true,'rows',count(*),'sent',count(*) FILTER(WHERE status='Sent'),'failed',count(*) FILTER(WHERE status='Failed'),'deadletter',count(*) FILTER(WHERE status='DeadLetter'),'pending',count(*) FILTER(WHERE status='Pending')) AS sms_acceptance FROM public.sms_queue_items;
ROLLBACK;
