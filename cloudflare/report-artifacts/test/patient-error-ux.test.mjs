import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { patientError } from '../src/patient-error.ts';

test('patient-facing malformed report link returns clear branded HTML without technical details', async () => {
  const response = patientError(404);
  const body = await response.text();
  assert.equal(response.status, 404);
  assert.match(response.headers.get('content-type') || '', /^text\/html/);
  assert.match(body, /Report link unavailable/);
  assert.match(body, /Bimal Pathology &amp; Diagnostic Center/);
  assert.match(body, /incorrect, expired, or replaced/);
  assert.doesNotMatch(body, /\{"error"|stack|SQL|PostgREST|R2/i);
});

test('patient route uses HTML errors while API route retains the controlled JSON contract', () => {
  const source = fs.readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
  assert.match(source, /if\(request\.method==='GET'&&api\)return serve\(env,api\[1\]\)/);
  assert.match(source, /if\(request\.method==='GET'&&patient\)return serve\(env,patient\[1\],true\)/);
});
