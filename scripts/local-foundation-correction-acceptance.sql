\set ON_ERROR_STOP on
BEGIN;
INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
 ('80000000-0000-0000-0000-000000000001','acceptance-admin@example.invalid','{"full_name":"Synthetic Acceptance Admin"}')
ON CONFLICT(id) DO NOTHING;
UPDATE user_profiles SET is_active=TRUE,is_super_admin=TRUE,full_name='Synthetic Acceptance Admin'
WHERE id='80000000-0000-0000-0000-000000000001';
SELECT set_config('request.jwt.claim.sub','80000000-0000-0000-0000-000000000001',false);

CREATE TEMP TABLE acceptance_results(test text,pass boolean,detail text);

DO $setup$
DECLARE pat uuid:=gen_random_uuid(); bill uuid:=gen_random_uuid(); ord uuid; t tests%rowtype; p parameters%rowtype;
  label text; bi uuid; sm uuid; oi uuid; st sample_status_enum;
BEGIN
 SELECT * INTO t FROM tests WHERE clinical_reporting_enabled AND collection_required
   AND EXISTS(SELECT 1 FROM parameters x WHERE x.test_id=tests.id AND x.is_active) LIMIT 1;
 SELECT * INTO p FROM parameters WHERE test_id=t.id AND is_active LIMIT 1;
 INSERT INTO patients(id,uhid,mobile,full_name,gender,age_years,address)
 VALUES(pat,'8888888801','9888888801','Correction Synthetic','Other',30,'Synthetic');
 INSERT INTO bills(id,bill_number,patient_id,patient_uhid_snapshot,patient_name_snapshot,patient_mobile_snapshot,patient_age_gender_snapshot,gross_amount_paisa,net_amount_paisa,due_amount_paisa)
 VALUES(bill,'BILL-CORRECTION-1',pat,'8888888801','Correction Synthetic','9888888801','30Y/O',0,0,0);
 INSERT INTO clinical_orders(bill_id,patient_id,order_number,order_date_bs) VALUES(bill,pat,'ALLOCATE','SYNTH') RETURNING id INTO ord;

 FOREACH label IN ARRAY ARRAY['MISSING','PENDING','COLLECTED','RECEIVED','REJECTED'] LOOP
   bi:=gen_random_uuid(); oi:=gen_random_uuid(); sm:=NULL;
   INSERT INTO bill_items(id,bill_id,test_id,test_code_snapshot,test_name_snapshot,reporting_type,unit_price_paisa,net_price_paisa)
   VALUES(bi,bill,t.id,t.code,t.name,t.reporting_type,0,0);
   IF label<>'MISSING' THEN
     sm:=gen_random_uuid(); st:=initcap(lower(label))::sample_status_enum;
     INSERT INTO samples(id,barcode,order_id,patient_id,specimen_type,container_type,status,
       collected_at,collected_by,collected_by_name,received_at,received_by,received_by_name,rejected_at,rejected_by,rejected_by_name,rejection_reason)
     VALUES(sm,'CORR-'||label,ord,pat,t.sample_type,t.container,st,
       CASE WHEN st IN('Collected','Received','Rejected') THEN now() END,
       CASE WHEN st IN('Collected','Received','Rejected') THEN '80000000-0000-0000-0000-000000000001'::uuid END,
       CASE WHEN st IN('Collected','Received','Rejected') THEN 'Synthetic Acceptance Admin' END,
       CASE WHEN st='Received' THEN now() END,CASE WHEN st='Received' THEN '80000000-0000-0000-0000-000000000001'::uuid END,
       CASE WHEN st='Received' THEN 'Synthetic Acceptance Admin' END,
       CASE WHEN st='Rejected' THEN now() END,CASE WHEN st='Rejected' THEN '80000000-0000-0000-0000-000000000001'::uuid END,
       CASE WHEN st='Rejected' THEN 'Synthetic Acceptance Admin' END,CASE WHEN st='Rejected' THEN 'Synthetic rejection' END);
   END IF;
   INSERT INTO clinical_order_items(id,order_id,bill_item_id,test_id,test_name,department,reporting_type,specimen_type,container_type,status,sample_id,workflow_type,clinical_reporting_enabled,collection_required)
   VALUES(oi,ord,bi,t.id,t.name,t.department,t.reporting_type,t.sample_type,t.container,'Pending',sm,t.workflow_type,TRUE,TRUE);
   INSERT INTO audit_logs(action,entity_type,entity_id,new_data) VALUES('ACCEPTANCE_ITEM_'||label,'ClinicalOrderItem',oi::text,jsonb_build_object('parameter_id',p.id));
 END LOOP;

 -- Clinical-disabled but collected: traceable, never result-reportable.
 bi:=gen_random_uuid(); sm:=gen_random_uuid(); oi:=gen_random_uuid();
 INSERT INTO bill_items(id,bill_id,test_id,test_code_snapshot,test_name_snapshot,reporting_type,unit_price_paisa,net_price_paisa)
 VALUES(bi,bill,t.id,t.code,t.name,t.reporting_type,0,0);
 INSERT INTO samples(id,barcode,order_id,patient_id,specimen_type,container_type,status,collected_at,collected_by,collected_by_name)
 VALUES(sm,'CORR-NOCLINICAL',ord,pat,t.sample_type,t.container,'Collected',now(),'80000000-0000-0000-0000-000000000001','Synthetic Acceptance Admin');
 INSERT INTO clinical_order_items(id,order_id,bill_item_id,test_id,test_name,department,reporting_type,specimen_type,container_type,status,sample_id,workflow_type,clinical_reporting_enabled,collection_required)
 VALUES(oi,ord,bi,t.id,t.name,t.department,t.reporting_type,t.sample_type,t.container,'SampleCollected',sm,'NoClinicalReport',FALSE,TRUE);
 INSERT INTO audit_logs(action,entity_type,entity_id,new_data) VALUES('ACCEPTANCE_ITEM_NOCLINICAL','ClinicalOrderItem',oi::text,jsonb_build_object('parameter_id',p.id));
END $setup$;
COMMIT;

-- Readiness matrix.
INSERT INTO acceptance_results
SELECT replace(a.action,'ACCEPTANCE_ITEM_',''),
  (r->>'ready')::boolean = (a.action IN('ACCEPTANCE_ITEM_COLLECTED','ACCEPTANCE_ITEM_RECEIVED')),
  r::text
FROM audit_logs a CROSS JOIN LATERAL clinical_result_collection_readiness(a.entity_id::uuid) r
WHERE a.action LIKE 'ACCEPTANCE_ITEM_%';

-- Trigger-level writes: fail closed except valid Collected/Received.
DO $writes$
DECLARE a record; pid uuid; outcome text; should_pass boolean;
BEGIN
 FOR a IN SELECT * FROM audit_logs WHERE action LIKE 'ACCEPTANCE_ITEM_%' LOOP
   pid:=(a.new_data->>'parameter_id')::uuid;
   should_pass:=a.action IN('ACCEPTANCE_ITEM_COLLECTED','ACCEPTANCE_ITEM_RECEIVED');
   BEGIN
     INSERT INTO test_results(order_item_id,parameter_id,parameter_name,value_type,display_value,status)
     SELECT a.entity_id::uuid,p.id,p.name,p.value_type,'CORRECTION-PROBE','Draft' FROM parameters p WHERE p.id=pid;
     outcome:='PERMITTED';
   EXCEPTION WHEN OTHERS THEN outcome:=SQLERRM; END;
   INSERT INTO acceptance_results VALUES(a.action||'_TRIGGER',
     (should_pass AND outcome='PERMITTED') OR (NOT should_pass AND outcome IN('RESULT_COLLECTION_NOT_READY','RESULT_REPORTING_DISABLED')),outcome);
 END LOOP;
END $writes$;

-- Same starting revision: first mutation succeeds once; stale second mutation
-- returns PT409/RESULT_REVISION_CONFLICT with the current revision in detail.
DO $race$
DECLARE oi uuid; pid uuid; payload jsonb; first jsonb; before_audit int; after_audit int; conflict text; conflict_state text; current_rev bigint;
BEGIN
 SELECT entity_id::uuid,(new_data->>'parameter_id')::uuid INTO oi,pid FROM audit_logs WHERE action='ACCEPTANCE_ITEM_COLLECTED' ORDER BY timestamp DESC LIMIT 1;
 DELETE FROM test_results WHERE order_item_id=oi;
 SELECT count(*) INTO before_audit FROM audit_logs WHERE entity_type='ClinicalOrderItem' AND entity_id=oi::text AND action='RESULTS_SAVED';
 SELECT jsonb_build_array(jsonb_build_object('parameter_id',p.id,'display_value','Actor A','text_value','Actor A','flag','Normal','is_critical',false,'critical_acknowledged',false)) INTO payload FROM parameters p WHERE p.id=pid;
 first:=save_test_results(oi,payload,'Draft',NULL,NULL,0);
 BEGIN
   PERFORM save_test_results(oi,payload,'Draft',NULL,NULL,0);
 EXCEPTION WHEN OTHERS THEN conflict:=SQLERRM; conflict_state:=SQLSTATE; END;
 SELECT result_revision INTO current_rev FROM clinical_order_items WHERE id=oi;
 SELECT count(*) INTO after_audit FROM audit_logs WHERE entity_type='ClinicalOrderItem' AND entity_id=oi::text AND action='RESULTS_SAVED';
 INSERT INTO acceptance_results VALUES('RESULT_REVISION_RACE',
   first->>'result_revision'='1' AND conflict='RESULT_REVISION_CONFLICT' AND conflict_state='PT409' AND current_rev=1 AND after_audit-before_audit=1,
   jsonb_build_object('first',first,'conflict',conflict,'sqlstate',conflict_state,'current_revision',current_rev,'audit_delta',after_audit-before_audit)::text);
END $race$;

-- Recollection lineage: rejected original and pending replacement fail; after
-- authoritative collection transition the replacement becomes actionable.
DO $recollection$
DECLARE old_id uuid; oi uuid; new_id uuid; before_state jsonb; pending_state jsonb; collected_state jsonb; response jsonb;
BEGIN
 SELECT a.entity_id::uuid,coi.sample_id INTO oi,old_id FROM audit_logs a JOIN clinical_order_items coi ON coi.id=a.entity_id::uuid WHERE a.action='ACCEPTANCE_ITEM_REJECTED' LIMIT 1;
 before_state:=clinical_result_collection_readiness(oi);
 response:=transition_sample_lifecycle(old_id,'Pending','Acceptance recollection'); new_id:=(response->>'sample_id')::uuid;
 pending_state:=clinical_result_collection_readiness(oi);
 PERFORM transition_sample_lifecycle(new_id,'Collected',NULL);
 collected_state:=clinical_result_collection_readiness(oi);
 INSERT INTO acceptance_results VALUES('RECOLLECTION_LINEAGE',
   NOT (before_state->>'ready')::boolean AND before_state->>'reason'='SAMPLE_REJECTED'
   AND NOT (pending_state->>'ready')::boolean AND pending_state->>'reason'='SAMPLE_PENDING'
   AND (collected_state->>'ready')::boolean
   AND (SELECT recollected_from_sample_id=old_id FROM samples WHERE id=new_id)
   AND (SELECT sample_id=new_id FROM clinical_order_items WHERE id=oi),
   jsonb_build_object('old',old_id,'replacement',new_id,'before',before_state,'pending',pending_state,'collected',collected_state)::text);
END $recollection$;

TABLE acceptance_results;
SELECT count(*) FILTER(WHERE pass),count(*) FILTER(WHERE NOT pass) FROM acceptance_results;
