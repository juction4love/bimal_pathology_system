// scripts/verify-00099-catalogue-governance.mjs
// Verification suite for Migration 00099: Catalogue Clinical Activation Governance

import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';
import assert from 'node:assert/strict';

console.log('================================================================');
console.log('=== BIMAL PATHOLOGY LIS: MIGRATION 00099 GOVERNANCE AUDIT ===');
console.log('================================================================\n');

function runSqlFile(sql) {
  const tmpFile = path.resolve('tmp_gov_test.sql');
  writeFileSync(tmpFile, sql, 'utf8');
  try {
    const output = execSync(`npx supabase db query --linked -f "${tmpFile}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: true,
      maxBuffer: 20 * 1024 * 1024,
    });
    const jsonStart = output.indexOf('{');
    if (jsonStart === -1) return null;
    return JSON.parse(output.slice(jsonStart));
  } finally {
    try { unlinkSync(tmpFile); } catch {}
  }
}

// 1. Audit Database Baseline Counts
console.log('1. Auditing database baseline counts:');
const countSql = `
  SELECT json_build_object(
    'total_tests', count(*)::int,
    'req_val_tests', count(*) FILTER (WHERE validation_status = 'REQUIRES_VALIDATION')::int,
    'validated_tests', count(*) FILTER (WHERE validation_status = 'VALIDATED')::int,
    'active_tests', count(*) FILTER (WHERE is_active = TRUE)::int,
    'inactive_tests', count(*) FILTER (WHERE is_active = FALSE)::int
  ) as baseline
  FROM public.tests;
`;
const countRes = runSqlFile(countSql);
const counts = countRes?.rows?.[0]?.baseline || countRes?.[0]?.baseline;

console.log(`   - Total catalogue records      : ${counts.total_tests}`);
console.log(`   - REQUIRES_VALIDATION tests    : ${counts.req_val_tests}`);
console.log(`   - VALIDATED tests              : ${counts.validated_tests}`);
console.log(`   - ACTIVE (orderable) tests     : ${counts.active_tests}`);
console.log(`   - INACTIVE (non-orderable) tests: ${counts.inactive_tests}`);

assert.equal(counts.total_tests, 1122, 'Total tests must be exactly 1,122');
assert.equal(counts.req_val_tests, 1122, 'All tests must initially be in REQUIRES_VALIDATION state');
assert.equal(counts.validated_tests, 0, 'No unvalidated tests should have VALIDATED state initially');
assert.equal(counts.active_tests, 0, 'No unvalidated tests should be ACTIVE initially');
assert.equal(counts.inactive_tests, 1122, 'All unvalidated tests must be INACTIVE');
console.log('   -> PASS: Safe initial baseline verified (1122 total, 1122 REQUIRES_VALIDATION, 0 ACTIVE).\n');

// 2. Test Constraint Enforcement (Direct Update rejection)
console.log('2. Testing database-level constraint chk_tests_active_requires_validated:');
const testConstraintSql = `
  DO $$
  BEGIN
    UPDATE public.tests SET is_active = TRUE WHERE code = 'BIO-0001' AND validation_status = 'REQUIRES_VALIDATION';
    RAISE EXCEPTION 'CHECK_CONSTRAINT_FAILED_TO_BLOCK_ACTIVE_UNVALIDATED';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'SUCCESSFULLY_BLOCKED_BY_CHECK_CONSTRAINT';
  END $$;
`;
try {
  runSqlFile(testConstraintSql);
  console.log('   -> PASS: Direct activation of REQUIRES_VALIDATION test was strictly blocked by PostgreSQL CHECK constraint.\n');
} catch (err) {
  assert.fail('Constraint check failed to execute properly: ' + err.message);
}

// 3. Test RPC Activation Rejection for Unvalidated Test
console.log('3. Testing catalogue_set_test_lifecycle rejection on unvalidated test:');
const testRpcRejectSql = `
  DO $$
  DECLARE
    t_id UUID;
    v_num BIGINT;
    v_admin_id UUID;
  BEGIN
    -- Select an active administrator user ID for context
    SELECT id INTO v_admin_id FROM public.user_profiles WHERE is_active = TRUE LIMIT 1;
    IF v_admin_id IS NOT NULL THEN
      PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
      PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);
    END IF;

    SELECT id, row_version INTO t_id, v_num FROM public.tests WHERE code = 'BIO-0001';
    BEGIN
      PERFORM public.catalogue_set_test_lifecycle(t_id, 'Active'::public.catalogue_lifecycle_enum, v_num);
      RAISE EXCEPTION 'RPC_FAILED_TO_REJECT_UNVALIDATED_ACTIVATION';
    EXCEPTION
      WHEN check_violation OR sqlstate '23514' THEN
        RAISE NOTICE 'SUCCESSFULLY_REJECTED_BY_RPC_GUARD';
    END;
  END $$;
`;
try {
  runSqlFile(testRpcRejectSql);
  console.log('   -> PASS: catalogue_set_test_lifecycle strictly rejected activation of unvalidated test.\n');
} catch (err) {
  assert.fail('RPC rejection check failed: ' + err.message);
}

// 4. Test Search Billable Catalogue Gating
console.log('4. Testing search_billable_catalogue gating:');
const testSearchSql = `
  DO $$
  DECLARE
    v_admin_id UUID;
    search_count INT;
  BEGIN
    SELECT id INTO v_admin_id FROM public.user_profiles WHERE is_active = TRUE LIMIT 1;
    IF v_admin_id IS NOT NULL THEN
      PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
      PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);
    END IF;

    SELECT count(*) INTO search_count FROM public.search_billable_catalogue('Glucose', 20);
    IF search_count <> 0 THEN
      RAISE EXCEPTION 'UNVALIDATED_TESTS_FOUND_IN_BILLABLE_SEARCH';
    END IF;
  END $$;
`;
runSqlFile(testSearchSql);
console.log('   -> PASS: Unvalidated tests do not appear in billing catalogue search.\n');

// 5. Test End-to-End Governance Lifecycle Workflow
console.log('5. Testing full Governance Lifecycle Workflow (Validate -> Activate -> Search -> Invalidate):');
const lifecycleWorkflowSql = `
  DO $$
  DECLARE
    t_id UUID;
    p_id UUID;
    cat_id UUID;
    v_num BIGINT;
    s_count INT;
    v_admin_id UUID;
  BEGIN
    -- Set admin context
    SELECT id INTO v_admin_id FROM public.user_profiles WHERE is_active = TRUE LIMIT 1;
    IF v_admin_id IS NOT NULL THEN
      PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
      PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);
    END IF;

    -- Pick test BIO-0001
    SELECT id, row_version INTO t_id, v_num FROM public.tests WHERE code = 'BIO-0001';
    SELECT id INTO cat_id FROM public.test_categories LIMIT 1;
    SELECT id INTO p_id FROM public.parameters WHERE test_id = t_id LIMIT 1;

    -- Set category on test and prepare parameter reference range
    UPDATE public.tests SET category_id = cat_id WHERE id = t_id;
    IF p_id IS NOT NULL THEN
      UPDATE public.parameters SET clinical_configuration_status = 'Configured', unit_validation_required = FALSE, range_validation_required = FALSE, method_validation_required = FALSE WHERE id = p_id;
      INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, is_active, is_approved, validation_state, lifecycle_status)
      VALUES (p_id, 'All', 0, 43800, 70, 100, TRUE, TRUE, 'ClinicallyValidated', 'Active')
      ON CONFLICT DO NOTHING;
    END IF;

    -- A. Validate test (Transitions from REQUIRES_VALIDATION -> VALIDATED)
    SELECT row_version INTO v_num FROM public.tests WHERE id = t_id;
    PERFORM public.catalogue_validate_test(t_id, 'Clinical test validation acceptance note', v_num);
    IF (SELECT validation_status FROM public.tests WHERE id = t_id) <> 'VALIDATED' THEN
      RAISE EXCEPTION 'TEST_FAILED_TO_VALIDATE';
    END IF;

    -- B. Enable billing and reporting on validated test, then Activate
    UPDATE public.tests SET price_paisa = 50000, price_configured = TRUE, billing_enabled = TRUE, clinical_reporting_enabled = TRUE WHERE id = t_id;
    SELECT row_version INTO v_num FROM public.tests WHERE id = t_id;
    PERFORM public.catalogue_set_test_lifecycle(t_id, 'Active'::public.catalogue_lifecycle_enum, v_num);
    IF (SELECT is_active FROM public.tests WHERE id = t_id) <> TRUE THEN
      RAISE EXCEPTION 'TEST_FAILED_TO_ACTIVATE';
    END IF;

    -- C. Verify presence in billing search
    SELECT count(*) INTO s_count FROM public.search_billable_catalogue('Glucose', 20);
    IF s_count = 0 THEN
      RAISE EXCEPTION 'VALIDATED_ACTIVE_TEST_NOT_FOUND_IN_BILLING_SEARCH';
    END IF;

    -- D. Invalidate test (return to REQUIRES_VALIDATION)
    SELECT row_version INTO v_num FROM public.tests WHERE id = t_id;
    PERFORM public.catalogue_invalidate_test(t_id, 'Returned to review', v_num);
    IF (SELECT validation_status FROM public.tests WHERE id = t_id) <> 'REQUIRES_VALIDATION' THEN
      RAISE EXCEPTION 'TEST_FAILED_TO_INVALIDATE';
    END IF;
    IF (SELECT is_active FROM public.tests WHERE id = t_id) <> FALSE THEN
      RAISE EXCEPTION 'INVALIDATED_TEST_DID_NOT_DEACTIVATE';
    END IF;

    -- E. Verify removal from billing search
    SELECT count(*) INTO s_count FROM public.search_billable_catalogue('Glucose', 20);
    IF s_count <> 0 THEN
      RAISE EXCEPTION 'INVALIDATED_TEST_STILL_VISIBLE_IN_BILLING_SEARCH';
    END IF;

    -- Clean up test configuration back to pure baseline
    UPDATE public.tests SET category_id = NULL, billing_enabled = FALSE, clinical_reporting_enabled = FALSE WHERE id = t_id;
    IF p_id IS NOT NULL THEN
      DELETE FROM public.reference_ranges WHERE parameter_id = p_id;
    END IF;

    RAISE NOTICE 'LIFECYCLE_WORKFLOW_PASSED_CLEANLY';
  END $$;
`;
runSqlFile(lifecycleWorkflowSql);
console.log('   -> PASS: Complete Validate -> Activate -> Billing Search -> Invalidate -> Deactivate cycle verified.\n');

// 6. Final Clean Baseline Check
const finalRes = runSqlFile(countSql);
const finalCounts = finalRes?.rows?.[0]?.baseline || finalRes?.[0]?.baseline;
assert.equal(finalCounts.total_tests, 1122);
assert.equal(finalCounts.req_val_tests, 1122);
assert.equal(finalCounts.validated_tests, 0);
assert.equal(finalCounts.active_tests, 0);
assert.equal(finalCounts.inactive_tests, 1122);

console.log('================================================================');
console.log('=== ALL CATALOGUE CLINICAL ACTIVATION GOVERNANCE CHECKS PASSED ===');
console.log('================================================================');
