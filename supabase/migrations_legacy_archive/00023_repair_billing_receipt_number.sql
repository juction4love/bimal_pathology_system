-- Forward-only repair: payment_transactions.receipt_number is NOT NULL and
-- must retain the established RCP-YYYY-NNNNN numbering sequence.

DO $repair_billing_receipt_number$
DECLARE
    v_signature REGPROCEDURE :=
        'public.create_patient_bill_and_order(jsonb,jsonb,jsonb[],jsonb)'::REGPROCEDURE;
    v_definition TEXT;
    v_fixed TEXT;
BEGIN
    SELECT pg_get_functiondef(v_signature) INTO v_definition;

    v_fixed := replace(
        v_definition,
        E'        INSERT INTO public.payment_transactions (\n            bill_id,\n            amount_paisa,',
        E'        INSERT INTO public.payment_transactions (\n            bill_id,\n            receipt_number,\n            amount_paisa,'
    );
    v_fixed := replace(
        v_fixed,
        E'        ) VALUES (\n            v_bill_id,\n            v_pay_amount,\n            COALESCE(p_payment_data->>\'payment_mode\', \'Cash\')::payment_mode_enum,',
        E'        ) VALUES (\n            v_bill_id,\n            \'RCP-\' || v_current_year || \'-\' || LPAD(NEXTVAL(\'receipt_seq\')::TEXT, 5, \'0\'),\n            v_pay_amount,\n            COALESCE(p_payment_data->>\'payment_mode\', \'Cash\')::payment_mode_enum,'
    );

    IF v_fixed = v_definition
       OR position(E'            receipt_number,\n            amount_paisa,' IN v_fixed) = 0
       OR position('NEXTVAL(''receipt_seq'')' IN v_fixed) = 0 THEN
        RAISE EXCEPTION
            'Billing RPC receipt-number repair did not match the deployed function; refusing partial repair';
    END IF;

    EXECUTE v_fixed;
END;
$repair_billing_receipt_number$;

REVOKE EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
TO authenticated;
