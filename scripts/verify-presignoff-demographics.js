import fs from 'node:fs';
import assert from 'node:assert/strict';

const read = (path) => fs.readFileSync(path, 'utf8');
const patients = read('src/features/patients/PatientsPage.tsx');
const results = read('src/features/worklist/ResultEntryPage.tsx');
const signoff = read('supabase/migrations/00030_fix_optional_authorizer_runtime.sql');
const patientSecurity = read('supabase/migrations/00042_safe_patient_management.sql');
const correctionAudit = read('supabase/migrations/00045_presignoff_patient_demographic_audit.sql');
const payments = read('supabase/migrations/00043_payment_receivables_integrity.sql');
const reportReady = read('supabase/migrations/00041_standardize_report_ready_sms.sql');
const technician = read('supabase/migrations/00019_technician_clinical_only_permissions.sql');
let passed = 0;
const check = (name, fn) => { try { fn(); passed += 1; console.log(`PASS ${name}`); } catch (error) { console.error(`FAIL ${name}: ${error.message}`); process.exitCode = 1; } };

check('existing patient is edited by stable patient ID', () => assert.match(patients, /update_patient_demographics'[\s\S]*p_patient_id: selectedPatient\?\.id/));
check('UHID cannot be changed by demographics update', () => assert.doesNotMatch(patientSecurity, /UPDATE public\.patients SET uhid/));
check('pre-signoff report workspace offers the shared Registry editor', () => assert.match(results, /CAN_EDIT_PATIENT[\s\S]*!hasExistingReport[\s\S]*Correct demographics/));
check('Registry deep link opens the existing patient form', () => assert.match(patients, /routeParams\.get\('edit'\)[\s\S]*handleOpenEdit\(patient\)/));
check('return to report remounts and refreshes current demographics', () => assert.match(patients, /returnTo\?\.startsWith\('\/worklist\/entry\/'\)[\s\S]*navigate\(returnTo\)/));
check('draft workspace reads current patient demographics', () => assert.match(results, /patient:patients\(id, uhid, full_name, mobile, address, dob, gender, age_years, age_months, age_days\)/));
check('signoff reloads patient master by unchanged order patient ID', () => assert.match(signoff, /SELECT \* INTO v_patient FROM public\.patients WHERE id = v_order\.patient_id/));
check('signed snapshot freezes corrected demographics', () => ['uhid','full_name','mobile','gender','dob','age_years','age_months','age_days','address'].forEach(field => assert.ok(signoff.includes(`'${field}', v_patient.${field}`))));
check('integrity hash includes the frozen snapshot', () => assert.match(signoff, /v_hash_input := v_order\.order_number \|\| '\|v' \|\| v_version::TEXT \|\| '\|' \|\| v_snapshot::TEXT/));
check('patient edits never rewrite signed reports', () => assert.doesNotMatch(patientSecurity, /UPDATE public\.diagnostic_reports/));
check('future payment uses current corrected mobile', () => assert.match(payments, /SELECT \* INTO v_patient FROM public\.patients WHERE id=v_bill\.patient_id[\s\S]*v_patient\.mobile/));
check('historical SMS is never updated or resent by edit', () => assert.doesNotMatch(patientSecurity, /sms_queue_items|enqueue/));
check('ReportReady after correction uses current mobile', () => assert.match(reportReady, /SELECT \* INTO v_patient FROM public\.patients WHERE id = v_report\.patient_id[\s\S]*v_patient\.mobile/));
check('audit contains UHID and changed fields without demographic values', () => { assert.match(correctionAudit, /'uhid',v_old\.uhid,'changed_fields',v_changed/); assert.doesNotMatch(correctionAudit, /'old_mobile'|'new_mobile'/); });
check('server RBAC uses can_edit_patient and Technician receives the operational capability', () => { assert.match(patientSecurity, /has_permission\('can_edit_patient'\)/); assert.match(technician, /'can_edit_patient'/); });
check('duplicate patient count remains protected by normalized mobile uniqueness', () => { assert.match(correctionAudit, /different patient with this mobile number already exists/); assert.doesNotMatch(correctionAudit, /INSERT INTO public\.patients/); });

console.log(`\nPre-signoff demographics: ${passed} passed, ${process.exitCode ? 1 : 0} failed`);
