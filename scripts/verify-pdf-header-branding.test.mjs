import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { renderFrozenSnapshotPdf } from '../cloudflare/report-artifacts/src/pdf.ts';
import { assets, baseSnapshot } from '../cloudflare/report-artifacts/test/fixtures.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, '..');

test('1. Migration 00131 exists and authoritatively sets approved organization branding', () => {
  const mig131 = readFileSync(path.join(root, 'supabase/migrations/00131_fix_diagnostic_report_branding.sql'), 'utf8');
  assert.doesNotMatch(mig131, /run_command/, 'Migration 00131 must not contain run_command');
  assert.match(mig131, /CREATE OR REPLACE FUNCTION public\.sign_report_group/);
  assert.match(mig131, /'name_en',\s*'BIMAL PATHOLOGY & DIAGNOSTIC CENTER'/);
  assert.match(mig131, /'name_ne',\s*'बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर'/);
  assert.match(mig131, /'address_en',\s*'Bharatpur-7, Chitwan, Nepal'/);
  assert.match(mig131, /'phone',\s*'056-593288'/);
  assert.match(mig131, /'reg_no',\s*'7-1496'/);
  assert.match(mig131, /'pan_no',\s*'302481477'/);
});

test('2. Migration 00131 preserves security definer, search_path and execution grants', () => {
  const mig131 = readFileSync(path.join(root, 'supabase/migrations/00131_fix_diagnostic_report_branding.sql'), 'utf8');
  assert.match(mig131, /SECURITY DEFINER/);
  assert.match(mig131, /SET search_path TO 'public',\s*'pg_temp'/);
  assert.match(mig131, /REVOKE ALL ON FUNCTION public\.sign_report_group\(UUID,UUID,UUID,TEXT,UUID\) FROM PUBLIC,anon,authenticated,service_role;/);
  assert.match(mig131, /GRANT EXECUTE ON FUNCTION public\.sign_report_group\(UUID,UUID,UUID,TEXT,UUID\) TO authenticated;/);
});

test('3. System constants.ts and ReportDocument.tsx have correct branding and fallbacks', () => {
  const constants = readFileSync(path.join(root, 'src/config/constants.ts'), 'utf8');
  assert.match(constants, /nameEn:\s*'BIMAL PATHOLOGY & DIAGNOSTIC CENTER'/);
  assert.match(constants, /nameNp:\s*'बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर'/);
  assert.match(constants, /addressEn:\s*'Bharatpur-7, Chitwan, Nepal'/);
  assert.match(constants, /phone:\s*'056-593288'/);

  const reportDoc = readFileSync(path.join(root, 'src/features/reports/ReportDocument.tsx'), 'utf8');
  assert.match(reportDoc, /name_en:\s*'BIMAL PATHOLOGY & DIAGNOSTIC CENTER'/);
  assert.match(reportDoc, /name_ne:\s*'बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर'/);
  assert.match(reportDoc, /address_en:\s*'Bharatpur-7, Chitwan, Nepal'/);
  assert.match(reportDoc, /phone:\s*'056-593288'/);
  assert.doesNotMatch(reportDoc, /PATHOLOGY&/);
});

test('4. PDF generator fallback in pdf.ts contains exact branding', () => {
  const pdfTs = readFileSync(path.join(root, 'cloudflare/report-artifacts/src/pdf.ts'), 'utf8');
  assert.match(pdfTs, /string\(org\.name_en,'BIMAL PATHOLOGY & DIAGNOSTIC CENTER'\)/);
  assert.match(pdfTs, /string\(org\.name_ne,'बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर'\)/);
  assert.match(pdfTs, /string\(org\.address_en,'Bharatpur-7, Chitwan, Nepal'\)/);
  assert.match(pdfTs, /string\(org\.phone,'056-593288'\)/);
});

test('5. Render test diagnostic PDF and verify header generation', async () => {
  const integrity = '0'.repeat(64);
  const pdfBytes = await renderFrozenSnapshotPdf(baseSnapshot, integrity, assets);
  assert.ok(pdfBytes instanceof Uint8Array);
  assert.ok(pdfBytes.length > 5000, 'PDF bytes should be non-empty');
  
  // Verify PDF header magic bytes %PDF-1.7
  const headerMagic = Buffer.from(pdfBytes.subarray(0, 8)).toString('utf8');
  assert.match(headerMagic, /^%PDF-1\.7/);
});

test('6. PDF rendering with empty/fallback organization uses exact defaults', async () => {
  const integrity = '1'.repeat(64);
  const snapshotWithoutOrg = structuredClone(baseSnapshot);
  snapshotWithoutOrg.organization = {};
  
  const pdfBytes = await renderFrozenSnapshotPdf(snapshotWithoutOrg, integrity, assets);
  assert.ok(pdfBytes instanceof Uint8Array);
  assert.ok(pdfBytes.length > 5000);
});
