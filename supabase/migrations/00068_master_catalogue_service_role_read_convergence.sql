-- Narrow hosted service-role convergence for the TM256 catalogue metadata.
-- Browser roles remain governed by 00067 RLS policies; no clinical DML is granted.

REVOKE ALL ON public.catalogue_master_sources,
    public.catalogue_master_source_rows,
    public.catalogue_identity_conflicts,
    public.catalogue_profile_components
FROM service_role;

GRANT SELECT ON public.catalogue_master_sources,
    public.catalogue_master_source_rows,
    public.catalogue_identity_conflicts,
    public.catalogue_profile_components
TO service_role;

REVOKE ALL ON FUNCTION public.catalogue_expand_profile(UUID) FROM service_role;
GRANT EXECUTE ON FUNCTION public.catalogue_expand_profile(UUID) TO service_role;

DO $$
BEGIN
  IF has_table_privilege('anon','public.catalogue_master_source_rows','SELECT') OR
     has_table_privilege('anon','public.catalogue_identity_conflicts','SELECT') OR
     has_table_privilege('anon','public.catalogue_profile_components','SELECT') THEN
    RAISE EXCEPTION 'TM256_ANON_METADATA_PRIVILEGE_LEAK';
  END IF;
  IF NOT has_table_privilege('service_role','public.catalogue_master_source_rows','SELECT') OR
     NOT has_table_privilege('service_role','public.catalogue_identity_conflicts','SELECT') OR
     NOT has_table_privilege('service_role','public.catalogue_profile_components','SELECT') THEN
    RAISE EXCEPTION 'TM256_SERVICE_ROLE_READ_CONVERGENCE_FAILED';
  END IF;
END $$;
