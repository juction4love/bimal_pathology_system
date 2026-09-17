-- Synthetic-only fixture for the disposable local PostgreSQL acceptance database.
-- Never deploy. UUIDs and identifiers are deliberately fixed for fingerprinting.
BEGIN;
SET LOCAL session_replication_role = replica;

INSERT INTO patients(id,uhid,mobile,full_name,gender,age_years,address,created_at,updated_at)
VALUES('10000000-0000-0000-0000-000000000001','UHID-SYNTH-0001','9800000001','Synthetic Legacy Patient','Male',40,'Synthetic Address','2025-01-01Z','2025-01-01Z');

INSERT INTO bills(id,bill_number,patient_id,patient_uhid_snapshot,patient_name_snapshot,patient_mobile_snapshot,patient_age_gender_snapshot,gross_amount_paisa,net_amount_paisa,paid_amount_paisa,due_amount_paisa,payment_status,created_at,updated_at)
VALUES('20000000-0000-0000-0000-000000000001','BILL-SYNTH-0001','10000000-0000-0000-0000-000000000001','UHID-SYNTH-0001','Synthetic Legacy Patient','9800000001','40Y/M',10000,10000,10000,0,'Paid','2025-01-01Z','2025-01-01Z');

INSERT INTO payment_transactions(id,bill_id,receipt_number,amount_paisa,payment_mode,received_by_name,created_at)
VALUES('21000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','REC-SYNTH-0001',10000,'Cash','Synthetic Operator','2025-01-01Z');

DO $fixture$
DECLARE tid uuid; pid uuid;
BEGIN
  SELECT t.id INTO tid FROM tests t WHERE t.reporting_type IN ('InHouse','OutsourceWithBimalReport') AND EXISTS (SELECT 1 FROM parameters p WHERE p.test_id=t.id) ORDER BY t.code LIMIT 1;
  SELECT p.id INTO pid FROM parameters p WHERE p.test_id=tid ORDER BY p.display_order,p.id LIMIT 1;
  INSERT INTO bill_items(id,bill_id,test_id,test_code_snapshot,test_name_snapshot,reporting_type,unit_price_paisa,net_price_paisa,created_at)
  SELECT '22000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',id,code,name,reporting_type,10000,10000,'2025-01-01Z' FROM tests WHERE id=tid;
  INSERT INTO clinical_orders(id,bill_id,patient_id,order_number,order_date_ad,order_date_bs,status,created_at,updated_at)
  VALUES('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','LAB-SYNTH-0001','2025-01-01','2081-09-17','SignedOff','2025-01-01Z','2025-01-01Z');
  INSERT INTO samples(id,barcode,order_id,patient_id,specimen_type,container_type,status,collected_at,collected_by_name,received_at,received_by_name,created_at,updated_at)
  VALUES('40000000-0000-0000-0000-000000000001','SYNTH-SAMPLE-0001','30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Blood','EDTA','Processing','2025-01-01Z','Synthetic Collector','2025-01-01Z','Synthetic Receiver','2025-01-01Z','2025-01-01Z');
  INSERT INTO clinical_order_items(id,order_id,bill_item_id,test_id,test_name,department,reporting_type,specimen_type,container_type,status,sample_id,created_at,updated_at)
  SELECT '50000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','22000000-0000-0000-0000-000000000001',id,name,department,reporting_type,'Blood','EDTA','SignedOff','40000000-0000-0000-0000-000000000001','2025-01-01Z','2025-01-01Z' FROM tests WHERE id=tid;
  INSERT INTO test_results(id,order_item_id,parameter_id,parameter_name,value_type,display_value,status,entered_by_name,entered_at,verified_by_name,verified_at,signed_off_name,signed_off_at,created_at,updated_at)
  SELECT '60000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001',id,name,value_type,'Synthetic result','SignedOff','Synthetic Operator','2025-01-01Z','Synthetic Verifier','2025-01-01Z','Synthetic Signatory','2025-01-01Z','2025-01-01Z','2025-01-01Z' FROM parameters WHERE id=pid;
END $fixture$;

INSERT INTO diagnostic_reports(id,order_id,patient_id,report_number,version,status,integrity_hash,performed_by_personnel_name,verified_by_personnel_name,signed_by_personnel_name,signed_at,clinical_snapshot_json,created_at,updated_at)
VALUES('70000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','REP-SYNTH-0001',1,'SignedOff',repeat('a',64),'Synthetic Operator','Synthetic Verifier','Synthetic Signatory','2025-01-01Z','{"synthetic":true,"lab_no":"LAB-SYNTH-0001"}','2025-01-01Z','2025-01-01Z');
INSERT INTO public_report_tokens(id,diagnostic_report_id,token_hash,expires_at,created_at,updated_at)
VALUES('71000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001',repeat('b',64),'2030-01-01Z','2025-01-01Z','2025-01-01Z');
INSERT INTO sms_queue_items(id,sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,bill_id,diagnostic_report_id,created_at,updated_at)
VALUES('72000000-0000-0000-0000-000000000001','ReportReady','9800000001','Synthetic Legacy Patient','Synthetic report ready: LAB-SYNTH-0001','Sent','SYNTH-SMS-0001','20000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','2025-01-01Z','2025-01-01Z');
INSERT INTO audit_logs(id,action,entity_type,entity_id,new_data,"timestamp")
VALUES('73000000-0000-0000-0000-000000000001','SYNTHETIC_BASELINE','acceptance_fixture','SYNTH-0001','{"synthetic":true}','2025-01-01Z');
COMMIT;
