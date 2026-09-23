-- Canonical separation-of-duties roles for verification and report authorization.
-- This migration changes role configuration only. It does not assign users,
-- alter direct permissions, grant table DML, or rewrite clinical data.

DO $canonical_clinical_roles$
DECLARE
    v_verifier_id CONSTANT UUID := '00000000-0000-0000-0000-000000000007'::UUID;
    v_signatory_id CONSTANT UUID := '00000000-0000-0000-0000-000000000008'::UUID;
    v_verifier_permissions CONSTANT TEXT[] := ARRAY[
        'can_view_dashboard', 'can_verify_results',
        'can_acknowledge_critical', 'can_print_reports'
    ];
    v_signatory_permissions CONSTANT TEXT[] := ARRAY[
        'can_view_dashboard', 'can_sign_reports',
        'can_amend_reports', 'can_print_reports'
    ];
    v_actual TEXT[];
BEGIN
    IF EXISTS (SELECT 1 FROM public.roles WHERE code='verifier' AND id<>v_verifier_id)
       OR EXISTS (SELECT 1 FROM public.roles WHERE id=v_verifier_id AND code<>'verifier') THEN
        RAISE EXCEPTION 'Canonical Verifier role identity conflicts with existing data.' USING ERRCODE='23514';
    END IF;
    IF EXISTS (SELECT 1 FROM public.roles WHERE code='signatory' AND id<>v_signatory_id)
       OR EXISTS (SELECT 1 FROM public.roles WHERE id=v_signatory_id AND code<>'signatory') THEN
        RAISE EXCEPTION 'Canonical Signatory role identity conflicts with existing data.' USING ERRCODE='23514';
    END IF;

    INSERT INTO public.roles(id,code,name,description,is_system) VALUES
      (v_verifier_id,'verifier','Verifier','Clinical result review, critical acknowledgement, verification and report preview without sign-off authority.',TRUE),
      (v_signatory_id,'signatory','Signatory','Verified-result review, report sign-off, amendment authorization and report delivery without system administration.',TRUE)
    ON CONFLICT(id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, is_system=TRUE;

    DELETE FROM public.role_permissions WHERE role_id=v_verifier_id AND NOT(permission_key=ANY(v_verifier_permissions));
    INSERT INTO public.role_permissions(role_id,permission_key)
    SELECT v_verifier_id,p FROM unnest(v_verifier_permissions) p ON CONFLICT(role_id,permission_key) DO NOTHING;
    DELETE FROM public.role_permissions WHERE role_id=v_signatory_id AND NOT(permission_key=ANY(v_signatory_permissions));
    INSERT INTO public.role_permissions(role_id,permission_key)
    SELECT v_signatory_id,p FROM unnest(v_signatory_permissions) p ON CONFLICT(role_id,permission_key) DO NOTHING;

    SELECT COALESCE(array_agg(permission_key ORDER BY permission_key),ARRAY[]::TEXT[])
      INTO v_actual FROM public.role_permissions WHERE role_id=v_verifier_id;
    IF v_actual<>ARRAY(SELECT p FROM unnest(v_verifier_permissions) p ORDER BY p) THEN
        RAISE EXCEPTION 'Verifier permission convergence failed.' USING ERRCODE='23514';
    END IF;
    SELECT COALESCE(array_agg(permission_key ORDER BY permission_key),ARRAY[]::TEXT[])
      INTO v_actual FROM public.role_permissions WHERE role_id=v_signatory_id;
    IF v_actual<>ARRAY(SELECT p FROM unnest(v_signatory_permissions) p ORDER BY p) THEN
        RAISE EXCEPTION 'Signatory permission convergence failed.' USING ERRCODE='23514';
    END IF;

    INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES
      (NULL,'Database migration 00059','CANONICAL_ROLE_CONVERGED','Role',v_verifier_id::TEXT,
       jsonb_build_object('code','verifier','permissions',to_jsonb(v_verifier_permissions))),
      (NULL,'Database migration 00059','CANONICAL_ROLE_CONVERGED','Role',v_signatory_id::TEXT,
       jsonb_build_object('code','signatory','permissions',to_jsonb(v_signatory_permissions)));
END;
$canonical_clinical_roles$;

COMMENT ON TABLE public.roles IS
  'Canonical RBAC roles. Verifier and Signatory are distinct least-privilege system roles; assignment remains through update_user_access.';
