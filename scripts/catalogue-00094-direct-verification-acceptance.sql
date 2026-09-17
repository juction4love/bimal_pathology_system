\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE verify_assertions(n INT PRIMARY KEY,name TEXT,passed BOOLEAN,detail TEXT);
CREATE OR REPLACE FUNCTION pg_temp.ok(n INT,name TEXT,passed BOOLEAN,detail TEXT DEFAULT NULL) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO verify_assertions VALUES(n,name,COALESCE(passed,FALSE),detail);
 IF passed THEN
  RAISE NOTICE 'PASS %: %',n,name;
 ELSE
  RAISE NOTICE 'FAIL %: % (%)',n,name,detail;
 END IF;
END$$;

-- Seed test user and reporting personnel
INSERT INTO public.user_profiles(id,email,full_name,is_active)
VALUES('11111111-1111-4000-8000-000000000001','tech@bimal.test','Technician Tester',TRUE)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.patients(id,uhid,mobile,full_name,gender,dob,address) VALUES
 ('99100000-0000-0000-0000-000000000094','9900000094','9800000094','Direct Verify Patient','Female','1986-01-01','Synthetic');

INSERT INTO public.bills(id,bill_number,patient_id,patient_uhid_snapshot,patient_name_snapshot,patient_mobile_snapshot,patient_age_gender_snapshot,gross_amount_paisa,net_amount_paisa,paid_amount_paisa,due_amount_paisa)
VALUES
 ('99200000-0000-0000-0000-000000000094','DIR-1','99100000-0000-0000-0000-000000000094','991094','Direct Verify Patient','9800000094','40/F',0,0,0,0);

INSERT INTO public.clinical_orders(id,bill_id,patient_id,order_number,order_date_ad,order_date_bs) VALUES
 ('99300000-0000-0000-0000-000000000094','99200000-0000-0000-0000-000000000094','99100000-0000-0000-0000-000000000094','DIR-ORDER-1','2026-01-01','synthetic');

DO $$
DECLARE t public.tests%ROWTYPE;
BEGIN
 SELECT * INTO t FROM public.tests WHERE code='LFT';
 INSERT INTO public.bill_items(id,bill_id,test_id,test_code_snapshot,test_name_snapshot,reporting_type,unit_price_paisa,net_price_paisa)
 VALUES('99500000-0000-0000-0000-000000000094','99200000-0000-0000-0000-000000000094',t.id,t.code,t.name,t.reporting_type,0,0);
 INSERT INTO public.clinical_order_items(id,order_id,bill_item_id,test_id,test_name,department,reporting_type,specimen_type,container_type,status,workflow_type,clinical_reporting_enabled,collection_required,result_revision)
 VALUES('99400000-0000-0000-0000-000000000094','99300000-0000-0000-0000-000000000094','99500000-0000-0000-0000-000000000094',t.id,t.name,t.department,t.reporting_type,COALESCE(t.sample_type,''),COALESCE(t.container,''),'ResultDrafted',t.workflow_type,TRUE,FALSE,1);
 INSERT INTO public.test_results(order_item_id,parameter_id,parameter_name,unit,value_type,display_value,status)
 SELECT '99400000-0000-0000-0000-000000000094',p.id,p.name,p.unit,p.value_type,CASE WHEN p.value_type='Calculated' THEN 'Pending calculation' ELSE '' END,'Draft'
 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active';
END$$;

-- Prepare LFT result payload
CREATE OR REPLACE FUNCTION pg_temp.test_direct_verify() RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
 lft_payload JSONB;
 res JSONB;
 t_id UUID;
 p RECORD;
BEGIN
 SELECT id INTO t_id FROM public.tests WHERE code='LFT';
 lft_payload := '[]'::JSONB;
 FOR p IN SELECT id, code, name FROM public.parameters WHERE test_id=t_id AND value_type <> 'Calculated' AND is_active LOOP
   IF p.code='TBIL' THEN
     lft_payload := lft_payload || jsonb_build_object('parameter_id', p.id, 'numeric_value', 1.01, 'display_value', '1.01', 'flag', 'Normal', 'is_critical', FALSE, 'critical_acknowledged', FALSE);
   ELSIF p.code='DBIL' THEN
     lft_payload := lft_payload || jsonb_build_object('parameter_id', p.id, 'numeric_value', 0.25, 'display_value', '0.25', 'flag', 'Normal', 'is_critical', FALSE, 'critical_acknowledged', FALSE);
   ELSIF p.code='SGOT' THEN
     lft_payload := lft_payload || jsonb_build_object('parameter_id', p.id, 'numeric_value', 35, 'display_value', '35', 'flag', 'Normal', 'is_critical', FALSE, 'critical_acknowledged', FALSE);
   ELSIF p.code='SGPT' THEN
     lft_payload := lft_payload || jsonb_build_object('parameter_id', p.id, 'numeric_value', 40, 'display_value', '40', 'flag', 'Normal', 'is_critical', FALSE, 'critical_acknowledged', FALSE);
   ELSIF p.code='ALP' THEN
     lft_payload := lft_payload || jsonb_build_object('parameter_id', p.id, 'numeric_value', 120, 'display_value', '120', 'flag', 'Normal', 'is_critical', FALSE, 'critical_acknowledged', FALSE);
   ELSIF p.code='TP' THEN
     lft_payload := lft_payload || jsonb_build_object('parameter_id', p.id, 'numeric_value', 7.2, 'display_value', '7.2', 'flag', 'Normal', 'is_critical', FALSE, 'critical_acknowledged', FALSE);
   ELSIF p.code='ALB' THEN
     lft_payload := lft_payload || jsonb_build_object('parameter_id', p.id, 'numeric_value', 4.2, 'display_value', '4.2', 'flag', 'Normal', 'is_critical', FALSE, 'critical_acknowledged', FALSE);
   END IF;
 END LOOP;

 -- Execute direct save_test_results with p_target_status = 'Verified'
 res := public.save_test_results(
   '99400000-0000-0000-0000-000000000094'::UUID,
   lft_payload,
   'Verified'::public.result_status_enum,
   NULL::UUID,
   NULL::TEXT,
   1::BIGINT
 );
 RETURN res;
END$$;

-- Verify execution of save_test_results directly to Verified
-- (Simulate as authenticated user with permissions)
DO $$
DECLARE
 r JSONB;
 oi_status TEXT;
 glob_val NUMERIC;
 ibil_val NUMERIC;
 ag_val NUMERIC;
BEGIN
 -- Perform direct verify
 r := pg_temp.test_direct_verify();
 SELECT status INTO oi_status FROM public.clinical_order_items WHERE id='99400000-0000-0000-0000-000000000094';
 SELECT numeric_value INTO ibil_val FROM public.test_results tr JOIN public.parameters p ON p.id=tr.parameter_id WHERE tr.order_item_id='99400000-0000-0000-0000-000000000094' AND p.code='IBIL';
 SELECT numeric_value INTO glob_val FROM public.test_results tr JOIN public.parameters p ON p.id=tr.parameter_id WHERE tr.order_item_id='99400000-0000-0000-0000-000000000094' AND p.code='GLOB';
 SELECT numeric_value INTO ag_val FROM public.test_results tr JOIN public.parameters p ON p.id=tr.parameter_id WHERE tr.order_item_id='99400000-0000-0000-0000-000000000094' AND p.code='AG_RATIO';

 PERFORM pg_temp.ok(1, 'Direct Save/Verify returns success', (r->>'success')::BOOLEAN IS TRUE);
 PERFORM pg_temp.ok(2, 'Order item status transitioned directly to Verified', oi_status = 'Verified');
 PERFORM pg_temp.ok(3, 'Indirect Bilirubin calculated (0.76)', ibil_val = 0.76);
 PERFORM pg_temp.ok(4, 'Globulin calculated (3.00)', glob_val = 3.00);
 PERFORM pg_temp.ok(5, 'A:G Ratio calculated (1.40)', ag_val = 1.40);
END$$;

SELECT count(*) passed,count(*) FILTER(WHERE NOT passed) failed FROM verify_assertions;
DO $$BEGIN IF EXISTS(SELECT 1 FROM verify_assertions WHERE NOT passed) THEN RAISE EXCEPTION 'Direct verification acceptance failed'; END IF; END$$;
ROLLBACK;
