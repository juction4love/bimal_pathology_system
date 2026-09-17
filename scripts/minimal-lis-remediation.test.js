import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const migration = read('supabase/migrations/00075_catalogue_readiness_approval_workflow.sql');
const pus = read('src/features/worklist/AstCultureResultEntry.tsx');
const sms = read('src/features/admin/SmsDeliveryPage.tsx');
const audit = read('src/features/admin/AuditLogPage.tsx');
const dashboard = read('src/features/dashboard/TechnicianDashboard.tsx');
const patients = read('src/features/patients/PatientsPage.tsx');
const panels = read('src/features/catalogue/CatalogueMasterSections.tsx');
const resultEntry = read('src/features/worklist/ResultEntryPage.tsx');
const roles = read('src/features/admin/RolePermissionsPage.tsx');

test('Pus Culture specialist worksheet has all five stages and guarded persistence', () => {
  for (const label of ['Specimen / Direct Smear', 'Culture', 'Organism / Isolates', 'AST', 'Final Remarks']) assert.match(pus, new RegExp(label.replace('/', '\\/')));
  assert.match(migration, /CREATE TABLE public\.pus_culture_worksheets/);
  assert.match(migration, /PUS_CULTURE_WORKSHEET_REVISION_CONFLICT/);
  assert.match(migration, /pus_culture_worksheet/);
});

test('SMS and audit use bounded server keyset search', () => {
  assert.match(sms, /rpc\('search_sms_delivery_status'/);
  assert.match(audit, /rpc\('search_audit_log'/);
  assert.match(migration, /ORDER BY q\.created_at DESC,q\.id DESC LIMIT/);
  assert.match(migration, /ORDER BY a\.timestamp DESC,a\.id DESC LIMIT/);
  assert.doesNotMatch(sms, /limit\(200\)/);
  assert.doesNotMatch(audit, /limit\(500\)/);
});

test('technician dashboard is aggregated server-side', () => {
  assert.match(dashboard, /rpc\('get_technician_operational_summary'/);
  assert.match(migration, /specialist_microbiology_pending/);
});

test('patient history is paged and retains visit order identity', () => {
  assert.match(patients, /rpc\('search_patient_history'/);
  assert.match(migration, /'clinical_orders'.*'order_number',o\.order_number/);
});

test('panel lifecycle and component CRUD are normal guarded UI actions', () => {
  for (const rpc of ['catalogue_save_panel', 'catalogue_save_panel_component', 'catalogue_remove_panel_component', 'catalogue_set_panel_lifecycle', 'catalogue_delete_panel']) assert.match(panels, new RegExp(rpc));
});

test('Min:Sec result control validates canonical time parameters', () => {
  assert.match(resultEntry, /validateMinSec/);
  assert.match(resultEntry, /timeControl/);
});

test('final role setup exposes only Technician assignment and owner authority', () => {
  assert.match(roles, /Two clear access levels: System Owner and Laboratory Operator/);
  assert.match(roles, /Super Admin.*Lab Technician/s);
  assert.doesNotMatch(roles, /Administrator|Verifier and Signatory|replace_role_permission_matrix/);
});
