-- Make staff status/super-admin/role changes one authorized transaction.
-- This prevents a failed role insert from leaving the target with deleted roles.

-- New Auth identities must never receive clinical access merely by signing up.
-- Preserve the empty-system first-admin bootstrap, but keep all subsequent
-- identities inactive and role-less until an administrator approves them.
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_is_first BOOLEAN;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('bimal:first-admin-bootstrap'));
    SELECT NOT EXISTS (SELECT 1 FROM public.user_profiles) INTO v_is_first;

    INSERT INTO public.user_profiles(
        id, email, full_name, phone, is_active, is_super_admin, created_at, updated_at
    ) VALUES (
        NEW.id,
        COALESCE(NEW.email, 'staff@bimalpathology.com'),
        COALESCE(NULLIF(btrim(NEW.raw_user_meta_data->>'full_name'), ''), 'Pending Staff Account'),
        NULLIF(btrim(NEW.raw_user_meta_data->>'phone'), ''),
        v_is_first,
        v_is_first,
        now(), now()
    )
    ON CONFLICT (id) DO NOTHING;

    IF v_is_first THEN
        INSERT INTO public.user_roles(user_id, role_id)
        VALUES (NEW.id, '00000000-0000-0000-0000-000000000001')
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_new_auth_user() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.update_user_access(
    p_user_id UUID,
    p_is_active BOOLEAN,
    p_is_super_admin BOOLEAN,
    p_role_ids UUID[] DEFAULT ARRAY[]::UUID[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_target public.user_profiles%ROWTYPE;
    v_actor_name TEXT;
    v_role_count INTEGER;
    v_distinct_role_count INTEGER;
BEGIN
    IF auth.uid() IS NULL OR NOT public.has_permission('can_manage_users') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_target
    FROM public.user_profiles
    WHERE id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User account was not found.' USING ERRCODE = 'P0002';
    END IF;

    IF p_user_id = auth.uid() AND NOT p_is_active THEN
        RAISE EXCEPTION 'You cannot deactivate your own account.' USING ERRCODE = '22023';
    END IF;

    IF v_target.is_super_admin AND (NOT p_is_active OR NOT p_is_super_admin) AND NOT EXISTS (
        SELECT 1 FROM public.user_profiles other
        WHERE other.id <> p_user_id
          AND other.is_active
          AND other.is_super_admin
    ) THEN
        RAISE EXCEPTION 'At least one active super administrator is required.' USING ERRCODE = '23514';
    END IF;

    SELECT count(*), count(DISTINCT requested.role_id)
    INTO v_role_count, v_distinct_role_count
    FROM unnest(COALESCE(p_role_ids, ARRAY[]::UUID[])) AS requested(role_id)
    JOIN public.roles r ON r.id = requested.role_id;

    IF v_role_count <> cardinality(COALESCE(p_role_ids, ARRAY[]::UUID[]))
       OR v_distinct_role_count <> v_role_count THEN
        RAISE EXCEPTION 'One or more selected roles are invalid.' USING ERRCODE = '22023';
    END IF;

    UPDATE public.user_profiles
    SET is_active = p_is_active,
        is_super_admin = p_is_super_admin,
        updated_at = now()
    WHERE id = p_user_id;

    DELETE FROM public.user_roles WHERE user_id = p_user_id;
    INSERT INTO public.user_roles(user_id, role_id)
    SELECT p_user_id, requested.role_id
    FROM unnest(COALESCE(p_role_ids, ARRAY[]::UUID[])) AS requested(role_id);

    SELECT COALESCE(full_name, 'Administrator') INTO v_actor_name
    FROM public.user_profiles WHERE id = auth.uid();

    INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES (
        auth.uid(), v_actor_name, 'USER_ACCESS_UPDATED', 'UserProfile', p_user_id::TEXT,
        jsonb_build_object(
            'changed_fields', jsonb_build_array('is_active', 'is_super_admin', 'roles'),
            'role_count', v_role_count
        )
    );

    RETURN jsonb_build_object('success', TRUE, 'user_id', p_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.update_user_access(UUID, BOOLEAN, BOOLEAN, UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_user_access(UUID, BOOLEAN, BOOLEAN, UUID[]) TO authenticated;

COMMENT ON FUNCTION public.update_user_access(UUID, BOOLEAN, BOOLEAN, UUID[]) IS
  'Atomically updates authorized staff access state and role membership with a server-derived audit event.';
