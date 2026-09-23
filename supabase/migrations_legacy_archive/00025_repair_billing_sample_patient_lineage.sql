-- Forward-only repair: samples.patient_id is required for clinical lineage.

DO $repair_billing_sample_patient_lineage$
DECLARE
    v_signature REGPROCEDURE :=
        'public.create_patient_bill_and_order(jsonb,jsonb,jsonb[],jsonb)'::REGPROCEDURE;
    v_definition TEXT;
    v_fixed TEXT;
BEGIN
    SELECT pg_get_functiondef(v_signature) INTO v_definition;
    v_fixed := replace(
        v_definition,
        E'                        barcode,\n                        order_id,\n                        specimen_type,',
        E'                        barcode,\n                        order_id,\n                        patient_id,\n                        specimen_type,'
    );
    v_fixed := replace(
        v_fixed,
        E'                        v_order_id,\n                        v_specimen,\n                        v_container,',
        E'                        v_order_id,\n                        v_patient_id,\n                        v_specimen,\n                        v_container,'
    );

    IF v_fixed = v_definition
       OR position(E'                        patient_id,\n                        specimen_type,' IN v_fixed) = 0
       OR position(E'                        v_patient_id,\n                        v_specimen,' IN v_fixed) = 0 THEN
        RAISE EXCEPTION
            'Billing RPC sample-patient-lineage repair did not match the deployed function; refusing partial repair';
    END IF;
    EXECUTE v_fixed;
END;
$repair_billing_sample_patient_lineage$;

REVOKE EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
TO authenticated;
