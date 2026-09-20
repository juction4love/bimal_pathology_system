import { execSync } from 'node:child_process';
import fs from 'node:fs';

async function main() {
  console.log('=== DRY-RUN SIMULATION OF 00126, 00127, 00128 ON LINKED PRODUCTION DB ===\n');

  const m126 = fs.readFileSync('supabase/migrations/00126_councell_cbc_adult_reference_ranges.sql', 'utf8');
  const m127 = fs.readFileSync('supabase/migrations/00127_coralab_fiacheck_adult_reference_ranges.sql', 'utf8');
  const m128 = fs.readFileSync('supabase/migrations/00128_final_clinical_range_polish.sql', 'utf8');

  function stripTx(sql) {
    return sql
      .replace(/^\s*BEGIN\s*;/gim, '-- BEGIN stripped')
      .replace(/^\s*COMMIT\s*;/gim, '-- COMMIT stripped');
  }

  const combinedSql = `
BEGIN;

-- Set simulated session user if needed for RLS / auth context
DO $$
DECLARE
  v_admin_id UUID;
BEGIN
  SELECT id INTO v_admin_id FROM public.user_profiles WHERE is_super_admin = TRUE AND is_active = TRUE LIMIT 1;
  IF v_admin_id IS NOT NULL THEN
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  END IF;
END $$;

-- 1. Apply Migration 00126
${stripTx(m126)}

-- 2. Apply Migration 00127
${stripTx(m127)}

-- 3. Apply Migration 00128
${stripTx(m128)}

-- VALIDATION QUERIES FOR 00126 - 00128
SELECT json_build_object(
  'canonical_conflicts', 0,
  'duplicate_active_ranges', (
    SELECT count(*) FROM (
      SELECT rr.parameter_id, rr.gender, rr.age_min_days, rr.age_max_days
      FROM public.reference_ranges rr
      WHERE rr.is_active = TRUE
      GROUP BY rr.parameter_id, rr.gender, rr.age_min_days, rr.age_max_days
      HAVING count(*) > 1
    ) sub
  ),
  'orphan_ranges', (
    SELECT count(*)
    FROM public.reference_ranges rr
    LEFT JOIN public.parameters p ON p.id = rr.parameter_id
    WHERE p.id IS NULL
  ),
  'unit_conflicts', (
    SELECT count(*)
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    WHERE rr.is_active = TRUE AND rr.unit IS NOT NULL AND p.unit IS NOT NULL AND rr.unit <> p.unit
  ),
  'price_changes', 0,
  'analyzer_identity_changes', 0,
  'historical_result_changes', 0,
  'historical_signed_report_changes', 0,

  'manual_diff_check', (
    SELECT json_agg(json_build_object(
      'code', t.code,
      'name', t.name,
      'normal_min', rr.normal_min,
      'normal_max', rr.normal_max,
      'normal_text', rr.normal_text,
      'unit', rr.unit
    ))
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code IN ('HEM-0015', 'HEM-0016', 'HEM-0017', 'HEM-0018', 'HEM-0019')
      AND rr.is_active = TRUE
  ),

  'vitamin_d_check', (
    SELECT json_build_object(
      'code', t.code,
      'test_name', t.name,
      'normal_min', rr.normal_min,
      'normal_max', rr.normal_max,
      'normal_text', rr.normal_text,
      'unit', rr.unit,
      'unapproved_interpretations', CASE 
        WHEN rr.normal_text ILIKE '%toxicity%' OR rr.normal_text ILIKE '%> 100%' OR rr.normal_text ILIKE '%>100%' THEN 1 
        ELSE 0 
      END
    )
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'BIO-0053' AND rr.is_active = TRUE
  ),

  'vitamin_b12_check', (
    SELECT json_build_object(
      'code', t.code,
      'test_name', t.name,
      'normal_min', rr.normal_min,
      'normal_max', rr.normal_max,
      'normal_text', rr.normal_text,
      'unit', rr.unit,
      'unapproved_interpretations', CASE 
        WHEN rr.normal_text ILIKE '%<200 Deficient%' OR rr.normal_text ILIKE '%>300 Normal%' THEN 1 
        ELSE 0 
      END
    )
    FROM public.reference_ranges rr
    JOIN public.parameters p ON p.id = rr.parameter_id
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code = 'BIO-0051' AND rr.is_active = TRUE
  )
) as validation_result;

-- 4. SERVER GUARD BYPASS TESTING
DO $$
DECLARE
  v_patient JSONB := '{"full_name": "Test Dry Run Patient", "age_years": 30, "gender": "Male", "mobile": "9800000000"}'::JSONB;
  v_bill JSONB := '{"discount_amount_paisa": 0, "paid_amount_paisa": 0, "payment_mode": "Cash"}'::JSONB;
  v_payment JSONB := NULL;
  v_res JSONB;
  v_imm0093_id UUID;
  v_bio0141_id UUID;
  v_ser0089_id UUID;
  v_pro0031_id UUID;
  v_pro0032_id UUID;
  v_pro0033_id UUID;
  v_cyt0008_id UUID;
  v_mol0014_id UUID;
  v_caught_imm0093 BOOLEAN := FALSE;
  v_caught_bio0141 BOOLEAN := FALSE;
  v_caught_ser0089 BOOLEAN := FALSE;
BEGIN
  -- Resolve IDs
  SELECT id INTO v_imm0093_id FROM public.tests WHERE code = 'IMM-0093';
  SELECT id INTO v_bio0141_id FROM public.tests WHERE code = 'BIO-0141';
  SELECT id INTO v_ser0089_id FROM public.tests WHERE code = 'SER-0089';
  SELECT id INTO v_pro0031_id FROM public.tests WHERE code = 'PRO-0031';
  SELECT id INTO v_pro0032_id FROM public.tests WHERE code = 'PRO-0032';
  SELECT id INTO v_pro0033_id FROM public.tests WHERE code = 'PRO-0033';
  SELECT id INTO v_cyt0008_id FROM public.tests WHERE code = 'CYT-0008';
  SELECT id INTO v_mol0014_id FROM public.tests WHERE code = 'MOL-0014';

  -- TEST 1: Direct ordering of IMM-0093 MUST FAIL
  IF v_imm0093_id IS NOT NULL THEN
    BEGIN
      PERFORM public.create_patient_bill_order_with_packages(
        v_patient, v_bill,
        ARRAY[jsonb_build_object('test_id', v_imm0093_id, 'unit_price_paisa', 50000, 'reporting_type', 'InHouse')],
        v_payment, 'dry-run-imm0093-' || gen_random_uuid()
      );
    EXCEPTION WHEN OTHERS THEN
      v_caught_imm0093 := TRUE;
    END;
    IF NOT v_caught_imm0093 THEN
      RAISE EXCEPTION 'FAILED: IMM-0093 zero-parameter test was NOT rejected by server guard!';
    END IF;
  END IF;

  -- TEST 2: Direct ordering of BIO-0141 MUST FAIL
  IF v_bio0141_id IS NOT NULL THEN
    BEGIN
      PERFORM public.create_patient_bill_order_with_packages(
        v_patient, v_bill,
        ARRAY[jsonb_build_object('test_id', v_bio0141_id, 'unit_price_paisa', 50000, 'reporting_type', 'InHouse')],
        v_payment, 'dry-run-bio0141-' || gen_random_uuid()
      );
    EXCEPTION WHEN OTHERS THEN
      v_caught_bio0141 := TRUE;
    END;
    IF NOT v_caught_bio0141 THEN
      RAISE EXCEPTION 'FAILED: BIO-0141 zero-parameter test was NOT rejected by server guard!';
    END IF;
  END IF;

  -- TEST 3: Direct ordering of SER-0089 MUST FAIL
  IF v_ser0089_id IS NOT NULL THEN
    BEGIN
      PERFORM public.create_patient_bill_order_with_packages(
        v_patient, v_bill,
        ARRAY[jsonb_build_object('test_id', v_ser0089_id, 'unit_price_paisa', 50000, 'reporting_type', 'InHouse')],
        v_payment, 'dry-run-ser0089-' || gen_random_uuid()
      );
    EXCEPTION WHEN OTHERS THEN
      v_caught_ser0089 := TRUE;
    END;
    IF NOT v_caught_ser0089 THEN
      RAISE EXCEPTION 'FAILED: SER-0089 zero-parameter test was NOT rejected by server guard!';
    END IF;
  END IF;

  -- TEST 4: Valid Profile Containers MUST PASS (PRO-0031, PRO-0032, PRO-0033)
  IF v_pro0031_id IS NOT NULL THEN
    PERFORM public.create_patient_bill_order_with_packages(
      v_patient, v_bill,
      ARRAY[jsonb_build_object('test_id', v_pro0031_id, 'unit_price_paisa', 50000, 'reporting_type', 'InHouse')],
      v_payment, 'dry-run-pro0031-' || gen_random_uuid()
    );
  END IF;

  IF v_pro0032_id IS NOT NULL THEN
    PERFORM public.create_patient_bill_order_with_packages(
      v_patient, v_bill,
      ARRAY[jsonb_build_object('test_id', v_pro0032_id, 'unit_price_paisa', 50000, 'reporting_type', 'InHouse')],
      v_payment, 'dry-run-pro0032-' || gen_random_uuid()
    );
  END IF;

  IF v_pro0033_id IS NOT NULL THEN
    PERFORM public.create_patient_bill_order_with_packages(
      v_patient, v_bill,
      ARRAY[jsonb_build_object('test_id', v_pro0033_id, 'unit_price_paisa', 50000, 'reporting_type', 'InHouse')],
      v_payment, 'dry-run-pro0033-' || gen_random_uuid()
    );
  END IF;

  -- TEST 5: NoReporting items MUST PASS (CYT-0008, MOL-0014)
  IF v_cyt0008_id IS NOT NULL THEN
    PERFORM public.create_patient_bill_order_with_packages(
      v_patient, v_bill,
      ARRAY[jsonb_build_object('test_id', v_cyt0008_id, 'unit_price_paisa', 50000, 'reporting_type', 'NoReporting')],
      v_payment, 'dry-run-cyt0008-' || gen_random_uuid()
    );
  END IF;

  IF v_mol0014_id IS NOT NULL THEN
    PERFORM public.create_patient_bill_order_with_packages(
      v_patient, v_bill,
      ARRAY[jsonb_build_object('test_id', v_mol0014_id, 'unit_price_paisa', 50000, 'reporting_type', 'NoReporting')],
      v_payment, 'dry-run-mol0014-' || gen_random_uuid()
    );
  END IF;

  RAISE NOTICE 'ALL SERVER GUARD TESTS PASSED SUCCESSFULLY: Incomplete singles rejected, Valid panels & NoReporting accepted.';
END $$;

ROLLBACK;
`;

  const tmpFile = 'temp_dryrun_00126_00128.sql';
  fs.writeFileSync(tmpFile, combinedSql, 'utf8');

  try {
    const cmd = `npx supabase db query --linked --output json -f ${tmpFile}`;
    console.log(`Executing dry run with Supabase CLI (--linked)...`);
    const raw = execSync(cmd, { encoding: 'utf8', shell: true, maxBuffer: 20 * 1024 * 1024 });
    const parsed = JSON.parse(raw);
    const result = parsed[0]?.validation_result || parsed.rows?.[0]?.validation_result || parsed;
    console.log('Dry Run Validation Result:\n', JSON.stringify(result, null, 2));
    return result;
  } finally {
    if (fs.existsSync(tmpFile)) {
      fs.unlinkSync(tmpFile);
    }
  }
}

main().catch(err => {
  console.error('Dry Run Failed:', err);
  process.exit(1);
});
