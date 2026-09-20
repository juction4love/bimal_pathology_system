// scripts/verify-full-catalogue-billing.mjs
import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const sql = `
DO $$
DECLARE
    v_patient_data JSONB;
    v_bill_data JSONB;
    v_items_data JSONB[];
    v_payment_data JSONB;
    v_idempotency_key TEXT := 'test_full_cat_' || gen_random_uuid()::text;
    v_res JSONB;
    v_creat_id UUID;
    v_cbc_id UUID;
    v_widal_id UUID;
    v_fbs_id UUID;
    v_urine_id UUID;
    v_unconf_id UUID;
    v_bill_id UUID;
BEGIN
    SELECT id INTO v_creat_id FROM public.tests WHERE code = 'BIO-0010';
    SELECT id INTO v_cbc_id FROM public.tests WHERE code = 'HEM-0001';
    SELECT id INTO v_widal_id FROM public.tests WHERE code = 'SER-0024';
    SELECT id INTO v_fbs_id FROM public.tests WHERE code = 'BIO-0001';
    SELECT id INTO v_urine_id FROM public.tests WHERE code = 'CLP-0001';
    SELECT id INTO v_unconf_id FROM public.tests WHERE id NOT IN (SELECT test_id FROM public.parameters WHERE is_active = TRUE) LIMIT 1;

    v_patient_data := jsonb_build_object(
        'full_name', 'Catalogue Expansion Test Patient',
        'age', 35,
        'age_unit', 'Years',
        'gender', 'Male',
        'mobile_number', '9899001122'
    );

    v_bill_data := jsonb_build_object(
        'discount_paisa', 0,
        'remarks', 'Verification of full catalogue billing'
    );

    v_items_data := ARRAY[
        jsonb_build_object('test_id', v_creat_id, 'unit_price_paisa', 20000, 'item_type', 'Test'),
        jsonb_build_object('test_id', v_cbc_id, 'unit_price_paisa', 40000, 'item_type', 'Test'),
        jsonb_build_object('test_id', v_widal_id, 'unit_price_paisa', 35000, 'item_type', 'Test'),
        jsonb_build_object('test_id', v_fbs_id, 'unit_price_paisa', 15000, 'item_type', 'Test'),
        jsonb_build_object('test_id', v_urine_id, 'unit_price_paisa', 20000, 'item_type', 'Test')
    ];

    IF v_unconf_id IS NOT NULL THEN
        v_items_data := v_items_data || jsonb_build_object('test_id', v_unconf_id, 'unit_price_paisa', 50000, 'item_type', 'Test');
    END IF;

    v_payment_data := jsonb_build_object(
        'amount_paisa', 180000,
        'payment_method', 'Cash',
        'status', 'Success'
    );

    v_res := public.create_patient_bill_order_with_packages(
        v_patient_data,
        v_bill_data,
        v_items_data,
        v_payment_data,
        v_idempotency_key
    );

    v_bill_id := (v_res->>'bill_id')::UUID;
    RAISE NOTICE 'SUCCESS: Created bill % with % items', v_bill_id, cardinality(v_items_data);

    -- Clean up test transaction
    DELETE FROM public.bill_package_components WHERE bill_package_selection_id IN (SELECT id FROM public.bill_package_selections WHERE bill_id = v_bill_id);
    DELETE FROM public.bill_package_selections WHERE bill_id = v_bill_id;
    DELETE FROM public.payments WHERE bill_id = v_bill_id;
    DELETE FROM public.test_results WHERE clinical_order_id IN (SELECT id FROM public.clinical_orders WHERE bill_id = v_bill_id);
    DELETE FROM public.clinical_order_items WHERE order_id IN (SELECT id FROM public.clinical_orders WHERE bill_id = v_bill_id);
    DELETE FROM public.samples WHERE order_id IN (SELECT id FROM public.clinical_orders WHERE bill_id = v_bill_id);
    DELETE FROM public.clinical_orders WHERE bill_id = v_bill_id;
    DELETE FROM public.bill_items WHERE bill_id = v_bill_id;
    DELETE FROM public.bills WHERE id = v_bill_id;
    DELETE FROM public.patients WHERE mobile_number = '9899001122';
END $$;
`;

const tmp = path.resolve('tmp_test_billing.sql');
writeFileSync(tmp, sql, 'utf8');
try {
  const out = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], shell: true });
  console.log(out);
} finally {
  try { unlinkSync(tmp); } catch {}
}
