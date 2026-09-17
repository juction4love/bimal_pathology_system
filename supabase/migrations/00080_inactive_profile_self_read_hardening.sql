-- Prevent inactive and non-staff Auth identities from reading even their own
-- auto-provisioned profile. Active LIS users retain self-profile access, and
-- authorized user administrators retain their existing management read path.

DROP POLICY IF EXISTS user_profiles_select_own ON public.user_profiles;

CREATE POLICY user_profiles_select_own
ON public.user_profiles
FOR SELECT
TO authenticated
USING (
  (id = auth.uid() AND public.is_active_user())
  OR public.has_permission('can_manage_users')
);

COMMENT ON POLICY user_profiles_select_own ON public.user_profiles IS
  'Active LIS users may read their own profile; authorized user administrators may read managed profiles. Inactive and non-staff Auth identities, including Gateway principals, see no profile rows.';
