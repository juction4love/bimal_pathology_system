-- Forward-only cleanup for the allocator introduced by 00031.
-- The integer FOR loop owns its iterator; do not predeclare a shadowed variable.

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

    PERFORM pg_advisory_xact_lock(hashtextextended('patient-uhid-day:' || v_prefix, 0));

    v_digest := encode(extensions.digest(
        convert_to('BIMAL-UHID-V1:' || p_normalized_mobile || ':' || v_prefix, 'UTF8'),
        'sha256'
    ), 'hex');
    v_base := (('x' || substring(v_digest FROM 1 FOR 8))::BIT(32)::BIGINT % 10000)::INTEGER;

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

COMMENT ON FUNCTION public.allocate_patient_uhid(TEXT, TIMESTAMPTZ) IS
'Allocates immutable YYMMDDXXXX patient UHIDs from normalized Nepal mobile plus first-registration date, with deterministic collision probing and day-scoped concurrency serialization.';
