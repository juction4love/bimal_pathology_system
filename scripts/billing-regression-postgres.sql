\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(ok BOOLEAN, message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(ok, FALSE) THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: %', message;
  END IF;
END $$;

INSERT INTO auth.users(id,email,raw_user_meta_data)
VALUES ('92000000-0000-0000-0000-000000000001','billing.regression@example.invalid','{"full_name":"Billing Regression Administrator"}');
UPDATE public.user_profiles SET is_active=TRUE,is_super_admin=TRUE
WHERE id='92000000-0000-0000-0000-000000000001';
INSERT INTO public.user_roles(user_id,role_id)
VALUES ('92000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','92000000-0000-0000-0000-000000000001',TRUE);

DO $$
DECLARE
  test_row public.tests%ROWTYPE;
  response JSONB;
BEGIN
  SELECT * INTO test_row FROM public.tests
  WHERE lifecycle_status='Active' AND is_active AND billing_enabled AND price_paisa>0
  ORDER BY code LIMIT 1;
  response:=public.create_patient_bill_order_with_packages(
    jsonb_build_object('mobile','9811111111','full_name','Synthetic Billing Regression','gender','Other','age_years',30,'age_months',0,'age_days',0,'address','Synthetic'),
    jsonb_build_object('referring_doctor_id',NULL,'referring_doctor_name_snapshot','Self / Walk-in','gross_amount_paisa',test_row.price_paisa,'discount_amount_paisa',0,'paid_amount_paisa',test_row.price_paisa,'order_date_bs','2083-05-15','remarks','rollback-only regression'),
    ARRAY[jsonb_build_object('test_id',test_row.id,'unit_price_paisa',test_row.price_paisa,'discount_paisa',0,'zero_price_acknowledged',FALSE)],
    jsonb_build_object('payment_mode','Cash','transaction_reference',NULL,'remarks','rollback-only','received_by_name','Synthetic Operator'),
    'billing-regression-standard-paid','[]'::JSONB);
  PERFORM pg_temp.assert_true((response->>'payment_status')='Paid','paid-at-registration contract');
  PERFORM pg_temp.assert_true((response->>'sms_queued')::BOOLEAN,'BillRegistration SMS enqueue contract');
END $$;

DO $$
DECLARE
  svc RECORD;
  response JSONB;
BEGIN
  SELECT s.id,p.row_version,r.price_paisa INTO svc
  FROM public.catalogue_panel_services s
  JOIN public.catalogue_panels p ON p.id=s.panel_id
  JOIN public.catalogue_rate_versions r ON r.panel_service_id=s.id AND r.status='Active'
  WHERE s.lifecycle_status='Active'
    AND NOT EXISTS (SELECT 1 FROM public.catalogue_panel_service_components(s.id) c WHERE c.readiness<>'Ready')
  ORDER BY s.code LIMIT 1;
  PERFORM pg_temp.assert_true(svc.id IS NOT NULL,'ready panel fixture');
  response:=public.create_patient_bill_order_with_panel_service(
    jsonb_build_object('mobile','9822222222','full_name','Synthetic Panel Regression','gender','Other','age_years',31,'age_months',0,'age_days',0,'address','Synthetic'),
    jsonb_build_object('referring_doctor_id',NULL,'referring_doctor_name_snapshot','Self / Walk-in','gross_amount_paisa',svc.price_paisa,'discount_amount_paisa',0,'paid_amount_paisa',svc.price_paisa,'order_date_bs','2083-05-15','remarks','rollback-only panel regression'),
    jsonb_build_object('payment_mode','Cash','transaction_reference',NULL,'remarks','rollback-only','received_by_name','Synthetic Operator'),
    'billing-regression-panel-paid',svc.id,svc.row_version);
  PERFORM pg_temp.assert_true((response->>'gross_amount_paisa')::BIGINT=svc.price_paisa,'panel rate is authoritative bill gross');
  PERFORM pg_temp.assert_true((response->>'payment_status')='Paid','panel paid-at-registration contract');
END $$;

SELECT 'billing PostgreSQL regression: PASS' AS result;
ROLLBACK;
