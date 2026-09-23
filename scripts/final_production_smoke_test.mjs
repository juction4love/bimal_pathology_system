import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const PROJECT_REF = 'rncjxstujioagcezvfkb';

function runSql(sql) {
  const tmpFile = path.resolve('scripts/output/temp_smoke.sql');
  fs.writeFileSync(tmpFile, sql, 'utf8');
  try {
    const stdout = execSync(`npx supabase db query --linked -f "${tmpFile}"`, {
      encoding: 'utf8',
      maxBuffer: 50 * 1024 * 1024,
      stdio: ['pipe', 'pipe', 'pipe']
    });
    return stdout;
  } finally {
    if (fs.existsSync(tmpFile)) fs.unlinkSync(tmpFile);
  }
}

function parseSqlOutput(raw) {
  const marker = raw.indexOf('{');
  if (marker === -1) return null;
  try {
    return JSON.parse(raw.slice(marker));
  } catch {
    return null;
  }
}

async function main() {
  console.log('=== PHASE 31 & 32: FINAL SMOKE TEST & ADMIN BOUNDARY VERIFICATION ===');

  const smokeTestSql = `
DO $$
DECLARE
    v_patient_id UUID;
    v_bill_id UUID;
    v_bill_item_id UUID;
    v_order_id UUID;
    v_order_item_id UUID;
    v_test_id UUID;
    v_param_id UUID;
    v_sample_id UUID;
    v_report_id UUID;
    v_personnel_id UUID;
    v_personnel_name VARCHAR;
    v_tech_id UUID;
    seq_rec RECORD;
BEGIN
    SELECT id INTO v_tech_id FROM auth.users LIMIT 1;
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'HEM-0001' LIMIT 1;
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;

    -- 1. CREATE PATIENT
    INSERT INTO public.patients (
        uhid, full_name, age_years, gender, mobile, address
    ) VALUES (
        '9800000001', 'Smoke Test Patient', 35, 'Male', '9800000000', 'Bharatpur-10, Chitwan'
    ) RETURNING id INTO v_patient_id;

    -- 2. CREATE BILL & BILL ITEM
    INSERT INTO public.bills (
        patient_id, bill_number, patient_uhid_snapshot, patient_name_snapshot,
        patient_mobile_snapshot, patient_age_gender_snapshot,
        gross_amount_paisa, discount_amount_paisa,
        net_amount_paisa, paid_amount_paisa, due_amount_paisa, payment_status, created_by
    ) VALUES (
        v_patient_id, 'INV-2026-SMOKE-01', '9800000001', 'Smoke Test Patient',
        '9800000000', '35 Y / Male',
        50000, 0, 50000, 50000, 0, 'Paid', v_tech_id
    ) RETURNING id INTO v_bill_id;

    INSERT INTO public.bill_items (
        bill_id, test_id, test_code_snapshot, test_name_snapshot, reporting_type,
        unit_price_paisa, discount_paisa, net_price_paisa
    ) VALUES (
        v_bill_id, v_test_id, 'HEM-0001', 'Complete Blood Count', 'InHouse',
        50000, 0, 50000
    ) RETURNING id INTO v_bill_item_id;

    -- 3. CREATE CLINICAL ORDER & ORDER ITEM
    INSERT INTO public.clinical_orders (
        patient_id, bill_id, order_number, status, order_date_ad, order_date_bs
    ) VALUES (
        v_patient_id, v_bill_id, 'LAB-2026-SMOKE-01', 'InProgress', CURRENT_DATE, '2083-06-07'
    ) RETURNING id INTO v_order_id;

    INSERT INTO public.clinical_order_items (
        order_id, bill_item_id, test_id, test_name, department, reporting_type, specimen_type, container_type, status
    ) VALUES (
        v_order_id, v_bill_item_id, v_test_id, 'Complete Blood Count', 'Hematology', 'InHouse', 'Whole Blood EDTA', 'Lavender Top (EDTA)', 'Pending'
    ) RETURNING id INTO v_order_item_id;

    -- 4. CREATE SAMPLE
    INSERT INTO public.samples (
        order_id, patient_id, barcode, specimen_type, container_type, status, collected_at, collected_by
    ) VALUES (
        v_order_id, v_patient_id, 'SMP-2026-SMOKE-01', 'Whole Blood EDTA', 'Lavender Top (EDTA)', 'Collected', NOW(), v_tech_id
    ) RETURNING id INTO v_sample_id;

    -- 5. INSERT TEST RESULTS
    INSERT INTO public.test_results (
        order_item_id, parameter_id, parameter_name, unit, numeric_value, display_value, value_type, flag, status, entered_by, verified_by
    ) VALUES (
        v_order_item_id, v_param_id, 'Hemoglobin', 'g/dL', 14.5, '14.5', 'Numeric', 'Normal', 'Verified', v_tech_id, v_tech_id
    );

    SELECT id, full_name INTO v_personnel_id, v_personnel_name FROM public.reporting_personnel WHERE is_active = true LIMIT 1;

    -- 6. CREATE DIAGNOSTIC REPORT
    INSERT INTO public.diagnostic_reports (
        order_id, patient_id, report_number, integrity_hash, status,
        performed_by_personnel_id, performed_by_personnel_name,
        verified_by_personnel_id, verified_by_personnel_name,
        signed_by_personnel_id, signed_by_personnel_name,
        clinical_snapshot_json, signed_at
    ) VALUES (
        v_order_id, v_patient_id, 'REP-2026-SMOKE-01', '10e011eb2ddf9757e9beef903109e79cc28de9c167488a1a995df481ae3e4427', 'SignedOff',
        v_personnel_id, v_personnel_name,
        v_personnel_id, v_personnel_name,
        v_personnel_id, v_personnel_name,
        '{"investigations": []}'::jsonb, NOW()
    ) RETURNING id INTO v_report_id;

    -- 7. CLEAN UP SMOKE TEST TRANSACTION (EXPLICIT FIXTURE IDS ONLY)
    DELETE FROM public.diagnostic_reports WHERE id = v_report_id;
    DELETE FROM public.test_results WHERE order_item_id = v_order_item_id;
    DELETE FROM public.samples WHERE id = v_sample_id;
    DELETE FROM public.clinical_order_items WHERE id = v_order_item_id;
    DELETE FROM public.clinical_orders WHERE id = v_order_id;
    DELETE FROM public.bill_items WHERE id = v_bill_item_id;
    DELETE FROM public.bills WHERE id = v_bill_id;
    DELETE FROM public.patients WHERE id = v_patient_id;
END $$;
`;

  const smokeRes = runSql(smokeTestSql);
  console.log('Smoke test execution result:', smokeRes);

  // Post-smoke verification
  const verifySql = `
SELECT 
  (SELECT count(*) FROM public.patients) AS count_patients,
  (SELECT count(*) FROM public.bills) AS count_bills,
  (SELECT count(*) FROM public.clinical_orders) AS count_orders,
  (SELECT count(*) FROM public.samples) AS count_samples,
  (SELECT count(*) FROM public.test_results) AS count_results,
  (SELECT count(*) FROM public.diagnostic_reports) AS count_reports,
  (SELECT count(*) FROM public.audit_logs) AS count_audit_logs;
`;

  const verifyRes = runSql(verifySql);
  const parsed = parseSqlOutput(verifyRes);
  console.log('Post-smoke clean state counts:', JSON.stringify(parsed?.rows?.[0], null, 2));
}

main().catch(err => {
  console.error('Smoke test failed:', err);
  process.exit(1);
});
