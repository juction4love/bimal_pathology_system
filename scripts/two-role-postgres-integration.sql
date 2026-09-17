\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(ok BOOLEAN, message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$ BEGIN IF NOT COALESCE(ok,FALSE) THEN RAISE EXCEPTION 'ASSERTION_FAILED: %',message; END IF; END $$;

INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
 ('90000000-0000-0000-0000-000000000001','admin.integration@example.invalid','{"full_name":"Integration Administrator"}'),
 ('90000000-0000-0000-0000-000000000002','tech.integration@example.invalid','{"full_name":"Integration Technician"}'),
 ('90000000-0000-0000-0000-000000000003','inactive.integration@example.invalid','{"full_name":"Inactive Technician"}'),
 ('90000000-0000-0000-0000-000000000004','super.integration@example.invalid','{"full_name":"Integration Super Admin"}');
UPDATE public.user_profiles SET is_active=TRUE,is_super_admin=(id='90000000-0000-0000-0000-000000000004')
WHERE id::TEXT LIKE '90000000-%';
INSERT INTO public.user_roles(user_id,role_id) VALUES
 ('90000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001'),
 ('90000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000004'),
 ('90000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004'),
 ('90000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;
UPDATE public.user_profiles SET is_active=FALSE WHERE id='90000000-0000-0000-0000-000000000003';

INSERT INTO public.reporting_personnel(
 id,user_id,full_name,professional_type,qualification,registration_council,registration_number,
 can_enter_results,can_verify_results,can_acknowledge_critical,can_sign_reports,is_active,display_order)
VALUES('91000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000002',
 'Integration Technician','Lab Technologist','BMLT','Integration Council','INT-TECH-1',
 TRUE,TRUE,TRUE,TRUE,TRUE,999);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000002',TRUE);

SELECT pg_temp.assert_true(public.is_active_user(),'Technician must be active');
SELECT pg_temp.assert_true(public.has_permission('can_create_bill'),'Technician billing permission');
SELECT pg_temp.assert_true(public.has_permission('can_edit_patient'),'Technician patient permission');
SELECT pg_temp.assert_true(public.has_permission('can_verify_results'),'Technician verification permission');
SELECT pg_temp.assert_true(public.has_permission('can_sign_reports'),'Technician signing permission');
SELECT pg_temp.assert_true(public.has_permission('can_amend_reports'),'Technician amendment permission');
SELECT pg_temp.assert_true(public.has_permission('can_view_financials'),'Technician operational financial access');
SELECT pg_temp.assert_true(NOT public.has_permission('can_manage_users'),'Technician user-admin restriction');
SELECT pg_temp.assert_true(NOT public.has_permission('can_manage_roles'),'Technician role-admin restriction');
SELECT pg_temp.assert_true(public.has_permission('can_manage_catalogue'),'Technician full catalogue authority');
SELECT pg_temp.assert_true(public.has_permission('can_view_audit_logs'),'Technician operational audit access');
SELECT pg_temp.assert_true(public.has_permission('can_view_hmis_reports'),'Technician HMIS operational access');

SELECT pg_temp.assert_true(EXISTS(SELECT 1 FROM public.search_billable_catalogue('aso',20) WHERE entity_type='Test'),'Technician billable catalogue RPC');
SELECT pg_temp.assert_true(EXISTS(SELECT 1 FROM public.catalogue_test_operational_state s JOIN public.tests t ON t.id=s.test_id WHERE t.code='ASO'),'Technician RLS-preserving operational-state view');

DO $$
DECLARE response JSONB; test_row public.tests%ROWTYPE; v_patient_id UUID; v_bill_id UUID; v_order_id UUID; v_sample_id UUID; v_item_id UUID; v_parameter_id UUID;
 result_payload JSONB; payment JSONB; signed JSONB; v_report_id UUID;
BEGIN
 SELECT * INTO test_row FROM public.tests WHERE code='ASO';
 response:=public.create_patient_bill_order_with_packages(
  jsonb_build_object('mobile','9812345678','full_name','Integration Workflow Patient','gender','Female','age_years',32,'age_months',0,'age_days',0,'address','Integration Test'),
  jsonb_build_object('referring_doctor_id',NULL,'referring_doctor_name_snapshot','Self / Walk-in','gross_amount_paisa',test_row.price_paisa,'discount_amount_paisa',0,'paid_amount_paisa',0,'order_date_bs','2083-05-15','remarks','two-role PostgreSQL integration'),
  ARRAY[jsonb_build_object('test_id',test_row.id,'unit_price_paisa',test_row.price_paisa,'discount_paisa',0,'zero_price_acknowledged',FALSE)],
  NULL,'two-role-integration-bill-1','[]'::JSONB);
 v_patient_id:=(response->>'patient_id')::UUID; v_bill_id:=(response->>'bill_id')::UUID;
 PERFORM pg_temp.assert_true(v_patient_id IS NOT NULL AND v_bill_id IS NOT NULL,'Patient and bill creation');
 PERFORM pg_temp.assert_true(EXISTS(SELECT 1 FROM public.search_patient_registry('9812345678','Active',NULL,NULL,20) r WHERE (r.item->>'id')::UUID=v_patient_id),'Patient registry search');
 SELECT co.id INTO v_order_id FROM public.clinical_orders co WHERE co.bill_id=v_bill_id;
 SELECT s.id INTO v_sample_id FROM public.samples s WHERE s.order_id=v_order_id;
 PERFORM public.transition_sample_lifecycle(v_sample_id,'Collected',NULL);
 PERFORM public.transition_sample_lifecycle(v_sample_id,'Received',NULL);
 SELECT oi.id INTO v_item_id FROM public.clinical_order_items oi WHERE oi.order_id=v_order_id;
 SELECT p.id INTO v_parameter_id FROM public.parameters p WHERE p.test_id=test_row.id AND p.is_active ORDER BY p.display_order LIMIT 1;
 result_payload:=jsonb_build_array(jsonb_build_object('parameter_id',v_parameter_id,'numeric_value','25','text_value',NULL,'display_value','25','flag','Normal','is_critical',FALSE,'critical_acknowledged',FALSE,'normal_range_text','Integration reference','normal_min',NULL,'normal_max',NULL,'critical_low',NULL,'critical_high',NULL));
 PERFORM public.save_test_results(v_item_id,result_payload,'SubmittedForVerification',NULL,NULL,0);
 PERFORM public.save_test_results(v_item_id,result_payload,'Verified',NULL,NULL,1);
 payment:=public.receive_bill_payment(v_bill_id,test_row.price_paisa,'Cash',NULL,'Integration payment','two-role-integration-payment-1');
 PERFORM pg_temp.assert_true((payment->>'receipt_number') IS NOT NULL AND (payment->>'payment_status')='Paid','Payment and receipt');
 signed:=public.sign_and_queue_diagnostic_report(v_order_id,'91000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001',NULL,NULL,repeat('a',64),'https://example.invalid/r/integration-token');
 v_report_id:=(signed->>'report_id')::UUID;
 PERFORM pg_temp.assert_true(EXISTS(SELECT 1 FROM public.diagnostic_reports dr WHERE dr.id=v_report_id AND dr.status='SignedOff' AND length(dr.integrity_hash)=64),'Final signed immutable report');
 PERFORM pg_temp.assert_true(EXISTS(SELECT 1 FROM public.diagnostic_reports dr WHERE dr.id=v_report_id),'Report view/print read path');
END $$;

DO $$ BEGIN
 BEGIN
  PERFORM public.replace_role_permission_matrix(jsonb_build_array(jsonb_build_object('role_id','00000000-0000-0000-0000-000000000004','permissions',jsonb_build_array('can_manage_users'))));
  RAISE EXCEPTION 'ASSERTION_FAILED: Technician role escalation unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.update_user_access('90000000-0000-0000-0000-000000000003',TRUE,FALSE,ARRAY['00000000-0000-0000-0000-000000000004']::UUID[]);
  RAISE EXCEPTION 'ASSERTION_FAILED: Technician user administration unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

SELECT set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000001',TRUE);
DO $$ BEGIN
 BEGIN PERFORM public.search_billable_catalogue('aso',20); RAISE EXCEPTION 'ASSERTION_FAILED: compatibility Administrator search succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
DO $$ BEGIN
 BEGIN
  PERFORM public.replace_role_permission_matrix(jsonb_build_array(jsonb_build_object('role_id','00000000-0000-0000-0000-000000000004','permissions',jsonb_build_array('can_create_bill','can_manage_users'))));
  RAISE EXCEPTION 'ASSERTION_FAILED: server accepted noncanonical Technician matrix';
 EXCEPTION WHEN check_violation OR insufficient_privilege THEN NULL; END;
END $$;

SELECT set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000004',TRUE);
SELECT pg_temp.assert_true(public.is_super_admin() AND EXISTS(SELECT 1 FROM public.search_billable_catalogue('aso',20)),'Super Admin catalogue search');

SELECT set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000003',TRUE);
DO $$ BEGIN
 BEGIN PERFORM public.search_billable_catalogue('aso',20); RAISE EXCEPTION 'ASSERTION_FAILED: inactive user search succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

RESET ROLE;
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claim.sub','',TRUE);
DO $$ BEGIN
 BEGIN PERFORM public.search_billable_catalogue('aso',20); RAISE EXCEPTION 'ASSERTION_FAILED: anonymous search succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

RESET ROLE;
SELECT 'two-role PostgreSQL integration: PASS' AS result;
ROLLBACK;
