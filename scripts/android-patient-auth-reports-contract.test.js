import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(
  new URL('../supabase/migrations/00095_android_patient_auth_reports.sql', import.meta.url),
  'utf8'
);

test('migration 00095 header and forward ordering', () => {
  assert.match(migration, /00095_android_patient_auth_reports\.sql/);
});

test('defines Nepal mobile normalizer function', () => {
  assert.match(migration, /CREATE OR REPLACE FUNCTION public\.normalize_nepal_mobile/);
  assert.match(migration, /\(97\|98\)\[0-9\]\{8\}/);
});

test('defines patient_app_identities table with RLS and constraints', () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.patient_app_identities/);
  assert.match(migration, /auth_user_id UUID NOT NULL UNIQUE REFERENCES auth\.users/);
  assert.match(migration, /patient_id UUID REFERENCES public\.patients/);
  assert.match(migration, /status IN \('LINKED', 'NO_MATCH', 'REQUIRES_REVIEW'\)/);
  assert.match(migration, /ALTER TABLE public\.patient_app_identities ENABLE ROW LEVEL SECURITY/);
  assert.match(migration, /CREATE POLICY patient_app_identities_self_read/);
  assert.match(migration, /CREATE POLICY patient_app_identities_staff_read/);
});

test('defines sync_my_patient_identity with ambiguity protection', () => {
  assert.match(migration, /CREATE OR REPLACE FUNCTION public\.sync_my_patient_identity/);
  assert.match(migration, /auth\.uid\(\)/);
  assert.match(migration, /REQUIRES_REVIEW/);
  assert.match(migration, /NO_MATCH/);
  assert.match(migration, /LINKED/);
  assert.match(migration, /SECURITY DEFINER/);
});

test('defines get_my_patient_profile getter', () => {
  assert.match(migration, /CREATE OR REPLACE FUNCTION public\.get_my_patient_profile/);
});

test('defines list_my_report_orders deriving patient from auth.uid', () => {
  assert.match(migration, /CREATE OR REPLACE FUNCTION public\.list_my_report_orders/);
  assert.match(migration, /WHERE auth_user_id = v_uid AND status = 'LINKED'/);
  assert.match(migration, /p_limit/);
  assert.match(migration, /p_offset/);
  assert.match(migration, /order_number/);
  assert.match(migration, /overall_status/);
  assert.doesNotMatch(migration, /p_patient_id UUID/);
});

test('defines list_my_report_groups with Ready/Pending isolation', () => {
  assert.match(migration, /CREATE OR REPLACE FUNCTION public\.list_my_report_groups/);
  assert.match(migration, /WHERE id = p_order_id AND patient_id = v_patient_id/);
  assert.match(migration, /CASE WHEN art\.is_ready = true THEN 'Ready' ELSE 'Pending' END/);
  assert.match(migration, /pdf_sha256/);
  assert.doesNotMatch(migration, /test_results/);
  assert.doesNotMatch(migration, /parameter_name/);
  assert.doesNotMatch(migration, /display_value/);
});

test('defines authorize_my_report_pdf with strict patient ownership check', () => {
  assert.match(migration, /CREATE OR REPLACE FUNCTION public\.authorize_my_report_pdf/);
  assert.match(migration, /id = p_report_id/);
  assert.match(migration, /version = p_version/);
  assert.match(migration, /patient_id = v_patient_id/);
  assert.match(migration, /status IN \('SignedOff', 'Amended'\)/);
  assert.match(migration, /is_ready = true/);
  assert.match(migration, /Bimal-Pathology-/);
});

test('revokes public mutations and grants execute on patient RPCs to authenticated', () => {
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.sync_my_patient_identity\(\) TO authenticated/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.list_my_report_orders\(INT, INT\) TO authenticated/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.list_my_report_groups\(UUID\) TO authenticated/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.authorize_my_report_pdf\(UUID, INT\) TO authenticated/);
});
