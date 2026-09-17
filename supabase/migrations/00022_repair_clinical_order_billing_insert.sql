-- Forward-only repair for the authoritative billing RPC.
-- clinical_orders has no created_by column in the production schema; actor
-- attribution remains available through bills.created_by and audit records.

DO $repair_billing_clinical_order_insert$
DECLARE
    v_signature REGPROCEDURE :=
        'public.create_patient_bill_and_order(jsonb,jsonb,jsonb[],jsonb)'::REGPROCEDURE;
    v_definition TEXT;
    v_fixed TEXT;
BEGIN
    SELECT pg_get_functiondef(v_signature) INTO v_definition;

    v_fixed := replace(
        v_definition,
        E'            status,\n            created_by\n        ) VALUES (',
        E'            status\n        ) VALUES ('
    );
    v_fixed := replace(
        v_fixed,
        E'            COALESCE(p_bill_data->>\'order_date_bs\', \'2083-05-03\'),\n            \'Pending\',\n            auth.uid()\n        ) RETURNING id INTO v_order_id;',
        E'            COALESCE(p_bill_data->>\'order_date_bs\', \'2083-05-03\'),\n            \'Pending\'\n        ) RETURNING id INTO v_order_id;'
    );

    IF v_fixed = v_definition
       OR position('INSERT INTO public.clinical_orders' IN v_fixed) = 0
       OR position(E'            status,\n            created_by\n        ) VALUES (' IN v_fixed) > 0 THEN
        RAISE EXCEPTION
            'Billing RPC clinical_orders repair did not match the deployed function; refusing partial repair';
    END IF;

    EXECUTE v_fixed;
END;
$repair_billing_clinical_order_insert$;

-- Preserve the privilege boundary established by migration 00021.
REVOKE EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
TO authenticated;
