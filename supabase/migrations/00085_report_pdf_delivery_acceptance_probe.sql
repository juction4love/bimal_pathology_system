-- Allow the existing dedicated artifact Worker identity to verify one latest
-- Ready artifact through the real patient route without granting table access.

CREATE FUNCTION public.get_report_pdf_delivery_acceptance_candidate()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE candidate RECORD; public_url TEXT;
BEGIN
  IF NOT public.is_report_artifact_worker() THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;
  SELECT a.*,r.report_number INTO candidate
  FROM public.report_pdf_artifacts a
  JOIN public.diagnostic_reports r ON r.id=a.diagnostic_report_id
  WHERE a.generation_status='Ready' AND r.status IN('SignedOff','Amended')
    AND a.report_version=r.version AND a.report_integrity_hash=r.integrity_hash
    AND encode(extensions.digest(r.clinical_snapshot_json::TEXT,'sha256'),'hex')=a.frozen_snapshot_sha256
  ORDER BY a.generated_at DESC,a.id DESC LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('available',FALSE); END IF;
  public_url:=public.report_artifact_public_url(candidate.diagnostic_report_id);
  IF public_url IS NULL THEN RETURN jsonb_build_object('available',FALSE); END IF;
  RETURN jsonb_build_object('available',TRUE,'public_url',public_url,
    'report_number',candidate.report_number,'report_version',candidate.report_version,
    'pdf_sha256',candidate.pdf_sha256,'byte_size',candidate.byte_size);
END $$;

REVOKE ALL ON FUNCTION public.get_report_pdf_delivery_acceptance_candidate() FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_report_pdf_delivery_acceptance_candidate() TO authenticated;
