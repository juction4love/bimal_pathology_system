import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync('supabase/migrations/00089_catalogue_readiness_creation_handoff.sql', 'utf8');

test('new and subsequently edited tests enter readiness governance conservatively', () => {
  assert.match(migration, /AFTER INSERT OR UPDATE ON public\.tests/);
  assert.match(migration, /INSERT INTO public\.catalogue_service_readiness/);
  assert.match(migration, /ON CONFLICT\(test_id\) DO NOTHING/);
  assert.doesNotMatch(migration, /INSERT INTO public\.catalogue_service_readiness[\s\S]{0,300}\bSELECT\b/);
  assert.doesNotMatch(migration, /UPDATE public\.tests SET/);
  assert.doesNotMatch(migration, /'Approved'::public\.catalogue_readiness_state_enum/);
});

test('readiness invariant trigger has a fixed search path and no browser execution grant', () => {
  assert.match(migration, /SECURITY DEFINER\s+SET search_path=public,pg_temp/);
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.ensure_catalogue_test_readiness\(\) FROM PUBLIC,anon,authenticated,service_role/);
  assert.doesNotMatch(migration, /GRANT EXECUTE ON FUNCTION public\.ensure_catalogue_test_readiness/);
});

test('unused deletion removes only empty readiness metadata and preserves reviewed evidence', () => {
  assert.match(migration, /EXISTS\(SELECT 1 FROM public\.catalogue_configuration_evidence WHERE test_id=p_test_id\)/);
  assert.match(migration, /DELETE FROM public\.catalogue_service_readiness WHERE test_id=p_test_id/);
  assert.doesNotMatch(migration, /DELETE FROM public\.catalogue_configuration_evidence/);
  assert.match(migration, /Referenced tests or reviewed configurations cannot be deleted/);
});
