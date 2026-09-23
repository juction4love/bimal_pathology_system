-- Bind future billing to the selected patient identity. A stale browser tab
-- holding the old mobile after a Registry correction must fail, never create a
-- second patient under the obsolete number.

DO $bind_existing_patient$
DECLARE
  v_signature REGPROCEDURE := 'public.create_patient_bill_and_order(jsonb,jsonb,jsonb[],jsonb,text)'::REGPROCEDURE;
  v_definition TEXT;
  v_fixed TEXT;
BEGIN
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_fixed := regexp_replace(
    v_definition,
    E'(BEGIN\n)',
    E'\\1  IF NULLIF(p_patient_data->>\'patient_id\', \'\') IS NOT NULL THEN\n    IF NOT EXISTS (\n      SELECT 1 FROM public.patients p\n       WHERE p.id = (p_patient_data->>\'patient_id\')::UUID\n         AND p.mobile = public.patient_normalize_mobile(p_patient_data->>\'mobile\')\n         AND p.is_active = TRUE\n    ) THEN\n      RAISE EXCEPTION \'The selected patient profile changed. Reload the patient by the current mobile before billing.\' USING ERRCODE=\'55000\';\n    END IF;\n  END IF;\n',
    ''
  );
  IF v_fixed = v_definition OR position('The selected patient profile changed.' IN v_fixed) = 0 THEN
    RAISE EXCEPTION 'Existing-patient billing bind patch mismatch; refusing partial migration.';
  END IF;
  EXECUTE v_fixed;
END;
$bind_existing_patient$;

REVOKE ALL ON FUNCTION public.create_patient_bill_and_order(JSONB,JSONB,JSONB[],JSONB,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB,JSONB,JSONB[],JSONB,TEXT) TO authenticated;

COMMENT ON FUNCTION public.create_patient_bill_and_order(JSONB,JSONB,JSONB[],JSONB,TEXT) IS
'Idempotent atomic billing wrapper; existing-patient submissions are bound to patient ID plus current normalized mobile so stale corrected-mobile tabs cannot create duplicates.';
