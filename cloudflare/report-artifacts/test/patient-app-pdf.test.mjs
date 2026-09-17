import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');

test('Patient app PDF endpoint pattern is registered in handleRequest', () => {
  assert.match(source, /patientAppPdf=url\.pathname\.match/);
  assert.match(source, /\/api\/patient-app\/reports/);
  assert.match(source, /servePatientAppPdf/);
});

test('Patient app PDF delivery enforces attachment disposition, private, no-store and nosniff', () => {
  assert.match(source, /authorize_patient_app_pdf_artifact/);
  assert.match(source, /attachment; filename=/);
  assert.match(source, /'content-disposition': disposition/);
  assert.match(source, /private, no-store/);
  assert.match(source, /nosniff/);
});