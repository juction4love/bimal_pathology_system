\set ON_ERROR_STOP on
SELECT set_config('request.jwt.claim.sub','80000000-0000-0000-0000-000000000001',false);
CREATE TABLE local_signoff_fixture(order_id uuid primary key,order_item_id uuid,parameter_id uuid,performer_id uuid,signer_id uuid,initial_report_id uuid);
DO $$
DECLARE pat uuid; b uuid:=gen_random_uuid(); o uuid; bi uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); oi uuid:=gen_random_uuid();
 t tests%rowtype; p parameters%rowtype; performer uuid:=gen_random_uuid(); signer uuid:=gen_random_uuid(); payload jsonb;
BEGIN
 SELECT id INTO pat FROM patients WHERE uhid='8888888801';
 SELECT * INTO t FROM tests WHERE clinical_reporting_enabled AND collection_required AND EXISTS(SELECT 1 FROM parameters x WHERE x.test_id=tests.id AND x.is_active) LIMIT 1;
 SELECT * INTO p FROM parameters WHERE test_id=t.id AND is_active LIMIT 1;
 INSERT INTO bills(id,bill_number,patient_id,patient_uhid_snapshot,patient_name_snapshot,patient_mobile_snapshot,patient_age_gender_snapshot,gross_amount_paisa,net_amount_paisa,due_amount_paisa)
 VALUES(b,'BILL-SIGNOFF-CLOSURE',pat,'8888888801','Correction Synthetic','9888888801','30Y/O',0,0,0);
 INSERT INTO bill_items(id,bill_id,test_id,test_code_snapshot,test_name_snapshot,reporting_type,unit_price_paisa,net_price_paisa)
 VALUES(bi,b,t.id,t.code,t.name,t.reporting_type,0,0);
 INSERT INTO clinical_orders(bill_id,patient_id,order_number,order_date_bs) VALUES(b,pat,'ALLOCATE','SYNTH') RETURNING id INTO o;
 INSERT INTO samples(id,barcode,order_id,patient_id,specimen_type,container_type,status,collected_at,collected_by,collected_by_name,received_at,received_by,received_by_name)
 VALUES(s,'SIGNOFF-CLOSURE-SAMPLE',o,pat,t.sample_type,t.container,'Received',now(),'80000000-0000-0000-0000-000000000001','Synthetic Acceptance Admin',now(),'80000000-0000-0000-0000-000000000001','Synthetic Acceptance Admin');
 INSERT INTO clinical_order_items(id,order_id,bill_item_id,test_id,test_name,department,reporting_type,specimen_type,container_type,status,sample_id,workflow_type,clinical_reporting_enabled,collection_required)
 VALUES(oi,o,bi,t.id,t.name,t.department,t.reporting_type,t.sample_type,t.container,'SampleReceived',s,t.workflow_type,true,true);
 INSERT INTO reporting_personnel(id,full_name,professional_type,qualification,registration_council,registration_number,can_enter_results,can_verify_results,can_acknowledge_critical,can_sign_reports)
 VALUES(performer,'Synthetic Performer','Lab Technologist','Synthetic','Synthetic Council','CLOSURE-P',true,false,false,false),
       (signer,'Synthetic Signer','Pathologist','Synthetic','Synthetic Council','CLOSURE-S',false,true,true,true);
 payload:=jsonb_build_array(jsonb_build_object('parameter_id',p.id,'display_value','Closure Initial','text_value','Closure Initial','flag','Normal','is_critical',false,'critical_acknowledged',false));
 PERFORM save_test_results(oi,payload,'SubmittedForVerification',NULL,NULL,0);
 PERFORM save_test_results(oi,payload,'Verified',NULL,NULL,1);
 INSERT INTO local_signoff_fixture VALUES(o,oi,p.id,performer,signer,NULL);
END $$;

CREATE FUNCTION local_sign_initial() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE f local_signoff_fixture%rowtype; token text:=encode(gen_random_bytes(32),'hex');
BEGIN
 PERFORM set_config('request.jwt.claim.sub','80000000-0000-0000-0000-000000000001',true);
 SELECT * INTO f FROM local_signoff_fixture LIMIT 1;
 RETURN sign_and_queue_diagnostic_report(f.order_id,f.performer_id,f.signer_id,NULL,NULL,encode(digest(token,'sha256'),'hex'),'https://lis.bimalpathology.com.np/r/'||token);
END $$;

CREATE FUNCTION local_prepare_amendment() RETURNS void LANGUAGE plpgsql AS $$
DECLARE f local_signoff_fixture%rowtype; payload jsonb; rid uuid;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','80000000-0000-0000-0000-000000000001',true);
 SELECT * INTO f FROM local_signoff_fixture LIMIT 1;
 SELECT id INTO rid FROM diagnostic_reports WHERE order_id=f.order_id AND version=1;
 UPDATE local_signoff_fixture SET initial_report_id=rid;
 payload:=jsonb_build_array(jsonb_build_object('parameter_id',f.parameter_id,'display_value','Closure Amendment','text_value','Closure Amendment','flag','Normal','is_critical',false,'critical_acknowledged',false));
 PERFORM save_test_results(f.order_item_id,payload,'SubmittedForVerification',rid,'Synthetic closure amendment',2);
 PERFORM save_test_results(f.order_item_id,payload,'Verified',rid,'Synthetic closure amendment',3);
END $$;

CREATE FUNCTION local_sign_amendment() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE f local_signoff_fixture%rowtype; token text:=encode(gen_random_bytes(32),'hex');
BEGIN
 PERFORM set_config('request.jwt.claim.sub','80000000-0000-0000-0000-000000000001',true);
 SELECT * INTO f FROM local_signoff_fixture LIMIT 1;
 RETURN sign_and_queue_diagnostic_report(f.order_id,f.performer_id,f.signer_id,'Synthetic closure amendment',f.initial_report_id,encode(digest(token,'sha256'),'hex'),'https://lis.bimalpathology.com.np/r/'||token);
END $$;
