-- Server-side laboratory worklist search and deterministic keyset pagination.
-- Forward-only after 00071. Does not alter clinical snapshots, results, SMS, or R2.

CREATE INDEX clinical_order_items_reportable_cursor_idx
ON public.clinical_order_items(created_at DESC,id DESC)
WHERE clinical_reporting_enabled
  AND reporting_type IN ('InHouse','OutsourceWithBimalReport');

CREATE INDEX clinical_order_items_order_id_idx
ON public.clinical_order_items(order_id);

CREATE INDEX patients_full_name_trgm_idx
ON public.patients USING gin(lower(full_name) gin_trgm_ops);

CREATE INDEX clinical_order_items_test_name_trgm_idx
ON public.clinical_order_items USING gin(lower(test_name) gin_trgm_ops);

CREATE FUNCTION public.search_laboratory_worklist(
  p_search TEXT DEFAULT NULL,
  p_department TEXT DEFAULT NULL,
  p_sample_status TEXT DEFAULT NULL,
  p_order_date DATE DEFAULT NULL,
  p_view TEXT DEFAULT 'All',
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 50
)
RETURNS TABLE(item JSONB)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path=public,pg_temp
AS $$
DECLARE
  term TEXT:=NULLIF(btrim(p_search),'');
  escaped_term TEXT;
BEGIN
  IF p_limit<1 OR p_limit>100 THEN
    RAISE EXCEPTION 'Invalid worklist page size.' USING ERRCODE='22023';
  END IF;
  IF (p_cursor_created_at IS NULL)<>(p_cursor_id IS NULL) THEN
    RAISE EXCEPTION 'Incomplete worklist cursor.' USING ERRCODE='22023';
  END IF;
  IF p_view NOT IN ('All','Pending','ToVerify','Verified','Signed') THEN
    RAISE EXCEPTION 'Invalid worklist view.' USING ERRCODE='22023';
  END IF;
  escaped_term:=replace(replace(replace(lower(term),'\','\\'),'%','\%'),'_','\_');

  RETURN QUERY
  SELECT jsonb_build_object(
    'id',coi.id,
    'order_id',coi.order_id,
    'test_id',coi.test_id,
    'test_name',coi.test_name,
    'department',coi.department,
    'reporting_type',coi.reporting_type,
    'outsource_lab_name',coi.outsource_lab_name,
    'status',coi.status,
    'created_at',coi.created_at,
    'order',jsonb_build_object(
      'id',o.id,'order_number',o.order_number,'order_date_ad',o.order_date_ad,
      'order_date_bs',o.order_date_bs,'patient',jsonb_build_object(
        'uhid',p.uhid,'full_name',p.full_name,'gender',p.gender,'age_years',p.age_years
      )
    ),
    'sample',CASE WHEN s.id IS NULL THEN NULL ELSE jsonb_build_object(
      'barcode',s.barcode,'status',s.status,'specimen_type',s.specimen_type,
      'container_type',s.container_type
    ) END,
    'results',COALESCE(result_set.results,'[]'::JSONB),
    'report',report_row.report
  )
  FROM public.clinical_order_items coi
  JOIN public.clinical_orders o ON o.id=coi.order_id
  JOIN public.patients p ON p.id=o.patient_id
  LEFT JOIN public.samples s ON s.id=coi.sample_id
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(jsonb_build_object(
      'id',tr.id,'flag',tr.flag,'is_critical',tr.is_critical,'status',tr.status
    ) ORDER BY tr.id) AS results
    FROM public.test_results tr WHERE tr.order_item_id=coi.id
  ) result_set ON TRUE
  LEFT JOIN LATERAL (
    SELECT jsonb_build_object('id',r.id,'report_number',r.report_number,'version',r.version,'status',r.status) AS report
    FROM public.diagnostic_reports r WHERE r.order_id=coi.order_id
    ORDER BY r.version DESC,r.created_at DESC,r.id DESC LIMIT 1
  ) report_row ON TRUE
  WHERE coi.clinical_reporting_enabled=TRUE
    AND coi.reporting_type IN ('InHouse','OutsourceWithBimalReport')
    AND (p_cursor_created_at IS NULL OR (coi.created_at,coi.id)<(p_cursor_created_at,p_cursor_id))
    AND (p_department IS NULL OR p_department='' OR coi.department=p_department)
    AND (p_sample_status IS NULL OR p_sample_status='' OR s.status::TEXT=p_sample_status)
    AND (p_order_date IS NULL OR o.order_date_ad=p_order_date)
    AND (
      p_view='All'
      OR (p_view='Pending' AND coi.status NOT IN ('Verified','SignedOff') AND report_row.report IS NULL)
      OR (p_view='ToVerify' AND coi.status NOT IN ('Verified','SignedOff') AND EXISTS(
        SELECT 1 FROM public.test_results pending_result
        WHERE pending_result.order_item_id=coi.id AND pending_result.status='SubmittedForVerification'
      ))
      OR (p_view='Verified' AND coi.status='Verified' AND report_row.report IS NULL)
      OR (p_view='Signed' AND (coi.status='SignedOff' OR report_row.report IS NOT NULL))
    )
    AND (
      term IS NULL
      OR (term~*'^BPDC-[0-9]{8}$' AND o.order_number=upper(term))
      OR (term!~*'^BPDC-[0-9]{8}$' AND (
        lower(p.full_name) LIKE '%'||escaped_term||'%' ESCAPE '\'
        OR lower(p.uhid) LIKE '%'||escaped_term||'%' ESCAPE '\'
        OR lower(o.order_number) LIKE '%'||escaped_term||'%' ESCAPE '\'
        OR lower(COALESCE(s.barcode,'')) LIKE '%'||escaped_term||'%' ESCAPE '\'
        OR lower(coi.test_name) LIKE '%'||escaped_term||'%' ESCAPE '\'
      ))
    )
  ORDER BY coi.created_at DESC,coi.id DESC
  LIMIT p_limit+1;
END $$;

REVOKE ALL ON FUNCTION public.search_laboratory_worklist(TEXT,TEXT,TEXT,DATE,TEXT,TIMESTAMPTZ,UUID,INT)
FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.search_laboratory_worklist(TEXT,TEXT,TEXT,DATE,TEXT,TIMESTAMPTZ,UUID,INT)
TO authenticated;

COMMENT ON FUNCTION public.search_laboratory_worklist(TEXT,TEXT,TEXT,DATE,TEXT,TIMESTAMPTZ,UUID,INT) IS
'RLS-preserving reportable worklist search with stable created_at/id keyset pagination.';
