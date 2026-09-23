-- Migration 00118: Final Role Access Model - Lab Technician Operational-Only RBAC
-- Restricts Lab Technician to day-to-day operational clinical workflow under "CLINICAL OPERATIONS".
-- Removes Catalogue, Personnel, Referring Doctors, and Administration governance from Lab Technician.
-- Administrator controls all catalogue, personnel, configuration, governance, permissions, and master data.

BEGIN;

-- 1. Tighten Catalogue Management Guards to Administrative Authority Only
CREATE OR REPLACE FUNCTION public.catalogue_require_manager() RETURNS VOID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT (
    public.has_permission('can_manage_catalogue') OR public.is_super_admin()
  ) THEN
    RAISE EXCEPTION 'Catalogue management requires administrative authorization.' USING ERRCODE='42501';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_require_technical() RETURNS VOID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT (
    public.has_permission('can_configure_catalogue_technical') OR public.is_super_admin()
  ) THEN
    RAISE EXCEPTION 'Catalogue technical configuration requires administrative authorization.' USING ERRCODE='42501';
  END IF;
END $$;

-- 2. Define the Authoritative 13-Permission Operational Set for Lab Technician
CREATE OR REPLACE FUNCTION public.replace_role_permission_matrix(p_matrix JSONB) RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  entry JSONB;
  role_row public.roles%ROWTYPE;
  seen UUID[] := ARRAY[]::UUID[];
  supplied TEXT[];
  admin_allowed CONSTANT TEXT[] := ARRAY[
    'can_view_dashboard',
    'can_create_bill',
    'can_edit_patient',
    'can_collect_sample',
    'can_receive_sample',
    'can_reject_sample',
    'can_enter_results',
    'can_verify_results',
    'can_acknowledge_critical',
    'can_sign_reports',
    'can_amend_reports',
    'can_print_reports',
    'can_manage_catalogue',
    'can_configure_catalogue_technical',
    'can_manage_ast_breakpoints',
    'can_manage_referring_doctors',
    'can_manage_personnel',
    'can_view_financials',
    'can_manage_users',
    'can_manage_roles',
    'can_view_audit_logs',
    'can_manage_outsource_tracking',
    'can_view_hmis_reports',
    'can_edit_hmis_reports',
    'can_finalize_hmis_reports'
  ];
  technician_allowed CONSTANT TEXT[] := ARRAY[
    'can_view_dashboard',
    'can_create_bill',
    'can_edit_patient',
    'can_collect_sample',
    'can_receive_sample',
    'can_reject_sample',
    'can_enter_results',
    'can_verify_results',
    'can_acknowledge_critical',
    'can_sign_reports',
    'can_amend_reports',
    'can_print_reports',
    'can_manage_outsource_tracking'
  ];
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_permission('can_manage_roles') OR public.is_super_admin()) THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;

  IF jsonb_typeof(COALESCE(p_matrix, '[]')) <> 'array' THEN
    RAISE EXCEPTION 'Role permission matrix must be an array.' USING ERRCODE='22023';
  END IF;

  FOR entry IN SELECT * FROM jsonb_array_elements(COALESCE(p_matrix, '[]')) LOOP
    SELECT * INTO role_row FROM public.roles WHERE id = (entry->>'role_id')::UUID FOR UPDATE;
    IF NOT FOUND OR role_row.code NOT IN ('admin', 'lab_technician') THEN
      RAISE EXCEPTION 'Only active Administrator and Lab Technician roles may be submitted.' USING ERRCODE='22023';
    END IF;

    IF role_row.id = ANY(seen) THEN
      RAISE EXCEPTION 'A role may occur only once.' USING ERRCODE='23505';
    END IF;

    IF jsonb_typeof(COALESCE(entry->'permissions', '[]')) <> 'array' THEN
      RAISE EXCEPTION 'Permissions must be an array.' USING ERRCODE='22023';
    END IF;

    SELECT COALESCE(array_agg(DISTINCT p ORDER BY p), ARRAY[]::TEXT[])
    INTO supplied
    FROM jsonb_array_elements_text(COALESCE(entry->'permissions', '[]')) p;

    IF role_row.code = 'admin' AND supplied <> ARRAY(SELECT p FROM unnest(admin_allowed) p ORDER BY p) THEN
      RAISE EXCEPTION 'Administrator must retain the complete operational and governance permission set.' USING ERRCODE='23514';
    END IF;

    IF role_row.code = 'lab_technician' AND supplied <> ARRAY(SELECT p FROM unnest(technician_allowed) p ORDER BY p) THEN
      RAISE EXCEPTION 'Lab Technician must retain the complete operational pathology permission set (13 operational permissions).' USING ERRCODE='23514';
    END IF;

    seen := array_append(seen, role_row.id);
  END LOOP;

  FOR entry IN SELECT * FROM jsonb_array_elements(COALESCE(p_matrix, '[]')) LOOP
    DELETE FROM public.role_permissions WHERE role_id = (entry->>'role_id')::UUID;
    INSERT INTO public.role_permissions (role_id, permission_key)
    SELECT (entry->>'role_id')::UUID, p
    FROM jsonb_array_elements_text(entry->'permissions') p;

    INSERT INTO public.audit_logs (user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES (
      auth.uid(),
      public.catalogue_actor_name(),
      'ROLE_PERMISSIONS_REPLACED',
      'Role',
      entry->>'role_id',
      jsonb_build_object('permissions', entry->'permissions')
    );
  END LOOP;

  RETURN cardinality(seen);
END $$;

-- 3. Reconcile Database Role Permissions for Lab Technician
-- Delete non-operational permissions (catalogue, personnel, referring doctors, hmis, financials, audit, users, roles)
DELETE FROM public.role_permissions
WHERE role_id IN (SELECT id FROM public.roles WHERE code = 'lab_technician')
  AND permission_key NOT IN (
    'can_view_dashboard',
    'can_create_bill',
    'can_edit_patient',
    'can_collect_sample',
    'can_receive_sample',
    'can_reject_sample',
    'can_enter_results',
    'can_verify_results',
    'can_acknowledge_critical',
    'can_sign_reports',
    'can_amend_reports',
    'can_print_reports',
    'can_manage_outsource_tracking'
  );

-- Ensure all 13 operational permissions exist for Lab Technician
INSERT INTO public.role_permissions (role_id, permission_key)
SELECT r.id, p.perm
FROM public.roles r
CROSS JOIN (
  VALUES
    ('can_view_dashboard'),
    ('can_create_bill'),
    ('can_edit_patient'),
    ('can_collect_sample'),
    ('can_receive_sample'),
    ('can_reject_sample'),
    ('can_enter_results'),
    ('can_verify_results'),
    ('can_acknowledge_critical'),
    ('can_sign_reports'),
    ('can_amend_reports'),
    ('can_print_reports'),
    ('can_manage_outsource_tracking')
) AS p(perm)
WHERE r.code = 'lab_technician'
ON CONFLICT (role_id, permission_key) DO NOTHING;

-- 4. Update Row-Level Security for Analyzer Parameter Mappings Write Policy
DROP POLICY IF EXISTS analyzer_param_mappings_write ON public.analyzer_parameter_mappings;
CREATE POLICY analyzer_param_mappings_write ON public.analyzer_parameter_mappings
  FOR ALL TO authenticated
  USING (public.has_permission('can_manage_catalogue') OR public.has_permission('can_configure_catalogue_technical') OR public.is_super_admin())
  WITH CHECK (public.has_permission('can_manage_catalogue') OR public.has_permission('can_configure_catalogue_technical') OR public.is_super_admin());

-- 5. Revoke Anonymous Access and Grant Authenticated Execute
REVOKE ALL ON FUNCTION public.catalogue_require_manager() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.catalogue_require_technical() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.replace_role_permission_matrix(JSONB) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.catalogue_require_manager() TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_require_technical() TO authenticated;
GRANT EXECUTE ON FUNCTION public.replace_role_permission_matrix(JSONB) TO authenticated;

-- Audit Log for Migration 00118 Execution
INSERT INTO public.audit_logs (user_id, user_name, action, entity_type, entity_id, new_data)
VALUES (
  auth.uid(),
  'Migration 00118',
  'FINAL_LAB_OPERATOR_RBAC_ENFORCED',
  'Role',
  'lab_technician',
  jsonb_build_object(
    'allowed_permissions', jsonb_build_array(
      'can_view_dashboard',
      'can_create_bill',
      'can_edit_patient',
      'can_collect_sample',
      'can_receive_sample',
      'can_reject_sample',
      'can_enter_results',
      'can_verify_results',
      'can_acknowledge_critical',
      'can_sign_reports',
      'can_amend_reports',
      'can_print_reports',
      'can_manage_outsource_tracking'
    ),
    'removed_permissions', jsonb_build_array(
      'can_manage_catalogue',
      'can_configure_catalogue_technical',
      'can_manage_ast_breakpoints',
      'can_manage_referring_doctors',
      'can_manage_personnel',
      'can_view_financials',
      'can_manage_users',
      'can_manage_roles',
      'can_view_audit_logs',
      'can_view_hmis_reports',
      'can_edit_hmis_reports',
      'can_finalize_hmis_reports'
    )
  )
);

COMMIT;
