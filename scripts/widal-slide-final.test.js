import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync(new URL('../supabase/migrations_legacy_archive/00075_catalogue_readiness_approval_workflow.sql', import.meta.url), 'utf8');
const resultEntry = readFileSync(new URL('../src/features/worklist/ResultEntryPage.tsx', import.meta.url), 'utf8');

test('final WIDAL_SLIDE identity, parameters, options and metadata are exact', () => {
  assert.match(migration, /name='Widal Slide Method'/);
  assert.match(migration, /sample_type='Serum',container='Not specified',method='Slide Agglutination \/ Rapid Semi-Quantitative Screening'/);
  assert.match(migration, /\('WIDAL_TO','Salmonella typhi ''O''','Select',1/);
  assert.match(migration, /\('WIDAL_TH','Salmonella typhi ''H''','Select',2/);
  assert.match(migration, /\('WIDAL_AH','Salmonella paratyphi ''AH''','Select',3/);
  assert.match(migration, /\('WIDAL_BH','Salmonella paratyphi ''BH''','Select',4/);
  assert.match(migration, /\('WIDAL_IMPRESSION','Impression \/ Remarks','Text',5/);
  const labels = ['No Agglutination (< 1:20)', '1:20', '1:40', '1:80', '1:160', '1:320', '> 1:320'];
  for (const label of labels) assert.ok(migration.includes(label));
  assert.match(migration, /No clumping with 80 µL → < 1:20 → Non-Reactive \/ Negative/);
  assert.match(migration, /Technician independently reports titers and impression/);
  assert.match(migration, /WIDAL_TUBE_METHOD remains distinct/);
});

test('Result Entry renders configured selects, defaults and multiline controls', () => {
  assert.match(resultEntry, /select=\{param\.value_type === 'Select' && Boolean\(param\.options\?\.length\)\}/);
  assert.match(resultEntry, /param\.options\?\.map/);
  assert.match(resultEntry, /interpretation\.default_value/);
  assert.match(resultEntry, /multiline=\{param\.multiline\}/);
});
