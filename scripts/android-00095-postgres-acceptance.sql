\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE verify_assertions(n INT PRIMARY KEY, name TEXT, passed BOOLEAN, detail TEXT);
CREATE OR REPLACE FUNCTION pg_temp.ok(n INT, name TEXT, passed BOOLEAN, detail TEXT DEFAULT NULL) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO verify_assertions VALUES(n, name, COALESCE(passed, FALSE), detail);
  IF passed THEN
    RAISE NOTICE 'PASS %: %', n, name;
  ELSE
    RAISE NOTICE 'FAIL %: % (%)', n, name, detail;
  END IF;
END$$;

-- Seed Patients
INSERT INTO public.patients (id, uhid, full_name, mobile, gender, dob, address)
VALUES
  ('a1111111-1111-1111-1111-111111111111', '2609010001', 'Patient Alice', '9811111111', 'Female', '1990-01-01', 'Bharatpur-7'),
  ('b2222222-2222-2222-2222-222222222222', '2609010002', 'Patient Bob', '9822222222', 'Male', '1985-05-15', 'Bharatpur-10'),
  ('d3333333-3333-3333-3333-333333333331', '2609010003', 'Ambiguous One', '9833333333', 'Female', '1992-02-02', 'Narayangarh'),
  ('d3333333-3333-3333-3333-333333333332', '2609010004', 'Ambiguous Two', '+9779833333333', 'Male', '1993-03-03', 'Tandi')
ON CONFLICT (id) DO NOTHING;

-- Seed Auth Users (staff)
INSERT INTO auth.users (id, email, phone, raw_user_meta_data)
VALUES ('99200000-0000-0000-0000-000000000001', 'tech@example.invalid', '9800000001', '{"full_name":"Test Tech"}')
ON CONFLICT (id) DO NOTHING;

UPDATE public.user_profiles SET is_active=true, is_super_admin=false WHERE id='99200000-0000-0000-0000-000000000001';

INSERT INTO public.reporting_personnel (id, user_id, full_name, professional_type, qualification, registration_council, registration_number, can_enter_results, can_verify_results, can_acknowledge_critical, can_sign_reports, is_active)
VALUES ('99200000-0000-0000-0000-000000000010', '99200000-0000-0000-0000-000000000001', 'Test Tech', 'Lab Technician', 'BMLT', 'NHPC', 'A-1234', true, true, true, true, true)
ON CONFLICT (id) DO NOTHING;

-- Seed Auth Users (patients)
INSERT INTO auth.users (id, email, phone, raw_user_meta_data)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'alice@patient.test', '+9779811111111', '{}'::jsonb),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bob@patient.test', '+9779822222222', '{}'::jsonb),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'unlinked@patient.test', '+9779800000000', '{}'::jsonb),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'ambiguous@patient.test', '+9779833333333', '{}'::jsonb)
ON CONFLICT (id) DO NOTHING;

-- Seed Bills and Clinical Orders
INSERT INTO public.bills (id, bill_number, patient_id, patient_uhid_snapshot, patient_name_snapshot, patient_mobile_snapshot, patient_age_gender_snapshot, gross_amount_paisa, net_amount_paisa, paid_amount_paisa, due_amount_paisa)
VALUES
  ('ba111111-1111-1111-1111-111111111111', 'BILL-2026-A1', 'a1111111-1111-1111-1111-111111111111', '2609010001', 'Patient Alice', '9811111111', '36/F', 150000, 150000, 150000, 0),
  ('bb222222-2222-2222-2222-222222222222', 'BILL-2026-B1', 'b2222222-2222-2222-2222-222222222222', '2609010002', 'Patient Bob', '9822222222', '41/M', 200000, 200000, 200000, 0)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.clinical_orders (id, bill_id, order_number, patient_id, order_date_ad, order_date_bs)
VALUES
  ('ea111111-1111-1111-1111-111111111111', 'ba111111-1111-1111-1111-111111111111', 'ORD-2026-A1', 'a1111111-1111-1111-1111-111111111111', '2026-09-01', '2083-05-16'),
  ('eb222222-2222-2222-2222-222222222222', 'bb222222-2222-2222-2222-222222222222', 'ORD-2026-B1', 'b2222222-2222-2222-2222-222222222222', '2026-09-02', '2083-05-17')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.clinical_report_groups (id, order_id, group_key, title, clinical_section, display_order, configuration_version, created_by)
VALUES
  ('9a111111-1111-4000-8000-111111111111', 'ea111111-1111-1111-1111-111111111111', 'lft', 'Liver Function Test (LFT)', 'Biochemistry', 1, 1, '99200000-0000-0000-0000-000000000001'),
  ('9a222222-2222-4000-8000-222222222222', 'ea111111-1111-1111-1111-111111111111', 'cbc', 'Complete Blood Count (CBC)', 'Hematology', 2, 1, '99200000-0000-0000-0000-000000000001'),
  ('9b111111-1111-4000-8000-111111111111', 'eb222222-2222-2222-2222-222222222222', 'lipid', 'Lipid Profile', 'Biochemistry', 1, 1, '99200000-0000-0000-0000-000000000001')
ON CONFLICT (id) DO NOTHING;

-- diagnostic_reports INSERT triggers queue_signed_report_artifact_trigger
-- which auto-creates Pending report_pdf_artifacts for SignedOff reports
INSERT INTO public.diagnostic_reports (id, order_id, report_group_id, patient_id, report_number, version, status, integrity_hash, performed_by_personnel_id, performed_by_personnel_name, verified_by_personnel_id, verified_by_personnel_name, signed_by_personnel_id, signed_by_personnel_name, clinical_snapshot_json, signed_at)
VALUES
  ('1a111111-1111-4000-8000-111111111111', 'ea111111-1111-1111-1111-111111111111', '9a111111-1111-4000-8000-111111111111', 'a1111111-1111-1111-1111-111111111111', 'REP-2026-A1', 1, 'SignedOff', repeat('a', 64), '99200000-0000-0000-0000-000000000010', 'Test Tech', '99200000-0000-0000-0000-000000000010', 'Test Tech', '99200000-0000-0000-0000-000000000010', 'Test Tech', '{}'::jsonb, now()),
  ('1a222222-2222-4000-8000-222222222222', 'ea111111-1111-1111-1111-111111111111', '9a222222-2222-4000-8000-222222222222', 'a1111111-1111-1111-1111-111111111111', 'REP-2026-A2', 1, 'Draft', repeat('b', 64), '99200000-0000-0000-0000-000000000010', 'Test Tech', '99200000-0000-0000-0000-000000000010', 'Test Tech', '99200000-0000-0000-0000-000000000010', 'Test Tech', '{}'::jsonb, now()),
  ('1b111111-1111-4000-8000-111111111111', 'eb222222-2222-2222-2222-222222222222', '9b111111-1111-4000-8000-111111111111', 'b2222222-2222-2222-2222-222222222222', 'REP-2026-B1', 1, 'SignedOff', repeat('c', 64), '99200000-0000-0000-0000-000000000010', 'Test Tech', '99200000-0000-0000-0000-000000000010', 'Test Tech', '99200000-0000-0000-0000-000000000010', 'Test Tech', '{}'::jsonb, now())
ON CONFLICT (id) DO NOTHING;

-- Promote auto-created Pending artifacts to Ready
UPDATE public.report_pdf_artifacts SET
  object_key = 'reports/2026/ea111111-1111-1111-1111-111111111111/v1/' || repeat('a', 64) || '.pdf',
  pdf_sha256 = repeat('a', 64),
  byte_size = 102400,
  mime_type = 'application/pdf',
  generated_at = now(),
  generation_status = 'Ready'
WHERE diagnostic_report_id = '1a111111-1111-4000-8000-111111111111' AND report_version = 1;

UPDATE public.report_pdf_artifacts SET
  object_key = 'reports/2026/eb222222-2222-2222-2222-222222222222/v1/' || repeat('b', 64) || '.pdf',
  pdf_sha256 = repeat('b', 64),
  byte_size = 204800,
  mime_type = 'application/pdf',
  generated_at = now(),
  generation_status = 'Ready'
WHERE diagnostic_report_id = '1b111111-1111-4000-8000-111111111111' AND report_version = 1;

-------------------------------------------------------------------------------
-- TEST 1: Mobile Normalizer Edge Cases
-- Run as postgres superuser (no role switch needed)
-------------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM pg_temp.ok(1, 'normalize_nepal_mobile standard 10 digit', public.normalize_nepal_mobile('9841234567') = '9841234567');
  PERFORM pg_temp.ok(2, 'normalize_nepal_mobile +977 prefix', public.normalize_nepal_mobile('+977-9841234567') = '9841234567');
  PERFORM pg_temp.ok(3, 'normalize_nepal_mobile 0 prefix', public.normalize_nepal_mobile('09841234567') = '9841234567');
  PERFORM pg_temp.ok(4, 'normalize_nepal_mobile 97 prefix', public.normalize_nepal_mobile('9741234567') = '9741234567');
  PERFORM pg_temp.ok(5, 'normalize_nepal_mobile invalid returns NULL', public.normalize_nepal_mobile('12345') IS NULL);
END $$;

-------------------------------------------------------------------------------
-- TEST 2: Patient A Linking & Report Access
-- RPCs are SECURITY DEFINER and use auth.uid() from request.jwt.claim.sub
-- No role switch needed; we set JWT claims only.
-------------------------------------------------------------------------------
DO $$
DECLARE
  v_prof JSONB;
  v_orders JSONB;
  v_groups JSONB;
  v_auth JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);
  PERFORM set_config('request.jwt.claim.phone', '+9779811111111', true);

  v_prof := public.sync_my_patient_identity();
  PERFORM pg_temp.ok(10, 'Patient A sync_my_patient_identity links', (v_prof->>'status') = 'LINKED' AND (v_prof->>'patient_id') = 'a1111111-1111-1111-1111-111111111111');
  PERFORM pg_temp.ok(11, 'Patient A get_my_patient_profile returns name', (public.get_my_patient_profile()->>'linked_patient_name') = 'Patient Alice');

  v_orders := public.list_my_report_orders(50, 0);
  PERFORM pg_temp.ok(12, 'Patient A list_my_report_orders returns 1 order', jsonb_array_length(v_orders) = 1 AND (v_orders->0->>'order_number') = 'ORD-2026-A1');
  PERFORM pg_temp.ok(13, 'Patient A order overall_status Partially Ready', (v_orders->0->>'overall_status') = 'Partially Ready');

  v_groups := public.list_my_report_groups('ea111111-1111-1111-1111-111111111111');
  PERFORM pg_temp.ok(14, 'Patient A list_my_report_groups returns 2 groups', jsonb_array_length(v_groups) = 2);
  PERFORM pg_temp.ok(15, 'Patient A Group 1 is Ready with report_id', (v_groups->0->>'status') = 'Ready' AND (v_groups->0->>'report_id') IS NOT NULL);
  PERFORM pg_temp.ok(16, 'Patient A Group 2 is Pending without report_id', (v_groups->1->>'status') = 'Pending' AND (v_groups->1->>'report_id') IS NULL);

  -- Authorize own Ready PDF
  v_auth := public.authorize_my_report_pdf('1a111111-1111-4000-8000-111111111111', 1);
  PERFORM pg_temp.ok(17, 'Patient A authorize_my_report_pdf returns authorized', (v_auth->>'authorized')::boolean = true);
  PERFORM pg_temp.ok(18, 'Patient A PDF URL uses /api/patient-app/reports/', (v_auth->>'delivery_url') LIKE 'https://dashboard.bimalpathology.com.np/api/patient-app/reports/%/pdf?filename=%');
  RAISE NOTICE 'DEBUG current_user=% session_user=% role=%', current_user, session_user, current_setting('role', true);
  PERFORM pg_temp.ok(19, 'Patient A PDF token recorded in patient_app_pdf_tokens', EXISTS(SELECT 1 FROM public.patient_app_pdf_tokens WHERE auth_user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));

  -- Cross-tenant order isolation
  PERFORM pg_temp.ok(20, 'Patient A listing Patient B order returns empty', jsonb_array_length(public.list_my_report_groups('eb222222-2222-2222-2222-222222222222')) = 0);

  -- Cross-tenant PDF authorization denial
  BEGIN
    PERFORM public.authorize_my_report_pdf('1b111111-1111-4000-8000-111111111111', 1);
    PERFORM pg_temp.ok(21, 'Patient A requesting Patient B PDF DENIED', false, 'Expected exception not raised');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.ok(21, 'Patient A requesting Patient B PDF DENIED', true);
  END;

  -- Random UUID denial
  BEGIN
    PERFORM public.authorize_my_report_pdf(gen_random_uuid(), 1);
    PERFORM pg_temp.ok(22, 'Random UUID PDF authorization DENIED', false, 'Expected exception not raised');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.ok(22, 'Random UUID PDF authorization DENIED', true);
  END;

  -- Pending report denial
  BEGIN
    PERFORM public.authorize_my_report_pdf('1a222222-2222-4000-8000-222222222222', 1);
    PERFORM pg_temp.ok(23, 'Draft/Pending PDF authorization DENIED', false, 'Expected exception not raised');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.ok(23, 'Draft/Pending PDF authorization DENIED', true);
  END;
END $$;

-------------------------------------------------------------------------------
-- TEST 3: Unlinked & Ambiguous Identity Scenarios
-------------------------------------------------------------------------------
DO $$
DECLARE
  v_prof JSONB;
BEGIN
  -- Unlinked User
  PERFORM set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', true);
  PERFORM set_config('request.jwt.claim.phone', '+9779800000000', true);

  v_prof := public.sync_my_patient_identity();
  PERFORM pg_temp.ok(30, 'Unlinked user status is NO_MATCH', (v_prof->>'status') = 'NO_MATCH' AND (v_prof->>'patient_id') IS NULL);
  PERFORM pg_temp.ok(31, 'Unlinked user list_my_report_orders returns empty', jsonb_array_length(public.list_my_report_orders(50, 0)) = 0);

  -- Ambiguous User (multiple matches)
  PERFORM set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', true);
  PERFORM set_config('request.jwt.claim.phone', '+9779833333333', true);

  v_prof := public.sync_my_patient_identity();
  PERFORM pg_temp.ok(32, 'Ambiguous user status is REQUIRES_REVIEW', (v_prof->>'status') = 'REQUIRES_REVIEW' AND (v_prof->>'patient_id') IS NULL);
  PERFORM pg_temp.ok(33, 'Ambiguous user match_count is 2', (v_prof->>'match_count')::int = 2);
  PERFORM pg_temp.ok(34, 'Ambiguous user candidate identities NOT leaked', (v_prof->>'linked_patient_name') IS NULL);
  PERFORM pg_temp.ok(35, 'Ambiguous user list_my_report_orders returns empty', jsonb_array_length(public.list_my_report_orders(50, 0)) = 0);
END $$;

-------------------------------------------------------------------------------
-- TEST 4: Anonymous Caller
-- auth.uid() returns NULL when request.jwt.claim.sub is empty -> RPCs return []
-------------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);

  PERFORM pg_temp.ok(40, 'Anonymous list_my_report_orders returns empty', jsonb_array_length(public.list_my_report_orders(50, 0)) = 0);
  PERFORM pg_temp.ok(41, 'Anonymous list_my_report_groups returns empty', jsonb_array_length(public.list_my_report_groups('ea111111-1111-1111-1111-111111111111')) = 0);
END $$;

-------------------------------------------------------------------------------
-- TEST 5: Worker PDF Authorization RPC
-------------------------------------------------------------------------------
DO $$
DECLARE
  v_tok_row public.patient_app_pdf_tokens%ROWTYPE;
  v_auth JSONB;
  v_expected_key TEXT;
BEGIN
  -- Re-set as Patient A to create a PDF token
  PERFORM set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);

  SELECT * INTO v_tok_row FROM public.patient_app_pdf_tokens LIMIT 1;

  -- Non-worker calling authorize_patient_app_pdf_artifact -> Denied
  v_auth := public.authorize_patient_app_pdf_artifact(v_tok_row.token_hash);
  PERFORM pg_temp.ok(50, 'Non-worker calling worker RPC is denied', (v_auth->>'authorized')::boolean = false);

  -- Seed Worker User
  INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'worker@bimalpathology.com.np', '{}'::jsonb) ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.user_profiles (id, email, full_name, is_active) VALUES ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'worker@bimalpathology.com.np', 'Artifact Worker', true) ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.system_settings (key, value) VALUES ('report_artifact_worker_email', '"worker@bimalpathology.com.np"'::jsonb) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

  PERFORM set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', true);

  v_auth := public.authorize_patient_app_pdf_artifact(v_tok_row.token_hash);
  v_expected_key := 'reports/2026/ea111111-1111-1111-1111-111111111111/v1/' || repeat('a', 64) || '.pdf';
  PERFORM pg_temp.ok(51, 'Worker calling worker RPC is authorized', (v_auth->>'authorized')::boolean = true);
  PERFORM pg_temp.ok(52, 'Worker returns object_key', (v_auth->>'object_key') = v_expected_key);

  -- Second call with same token -> Denied (consumed)
  v_auth := public.authorize_patient_app_pdf_artifact(v_tok_row.token_hash);
  PERFORM pg_temp.ok(53, 'Replaying consumed token is denied', (v_auth->>'authorized')::boolean = false);
END $$;

-------------------------------------------------------------------------------
-- TEST 6: Table RLS Guards
-- This test MUST switch to the authenticated role so RLS is enforced.
-- We use SAVEPOINT/ROLLBACK TO to restore the postgres role after.
-------------------------------------------------------------------------------
SAVEPOINT before_rls_test;
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  v_count INT;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);

  SELECT count(*) INTO v_count FROM public.patient_app_identities;
  -- We inline the assertion here since pg_temp.ok may not be callable as authenticated
  INSERT INTO verify_assertions VALUES(60, 'Patient A sees only own row in patient_app_identities', v_count = 1, 'got ' || v_count);
  IF v_count = 1 THEN
    RAISE NOTICE 'PASS 60: Patient A sees only own row in patient_app_identities';
  ELSE
    RAISE NOTICE 'FAIL 60: Patient A sees only own row in patient_app_identities (got %)', v_count;
  END IF;
END $$;
ROLLBACK TO before_rls_test;

SELECT count(*) AS total_assertions, count(*) FILTER (WHERE passed) AS passed, count(*) FILTER (WHERE NOT passed) AS failed FROM verify_assertions;
DO $$
DECLARE
  v_failed INT;
BEGIN
  SELECT count(*) INTO v_failed FROM verify_assertions WHERE NOT passed;
  IF v_failed > 0 THEN
    RAISE EXCEPTION '% assertions failed', v_failed;
  END IF;
END $$;
ROLLBACK;
