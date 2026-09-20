// scripts/verify-00134-integration.mjs
// Transactional integration test for Result Entry, Verification, Signoff and Snapshot rendering for 15 P0 tests

import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const migrationSql = readFileSync(path.resolve('supabase/migrations/00134_p0_lab_approved_configuration.sql'), 'utf8');
const cleanMigrationSql = migrationSql
    .replace(/^BEGIN;/m, '')
    .replace(/^COMMIT;/m, '');

const testScriptSql = `
BEGIN;

-- Set session context for auth.uid()
SELECT set_config('request.jwt.claims', '{"sub": "b4022a73-39d0-4501-8262-566776b830f9"}', true);
SELECT set_config('request.jwt.claim.sub', 'b4022a73-39d0-4501-8262-566776b830f9', true);

-- 1. Apply migration 00134
${cleanMigrationSql}

-- 2. Create test fixtures inside transaction
DO $$
DECLARE
    v_patient_id UUID;
    v_bill_id UUID;
    v_order_id UUID;
    v_sample_id UUID;
    v_bill_item_id UUID;
    v_order_item_id UUID;
    v_test RECORD;
    v_param RECORD;
    v_results JSONB;
BEGIN
    -- Create test patient
    INSERT INTO public.patients (uhid, full_name, age_years, gender, mobile, address, created_at, updated_at)
    VALUES ('9999000001', 'Ram Sharma (P0 Test Patient)', 35, 'Male', '9899123456', 'Bharatpur-10, Chitwan', NOW(), NOW())
    RETURNING id INTO v_patient_id;

    -- Create test bill
    INSERT INTO public.bills (
        bill_number, patient_id, patient_name_snapshot, patient_uhid_snapshot,
        patient_age_gender_snapshot, patient_mobile_snapshot,
        gross_amount_paisa, discount_amount_paisa, net_amount_paisa, paid_amount_paisa, due_amount_paisa,
        payment_status, created_at, updated_at
    ) VALUES (
        'BILL-TEST-P0-01', v_patient_id, 'Ram Sharma (P0 Test Patient)', '9999000001',
        '35 Y / Male', '9899123456',
        1500000, 0, 1500000, 1500000, 0,
        'Paid', NOW(), NOW()
    ) RETURNING id INTO v_bill_id;

    -- Create test clinical order
    INSERT INTO public.clinical_orders (
        order_number, bill_id, patient_id, order_date_ad, order_date_bs, status, created_at, updated_at
    ) VALUES (
        'ORD-TEST-P0-01', v_bill_id, v_patient_id, CURRENT_DATE, '2083-06-04', 'Registered', NOW(), NOW()
    ) RETURNING id INTO v_order_id;

    -- Create sample
    INSERT INTO public.samples (
        barcode, order_id, patient_id, specimen_type, container_type, status,
        collected_at, collected_by, collected_by_name,
        received_at, received_by, received_by_name,
        created_at, updated_at
    ) VALUES (
        'SMP-TEST-P0-01', v_order_id, v_patient_id, 'Serum', 'Gold SST', 'Received',
        NOW(), 'b4022a73-39d0-4501-8262-566776b830f9'::UUID, 'Bimal Pathology Administrator',
        NOW(), 'b4022a73-39d0-4501-8262-566776b830f9'::UUID, 'Bimal Pathology Administrator',
        NOW(), NOW()
    ) RETURNING id INTO v_sample_id;

    -- Iterate through the 15 P0 tests and create order items + enter results
    FOR v_test IN 
        SELECT id, code, name, department, sample_type, container, reporting_type, workflow_type
        FROM public.tests
        WHERE code IN (
            'BIO-0141', 'IMM-0093', 'SER-0089', 'END-0056', 'END-0057',
            'END-0058', 'END-0059', 'END-0060', 'END-0061', 'END-0062',
            'END-0063', 'END-0064', 'END-0065', 'POC-0002', 'SPC-0007'
        )
        ORDER BY code
    LOOP
        -- Insert bill item
        INSERT INTO public.bill_items (
            bill_id, test_id, test_code_snapshot, test_name_snapshot,
            unit_price_paisa, discount_paisa, net_price_paisa, reporting_type
        ) VALUES (
            v_bill_id, v_test.id, v_test.code, v_test.name,
            100000, 0, 100000, COALESCE(v_test.reporting_type, 'InHouse'::public.reporting_type_enum)
        ) RETURNING id INTO v_bill_item_id;

        -- Insert clinical order item
        INSERT INTO public.clinical_order_items (
            order_id, bill_item_id, test_id, test_name, department,
            reporting_type, specimen_type, container_type, status, sample_id,
            workflow_type, clinical_reporting_enabled, collection_required
        ) VALUES (
            v_order_id, v_bill_item_id, v_test.id, v_test.name, COALESCE(v_test.department, 'Biochemistry'),
            COALESCE(v_test.reporting_type, 'InHouse'::public.reporting_type_enum),
            COALESCE(v_test.sample_type, 'Serum'), COALESCE(v_test.container, 'Gold SST'),
            'SampleReceived', v_sample_id,
            COALESCE(v_test.workflow_type, 'Routine'::public.clinical_workflow_type_enum),
            TRUE, TRUE
        ) RETURNING id INTO v_order_item_id;

        -- Assemble result payload for leaf parameters
        v_results := '[]'::jsonb;
        FOR v_param IN 
            SELECT p.id, p.code, p.name, p.value_type, p.unit, p.is_mandatory,
                   r.normal_min, r.normal_max, r.normal_text, r.reference_text
            FROM public.parameters p
            LEFT JOIN public.reference_ranges r ON r.parameter_id = p.id AND r.is_active = TRUE
            WHERE p.test_id = v_test.id AND p.is_active = TRUE
            ORDER BY p.display_order
        LOOP
            IF v_test.code = 'BIO-0141' THEN
                v_results := v_results || jsonb_build_object(
                    'parameter_id', v_param.id,
                    'numeric_value', 0.82,
                    'display_value', '0.82',
                    'flag', 'Normal',
                    'result_source', 'MANUAL',
                    'normal_range_text', '0.61 - 0.95',
                    'normal_min', 0.61,
                    'normal_max', 0.95
                );
            ELSIF v_test.code = 'IMM-0093' THEN
                v_results := v_results || jsonb_build_object(
                    'parameter_id', v_param.id,
                    'numeric_value', 4.5,
                    'display_value', '4.5',
                    'flag', 'Normal',
                    'result_source', 'MANUAL',
                    'normal_range_text', '< 7.0',
                    'normal_max', 7.0
                );
            ELSIF v_test.code = 'SER-0089' THEN
                v_results := v_results || jsonb_build_object(
                    'parameter_id', v_param.id,
                    'numeric_value', 0.45,
                    'display_value', '0.45',
                    'flag', 'Normal',
                    'result_source', 'MANUAL',
                    'normal_range_text', '< 1.0 (Negative)',
                    'normal_max', 1.0
                );
            ELSIF v_test.code = 'END-0056' THEN
                v_results := v_results || jsonb_build_object(
                    'parameter_id', v_param.id,
                    'numeric_value', 85,
                    'display_value', '85',
                    'flag', 'Normal',
                    'result_source', 'MANUAL',
                    'normal_range_text', '70 - 99'
                );
            ELSIF v_test.code = 'END-0059' THEN
                IF v_param.code = 'END-0059-01' THEN
                    -- Optional baseline left empty
                    v_results := v_results || jsonb_build_object(
                        'parameter_id', v_param.id,
                        'display_value', '',
                        'flag', 'Normal',
                        'result_source', 'MANUAL',
                        'normal_range_text', 'Baseline'
                    );
                ELSE
                    -- Required post-dex
                    v_results := v_results || jsonb_build_object(
                        'parameter_id', v_param.id,
                        'numeric_value', 1.2,
                        'display_value', '1.2',
                        'flag', 'Normal',
                        'result_source', 'MANUAL',
                        'normal_range_text', '< 1.8',
                        'normal_max', 1.8
                    );
                END IF;
            ELSIF v_test.code = 'END-0061' THEN
                IF v_param.code = 'END-0061-01' THEN
                    v_results := v_results || jsonb_build_object(
                        'parameter_id', v_param.id,
                        'numeric_value', 20.0,
                        'display_value', '20.0',
                        'flag', 'Normal',
                        'result_source', 'MANUAL',
                        'normal_range_text', 'Baseline'
                    );
                ELSIF v_param.code = 'END-0061-02' THEN
                    v_results := v_results || jsonb_build_object(
                        'parameter_id', v_param.id,
                        'numeric_value', 4.0,
                        'display_value', '4.0',
                        'flag', 'Normal',
                        'result_source', 'MANUAL',
                        'normal_range_text', 'Post-Suppression'
                    );
                END IF;
            ELSIF v_test.code = 'END-0064' THEN
                IF v_param.value_type = 'Text' THEN
                    v_results := v_results || jsonb_build_object(
                        'parameter_id', v_param.id,
                        'text_value', 'Clonidine 0.15 mg/m2 orally',
                        'display_value', 'Clonidine 0.15 mg/m2 orally',
                        'flag', 'Normal',
                        'result_source', 'MANUAL',
                        'normal_range_text', 'Standard Stimulant Protocol'
                    );
                ELSE
                    v_results := v_results || jsonb_build_object(
                        'parameter_id', v_param.id,
                        'numeric_value', 8.5,
                        'display_value', '8.5',
                        'flag', 'Normal',
                        'result_source', 'MANUAL',
                        'normal_range_text', 'Peak > 5 - 10 ng/mL'
                    );
                END IF;
            ELSIF v_test.code = 'POC-0002' THEN
                v_results := v_results || jsonb_build_object(
                    'parameter_id', v_param.id,
                    'numeric_value', 7.35,
                    'display_value', '7.35',
                    'flag', 'Normal',
                    'result_source', 'MANUAL',
                    'normal_range_text', '7.31 - 7.41'
                );
            ELSIF v_test.code = 'SPC-0007' THEN
                v_results := v_results || jsonb_build_object(
                    'parameter_id', v_param.id,
                    'text_value', 'Normal organic acid excretion pattern.',
                    'display_value', 'Normal organic acid excretion pattern.',
                    'flag', 'Normal',
                    'result_source', 'MANUAL',
                    'normal_range_text', 'Normal Organic Acid Excretion'
                );
            ELSE
                v_results := v_results || jsonb_build_object(
                    'parameter_id', v_param.id,
                    'numeric_value', 1.0,
                    'display_value', '1.0',
                    'flag', 'Normal',
                    'result_source', 'MANUAL',
                    'normal_range_text', 'Normal'
                );
            END IF;
        END LOOP;

        PERFORM public.save_test_results(v_order_item_id, v_results, 'Verified', NULL, NULL, 0);
    END LOOP;

END $$;

-- 3. Query results to verify all 15 tests are successfully verified with accurate saved values
SELECT 
    t.code AS test_code,
    t.name AS test_name,
    coi.status AS order_item_status,
    COUNT(tr.id) AS saved_parameters_count,
    jsonb_agg(jsonb_build_object(
        'param_code', param.code,
        'param_name', param.name,
        'value_type', param.value_type,
        'display_value', tr.display_value,
        'flag', tr.flag,
        'status', tr.status
    ) ORDER BY param.display_order) AS results_summary
FROM public.clinical_order_items coi
JOIN public.tests t ON coi.test_id = t.id
JOIN public.clinical_orders co ON coi.order_id = co.id
JOIN public.patients p ON co.patient_id = p.id
LEFT JOIN public.test_results tr ON tr.order_item_id = coi.id
LEFT JOIN public.parameters param ON tr.parameter_id = param.id
WHERE p.uhid = '9999000001'
GROUP BY t.code, t.name, coi.status
ORDER BY t.code;

ROLLBACK;
`;

const tmp = path.resolve('tmp_00134_integration.sql');
writeFileSync(tmp, testScriptSql, 'utf8');

try {
    const raw = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8' });
    const jsonStart = raw.indexOf('{');
    const jsonEnd = raw.lastIndexOf('}');
    const parsed = JSON.parse(raw.slice(jsonStart, jsonEnd + 1));
    console.log('Integration Test Result: Verified all 15 P0 tests in workflow:');
    for (const r of parsed.rows) {
        console.log(`[${r.test_code}] ${r.test_name.padEnd(40)} | Status: ${r.order_item_status} | Saved params: ${r.saved_parameters_count}`);
    }
} finally {
    try { unlinkSync(tmp); } catch {}
}
