\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE multi_report_results(n int primary key,name text);
GRANT ALL ON multi_report_results TO authenticated;
CREATE OR REPLACE FUNCTION pg_temp.ok(n int,name text,condition boolean) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF NOT coalesce(condition,false) THEN RAISE EXCEPTION 'TEST_%_FAILED: %',n,name; END IF; INSERT INTO multi_report_results VALUES(n,name); RAISE NOTICE 'PASS %: %',n,name; END$$;
CREATE OR REPLACE FUNCTION pg_temp.token_hash(raw text) RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path=extensions,pg_temp AS $$SELECT encode(digest(convert_to(raw,'UTF8'),'sha256'),'hex')$$;
GRANT EXECUTE ON FUNCTION pg_temp.token_hash(text) TO authenticated;

INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
('99200000-0000-0000-0000-000000000001','multi-report-tech@example.invalid','{"full_name":"Multi Report Technician"}'),
('99200000-0000-0000-0000-000000000002','multi-report-worker@example.invalid','{}') ON CONFLICT DO NOTHING;
UPDATE public.user_profiles SET is_active=true,is_super_admin=false WHERE id='99200000-0000-0000-0000-000000000001';
INSERT INTO public.user_roles(user_id,role_id) SELECT '99200000-0000-0000-0000-000000000001',id FROM public.roles WHERE name='Lab Technician' ON CONFLICT DO NOTHING;
INSERT INTO public.reporting_personnel(id,user_id,full_name,professional_type,qualification,registration_council,registration_number,can_enter_results,can_verify_results,can_acknowledge_critical,can_sign_reports,is_active)
VALUES('99200000-0000-0000-0000-000000000010','99200000-0000-0000-0000-000000000001','Multi Report Technician','Lab Technician','BMLT','NHPC','SYNTHETIC',true,true,true,true,true);
INSERT INTO public.report_artifact_worker_identities(auth_user_id,worker_name,created_by) VALUES('99200000-0000-0000-0000-000000000002','MultiReportWorker','99200000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','99200000-0000-0000-0000-000000000001',true);

DO $$DECLARE items jsonb[]; response jsonb; oid uuid; bid uuid; BEGIN
 SELECT array_agg(jsonb_build_object('test_id',id,'unit_price_paisa',10000,'manual_price_paisa',10000,'discount_paisa',0,'zero_price_acknowledged',false) ORDER BY array_position(ARRAY['CBC','LFT','KFT','THYROID_PROFILE','URINE_RE'],code)) INTO items FROM public.tests WHERE code=ANY(ARRAY['CBC','LFT','KFT','THYROID_PROFILE','URINE_RE']);
 response:=public.create_patient_bill_order_with_packages(jsonb_build_object('mobile','9800000092','full_name','Synthetic Multi Report Patient','gender','Female','age_years',30,'address','Synthetic'),jsonb_build_object('gross_amount_paisa',50000,'discount_amount_paisa',0,'paid_amount_paisa',0,'order_date_bs','2083-05-15','remarks','rollback multi report'),items,NULL,'multi-report-00092','[]');
 oid:=(response->>'order_id')::uuid;bid:=(response->>'bill_id')::uuid;PERFORM set_config('multi.order',oid::text,true);PERFORM set_config('multi.bill',bid::text,true);
 PERFORM pg_temp.ok(1,'one bill',1=(SELECT count(*) FROM public.bills WHERE id=bid)); PERFORM pg_temp.ok(2,'one clinical order',1=(SELECT count(*) FROM public.clinical_orders WHERE id=oid)); PERFORM pg_temp.ok(3,'five order items',5=(SELECT count(*) FROM public.clinical_order_items WHERE order_id=oid)); PERFORM pg_temp.ok(4,'five immutable bill snapshots',5=(SELECT count(*) FROM public.bill_items WHERE bill_id=bid));
END$$;

SELECT pg_temp.ok(5,'three shared specimen identities',3=(SELECT count(DISTINCT specimen_requirement_key) FROM public.samples WHERE order_id=current_setting('multi.order')::uuid));
SELECT pg_temp.ok(6,'serum sample shared by three investigations',3=(SELECT count(*) FROM public.clinical_order_items oi JOIN public.samples s ON s.id=oi.sample_id WHERE oi.order_id=current_setting('multi.order')::uuid AND s.specimen_requirement_key=(SELECT specimen_requirement_key FROM public.tests WHERE code='LFT')));
SELECT pg_temp.ok(7,'four deterministic report groups',4=(SELECT count(*) FROM public.clinical_report_groups WHERE order_id=current_setting('multi.order')::uuid));
SELECT pg_temp.ok(8,'biochemistry freezes LFT and KFT',2=(SELECT count(*) FROM public.clinical_report_group_items gi JOIN public.clinical_report_groups g ON g.id=gi.report_group_id WHERE g.order_id=current_setting('multi.order')::uuid AND g.group_key='biochemistry'));
SELECT pg_temp.ok(9,'order workspace exposes all investigations',5=(SELECT count(*) FROM public.order_report_group_workspace WHERE order_id=current_setting('multi.order')::uuid));

RESET ROLE;
UPDATE public.samples SET status='Received',collected_at=now(),received_at=now(),collected_by='99200000-0000-0000-0000-000000000001',collected_by_name='Multi Report Technician',received_by='99200000-0000-0000-0000-000000000001',received_by_name='Multi Report Technician' WHERE order_id=current_setting('multi.order')::uuid;
UPDATE public.test_results tr SET display_value='1',numeric_value=1,status='Verified',critical_acknowledged_at=CASE WHEN is_critical THEN now() END WHERE order_item_id IN(SELECT id FROM public.clinical_order_items WHERE order_id=current_setting('multi.order')::uuid AND test_id IN(SELECT id FROM public.tests WHERE code<>'THYROID_PROFILE'));
UPDATE public.clinical_order_items SET status='Verified' WHERE order_id=current_setting('multi.order')::uuid AND test_id IN(SELECT id FROM public.tests WHERE code<>'THYROID_PROFILE');
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','99200000-0000-0000-0000-000000000001',true);
SELECT pg_temp.ok(10,'hematology independently signable',(public.check_report_group_readiness((SELECT id FROM public.clinical_report_groups WHERE order_id=current_setting('multi.order')::uuid AND group_key='hematology'))->>'is_ready')::boolean);
SELECT pg_temp.ok(11,'biochemistry independently signable',(public.check_report_group_readiness((SELECT id FROM public.clinical_report_groups WHERE order_id=current_setting('multi.order')::uuid AND group_key='biochemistry'))->>'is_ready')::boolean);
SELECT pg_temp.ok(12,'clinical pathology independently signable',(public.check_report_group_readiness((SELECT id FROM public.clinical_report_groups WHERE order_id=current_setting('multi.order')::uuid AND group_key='clinical_pathology'))->>'is_ready')::boolean);
SELECT pg_temp.ok(13,'endocrinology remains blocked',NOT (public.check_report_group_readiness((SELECT id FROM public.clinical_report_groups WHERE order_id=current_setting('multi.order')::uuid AND group_key='endocrinology'))->>'is_ready')::boolean);
DO $$DECLARE key text; outcome jsonb; raw text; BEGIN FOREACH key IN ARRAY ARRAY['hematology','biochemistry','clinical_pathology'] LOOP raw:=repeat(substr(key,1,1),48);outcome:=public.sign_and_queue_report_group((SELECT id FROM public.clinical_report_groups WHERE order_id=current_setting('multi.order')::uuid AND group_key=key),'99200000-0000-0000-0000-000000000010',NULL,NULL,NULL,pg_temp.token_hash(raw),'https://dashboard.bimalpathology.com.np/o/'||raw); END LOOP; END$$;
SELECT pg_temp.ok(14,'three independent report lineages',3=(SELECT count(*) FROM public.diagnostic_reports WHERE order_id=current_setting('multi.order')::uuid));
SELECT pg_temp.ok(15,'three artifact intents',3=(SELECT count(DISTINCT latest_report_id) FROM public.order_report_group_workspace WHERE order_id=current_setting('multi.order')::uuid AND latest_report_id IS NOT NULL AND pdf_state='Pending'));
SELECT pg_temp.ok(16,'pending thyroid excluded from every snapshot',NOT EXISTS(SELECT 1 FROM public.diagnostic_reports r CROSS JOIN LATERAL jsonb_array_elements(r.clinical_snapshot_json->'investigations')i WHERE r.order_id=current_setting('multi.order')::uuid AND i->>'test_code'='THYROID_PROFILE'));
SELECT pg_temp.ok(17,'order partially reported',public.derive_order_reporting_state(current_setting('multi.order')::uuid)='Partially Reported');
RESET ROLE;
SELECT pg_temp.ok(23,'one order delivery token',1=(SELECT count(*) FROM public.order_report_delivery_tokens WHERE order_id=current_setting('multi.order')::uuid));
SELECT pg_temp.ok(24,'all four groups are frozen entitlements',4=(SELECT count(*) FROM public.order_report_delivery_entitlements e JOIN public.order_report_delivery_tokens t ON t.id=e.order_token_id WHERE t.order_id=current_setting('multi.order')::uuid));
SELECT pg_temp.ok(25,'all finalized groups share one order portal URL',1=(SELECT count(DISTINCT public_url) FROM public.report_pdf_delivery_intents i JOIN public.diagnostic_reports r ON r.id=i.diagnostic_report_id WHERE r.order_id=current_setting('multi.order')::uuid));
SELECT pg_temp.ok(26,'worker claim URL resolves for every finalized group',3=(SELECT count(*) FROM public.diagnostic_reports r WHERE r.order_id=current_setting('multi.order')::uuid AND public.report_artifact_public_url(r.id) IS NOT NULL));
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.role','authenticated',true); SELECT set_config('request.jwt.claim.sub','99200000-0000-0000-0000-000000000002',true);
DO $$DECLARE c record; i int; BEGIN FOR i IN 1..3 LOOP SELECT * INTO c FROM public.claim_report_pdf_artifact_v2(300) LIMIT 1; IF c.artifact_id IS NULL THEN RAISE EXCEPTION 'worker claim missing'; END IF; PERFORM public.complete_report_pdf_artifact_v2(c.artifact_id,c.lease_owner,true,repeat(substr(i::text,1,1),64),12000+i,'synthetic-worker','00092',NULL); END LOOP; END$$;
RESET ROLE;
SELECT pg_temp.ok(27,'three independent PDFs become Ready',3=(SELECT count(*) FROM public.report_pdf_artifacts a JOIN public.diagnostic_reports r ON r.id=a.diagnostic_report_id WHERE r.order_id=current_setting('multi.order')::uuid AND a.generation_status='Ready'));
SELECT pg_temp.ok(28,'first-ready automatic order SMS exactly once',1=(SELECT count(*) FROM public.sms_queue_items WHERE idempotency_key='ORDER_REPORT_READY:'||current_setting('multi.order')||':1'));
SELECT pg_temp.ok(29,'first notification generation exactly once',1=(SELECT count(*) FROM public.order_report_notification_generations WHERE order_id=current_setting('multi.order')::uuid AND generation=1));
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.role','authenticated',true); SELECT set_config('request.jwt.claim.sub','99200000-0000-0000-0000-000000000002',true);
SELECT pg_temp.ok(30,'order portal exposes states without draft values',4=jsonb_array_length(public.authorize_order_report_delivery(pg_temp.token_hash(repeat('h',48)))->'reports') AND public.authorize_order_report_delivery(pg_temp.token_hash(repeat('h',48)))::text NOT LIKE '%display_value%');
SELECT pg_temp.ok(31,'wrong report denied',NOT (public.authorize_order_report_pdf_artifact(pg_temp.token_hash(repeat('h',48)),'00000000-0000-0000-0000-000000000001')->>'authorized')::boolean);
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','99200000-0000-0000-0000-000000000001',true);

RESET ROLE; UPDATE public.test_results SET display_value='1',numeric_value=1,status='Verified' WHERE order_item_id=(SELECT id FROM public.clinical_order_items WHERE order_id=current_setting('multi.order')::uuid AND test_id=(SELECT id FROM public.tests WHERE code='THYROID_PROFILE')); UPDATE public.clinical_order_items SET status='Verified' WHERE order_id=current_setting('multi.order')::uuid AND test_id=(SELECT id FROM public.tests WHERE code='THYROID_PROFILE');
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','99200000-0000-0000-0000-000000000001',true);
SELECT public.sign_and_queue_report_group((SELECT id FROM public.clinical_report_groups WHERE order_id=current_setting('multi.order')::uuid AND group_key='endocrinology'),'99200000-0000-0000-0000-000000000010',NULL,NULL,NULL,pg_temp.token_hash(repeat('e',48)),'https://dashboard.bimalpathology.com.np/o/'||repeat('e',48));
SELECT pg_temp.ok(18,'fourth report signs later',4=(SELECT count(*) FROM public.diagnostic_reports WHERE order_id=current_setting('multi.order')::uuid)); SELECT pg_temp.ok(19,'order fully reported',public.derive_order_reporting_state(current_setting('multi.order')::uuid)='Fully Reported');
RESET ROLE; SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.role','authenticated',true); SELECT set_config('request.jwt.claim.sub','99200000-0000-0000-0000-000000000002',true);
DO $$DECLARE c record; BEGIN SELECT * INTO c FROM public.claim_report_pdf_artifact_v2(300) LIMIT 1; PERFORM public.complete_report_pdf_artifact_v2(c.artifact_id,c.lease_owner,true,repeat('4',64),12004,'synthetic-worker','00092',NULL); END$$;
RESET ROLE;
SELECT pg_temp.ok(32,'later group produces no automatic SMS',1=(SELECT count(*) FROM public.sms_queue_items WHERE idempotency_key LIKE 'ORDER_REPORT_READY:'||current_setting('multi.order')||':%'));
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','99200000-0000-0000-0000-000000000001',true); SELECT public.notify_updated_order_reports(current_setting('multi.order')::uuid,1,'Synthetic updated-report notification');
RESET ROLE;
SELECT pg_temp.ok(33,'explicit updated notification creates generation two once',1=(SELECT count(*) FROM public.order_report_notification_generations WHERE order_id=current_setting('multi.order')::uuid AND generation=2));

RESET ROLE; UPDATE public.test_results SET status='Verified' WHERE order_item_id IN(SELECT gi.order_item_id FROM public.clinical_report_group_items gi JOIN public.clinical_report_groups g ON g.id=gi.report_group_id WHERE g.order_id=current_setting('multi.order')::uuid AND g.group_key='hematology'); UPDATE public.clinical_order_items SET status='Verified' WHERE id IN(SELECT gi.order_item_id FROM public.clinical_report_group_items gi JOIN public.clinical_report_groups g ON g.id=gi.report_group_id WHERE g.order_id=current_setting('multi.order')::uuid AND g.group_key='hematology');
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','99200000-0000-0000-0000-000000000001',true);
SELECT public.sign_and_queue_report_group((SELECT id FROM public.clinical_report_groups WHERE order_id=current_setting('multi.order')::uuid AND group_key='hematology'),'99200000-0000-0000-0000-000000000010',NULL,'Synthetic correction',(SELECT id FROM public.diagnostic_reports WHERE order_id=current_setting('multi.order')::uuid AND report_group_id=(SELECT id FROM public.clinical_report_groups WHERE order_id=current_setting('multi.order')::uuid AND group_key='hematology') AND version=1),pg_temp.token_hash(repeat('a',48)),'https://dashboard.bimalpathology.com.np/o/'||repeat('a',48));
SELECT pg_temp.ok(20,'hematology amendment is v2',EXISTS(SELECT 1 FROM public.diagnostic_reports r JOIN public.clinical_report_groups g ON g.id=r.report_group_id WHERE r.order_id=current_setting('multi.order')::uuid AND g.group_key='hematology' AND r.version=2));
SELECT pg_temp.ok(21,'sibling versions remain v1',3=(SELECT count(*) FROM public.diagnostic_reports r JOIN public.clinical_report_groups g ON g.id=r.report_group_id WHERE r.order_id=current_setting('multi.order')::uuid AND g.group_key<>'hematology' AND r.version=1));
SELECT pg_temp.ok(22,'no sibling v2',0=(SELECT count(*) FROM public.diagnostic_reports r JOIN public.clinical_report_groups g ON g.id=r.report_group_id WHERE r.order_id=current_setting('multi.order')::uuid AND g.group_key<>'hematology' AND r.version>1));
SELECT count(*) passed,0 failed FROM multi_report_results;
ROLLBACK;
