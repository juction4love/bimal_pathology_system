-- Forward-only UHID presentation/allocation change.
-- Historical UHIDs and timestamps are intentionally not rewritten.

CREATE OR REPLACE FUNCTION public.allocate_patient_uhid(
    p_normalized_mobile TEXT,
    p_registered_at TIMESTAMPTZ
)
RETURNS VARCHAR(10)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_registration_date DATE := (p_registered_at AT TIME ZONE 'Asia/Kathmandu')::DATE;
    v_prefix TEXT := TO_CHAR(v_registration_date, 'YYMMDD');
    v_digest TEXT;
    v_base INTEGER;
    v_attempt INTEGER;
    v_code INTEGER;
    v_candidate VARCHAR(10);
BEGIN
    IF p_normalized_mobile !~ '^(97|98)[0-9]{8}$' THEN
        RAISE EXCEPTION 'A normalized 10-digit Nepal mobile is required for UHID allocation.'
            USING ERRCODE = '22023';
    END IF;
    IF p_registered_at IS NULL THEN
        RAISE EXCEPTION 'A registration timestamp is required for UHID allocation.'
            USING ERRCODE = '22023';
    END IF;

    -- Serialize the 10,000-code namespace for this Nepal registration day.
    -- The patients.uhid UNIQUE constraint remains the final safety boundary.
    PERFORM pg_advisory_xact_lock(hashtextextended('patient-uhid-day:' || v_prefix, 0));

    v_digest := encode(extensions.digest(
        convert_to('BIMAL-UHID-V1:' || p_normalized_mobile || ':' || v_prefix, 'UTF8'),
        'sha256'
    ), 'hex');
    v_base := (('x' || substring(v_digest FROM 1 FOR 8))::BIT(32)::BIGINT % 10000)::INTEGER;

    -- 7919 is coprime with 10000, so deterministic probing visits every code
    -- exactly once before exhaustion without exposing the mobile's last digits.
    FOR v_attempt IN 0..9999 LOOP
        v_code := (v_base + (v_attempt * 7919)) % 10000;
        v_candidate := v_prefix || LPAD(v_code::TEXT, 4, '0');
        IF NOT EXISTS (SELECT 1 FROM public.patients WHERE uhid = v_candidate) THEN
            RETURN v_candidate;
        END IF;
    END LOOP;

    RAISE EXCEPTION 'UHID namespace exhausted for Nepal registration date %.', v_registration_date
        USING ERRCODE = '54000';
END;
$$;

REVOKE ALL ON FUNCTION public.allocate_patient_uhid(TEXT, TIMESTAMPTZ)
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.prevent_patient_uhid_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.uhid !~ '^[0-9]{10}$' THEN
        RAISE EXCEPTION 'New patient UHID must contain exactly 10 numeric digits.' USING ERRCODE = '22023';
    ELSIF TG_OP = 'UPDATE' AND NEW.uhid IS DISTINCT FROM OLD.uhid THEN
        RAISE EXCEPTION 'Patient UHID is immutable.' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_patients_uhid_immutable ON public.patients;
DROP TRIGGER IF EXISTS trg_patients_uhid_new_format ON public.patients;
CREATE TRIGGER trg_patients_uhid_new_format
BEFORE INSERT ON public.patients
FOR EACH ROW EXECUTE FUNCTION public.prevent_patient_uhid_change();
CREATE TRIGGER trg_patients_uhid_immutable
BEFORE UPDATE OF uhid ON public.patients
FOR EACH ROW EXECUTE FUNCTION public.prevent_patient_uhid_change();

REVOKE ALL ON FUNCTION public.prevent_patient_uhid_change() FROM PUBLIC, anon, authenticated;

-- Patch only the four-argument atomic worker. The five-argument idempotent
-- public entrypoint continues to delegate to it unchanged.
DO $patch_numeric_uhid$
DECLARE
    v_signature REGPROCEDURE :=
        'public.create_patient_bill_and_order(jsonb,jsonb,jsonb[],jsonb)'::REGPROCEDURE;
    v_definition TEXT;
    v_fixed TEXT;
BEGIN
    SELECT pg_get_functiondef(v_signature) INTO v_definition;
    v_fixed := v_definition;

    -- pg_get_functiondef() omits a PL/pgSQL variable's VARCHAR typmod on some
    -- PostgreSQL versions. Match the declaration independently of that
    -- deparser detail and require exactly one replacement below.
    v_fixed := regexp_replace(
        v_fixed,
        E'(    v_patient_uhid (?:character varying|varchar)(?:\\([0-9]+\\))?;\\n)',
        E'\\1    v_registration_instant timestamp with time zone;\n',
        'i'
    );

    v_fixed := replace(
        v_fixed,
        E'    SELECT id, uhid INTO v_patient_id, v_patient_uhid\n    FROM public.patients\n    WHERE mobile = v_clean_mobile\n    FOR UPDATE;',
        E'    -- Same normalized mobile always resolves to the first patient, including concurrent requests.\n    PERFORM pg_advisory_xact_lock(hashtextextended(\'patient-mobile:\' || v_clean_mobile, 0));\n\n    SELECT id, uhid INTO v_patient_id, v_patient_uhid\n    FROM public.patients\n    WHERE mobile = v_clean_mobile\n    FOR UPDATE;'
    );

    v_fixed := replace(
        v_fixed,
        E'        v_patient_uhid := \'BP-\' || v_current_year || \'-\' || LPAD(NEXTVAL(\'uhid_seq\')::TEXT, 5, \'0\');',
        E'        v_registration_instant := clock_timestamp();\n        v_patient_uhid := public.allocate_patient_uhid(v_clean_mobile, v_registration_instant);'
    );

    v_fixed := replace(
        v_fixed,
        E'            identification_no\n        ) VALUES (',
        E'            identification_no,\n            created_at\n        ) VALUES ('
    );

    v_fixed := replace(
        v_fixed,
        E'            p_patient_data->>\'identification_no\'\n        )',
        E'            p_patient_data->>\'identification_no\',\n            v_registration_instant\n        )'
    );

    IF v_fixed = v_definition
       OR position('public.allocate_patient_uhid(v_clean_mobile, v_registration_instant)' IN v_fixed) = 0
       OR position('v_registration_instant timestamp with time zone;' IN v_fixed) = 0
       OR position('patient-mobile:' IN v_fixed) = 0
       OR position('ON CONFLICT (mobile) DO UPDATE' IN v_fixed) = 0
       OR position(E'            created_at\n        ) VALUES (' IN v_fixed) = 0
       OR position(E'            v_registration_instant\n        )' IN v_fixed) = 0
       OR position(E'\'BP-\' || v_current_year || \'-\'' IN v_fixed) > 0 THEN
        RAISE EXCEPTION
            'UHID patch mismatch (changed=%, allocator=%, declaration=%, mobile_lock=%, conflict=%, created_column=%, created_value=%, legacy=%); refusing partial migration.',
            v_fixed <> v_definition,
            position('public.allocate_patient_uhid(v_clean_mobile, v_registration_instant)' IN v_fixed) > 0,
            position('v_registration_instant timestamp with time zone;' IN v_fixed) > 0,
            position('patient-mobile:' IN v_fixed) > 0,
            position('ON CONFLICT (mobile) DO UPDATE' IN v_fixed) > 0,
            position(E'            created_at\n        ) VALUES (' IN v_fixed) > 0,
            position(E'            v_registration_instant\n        )' IN v_fixed) > 0,
            position(E'\'BP-\' || v_current_year || \'-\'' IN v_fixed) > 0;
    END IF;

    EXECUTE v_fixed;
END;
$patch_numeric_uhid$;

-- Preserve the established privilege boundary: browser callers use only the
-- five-argument idempotent transaction wrapper.
REVOKE EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
TO authenticated;

COMMENT ON FUNCTION public.allocate_patient_uhid(TEXT, TIMESTAMPTZ) IS
'Allocates immutable YYMMDDXXXX patient UHIDs from normalized Nepal mobile plus first-registration date, with deterministic collision probing and day-scoped concurrency serialization.';
