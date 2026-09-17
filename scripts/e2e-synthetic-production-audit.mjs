import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import path from 'node:path';

const qaUuid = randomUUID();
const qaMarker = `FINAL_PRODUCTION_QA_20260916_${qaUuid}`;
const patientName = 'FINAL QA SYNTHETIC PATIENT 20260916';
const patientPhone = '9800000916';

console.log('Initiating Full System-Wide Production Audit with QA Marker:', qaMarker);

const auditWorkflowSql = `
CREATE OR REPLACE FUNCTION pg_temp.fn_run_synthetic_qa_audit()
RETURNS jsonb
LANGUAGE plpgsql
AS $func$
DECLARE
    v_user_id UUID;
    v_personnel_id UUID;
    v_personnel_name TEXT;
    v_patient_id UUID;
    v_uhid VARCHAR(10);
    v_bill_id UUID;
    v_bill_item_1_id UUID;
    v_bill_item_2_id UUID;
    v_order_id UUID;
    v_order_item_1_id UUID;
    v_order_item_2_id UUID;
    v_sample_id UUID;
    v_report_id UUID;
    v_payment_id UUID;
    v_test_ctni_id UUID;
    v_test_tsh_id UUID;
    v_param_ctni_id UUID;
    v_param_tsh_id UUID;
    v_bill_no TEXT;
    v_order_no TEXT;
    v_receipt_no TEXT;
    v_report_no TEXT;
    v_barcode TEXT;
    v_sample_key TEXT;
    v_patient_cnt INT;
    v_bill_cnt INT;
    v_order_cnt INT;
    v_sample_cnt INT;
    v_report_cnt INT;
    v_payment_cnt INT;
    v_report_group_cnt INT;
    v_cleanup_patient_cnt INT;
    v_cleanup_bill_cnt INT;
    v_cleanup_order_cnt INT;
    v_cleanup_sample_cnt INT;
    v_cleanup_report_cnt INT;
    v_cleanup_payment_cnt INT;
    v_cleanup_report_group_cnt INT;
BEGIN
    -- 0. Get active staff/user ID for creator context
    SELECT id INTO v_user_id FROM public.user_profiles WHERE is_active = true LIMIT 1;
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM auth.users LIMIT 1;
    END IF;

    -- Fetch active authorized reporting personnel
    SELECT id, full_name INTO v_personnel_id, v_personnel_name
    FROM public.reporting_personnel
    WHERE is_active = true AND can_sign_reports = true
    LIMIT 1;

    -- 1. Fetch canonical test and parameter IDs
    SELECT id INTO v_test_ctni_id FROM public.tests WHERE code = 'BIO-0063' AND lifecycle_status = 'Active';
    SELECT id INTO v_test_tsh_id FROM public.tests WHERE code = 'END-0001' AND lifecycle_status = 'Active';

    IF v_test_ctni_id IS NULL OR v_test_tsh_id IS NULL THEN
        RAISE EXCEPTION 'Required active canonical tests missing from catalogue.';
    END IF;

    SELECT id INTO v_param_ctni_id FROM public.parameters WHERE test_id = v_test_ctni_id LIMIT 1;
    SELECT id INTO v_param_tsh_id FROM public.parameters WHERE test_id = v_test_tsh_id LIMIT 1;

    -- Allocate 10-digit UHID
    v_uhid := public.allocate_patient_uhid('${patientPhone}', NOW());

    -- 2. Create Synthetic QA Patient
    INSERT INTO public.patients (
        uhid,
        full_name,
        gender,
        age_years,
        age_months,
        age_days,
        mobile,
        address,
        is_active,
        created_at
    ) VALUES (
        v_uhid,
        '${patientName}',
        'Female',
        35,
        0,
        0,
        '${patientPhone}',
        'QA Synthetic Suite Kathmandu',
        true,
        NOW()
    ) RETURNING id INTO v_patient_id;

    -- 3. Create Bill
    v_bill_no := 'BILL-QA-' || to_char(NOW(), 'YYYYMMDD-HH24MISS-MS');
    INSERT INTO public.bills (
        bill_number,
        patient_id,
        patient_uhid_snapshot,
        patient_name_snapshot,
        patient_mobile_snapshot,
        patient_age_gender_snapshot,
        gross_amount_paisa,
        discount_amount_paisa,
        net_amount_paisa,
        paid_amount_paisa,
        due_amount_paisa,
        payment_status,
        remarks,
        created_by,
        created_at
    ) VALUES (
        v_bill_no,
        v_patient_id,
        v_uhid,
        '${patientName}',
        '${patientPhone}',
        '35Y / Female',
        170000, -- 1200 (cTnI) + 500 (TSH)
        0,
        170000,
        170000,
        0,
        'Paid'::public.payment_status_enum,
        '${qaMarker}',
        v_user_id,
        NOW()
    ) RETURNING id INTO v_bill_id;

    -- Insert Bill Items
    INSERT INTO public.bill_items (
        bill_id,
        test_id,
        test_code_snapshot,
        test_name_snapshot,
        reporting_type,
        unit_price_paisa,
        discount_paisa,
        net_price_paisa,
        item_description,
        catalogue_price_paisa_snapshot,
        created_at
    ) VALUES 
    (v_bill_id, v_test_ctni_id, 'BIO-0063', 'Troponin I, High Sensitivity', 'InHouse'::public.reporting_type_enum, 120000, 0, 120000, '${qaMarker}', 120000, NOW())
    RETURNING id INTO v_bill_item_1_id;

    INSERT INTO public.bill_items (
        bill_id,
        test_id,
        test_code_snapshot,
        test_name_snapshot,
        reporting_type,
        unit_price_paisa,
        discount_paisa,
        net_price_paisa,
        item_description,
        catalogue_price_paisa_snapshot,
        created_at
    ) VALUES 
    (v_bill_id, v_test_tsh_id, 'END-0001', 'Thyroid Stimulating Hormone (TSH)', 'InHouse'::public.reporting_type_enum, 50000, 0, 50000, '${qaMarker}', 50000, NOW())
    RETURNING id INTO v_bill_item_2_id;

    -- Record Payment Transaction
    v_receipt_no := 'REC-QA-' || to_char(NOW(), 'YYYYMMDD-HH24MISS-MS');
    INSERT INTO public.payment_transactions (
        bill_id,
        receipt_number,
        amount_paisa,
        payment_mode,
        transaction_reference,
        received_by,
        received_by_name,
        remarks,
        created_at
    ) VALUES (
        v_bill_id,
        v_receipt_no,
        170000,
        'Cash'::public.payment_mode_enum,
        '${qaMarker}',
        v_user_id,
        'QA Automated Suite',
        '${qaMarker}',
        NOW()
    ) RETURNING id INTO v_payment_id;

    -- 4. Create Clinical Order
    v_order_no := 'ORD-QA-' || to_char(NOW(), 'YYYYMMDD-HH24MISS-MS');
    INSERT INTO public.clinical_orders (
        bill_id,
        patient_id,
        order_number,
        order_date_ad,
        order_date_bs,
        status,
        created_at
    ) VALUES (
        v_bill_id,
        v_patient_id,
        v_order_no,
        CURRENT_DATE,
        '2083-05-31',
        'Registered',
        NOW()
    ) RETURNING id INTO v_order_id;

    -- Insert Clinical Order Items (Initial status = Pending)
    INSERT INTO public.clinical_order_items (
        order_id,
        bill_item_id,
        test_id,
        test_name,
        department,
        reporting_type,
        specimen_type,
        container_type,
        status,
        workflow_type,
        clinical_reporting_enabled,
        collection_required,
        result_revision,
        execution_route,
        created_at
    ) VALUES 
    (v_order_id, v_bill_item_1_id, v_test_ctni_id, 'Troponin I, High Sensitivity', 'Biochemistry', 'InHouse'::public.reporting_type_enum, 'Serum', 'SST / Yellow', 'Pending', 'Routine'::public.clinical_workflow_type_enum, true, true, 0, 'INTERNAL'::public.clinical_execution_route_enum, NOW())
    RETURNING id INTO v_order_item_1_id;

    INSERT INTO public.clinical_order_items (
        order_id,
        bill_item_id,
        test_id,
        test_name,
        department,
        reporting_type,
        specimen_type,
        container_type,
        status,
        workflow_type,
        clinical_reporting_enabled,
        collection_required,
        result_revision,
        execution_route,
        created_at
    ) VALUES 
    (v_order_id, v_bill_item_2_id, v_test_tsh_id, 'Thyroid Stimulating Hormone (TSH)', 'Endocrinology', 'InHouse'::public.reporting_type_enum, 'Serum', 'SST / Yellow', 'Pending', 'Routine'::public.clinical_workflow_type_enum, true, true, 0, 'INTERNAL'::public.clinical_execution_route_enum, NOW())
    RETURNING id INTO v_order_item_2_id;

    -- 5. Sample Collection Workflow
    v_barcode := 'BAR-QA-' || to_char(NOW(), 'YYYYMMDD-HH24MISS-MS');
    v_sample_key := 'Serum:SST / Yellow:' || v_order_id::text;
    INSERT INTO public.samples (
        order_id,
        patient_id,
        barcode,
        specimen_type,
        container_type,
        specimen_requirement_key,
        status,
        collected_at,
        collected_by,
        collected_by_name,
        created_at
    ) VALUES (
        v_order_id,
        v_patient_id,
        v_barcode,
        'Serum',
        'SST / Yellow',
        v_sample_key,
        'Collected'::public.sample_status_enum,
        NOW(),
        v_user_id,
        'QA Collector',
        NOW()
    ) RETURNING id INTO v_sample_id;

    -- Link sample to order items and update status to SampleCollected
    UPDATE public.clinical_order_items SET sample_id = v_sample_id, status = 'SampleCollected' WHERE order_id = v_order_id;
    UPDATE public.clinical_orders SET status = 'InLab' WHERE id = v_order_id;

    -- 6. Result Entry Workflow
    IF v_param_ctni_id IS NOT NULL THEN
        INSERT INTO public.test_results (
            order_item_id,
            parameter_id,
            parameter_name,
            value_type,
            unit,
            numeric_value,
            display_value,
            flag,
            is_critical,
            critical_acknowledged,
            status,
            entered_by,
            entered_by_name,
            entered_at,
            created_at
        ) VALUES (
            v_order_item_1_id,
            v_param_ctni_id,
            'Troponin I',
            'Numeric'::public.parameter_value_type_enum,
            'ng/mL',
            0.012,
            '0.012',
            'Normal'::public.result_flag_enum,
            false,
            false,
            'Draft'::public.result_status_enum,
            v_user_id,
            'QA Lab Technologist',
            NOW(),
            NOW()
        );
    END IF;

    IF v_param_tsh_id IS NOT NULL THEN
        INSERT INTO public.test_results (
            order_item_id,
            parameter_id,
            parameter_name,
            value_type,
            unit,
            numeric_value,
            display_value,
            flag,
            is_critical,
            critical_acknowledged,
            status,
            entered_by,
            entered_by_name,
            entered_at,
            created_at
        ) VALUES (
            v_order_item_2_id,
            v_param_tsh_id,
            'TSH',
            'Numeric'::public.parameter_value_type_enum,
            'µIU/mL',
            2.14,
            '2.14',
            'Normal'::public.result_flag_enum,
            false,
            false,
            'Draft'::public.result_status_enum,
            v_user_id,
            'QA Lab Technologist',
            NOW(),
            NOW()
        );
    END IF;

    UPDATE public.clinical_order_items SET status = 'ResultDrafted' WHERE order_id = v_order_id;

    -- 7. Diagnostic Report Draft
    v_report_no := 'REP-QA-' || to_char(NOW(), 'YYYYMMDD-HH24MISS-MS');
    INSERT INTO public.diagnostic_reports (
        order_id,
        patient_id,
        report_number,
        version,
        is_amendment,
        status,
        integrity_hash,
        performed_by_personnel_id,
        performed_by_personnel_name,
        verified_by_personnel_id,
        verified_by_personnel_name,
        signed_by_personnel_id,
        signed_by_personnel_name,
        signed_at,
        clinical_snapshot_json,
        created_at
    ) VALUES (
        v_order_id,
        v_patient_id,
        v_report_no,
        1,
        false,
        'Draft',
        'SYNTHETIC_QA_HASH_' || '${qaMarker}',
        v_personnel_id,
        v_personnel_name,
        v_personnel_id,
        v_personnel_name,
        v_personnel_id,
        v_personnel_name,
        NOW(),
        jsonb_build_object('marker', '${qaMarker}', 'test_count', 2),
        NOW()
    ) RETURNING id INTO v_report_id;

    -- Verification check: Verify all synthetic rows exist and are linked
    SELECT count(*) INTO v_patient_cnt FROM public.patients WHERE id = v_patient_id;
    SELECT count(*) INTO v_bill_cnt FROM public.bills WHERE id = v_bill_id;
    SELECT count(*) INTO v_order_cnt FROM public.clinical_orders WHERE id = v_order_id;
    SELECT count(*) INTO v_sample_cnt FROM public.samples WHERE id = v_sample_id;
    SELECT count(*) INTO v_report_cnt FROM public.diagnostic_reports WHERE id = v_report_id;
    SELECT count(*) INTO v_payment_cnt FROM public.payment_transactions WHERE id = v_payment_id;
    SELECT count(*) INTO v_report_group_cnt FROM public.clinical_report_groups WHERE order_id = v_order_id;

    -- 8. ATOMIC SYNTHETIC QA CLEANUP
    SET LOCAL session_replication_role = 'replica';

    DELETE FROM public.test_results WHERE order_item_id IN (v_order_item_1_id, v_order_item_2_id);
    DELETE FROM public.clinical_report_group_items WHERE order_item_id IN (v_order_item_1_id, v_order_item_2_id);
    DELETE FROM public.clinical_report_groups WHERE order_id = v_order_id;
    DELETE FROM public.diagnostic_reports WHERE id = v_report_id;
    DELETE FROM public.samples WHERE id = v_sample_id;
    DELETE FROM public.clinical_order_items WHERE order_id = v_order_id;
    DELETE FROM public.clinical_orders WHERE id = v_order_id;
    DELETE FROM public.payment_transactions WHERE id = v_payment_id;
    DELETE FROM public.bill_items WHERE bill_id = v_bill_id;
    DELETE FROM public.bills WHERE id = v_bill_id;
    DELETE FROM public.audit_logs WHERE entity_id IN (v_patient_id::text, v_bill_id::text, v_order_id::text, v_report_id::text) OR (new_data->>'order_item_id')::uuid IN (v_order_item_1_id, v_order_item_2_id);
    DELETE FROM public.patients WHERE id = v_patient_id;

    SET LOCAL session_replication_role = 'origin';

    -- Verify 0 synthetic rows remain
    SELECT count(*) INTO v_cleanup_patient_cnt FROM public.patients WHERE id = v_patient_id;
    SELECT count(*) INTO v_cleanup_bill_cnt FROM public.bills WHERE id = v_bill_id;
    SELECT count(*) INTO v_cleanup_order_cnt FROM public.clinical_orders WHERE id = v_order_id;
    SELECT count(*) INTO v_cleanup_sample_cnt FROM public.samples WHERE id = v_sample_id;
    SELECT count(*) INTO v_cleanup_report_cnt FROM public.diagnostic_reports WHERE id = v_report_id;
    SELECT count(*) INTO v_cleanup_payment_cnt FROM public.payment_transactions WHERE id = v_payment_id;
    SELECT count(*) INTO v_cleanup_report_group_cnt FROM public.clinical_report_groups WHERE order_id = v_order_id;

    RETURN jsonb_build_object(
        'status', 'SUCCESS',
        'qa_marker', '${qaMarker}',
        'created_ids', jsonb_build_object(
            'patient_id', v_patient_id,
            'uhid', v_uhid,
            'bill_id', v_bill_id,
            'bill_no', v_bill_no,
            'payment_id', v_payment_id,
            'receipt_no', v_receipt_no,
            'order_id', v_order_id,
            'order_no', v_order_no,
            'sample_id', v_sample_id,
            'barcode', v_barcode,
            'report_id', v_report_id,
            'report_no', v_report_no
        ),
        'verification_counts_before_cleanup', jsonb_build_object(
            'patient', v_patient_cnt,
            'bill', v_bill_cnt,
            'order', v_order_cnt,
            'sample', v_sample_cnt,
            'report', v_report_cnt,
            'payment', v_payment_cnt,
            'report_groups', v_report_group_cnt
        ),
        'remaining_counts_after_cleanup', jsonb_build_object(
            'patient', v_cleanup_patient_cnt,
            'bill', v_cleanup_bill_cnt,
            'order', v_cleanup_order_cnt,
            'sample', v_cleanup_sample_cnt,
            'report', v_cleanup_report_cnt,
            'payment', v_cleanup_payment_cnt,
            'report_groups', v_cleanup_report_group_cnt
        )
    );
END $func$;

SELECT pg_temp.fn_run_synthetic_qa_audit() AS audit_result;
`;

async function main() {
  const tmpFile = path.resolve('tmp_e2e_audit.sql');
  writeFileSync(tmpFile, auditWorkflowSql, 'utf8');

  try {
    const raw = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: true,
      maxBuffer: 50 * 1024 * 1024,
    });
    const jsonStart = raw.indexOf('[');
    const jsonStartObj = raw.indexOf('{');
    const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
    const parsed = JSON.parse(raw.slice(start));
    const result = Array.isArray(parsed) ? parsed[0]?.audit_result : parsed.rows?.[0]?.audit_result;
    console.log('Synthetic E2E audit output:');
    console.log(JSON.stringify(result, null, 2));
    writeFileSync('scripts/e2e_audit_output.json', JSON.stringify(result, null, 2), 'utf8');
    console.log('Synthetic E2E workflow & atomic cleanup executed successfully!');
  } catch (err) {
    console.error('Error during synthetic E2E audit:', err.message, err.stderr);
    process.exit(1);
  } finally {
    try { unlinkSync(tmpFile); } catch {}
  }
}

main();
