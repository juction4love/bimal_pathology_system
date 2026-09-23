-- Additive transition from project-wide service-role authentication to a
-- dedicated report-artifact Worker identity. The legacy caller remains valid
-- only until the follow-up revocation migration is applied after deployment.

CREATE TABLE public.report_artifact_worker_identities (
  auth_user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
  worker_name TEXT NOT NULL UNIQUE CHECK (worker_name ~ '^[A-Za-z0-9_-]{3,64}$'),
  is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.report_artifact_worker_identities ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.report_artifact_worker_identities FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.is_report_artifact_worker()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
  SELECT auth.role()='service_role' OR (
    auth.role()='authenticated' AND auth.uid() IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.report_artifact_worker_identities w
      WHERE w.auth_user_id=auth.uid() AND w.is_enabled
    )
  )
$$;
REVOKE ALL ON FUNCTION public.is_report_artifact_worker() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.register_report_artifact_worker(p_auth_user_id UUID,p_worker_name TEXT,p_confirmation TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF NOT public.is_super_admin() OR p_confirmation<>'REGISTER_REPORT_ARTIFACT_WORKER' THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_auth_user_id) THEN
    RAISE EXCEPTION 'Auth identity not found.' USING ERRCODE='22023';
  END IF;
  IF EXISTS(SELECT 1 FROM public.user_profiles WHERE id=p_auth_user_id AND is_active)
     OR EXISTS(SELECT 1 FROM public.user_roles WHERE user_id=p_auth_user_id)
     OR EXISTS(SELECT 1 FROM public.user_direct_permissions WHERE user_id=p_auth_user_id) THEN
    RAISE EXCEPTION 'Worker identity must not have LIS staff access.' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.report_artifact_worker_identities(auth_user_id,worker_name,created_by)
  VALUES(p_auth_user_id,p_worker_name,auth.uid());
END $$;
REVOKE ALL ON FUNCTION public.register_report_artifact_worker(UUID,TEXT,TEXT) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.register_report_artifact_worker(UUID,TEXT,TEXT) TO authenticated;

-- The existing artifact functions retain all immutable-report, lease, hash,
-- and token checks. Only their caller guard changes during this transition.
DO $migration$
DECLARE fn REGPROCEDURE; definition TEXT;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.claim_report_pdf_artifact(integer)'::REGPROCEDURE,
    'public.complete_report_pdf_artifact(uuid,uuid,boolean,text,bigint,text,text,text)'::REGPROCEDURE,
    'public.authorize_report_pdf_artifact(character varying)'::REGPROCEDURE
  ] LOOP
    definition:=pg_get_functiondef(fn);
    definition:=replace(definition,
      'IF auth.role()<>''service_role'' THEN',
      'IF NOT public.is_report_artifact_worker() THEN');
    definition:=replace(definition,
      'IF auth.role() <> ''service_role'' THEN',
      'IF NOT public.is_report_artifact_worker() THEN');
    IF definition NOT LIKE '%IF NOT public.is_report_artifact_worker() THEN%' THEN
      RAISE EXCEPTION 'Expected legacy artifact authorization guard was not found in %.',fn;
    END IF;
    EXECUTE definition;
  END LOOP;
END $migration$;

REVOKE ALL ON FUNCTION public.claim_report_pdf_artifact(INT),public.complete_report_pdf_artifact(UUID,UUID,BOOLEAN,TEXT,BIGINT,TEXT,TEXT,TEXT),public.authorize_report_pdf_artifact(VARCHAR) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.claim_report_pdf_artifact(INT),public.complete_report_pdf_artifact(UUID,UUID,BOOLEAN,TEXT,BIGINT,TEXT,TEXT,TEXT),public.authorize_report_pdf_artifact(VARCHAR) TO authenticated,service_role;
