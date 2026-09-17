-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Migration 00007: Safe First-Admin Bootstrap & User Profile Auto-Provisioning
-- ============================================================================

-- 1. Function to handle new user registration automatically from auth.users
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_profile_count INT;
    v_is_first BOOLEAN;
    v_full_name VARCHAR(255);
    v_phone VARCHAR(50);
BEGIN
    SELECT count(*) INTO v_profile_count FROM public.user_profiles;
    v_is_first := (v_profile_count = 0);

    v_full_name := COALESCE(NEW.raw_user_meta_data->>'full_name', 'Staff Member');
    v_phone := NEW.raw_user_meta_data->>'phone';

    -- Insert into user_profiles
    INSERT INTO public.user_profiles (
        id,
        email,
        full_name,
        phone,
        is_active,
        is_super_admin,
        created_at,
        updated_at
    ) VALUES (
        NEW.id,
        COALESCE(NEW.email, 'user@bimalpathology.com'),
        v_full_name,
        v_phone,
        TRUE,
        v_is_first,
        NOW(),
        NOW()
    )
    ON CONFLICT (id) DO UPDATE
    SET is_super_admin = CASE WHEN v_is_first THEN TRUE ELSE user_profiles.is_super_admin END,
        is_active = TRUE,
        updated_at = NOW();

    -- Assign role: Admin for first user, Receptionist/Staff for subsequent users
    IF v_is_first THEN
        INSERT INTO public.user_roles (user_id, role_id)
        VALUES (NEW.id, '00000000-0000-0000-0000-000000000001')
        ON CONFLICT DO NOTHING;
    ELSE
        INSERT INTO public.user_roles (user_id, role_id)
        VALUES (NEW.id, '00000000-0000-0000-0000-000000000005')
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$;

-- 2. Trigger on auth.users (idempotent)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_auth_user();

-- 3. Explicit RPC for client-side First-Admin bootstrap check
CREATE OR REPLACE FUNCTION public.bootstrap_first_admin()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id UUID;
    v_profile_count INT;
    v_email VARCHAR(255);
    v_caller_email VARCHAR(255);
    v_full_name VARCHAR(255);
    v_phone VARCHAR(50);
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required: Anonymous callers cannot bootstrap administrator.';
    END IF;

    SELECT email, raw_user_meta_data->>'full_name', raw_user_meta_data->>'phone'
    INTO v_caller_email, v_full_name, v_phone
    FROM auth.users
    WHERE id = v_caller_id;

    SELECT count(*) INTO v_profile_count FROM public.user_profiles;

    IF v_profile_count = 0 THEN
        -- First user gets Super Admin & Admin Role
        INSERT INTO public.user_profiles (
            id,
            email,
            full_name,
            phone,
            is_active,
            is_super_admin,
            created_at,
            updated_at
        ) VALUES (
            v_caller_id,
            COALESCE(v_caller_email, 'admin@bimalpathology.com'),
            COALESCE(v_full_name, 'System Administrator'),
            v_phone,
            TRUE,
            TRUE,
            NOW(),
            NOW()
        )
        ON CONFLICT (id) DO UPDATE
        SET is_super_admin = TRUE, is_active = TRUE, updated_at = NOW();

        INSERT INTO public.user_roles (user_id, role_id)
        VALUES (v_caller_id, '00000000-0000-0000-0000-000000000001')
        ON CONFLICT DO NOTHING;

        RETURN jsonb_build_object(
            'success', true,
            'bootstrapped', true,
            'is_super_admin', true,
            'message', 'Initial Super Administrator successfully bootstrapped.'
        );
    ELSE
        -- Ensure profile exists
        IF NOT EXISTS (SELECT 1 FROM public.user_profiles WHERE id = v_caller_id) THEN
            INSERT INTO public.user_profiles (
                id,
                email,
                full_name,
                phone,
                is_active,
                is_super_admin,
                created_at,
                updated_at
            ) VALUES (
                v_caller_id,
                COALESCE(v_caller_email, 'staff@bimalpathology.com'),
                COALESCE(v_full_name, 'Staff Member'),
                v_phone,
                TRUE,
                FALSE,
                NOW(),
                NOW()
            )
            ON CONFLICT (id) DO NOTHING;

            INSERT INTO public.user_roles (user_id, role_id)
            VALUES (v_caller_id, '00000000-0000-0000-0000-000000000005')
            ON CONFLICT DO NOTHING;
        END IF;

        RETURN jsonb_build_object(
            'success', true,
            'bootstrapped', false,
            'is_super_admin', (SELECT is_super_admin FROM public.user_profiles WHERE id = v_caller_id),
            'message', 'User profile confirmed.'
        );
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.bootstrap_first_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bootstrap_first_admin() TO authenticated;
