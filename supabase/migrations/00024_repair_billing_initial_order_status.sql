-- Forward-only repair: clinical_orders accepts Registered as its initial state,
-- not the invalid Pending literal introduced by a later RPC replacement.

DO $repair_billing_initial_order_status$
DECLARE
    v_signature REGPROCEDURE :=
        'public.create_patient_bill_and_order(jsonb,jsonb,jsonb[],jsonb)'::REGPROCEDURE;
    v_definition TEXT;
    v_fixed TEXT;
BEGIN
    SELECT pg_get_functiondef(v_signature) INTO v_definition;
    v_fixed := replace(
        v_definition,
        E'            COALESCE(p_bill_data->>\'order_date_bs\', \'2083-05-03\'),\n            \'Pending\'\n        ) RETURNING id INTO v_order_id;',
        E'            COALESCE(p_bill_data->>\'order_date_bs\', \'2083-05-03\'),\n            \'Registered\'\n        ) RETURNING id INTO v_order_id;'
    );

    IF v_fixed = v_definition
       OR position(E'            \'Registered\'\n        ) RETURNING id INTO v_order_id;' IN v_fixed) = 0 THEN
        RAISE EXCEPTION
            'Billing RPC initial-order-status repair did not match the deployed function; refusing partial repair';
    END IF;
    EXECUTE v_fixed;
END;
$repair_billing_initial_order_status$;

REVOKE EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
TO authenticated;
