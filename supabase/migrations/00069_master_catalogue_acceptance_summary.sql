-- Aggregate, non-PII acceptance evidence for the hosted TM256 catalogue.
-- This avoids granting service_role direct access to protected catalogue tables.

CREATE OR REPLACE FUNCTION public.catalogue_master_acceptance_summary()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
DECLARE result JSONB;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Service-role acceptance authority required.' USING ERRCODE='42501';
  END IF;
  SELECT jsonb_build_object(
    'tests',count(*),
    'profiles',count(*) FILTER(WHERE test_kind='Profile'),
    'unique_codes',count(*)=count(DISTINCT upper(code)),
    'draft_operational',count(*) FILTER(WHERE lifecycle_status='Draft' AND (is_active OR billing_enabled OR clinical_reporting_enabled)),
    'reporting_without_structure',count(*) FILTER(WHERE clinical_reporting_enabled AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=tests.id AND p.is_active AND p.lifecycle_status='Active')),
    'specialist_generic_reporting',count(*) FILTER(WHERE reporting_model IN('MicrobiologyWorkflow','CytologyWorkflow','MolecularWorkflow','StructuredNested') AND workflow_supported AND clinical_reporting_enabled),
    'reporting_models',(SELECT jsonb_object_agg(reporting_model,n) FROM(SELECT reporting_model::TEXT,count(*) n FROM public.tests GROUP BY reporting_model)s),
    'departments',(SELECT jsonb_object_agg(department,n) FROM(SELECT department,count(*) n FROM public.tests GROUP BY department)s),
    'alias_checks',jsonb_build_object(
      'TLC',COALESCE((SELECT search_aliases @> ARRAY['wbc','tc'] FROM public.tests WHERE code='TLC'),FALSE),
      'PCV',COALESCE((SELECT search_aliases @> ARRAY['hct','hematocrit'] FROM public.tests WHERE code='PCV'),FALSE),
      'CK_MB',COALESCE((SELECT search_aliases @> ARRAY['ck-mb','cpk-mb'] FROM public.tests WHERE code='CK_MB'),FALSE),
      'KFT',COALESCE((SELECT search_aliases @> ARRAY['rft'] FROM public.tests WHERE code='KFT'),FALSE),
      'LIPID_PROFILE',COALESCE((SELECT search_aliases @> ARRAY['lipid'] FROM public.tests WHERE code='LIPID_PROFILE'),FALSE)
    ),
    'required_profiles',(SELECT jsonb_object_agg(code,present) FROM(SELECT x.code,EXISTS(SELECT 1 FROM public.tests t WHERE t.code=x.code AND t.test_kind='Profile')present FROM unnest(ARRAY['ABS_DLC','RBC_INDICES','PLATELET_INDICES','IRON_PROFILE','COAG_PROFILE','DENGUE_PANEL','HAV_PANEL'])x(code))s),
    'profile_components',(SELECT count(*) FROM public.catalogue_profile_components),
    'invalid_profile_components',(SELECT count(*) FROM public.catalogue_profile_components c LEFT JOIN public.tests p ON p.id=c.profile_test_id LEFT JOIN public.tests ct ON ct.id=c.component_test_id LEFT JOIN public.parameters cp ON cp.id=c.component_parameter_id WHERE p.id IS NULL OR (c.component_test_id IS NOT NULL AND ct.id IS NULL) OR (c.component_parameter_id IS NOT NULL AND cp.id IS NULL)),
    'duplicate_profile_order',(SELECT count(*) FROM(SELECT profile_test_id,display_order FROM public.catalogue_profile_components GROUP BY 1,2 HAVING count(*)>1)d)
  ) INTO result FROM public.tests;
  RETURN result;
END $$;

REVOKE ALL ON FUNCTION public.catalogue_master_acceptance_summary() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_master_acceptance_summary() TO service_role;
