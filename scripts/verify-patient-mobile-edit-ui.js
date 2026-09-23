import fs from 'node:fs';
import assert from 'node:assert/strict';

const read = (path) => fs.readFileSync(path, 'utf8');
const page = read('src/features/patients/PatientsPage.tsx');
const m42 = read('supabase/migrations_legacy_archive/00042_safe_patient_management.sql');
const m43 = read('supabase/migrations_legacy_archive/00043_payment_receivables_integrity.sql');
const m45 = read('supabase/migrations_legacy_archive/00045_presignoff_patient_demographic_audit.sql');
const signoff = read('supabase/migrations_legacy_archive/00030_fix_optional_authorizer_runtime.sql');
const reportReady = read('supabase/migrations_legacy_archive/00041_standardize_report_ready_sms.sql');
const technician = read('supabase/migrations_legacy_archive/00019_technician_clinical_only_permissions.sql');
let passed = 0;
const check = (name, fn) => { try { fn(); passed += 1; console.log(`PASS ${name}`); } catch (error) { console.error(`FAIL ${name}: ${error.message}`); process.exitCode = 1; } };

check('edit state loads current patient mobile', () => assert.match(page, /mobile: patient\.mobile/));
check('existing demographics dialog exposes required telephone field', () => assert.match(page, /type="tel"[\s\S]{0,160}name="mobile"[\s\S]{0,160}label="Mobile Number"[\s\S]{0,160}value=\{editForm\.mobile \|\| ''\}/));
check('mobile field is editable and normalized centrally', () => { assert.match(page, /setEditForm\(\{ \.\.\.editForm, mobile: e\.target\.value \}\)/); assert.match(page, /normalizeNepalMobile\(editForm\.mobile\)/); });
check('malformed Nepal mobile is validated before RPC save', () => assert.match(page, /validateNepalMobile\(editForm\.mobile\)[\s\S]*if \(mobileError\)[\s\S]*supabase\.rpc/));
check('normalized mobile is sent through secured demographics RPC', () => assert.match(page, /mobile: normalizedMobile[\s\S]*update_patient_demographics/));
check('duplicate mobile is rejected without merge', () => assert.match(m45, /different patient with this mobile number already exists[\s\S]*never auto-merged/i));
check('patient UUID and UHID remain stable', () => { assert.match(page, /p_patient_id: selectedPatient\?\.id/); assert.doesNotMatch(m45, /SET[\s\S]{0,300}uhid\s*=/); });
check('historical snapshots remain untouched', () => assert.doesNotMatch(m45, /UPDATE public\.(bills|payment_transactions|sms_queue_items|diagnostic_reports)/));
check('future payments resolve current patient mobile', () => assert.match(m43, /SELECT \* INTO v_patient FROM public\.patients WHERE id=v_bill\.patient_id[\s\S]*v_patient\.mobile/));
check('pre-signoff snapshot and ReportReady use corrected mobile', () => { assert.match(signoff, /'mobile', v_patient\.mobile/); assert.match(reportReady, /SELECT \* INTO v_patient FROM public\.patients WHERE id = v_report\.patient_id[\s\S]*v_patient\.mobile/); });
check('audit records mobile field name without number values', () => { assert.match(m45, /array_append\(v_changed,'mobile'\)/); assert.doesNotMatch(m45, /old_mobile|new_mobile/); });
check('unauthorized roles are denied server-side', () => { assert.match(m45, /has_permission\('can_edit_patient'\)/); assert.match(technician, /'can_edit_patient'/); assert.match(m42, /DROP POLICY IF EXISTS "patients_update"/); });
check('dialog grid stacks safely on phones and pairs mobile with email on larger screens', () => { assert.match(page, /<Grid item xs=\{12\} sm=\{6\}>[\s\S]{0,500}name="mobile"/); assert.match(page, /name="mobile"[\s\S]{0,700}<Grid item xs=\{12\} sm=\{6\}>[\s\S]{0,300}label="Email Address"/); });

console.log(`\nPatient mobile edit UI: ${passed} passed, ${process.exitCode ? 1 : 0} failed`);
