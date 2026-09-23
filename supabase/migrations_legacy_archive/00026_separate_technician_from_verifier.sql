-- A technician may enter and submit results, but technician role membership
-- alone must never grant clinical verification authority.

DELETE FROM public.role_permissions rp
USING public.roles r
WHERE rp.role_id = r.id
  AND r.code = 'lab_technician'
  AND rp.permission_key IN ('can_verify_results', 'can_sign_reports', 'can_amend_reports');

COMMENT ON TABLE public.role_permissions IS
    'Role permissions; lab_technician intentionally excludes verification, signing, and amendment authority.';
