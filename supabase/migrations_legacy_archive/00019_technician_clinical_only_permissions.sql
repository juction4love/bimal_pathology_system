-- Keep the existing role model while enforcing separation of laboratory work
-- from billing, finance, patient administration and configuration.
-- Forward-only and data-preserving: only role permission assignments change.

DELETE FROM public.role_permissions
WHERE role_id = '00000000-0000-0000-0000-000000000004'
  AND permission_key IN (
    'can_create_bill',
    'can_edit_patient',
    'can_view_financials',
    'can_manage_catalogue',
    'can_manage_referring_doctors',
    'can_manage_personnel',
    'can_manage_users',
    'can_manage_roles',
    'can_view_audit_logs'
  );

-- Explicitly preserve only implemented technical workflow capabilities.
INSERT INTO public.role_permissions (role_id, permission_key) VALUES
  ('00000000-0000-0000-0000-000000000004', 'can_view_dashboard'),
  ('00000000-0000-0000-0000-000000000004', 'can_collect_sample'),
  ('00000000-0000-0000-0000-000000000004', 'can_receive_sample'),
  ('00000000-0000-0000-0000-000000000004', 'can_reject_sample'),
  ('00000000-0000-0000-0000-000000000004', 'can_enter_results'),
  ('00000000-0000-0000-0000-000000000004', 'can_acknowledge_critical'),
  ('00000000-0000-0000-0000-000000000004', 'can_print_reports'),
  ('00000000-0000-0000-0000-000000000004', 'can_manage_outsource_tracking')
ON CONFLICT (role_id, permission_key) DO NOTHING;
