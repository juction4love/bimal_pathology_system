-- Distinguish trusted billing-time empty row initialization from clinical
-- result entry. This migration changes no existing result or report data.

CREATE OR REPLACE FUNCTION public.guard_clinical_result_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path=public,pg_temp
AS $$
BEGIN
  -- Billing's SECURITY DEFINER transaction initializes parameter-shaped Draft
  -- rows. Ordinary application roles have no INSERT privilege after 00057.
  -- A placeholder is structurally incapable of carrying clinical meaning.
  IF TG_OP = 'INSERT'
     AND NEW.status = 'Draft'
     AND NEW.numeric_value IS NULL
     AND NEW.text_value IS NULL
     AND COALESCE(NEW.display_value, '') = ''
     AND NEW.flag = 'Normal'
     AND NOT NEW.is_critical
     AND NOT NEW.critical_acknowledged
     AND NEW.critical_acknowledged_by IS NULL
     AND NEW.critical_acknowledged_at IS NULL
     AND NEW.normal_range_text IS NULL
     AND NEW.normal_min IS NULL
     AND NEW.normal_max IS NULL
     AND NEW.critical_low IS NULL
     AND NEW.critical_high IS NULL
     AND NEW.entered_by IS NULL
     AND NEW.entered_by_name IS NULL
     AND NEW.entered_at IS NULL
     AND NEW.verified_by IS NULL
     AND NEW.verified_by_name IS NULL
     AND NEW.verified_at IS NULL
     AND NEW.signed_off_by IS NULL
     AND NEW.signed_off_name IS NULL
     AND NEW.signed_off_at IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM public.assert_clinical_result_ready(NEW.order_item_id);
  RETURN NEW;
END $$;

REVOKE ALL ON FUNCTION public.guard_clinical_result_write()
FROM PUBLIC,anon,authenticated,service_role;

-- Browser roles cannot manufacture even an empty placeholder. Initialization
-- authority is the trusted database transaction, never a request flag.
REVOKE INSERT,UPDATE,DELETE ON TABLE public.test_results FROM PUBLIC,anon,authenticated;

DO $$
BEGIN
  IF has_table_privilege('authenticated','public.test_results','INSERT')
     OR has_table_privilege('authenticated','public.test_results','UPDATE')
     OR has_table_privilege('anon','public.test_results','INSERT') THEN
    RAISE EXCEPTION 'RESULT_INITIALIZATION_DIRECT_WRITE_BOUNDARY_FAILED';
  END IF;
  IF has_function_privilege('authenticated','public.guard_clinical_result_write()','EXECUTE')
     OR has_function_privilege('anon','public.guard_clinical_result_write()','EXECUTE') THEN
    RAISE EXCEPTION 'RESULT_INITIALIZATION_TRIGGER_EXPOSURE_FAILED';
  END IF;
END $$;
