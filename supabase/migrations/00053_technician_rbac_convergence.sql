-- Bimal Pathology: converge the canonical Lab Technician role to the
-- clinical-only permission matrix established by 00019 and 00026.
--
-- This migration intentionally leaves users, direct user overrides, Admin,
-- and every unrelated role untouched. Direct overrides require separate
-- operator evidence and are never silently rewritten by role convergence.

DO $technician_rbac_convergence$
DECLARE
    v_role public.roles%ROWTYPE;
    v_expected_permissions CONSTANT TEXT[] := ARRAY[
        'can_view_dashboard',
        'can_collect_sample',
        'can_receive_sample',
        'can_reject_sample',
        'can_enter_results',
        'can_acknowledge_critical',
        'can_print_reports',
        'can_manage_outsource_tracking'
    ];
    v_old_permissions TEXT[];
    v_new_permissions TEXT[];
BEGIN
    SELECT * INTO STRICT v_role
    FROM public.roles
    WHERE code = 'lab_technician'
    FOR UPDATE;

    IF v_role.id <> '00000000-0000-0000-0000-000000000004'::UUID
       OR v_role.name <> 'Lab Technician'
       OR NOT v_role.is_system THEN
        RAISE EXCEPTION 'Canonical Lab Technician role identity is inconsistent.'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(array_agg(permission_key ORDER BY permission_key), ARRAY[]::TEXT[])
    INTO v_old_permissions
    FROM public.role_permissions
    WHERE role_id = v_role.id;

    DELETE FROM public.role_permissions
    WHERE role_id = v_role.id
      AND NOT (permission_key = ANY(v_expected_permissions));

    INSERT INTO public.role_permissions(role_id, permission_key)
    SELECT v_role.id, permission_key
    FROM unnest(v_expected_permissions) AS expected(permission_key)
    ON CONFLICT(role_id, permission_key) DO NOTHING;

    SELECT COALESCE(array_agg(permission_key ORDER BY permission_key), ARRAY[]::TEXT[])
    INTO v_new_permissions
    FROM public.role_permissions
    WHERE role_id = v_role.id;

    IF v_new_permissions <> ARRAY(
        SELECT permission_key FROM unnest(v_expected_permissions) AS expected(permission_key)
        ORDER BY permission_key
    ) THEN
        RAISE EXCEPTION 'Lab Technician permission convergence did not produce the canonical matrix.'
            USING ERRCODE = '23514';
    END IF;

    IF v_old_permissions IS DISTINCT FROM v_new_permissions THEN
        INSERT INTO public.audit_logs(
            user_id,
            user_name,
            action,
            entity_type,
            entity_id,
            old_data,
            new_data
        ) VALUES (
            NULL,
            'Database migration 00053',
            'TECHNICIAN_RBAC_CONVERGED',
            'Role',
            v_role.id::TEXT,
            jsonb_build_object('permissions', to_jsonb(v_old_permissions)),
            jsonb_build_object('permissions', to_jsonb(v_new_permissions))
        );
    END IF;
END;
$technician_rbac_convergence$;

COMMENT ON TABLE public.role_permissions IS
    'Role permissions; lab_technician is migration-converged to clinical-only access and excludes billing, patient-master administration, verification, signing, catalogue, finance, user and role administration.';
