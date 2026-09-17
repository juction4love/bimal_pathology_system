-- Temporary, service-role-only diagnostic for the notification sub-operation.
-- The nested block is always rolled back, so this function cannot persist a
-- token, queue row, audit event, or provider-triggering side effect.

CREATE OR REPLACE FUNCTION public.diagnose_report_notification_rollback(
    p_report_id UUID,
    p_actor_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_raw_token TEXT;
    v_token_hash TEXT;
    v_result JSONB;
BEGIN
    IF auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'Service role required.' USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.user_profiles WHERE id = p_actor_id) THEN
        RAISE EXCEPTION 'Diagnostic actor does not exist.' USING ERRCODE = '22023';
    END IF;

    -- Reproduce the original authenticated caller context without retaining it
    -- beyond this request transaction.
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', p_actor_id, 'role', 'authenticated')::TEXT,
        TRUE
    );

    v_raw_token := encode(extensions.gen_random_bytes(32), 'hex');
    v_token_hash := encode(
        extensions.digest(convert_to(v_raw_token, 'UTF8'), 'sha256'),
        'hex'
    );

    BEGIN
        v_result := public.create_public_report_token(
            p_report_id,
            v_token_hash,
            30,
            'https://lis.bimalpathology.com.np/r/' || v_raw_token
        );

        RAISE EXCEPTION 'BPSG_DIAGNOSTIC_ROLLBACK'
            USING ERRCODE = 'P0001', DETAIL = v_result::TEXT;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'BPSG_DIAGNOSTIC_ROLLBACK' THEN
            RETURN jsonb_build_object(
                'branch_succeeded', TRUE,
                'rolled_back', TRUE
            );
        END IF;

        RETURN jsonb_build_object(
            'branch_succeeded', FALSE,
            'rolled_back', TRUE,
            'sqlstate', SQLSTATE,
            'error', left(SQLERRM, 500)
        );
    END;
END;
$$;

REVOKE ALL ON FUNCTION public.diagnose_report_notification_rollback(UUID, UUID)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.diagnose_report_notification_rollback(UUID, UUID)
TO service_role;
