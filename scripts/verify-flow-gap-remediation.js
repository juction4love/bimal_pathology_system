import assert from 'node:assert/strict';
import fs from 'node:fs';

const headers = fs.readFileSync('public/_headers', 'utf8');
const patients = fs.readFileSync('src/features/patients/PatientsPage.tsx', 'utf8');
const reports = fs.readFileSync('src/features/reports/ReportsPage.tsx', 'utf8');
const worklist = fs.readFileSync('src/features/worklist/WorklistPage.tsx', 'utf8');
const migration = fs.readFileSync('supabase/migrations/00074_registry_payload_and_worklist_filter_continuity.sql', 'utf8');
const workerConfig = fs.readFileSync('cloudflare/report-artifacts/wrangler.toml', 'utf8');

assert.match(headers, /\/r\/\*[\s\S]*?Cache-Control: private, no-store/);
assert.match(headers, /\/r\/\*[\s\S]*?Content-Security-Policy:[^\n]*object-src 'none'/);
assert.match(headers, /\/r\/\*[\s\S]*?Referrer-Policy: no-referrer/);
assert.match(patients, /from\('patients'\)[\s\S]*?\.eq\('id', patientId\)[\s\S]*?\.eq\('is_active', true\)/);
assert.match(reports, /from\('diagnostic_reports'\)[\s\S]*?\.eq\('id', reportId\)/);
assert.match(worklist, /rpc\('list_laboratory_worklist_departments'/);
assert.match(migration, /'item_description',bi\.item_description/);
assert.match(migration, /list_laboratory_worklist_departments\(\)[\s\S]*?SECURITY INVOKER/);
const executableMigration = migration.replace(/^--.*$/gm, '');
assert.doesNotMatch(executableMigration, /\b(?:INSERT|UPDATE|DELETE)\b|sms_queue|report_pdf_artifacts/i);
assert.match(workerConfig, /dashboard\.bimalpathology\.com\.np\/\*/);
assert.doesNotMatch(workerConfig, /route intentionally deferred/i);
assert.match(workerConfig, /GENERATION_ENABLED = "true"/);

console.log('Flow-gap remediation contracts verified.');
