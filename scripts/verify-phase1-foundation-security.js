import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');
const migration = read('supabase/migrations_legacy_archive/00050_catalogue_management_architecture.sql');
const auth = read('src/context/AuthContext.tsx');
const roles = read('src/features/admin/RolePermissionsPage.tsx');
const personnel = read('src/features/personnel/ReportingPersonnelPage.tsx');
const doctors = read('src/features/personnel/ReferringDoctorsPage.tsx');
let passed = 0;
const check = (condition, message) => { assert.ok(condition, message); passed += 1; };

const functionMatches = [...migration.matchAll(/CREATE OR REPLACE FUNCTION\s+public\.([a-z0-9_]+)\s*\(([^)]*)\)[\s\S]*?(?=\nCREATE OR REPLACE FUNCTION|\nREVOKE |\nCOMMENT ON|\n-- Reviewed identities)/gi)];
check(functionMatches.length >= 24, 'all 00050 functions are discoverable');
for (const match of functionMatches) {
  if (/SECURITY DEFINER/i.test(match[0])) check(/SET search_path=public,pg_temp/i.test(match[0]), `${match[1]} fixes search_path`);
}

check(/REVOKE ALL ON FUNCTION[\s\S]*FROM PUBLIC,anon,authenticated/.test(migration), '00050 functions start from deny-all execution');
check(/catalogue_test_missing_configuration[\s\S]*PERFORM public\.catalogue_require_manager\(\)/.test(migration), 'configuration inspection requires catalogue manager');
check(/catalogue_expand_package[\s\S]*can_create_bill/.test(migration), 'package expansion requires billing permission');
check(/search_billable_catalogue[\s\S]*can_create_bill/.test(migration), 'catalogue search requires billing permission');
check(/create_patient_bill_order_with_packages[\s\S]*can_create_bill/.test(migration), 'billing wrapper checks billing permission');
check(/REVOKE INSERT,UPDATE,DELETE ON public\.role_permissions,public\.reporting_personnel,public\.referring_doctors FROM authenticated/.test(migration), 'direct master mutations are revoked');
check(/replace_role_permission_matrix[\s\S]*can_manage_roles[\s\S]*FOR UPDATE/.test(migration), 'role replacement is authorized and locked');
check(/allowed_permissions TEXT\[\][\s\S]*NOT p=ANY\(allowed_permissions\)/.test(migration), 'role replacement rejects unknown permission keys');
check(/row_version BIGINT NOT NULL DEFAULT 1[\s\S]*catalogue_set_category_lifecycle\([^)]*p_expected_version/.test(migration), 'category lifecycle has optimistic concurrency');
check(/save_reporting_personnel[\s\S]*can_manage_personnel[\s\S]*REPORTING_PERSONNEL_SAVED/.test(migration), 'reporting personnel mutation is authorized and audited');
check(/save_referring_doctor[\s\S]*can_manage_referring_doctors[\s\S]*REFERRING_DOCTOR_SAVED/.test(migration), 'referring doctor mutation is authorized and audited');
check(!/from\('user_profiles'\)\.insert/.test(auth), 'signup does not directly activate/create a profile');
check(/migration 00048 is authoritative/.test(auth), 'signup documents database authority');
check(/System Owner/.test(roles) && /Lab Technician/.test(roles) && /cannot be changed/i.test(roles) && !/rpc\('replace_role_permission_matrix'/.test(roles) && !/from\('role_permissions'\)\s*\.delete\(/.test(roles), 'role UI presents the locked owner/operator model without mutation');
check(/rpc\('save_reporting_personnel'/.test(personnel) && !/from\('reporting_personnel'\)\s*\.(insert|update)\(/.test(personnel), 'personnel UI uses guarded RPC');
check(/rpc\('save_referring_doctor'/.test(doctors) && !/from\('referring_doctors'\)\s*\.(insert|update)\(/.test(doctors), 'doctor UI uses guarded RPC');
check(/LegacyDefaultRequiresValidation/.test(migration) && /ClinicallyValidated/.test(migration), 'range provenance states exist');
check(/WHERE method='Default reference interval - verify with analyzer\/reagent'/.test(migration), '00011 legacy rows are classified without value changes');

const draftSeedSection = migration.split('WITH draft(code,name,kind,category_code,notes) AS (VALUES')[1]?.split('INSERT INTO public.tests')[0] || '';
const draftCount = (draftSeedSection.match(/^ \('[A-Z0-9_]+',/gm) || []).length;
check(draftCount === 23, 'the 23 reviewed Draft identities remain represented');
const prioritySeed = migration.split('-- Priority investigation parameter shapes only.')[1]?.split('-- Specialized identities remain catalogue-only')[0] || '';
check(!/INSERT INTO public\.reference_ranges/.test(prioritySeed), 'priority seeds invent no reference ranges');
check(!/SERVER_INR/.test(migration), 'priority seeds invent no INR formula');

console.log(`Phase 1 foundation security: ${passed} passed, 0 failed`);
