-- Converge the canonical Lab Technician role to the accepted clinical-only
-- permission set. This migration does not alter any user assignment, other
-- canonical role, direct permission, clinical row, or financial row.

DO $technician_permission_convergence$
DECLARE
    v_technician_id CONSTANT UUID := '00000000-0000-0000-0000-000000000004'::UUID;
    v_target_permissions CONSTANT TEXT[] := ARRAY[
        'can_view_dashboard',
        'can_collect_sample',
        'can_receive_sample',
        'can_reject_sample',
        'can_enter_results',
        'can_acknowledge_critical',
        'can_print_reports',
        'can_manage_outsource_tracking'
    ];
    v_actual TEXT[];
    v_old_permissions TEXT[];
    v_other_role_permissions JSONB;
    v_user_roles JSONB;
    v_user_profiles JSONB;
    v_user_direct_permissions JSONB;
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM public.roles
         WHERE id = v_technician_id
           AND code = 'lab_technician'
           AND name = 'Lab Technician'
    ) THEN
        RAISE EXCEPTION 'Canonical Lab Technician role identity is missing or conflicting.'
          USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(array_agg(permission_key ORDER BY permission_key), ARRAY[]::TEXT[])
      INTO v_old_permissions
      FROM public.role_permissions
     WHERE role_id = v_technician_id;

    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.role_id, x.permission_key), '[]'::JSONB)
      INTO v_other_role_permissions
      FROM public.role_permissions x
     WHERE x.role_id <> v_technician_id;
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.user_id, x.role_id), '[]'::JSONB)
      INTO v_user_roles
      FROM public.user_roles x;
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.id), '[]'::JSONB)
      INTO v_user_profiles
      FROM public.user_profiles x;
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.user_id, x.permission_key), '[]'::JSONB)
      INTO v_user_direct_permissions
      FROM public.user_direct_permissions x;

    DELETE FROM public.role_permissions
     WHERE role_id = v_technician_id
       AND NOT (permission_key = ANY(v_target_permissions));

    INSERT INTO public.role_permissions(role_id, permission_key)
    SELECT v_technician_id, permission_key
      FROM unnest(v_target_permissions) AS permission_key
    ON CONFLICT(role_id, permission_key) DO NOTHING;

    SELECT COALESCE(array_agg(permission_key ORDER BY permission_key), ARRAY[]::TEXT[])
      INTO v_actual
      FROM public.role_permissions
     WHERE role_id = v_technician_id;
    IF v_actual <> ARRAY(SELECT p FROM unnest(v_target_permissions) p ORDER BY p) THEN
        RAISE EXCEPTION 'Lab Technician permission convergence failed.'
          USING ERRCODE = '23514';
    END IF;

    IF v_other_role_permissions <> (
        SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.role_id, x.permission_key), '[]'::JSONB)
          FROM public.role_permissions x
         WHERE x.role_id <> v_technician_id
    ) THEN
        RAISE EXCEPTION 'Non-Technician role permissions changed during convergence.'
          USING ERRCODE = '23514';
    END IF;
    IF v_user_roles <> (
        SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.user_id, x.role_id), '[]'::JSONB)
          FROM public.user_roles x
    ) OR v_user_profiles <> (
        SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.id), '[]'::JSONB)
          FROM public.user_profiles x
    ) OR v_user_direct_permissions <> (
        SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.user_id, x.permission_key), '[]'::JSONB)
          FROM public.user_direct_permissions x
    ) THEN
        RAISE EXCEPTION 'User access assignments changed during Technician convergence.'
          USING ERRCODE = '23514';
    END IF;

    INSERT INTO public.audit_logs(
        user_id, user_name, action, entity_type, entity_id, old_data, new_data
    ) VALUES (
        NULL,
        'Database migration 00060',
        'TECHNICIAN_PERMISSION_CONVERGED',
        'Role',
        v_technician_id::TEXT,
        jsonb_build_object('permissions', to_jsonb(v_old_permissions)),
        jsonb_build_object('permissions', to_jsonb(v_actual))
    );
END;
$technician_permission_convergence$;

