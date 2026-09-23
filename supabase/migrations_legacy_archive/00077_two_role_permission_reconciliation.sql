-- Production head 00075 showed authorization drift in the two active roles.
-- Reconcile role permissions only; do not alter users, assignments, direct
-- overrides, clinical data, or the legacy role rows retained for compatibility.

DO $two_role_reconciliation$
DECLARE
  v_admin CONSTANT UUID := '00000000-0000-0000-0000-000000000001';
  v_technician CONSTANT UUID := '00000000-0000-0000-0000-000000000004';
  v_admin_permissions CONSTANT TEXT[] := ARRAY[
    'can_view_dashboard','can_create_bill','can_edit_patient','can_collect_sample',
    'can_receive_sample','can_reject_sample','can_enter_results','can_verify_results',
    'can_acknowledge_critical','can_sign_reports','can_amend_reports','can_print_reports',
    'can_manage_catalogue','can_configure_catalogue_technical','can_manage_ast_breakpoints',
    'can_manage_referring_doctors','can_manage_personnel','can_view_financials',
    'can_manage_users','can_manage_roles','can_view_audit_logs',
    'can_manage_outsource_tracking','can_view_hmis_reports','can_edit_hmis_reports',
    'can_finalize_hmis_reports'
  ];
  v_technician_permissions CONSTANT TEXT[] := ARRAY[
    'can_view_dashboard','can_create_bill','can_edit_patient',
    'can_collect_sample','can_receive_sample','can_reject_sample',
    'can_enter_results','can_verify_results','can_acknowledge_critical',
    'can_sign_reports','can_amend_reports','can_print_reports',
    'can_manage_outsource_tracking','can_configure_catalogue_technical'
  ];
  v_old_admin TEXT[]; v_old_technician TEXT[]; v_new_admin TEXT[]; v_new_technician TEXT[];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.roles WHERE id=v_admin AND code='admin' AND is_system)
     OR NOT EXISTS (SELECT 1 FROM public.roles WHERE id=v_technician AND code='lab_technician' AND is_system) THEN
    RAISE EXCEPTION 'Canonical active role identity is missing or conflicting.' USING ERRCODE='23514';
  END IF;
  SELECT COALESCE(array_agg(permission_key ORDER BY permission_key),ARRAY[]::TEXT[]) INTO v_old_admin FROM public.role_permissions WHERE role_id=v_admin;
  SELECT COALESCE(array_agg(permission_key ORDER BY permission_key),ARRAY[]::TEXT[]) INTO v_old_technician FROM public.role_permissions WHERE role_id=v_technician;
  DELETE FROM public.role_permissions WHERE role_id=v_admin AND NOT(permission_key=ANY(v_admin_permissions));
  INSERT INTO public.role_permissions(role_id,permission_key) SELECT v_admin,p FROM unnest(v_admin_permissions)p ON CONFLICT DO NOTHING;
  DELETE FROM public.role_permissions WHERE role_id=v_technician AND NOT(permission_key=ANY(v_technician_permissions));
  INSERT INTO public.role_permissions(role_id,permission_key) SELECT v_technician,p FROM unnest(v_technician_permissions)p ON CONFLICT DO NOTHING;
  SELECT array_agg(permission_key ORDER BY permission_key) INTO v_new_admin FROM public.role_permissions WHERE role_id=v_admin;
  SELECT array_agg(permission_key ORDER BY permission_key) INTO v_new_technician FROM public.role_permissions WHERE role_id=v_technician;
  IF v_new_admin<>ARRAY(SELECT p FROM unnest(v_admin_permissions)p ORDER BY p)
     OR v_new_technician<>ARRAY(SELECT p FROM unnest(v_technician_permissions)p ORDER BY p) THEN
    RAISE EXCEPTION 'Two-role permission reconciliation failed.' USING ERRCODE='23514';
  END IF;
  IF v_old_admin IS DISTINCT FROM v_new_admin OR v_old_technician IS DISTINCT FROM v_new_technician THEN
    INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data)
    VALUES(NULL,'Database migration 00077','ACTIVE_ROLE_PERMISSIONS_RECONCILED','Role','admin,lab_technician',
      jsonb_build_object('admin',v_old_admin,'lab_technician',v_old_technician),
      jsonb_build_object('admin',v_new_admin,'lab_technician',v_new_technician));
  END IF;
END $two_role_reconciliation$;

COMMENT ON TABLE public.roles IS
  'Administrator and Lab Technician are the only active assignable roles. Verifier and Signatory remain legacy compatibility identities with no active assignments.';
