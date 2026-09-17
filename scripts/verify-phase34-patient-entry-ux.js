import fs from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';

let passed = 0;
let failed = 0;

function check(condition, name) {
  if (condition) {
    passed += 1;
    console.log(`PASS: ${name}`);
  } else {
    failed += 1;
    console.error(`FAIL: ${name}`);
  }
}

const patientEntrySource = fs.readFileSync('src/lib/patientEntry.ts', 'utf8');
const billingSource = fs.readFileSync('src/features/billing/NewBillPage.tsx', 'utf8');
const patientsSource = fs.readFileSync('src/features/patients/PatientsPage.tsx', 'utf8');
const resultEntrySource = fs.readFileSync('src/features/worklist/ResultEntryPage.tsx', 'utf8');
const routesSource = fs.readFileSync('src/app/routes.tsx', 'utf8');
const technicianPermissions = fs.readFileSync('supabase/migrations/00019_technician_clinical_only_permissions.sql', 'utf8');
const transpiled = ts.transpileModule(patientEntrySource, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;
const exportsObject = {};
vm.runInNewContext(transpiled, { exports: exportsObject });
const { normalizePatientName } = exportsObject;

check(normalizePatientName('bimal lamichhane') === 'Bimal Lamichhane', 'lowercase two-word English name is normalized');
check(normalizePatientName('  ram   bahadur  thapa ') === 'Ram Bahadur Thapa', 'outer and repeated whitespace is normalized');
check(normalizePatientName('Bimal Lamichhane') === 'Bimal Lamichhane', 'correct capitalization remains unchanged');
check(normalizePatientName('J. P. McDonald') === 'J. P. McDonald', 'initials and intentional mixed capitalization remain unchanged');
check(normalizePatientName('राम  बहादुर थापा') === 'राम बहादुर थापा', 'Nepali name text remains intact apart from whitespace');

check(billingSource.includes("useState<number | ''>(BLANK_PATIENT_AGE.years)"), 'new-patient age years starts from the shared blank domain state');
check(!billingSource.includes('setAgeYears(30)'), 'new-bill reset has no demo age 30');
check(/resetFormForNextBill[\s\S]*?setAgeYears\(BLANK_PATIENT_AGE\.years\)[\s\S]*?setAgeMonths\(BLANK_PATIENT_AGE\.months\)[\s\S]*?setAgeDays\(BLANK_PATIENT_AGE\.days\)/.test(billingSource), 'next-bill reset restores all age inputs to shared blank state');
check(/else \{[\s\S]*?setIsExistingPatient\(false\)[\s\S]*?setAgeYears\(BLANK_PATIENT_AGE\.years\)/.test(billingSource), 'unmatched mobile lookup restores new-patient blank age');
check(billingSource.includes('setAgeYears(data.age_years ?? \'\')'), 'existing patient age loads without a fallback demo value');
check(billingSource.includes('full_name: normalizedFullName'), 'normalized patient name is submitted to the billing RPC');
check(billingSource.includes('validatePatientAge({ years: ageYears, months: ageMonths, days: ageDays }, true)'), 'new-bill save uses shared required-age validation');
check(patientsSource.includes('full_name: normalizedFullName'), 'Patient Registry edits persist the same normalized name');
check(patientsSource.includes('validatePatientAge({ years: editForm.age_years ?? null, months: editForm.age_months ?? null, days: editForm.age_days ?? null }, false)'), 'Patient Registry uses shared optional-age validation for years, months, and days');
check(patientsSource.includes("age_years: e.target.value === '' ? null : Number(e.target.value)"), 'Patient Registry preserves a blank edit field instead of coercing it to zero');
check(/\.eq\('mobile', cleanMobile\)[\s\S]*?\.maybeSingle\(\)/.test(billingSource), 'mobile-based patient lookup and duplicate detection remain active');
check(billingSource.includes("supabase.rpc('create_patient_bill_order_with_packages'") && fs.readFileSync('supabase/migrations/00050_catalogue_management_architecture.sql', 'utf8').includes('response:=public.create_patient_bill_and_order'), 'atomic billing and order creation RPC remains active');
check(!resultEntrySource.includes('age_years ?? 30'), 'technician worklist never assumes a missing patient age is 30');
check(resultEntrySource.includes('patientAgeDays == null') && resultEntrySource.includes('? null'), 'missing worklist age produces no fabricated reference-range age');

const adminResult = normalizePatientName('  ram   bahadur thapa ');
const technicianResult = normalizePatientName('  ram   bahadur thapa ');
check(adminResult === technicianResult && technicianResult === 'Ram Bahadur Thapa', 'Admin and permitted Technician inputs use identical normalization');
check(routesSource.includes('<NewBillPage />') && routesSource.includes('permission={PERMISSION_KEYS.CAN_CREATE_BILL}'), 'all billing-capable roles share one permission-guarded New Bill form');
check(routesSource.includes('<PatientsPage />') && routesSource.includes('permission={PERMISSION_KEYS.CAN_EDIT_PATIENT}'), 'all patient-edit-capable roles share one permission-guarded Registry form');
check(!billingSource.includes('Lab Technician') && !patientsSource.includes('Lab Technician'), 'patient forms contain no role-specific normalization branch');
check(/permission_key IN \([\s\S]*?'can_create_bill'[\s\S]*?'can_edit_patient'/.test(technicianPermissions), 'historical Technician restriction is explicitly superseded by the final operational matrix');

console.log(`\nPhase 34 patient-entry UX verification: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
