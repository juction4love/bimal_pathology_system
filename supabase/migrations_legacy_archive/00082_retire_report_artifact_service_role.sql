-- Finalize report-artifact Worker least privilege after the dedicated identity
-- deployment has been accepted. No table data or report artifact is rewritten.

CREATE OR REPLACE FUNCTION public.is_report_artifact_worker()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
  SELECT auth.role()='authenticated' AND auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.report_artifact_worker_identities w
    WHERE w.auth_user_id=auth.uid() AND w.is_enabled
  )
$$;

REVOKE ALL ON FUNCTION public.claim_report_pdf_artifact(INT),public.complete_report_pdf_artifact(UUID,UUID,BOOLEAN,TEXT,BIGINT,TEXT,TEXT,TEXT),public.authorize_report_pdf_artifact(VARCHAR) FROM service_role;

