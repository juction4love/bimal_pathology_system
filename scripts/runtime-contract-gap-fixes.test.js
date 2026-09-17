import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const migration=readFileSync('supabase/migrations/00088_runtime_contract_gap_fixes.sql','utf8');

test('patient bill history uses the authoritative bill timestamp',()=>{
  assert.match(migration,/'bill_date',b\.created_at/);
  assert.doesNotMatch(migration,/b\.bill_date/);
});

test('rate archive CASE is explicitly cast to its enum',()=>{
  assert.match(migration,/CASE WHEN v_used THEN 'Inactive' ELSE 'Archived' END\)::public\.catalogue_rate_status_enum/);
});

test('artifact failure status is explicitly cast and keeps worker authorization',()=>{
  assert.match(migration,/CASE WHEN p_failure_code='R2_UPLOAD_FAILED' THEN 'UploadFailed' ELSE 'GenerationFailed' END\)::public\.report_artifact_status_enum/);
  assert.match(migration,/IF NOT public\.is_report_artifact_worker\(\)/);
});

test('function signatures, fixed search paths and narrow grants are preserved',()=>{
  assert.equal((migration.match(/SECURITY DEFINER SET search_path=public,pg_temp/g)||[]).length,4);
  assert.match(migration,/REVOKE ALL ON FUNCTION public\.search_patient_history[\s\S]*FROM PUBLIC,anon,service_role/);
  assert.match(migration,/REVOKE ALL ON FUNCTION public\.catalogue_delete_or_archive_rate[\s\S]*FROM PUBLIC,anon,service_role/);
  assert.match(migration,/REVOKE ALL ON FUNCTION public\.complete_report_pdf_artifact[\s\S]*FROM PUBLIC,anon,service_role/);
  assert.match(migration,/REVOKE ALL ON FUNCTION public\.catalogue_decide_readiness[\s\S]*FROM PUBLIC,anon,authenticated,service_role/);
});
