\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE calc_assertions(n INT PRIMARY KEY,name TEXT,passed BOOLEAN,detail TEXT);
CREATE OR REPLACE FUNCTION pg_temp.ok(n INT,name TEXT,passed BOOLEAN,detail TEXT DEFAULT NULL) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO calc_assertions VALUES(n,name,COALESCE(passed,FALSE),detail);
 IF passed THEN
  RAISE NOTICE 'PASS %: %',n,name;
 ELSE
  RAISE NOTICE 'FAIL %: % (%)',n,name,detail;
 END IF;
END$$;

-- Seed synthetic patient and bills
INSERT INTO public.patients(id,uhid,mobile,full_name,gender,dob,address) VALUES
 ('99100000-0000-0000-0000-000000000001','9900000001','9800000001','Formula Female','Female','1986-01-01','Synthetic'),
 ('99100000-0000-0000-0000-000000000002','9900000002','9800000002','Missing Age','Female',NULL,'Synthetic'),
 ('99100000-0000-0000-0000-000000000003','9900000003','9800000003','Unsupported Sex','Other','1986-01-01','Synthetic');

INSERT INTO public.bills(id,bill_number,patient_id,patient_uhid_snapshot,patient_name_snapshot,patient_mobile_snapshot,patient_age_gender_snapshot,gross_amount_paisa,net_amount_paisa,paid_amount_paisa,due_amount_paisa)
VALUES
 ('99200000-0000-0000-0000-000000000001','CALC-1','99100000-0000-0000-0000-000000000001','991001','Formula Female','9800000001','40/F',0,0,0,0),
 ('99200000-0000-0000-0000-000000000002','CALC-2','99100000-0000-0000-0000-000000000002','991002','Missing Age','9800000002','?/F',0,0,0,0),
 ('99200000-0000-0000-0000-000000000003','CALC-3','99100000-0000-0000-0000-000000000003','991003','Unsupported Sex','9800000003','40/O',0,0,0,0);

INSERT INTO public.clinical_orders(id,bill_id,patient_id,order_number,order_date_ad,order_date_bs) VALUES
 ('99300000-0000-0000-0000-000000000001','99200000-0000-0000-0000-000000000001','99100000-0000-0000-0000-000000000001','CALC-ORDER-1','2026-01-01','synthetic'),
 ('99300000-0000-0000-0000-000000000002','99200000-0000-0000-0000-000000000002','99100000-0000-0000-0000-000000000002','CALC-ORDER-2','2026-01-01','synthetic'),
 ('99300000-0000-0000-0000-000000000003','99200000-0000-0000-0000-000000000003','99100000-0000-0000-0000-000000000003','CALC-ORDER-3','2026-01-01','synthetic');

CREATE OR REPLACE FUNCTION pg_temp.add_item(order_id UUID,test_code TEXT,item_id UUID,bill_item_id UUID) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE t public.tests%ROWTYPE; bill UUID;
BEGIN
 SELECT * INTO t FROM public.tests WHERE code=test_code;
 SELECT o.bill_id INTO bill FROM public.clinical_orders o WHERE o.id=order_id;
 INSERT INTO public.bill_items(id,bill_id,test_id,test_code_snapshot,test_name_snapshot,reporting_type,unit_price_paisa,net_price_paisa)
 VALUES(bill_item_id,bill,t.id,t.code,t.name,t.reporting_type,0,0);
 INSERT INTO public.clinical_order_items(id,order_id,bill_item_id,test_id,test_name,department,reporting_type,specimen_type,container_type,status,workflow_type,clinical_reporting_enabled,collection_required,result_revision)
 VALUES(item_id,order_id,bill_item_id,t.id,t.name,t.department,t.reporting_type,COALESCE(t.sample_type,''),COALESCE(t.container,''),'ResultDrafted',t.workflow_type,TRUE,FALSE,1);
 INSERT INTO public.test_results(order_item_id,parameter_id,parameter_name,unit,value_type,display_value,status)
 SELECT item_id,p.id,p.name,p.unit,p.value_type,CASE WHEN p.value_type='Calculated' THEN 'Pending calculation' ELSE '' END,'Draft'
 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active';
END$$;

CREATE OR REPLACE FUNCTION pg_temp.setval(p_item UUID,p_code TEXT,p_value NUMERIC) RETURNS VOID LANGUAGE sql AS $$
 UPDATE public.test_results tr SET numeric_value=p_value,display_value=p_value::TEXT
 FROM public.parameters p WHERE tr.parameter_id=p.id AND tr.order_item_id=p_item AND p.code=p_code;
$$;

CREATE OR REPLACE FUNCTION pg_temp.val(p_item UUID,p_code TEXT) RETURNS NUMERIC LANGUAGE sql AS $$
 SELECT tr.numeric_value FROM public.test_results tr
 JOIN public.parameters p ON p.id=tr.parameter_id
 WHERE tr.order_item_id=p_item AND p.code=p_code;
$$;

-- ---------------------------------------------------------------------------
-- TEST 1: Synthetic LFT Calculations
-- Total bilirubin 1.01, Direct bilirubin 0.25 -> Indirect = 0.76
-- Total protein 7.2, Albumin 4.2 -> Globulin = 3.00, A/G Ratio = 1.40
-- ---------------------------------------------------------------------------
SELECT pg_temp.add_item('99300000-0000-0000-0000-000000000001','LFT','99400000-0000-0000-0000-000000000012','99500000-0000-0000-0000-000000000012');
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000012','TBIL',1.01);
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000012','DBIL',0.25);
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000012','TP',7.2);
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000012','ALB',4.2);
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000012','SGOT',35);
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000012','SGPT',40);
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000012','ALP',120);

SELECT public.run_governed_order_item_calculations('99400000-0000-0000-0000-000000000012');

SELECT pg_temp.ok(1,'A. LFT Indirect Bilirubin 1.01 - 0.25 = 0.76',pg_temp.val('99400000-0000-0000-0000-000000000012','IBIL')=0.76);
SELECT pg_temp.ok(2,'B. LFT Globulin 7.2 - 4.2 = 3.00 and A/G = 1.40',pg_temp.val('99400000-0000-0000-0000-000000000012','GLOB')=3.00 AND pg_temp.val('99400000-0000-0000-0000-000000000012','AG_RATIO')=1.40);

-- ---------------------------------------------------------------------------
-- TEST 2: Direct > Total -> Safe validation failure
-- ---------------------------------------------------------------------------
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000012','DBIL',1.50);
SELECT public.run_governed_order_item_calculations('99400000-0000-0000-0000-000000000012');
SELECT pg_temp.ok(3,'C. Direct > Total blocks Indirect Bilirubin calculation',pg_temp.val('99400000-0000-0000-0000-000000000012','IBIL') IS NULL);

-- ---------------------------------------------------------------------------
-- TEST 3: Globulin = 0 -> A/G Ratio safely blocked (division by zero)
-- ---------------------------------------------------------------------------
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000012','DBIL',0.25);
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000012','TP',4.2);
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000012','ALB',4.2);
SELECT public.run_governed_order_item_calculations('99400000-0000-0000-0000-000000000012');
SELECT pg_temp.ok(4,'D. Globulin = 0 safely blocks AG Ratio division by zero',pg_temp.val('99400000-0000-0000-0000-000000000012','GLOB')=0.00 AND pg_temp.val('99400000-0000-0000-0000-000000000012','AG_RATIO') IS NULL);

-- ---------------------------------------------------------------------------
-- TEST 4: Missing Total Protein -> Exact blocker reported
-- ---------------------------------------------------------------------------
UPDATE public.test_results tr SET numeric_value=NULL,display_value=''
FROM public.parameters p WHERE tr.parameter_id=p.id AND tr.order_item_id='99400000-0000-0000-0000-000000000012' AND p.code='TP';
SELECT public.run_governed_order_item_calculations('99400000-0000-0000-0000-000000000012');
SELECT pg_temp.ok(5,'E. Missing Total Protein blocks Globulin & A/G ratio',pg_temp.val('99400000-0000-0000-0000-000000000012','GLOB') IS NULL AND pg_temp.val('99400000-0000-0000-0000-000000000012','AG_RATIO') IS NULL);

-- ---------------------------------------------------------------------------
-- TEST 5: Missing Albumin -> Exact blocker reported
-- ---------------------------------------------------------------------------
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000012','TP',7.2);
UPDATE public.test_results tr SET numeric_value=NULL,display_value=''
FROM public.parameters p WHERE tr.parameter_id=p.id AND tr.order_item_id='99400000-0000-0000-0000-000000000012' AND p.code='ALB';
SELECT public.run_governed_order_item_calculations('99400000-0000-0000-0000-000000000012');
SELECT pg_temp.ok(6,'F. Missing Albumin blocks Globulin & A/G ratio',pg_temp.val('99400000-0000-0000-0000-000000000012','GLOB') IS NULL AND pg_temp.val('99400000-0000-0000-0000-000000000012','AG_RATIO') IS NULL);

-- ---------------------------------------------------------------------------
-- TEST 6: Other Formula Tests Isolation
-- ---------------------------------------------------------------------------
-- Bilirubin T/D
SELECT pg_temp.add_item('99300000-0000-0000-0000-000000000001','BILIRUBIN_TD','99400000-0000-0000-0000-000000000011','99500000-0000-0000-0000-000000000011');
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000011','TOTAL_BILIRUBIN',1.2);
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000011','DIRECT_BILIRUBIN',0.3);
SELECT public.run_governed_order_item_calculations('99400000-0000-0000-0000-000000000011');
SELECT pg_temp.ok(7,'H1. BILIRUBIN_TD indirect bilirubin computed',pg_temp.val('99400000-0000-0000-0000-000000000011','INDIRECT_BILIRUBIN')=0.9);

-- Lipid Profile
SELECT pg_temp.add_item('99300000-0000-0000-0000-000000000001','LIPID_PROFILE','99400000-0000-0000-0000-000000000013','99500000-0000-0000-0000-000000000013');
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000013','CHOL',200);
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000013','TRIG',150);
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000013','HDL',50);
SELECT public.run_governed_order_item_calculations('99400000-0000-0000-0000-000000000013');
SELECT pg_temp.ok(8,'H2. Lipid Profile derived values computed (VLDL=30, TC/HDL=4, Non-HDL=150)',pg_temp.val('99400000-0000-0000-0000-000000000013','VLDL')=30 AND pg_temp.val('99400000-0000-0000-0000-000000000013','TC_HDL_RATIO')=4 AND pg_temp.val('99400000-0000-0000-0000-000000000013','NON_HDL')=150);

-- PT/INR
SELECT pg_temp.add_item('99300000-0000-0000-0000-000000000001','PT_INR','99400000-0000-0000-0000-000000000015','99500000-0000-0000-0000-000000000015');
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000015','PATIENT_PT',24);
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000015','CONTROL_TIME',12);
SELECT pg_temp.setval('99400000-0000-0000-0000-000000000015','ISI',1);
SELECT public.run_governed_order_item_calculations('99400000-0000-0000-0000-000000000015');
SELECT pg_temp.ok(9,'H3. PT/INR computed (INR=2.00)',pg_temp.val('99400000-0000-0000-0000-000000000015','INR')=2);

SELECT count(*) passed,count(*) FILTER(WHERE NOT passed) failed FROM calc_assertions;
DO $$BEGIN IF EXISTS(SELECT 1 FROM calc_assertions WHERE NOT passed) THEN RAISE EXCEPTION 'Formula runtime failures remain in 00093 acceptance'; END IF; END$$;
ROLLBACK;
