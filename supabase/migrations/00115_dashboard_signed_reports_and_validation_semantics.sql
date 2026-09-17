-- Migration 00115: Dashboard Signed Reports Semantics & Exact KPI Consistency
-- 1. Aligns Admin and Technician signed reports to signed_at timestamp on Nepal business-day (Asia/Kathmandu)
-- 2. Aligns Pending Results on dashboard and worklist to status IN ('SampleReceived', 'ResultDrafted')
-- 3. Extends search_patient_registry with optional date filter for exact dashboard click-through

-- ============================================================================
-- 1. ADMIN DASHBOARD OPERATIONAL SUMMARY
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_dashboard_operational_summary()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_today_date DATE := (now() AT TIME ZONE 'Asia/Kathmandu')::date;
    v_departments JSONB;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.has_permission('can_view_financials') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object('dept', department, 'count', item_count)
               ORDER BY department), '[]'::jsonb)
      INTO v_departments
      FROM (
        SELECT COALESCE(NULLIF(btrim(department), ''), 'Unassigned') AS department,
               count(*)::INT AS item_count
          FROM public.clinical_order_items
         WHERE status IN ('Pending', 'SampleCollected', 'SampleReceived', 'ResultDrafted')
         GROUP BY 1
      ) workload;

    RETURN jsonb_build_object(
        'today_patients', (SELECT count(*) FROM public.patients WHERE (created_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'today_invoices', (SELECT count(*) FROM public.bills WHERE (created_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'today_collection_paisa', (SELECT COALESCE(sum(amount_paisa), 0) FROM public.payment_transactions WHERE (created_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'outstanding_due_paisa', (SELECT COALESCE(sum(due_amount_paisa), 0) FROM public.bills WHERE due_amount_paisa > 0),
        'pending_samples', (SELECT count(*) FROM public.samples WHERE status = 'Pending'),
        'received_samples', (SELECT count(*) FROM public.samples WHERE status = 'Received'),
        'rejected_samples', (SELECT count(*) FROM public.samples WHERE status = 'Rejected'),
        'pending_results', (SELECT count(*) FROM public.clinical_order_items WHERE status IN ('SampleReceived', 'ResultDrafted')),
        'awaiting_verification', (
            SELECT count(DISTINCT coi.id)
            FROM public.clinical_order_items coi
            WHERE coi.status NOT IN ('Verified', 'SignedOff')
              AND EXISTS (
                SELECT 1
                FROM public.test_results tr
                WHERE tr.order_item_id = coi.id
                  AND tr.status = 'SubmittedForVerification'
              )
        ),
        'signed_reports', (SELECT count(*) FROM public.diagnostic_reports WHERE status = 'SignedOff' AND signed_at IS NOT NULL AND (signed_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'signed_reports_today', (SELECT count(*) FROM public.diagnostic_reports WHERE status = 'SignedOff' AND signed_at IS NOT NULL AND (signed_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'total_signed_reports', (SELECT count(*) FROM public.diagnostic_reports WHERE status = 'SignedOff'),
        'critical_unacknowledged', (SELECT count(*) FROM public.test_results WHERE is_critical = TRUE AND critical_acknowledged = FALSE),
        'department_workload', v_departments
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_dashboard_operational_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_dashboard_operational_summary() TO authenticated;

-- ============================================================================
-- 2. TECHNICIAN DASHBOARD OPERATIONAL SUMMARY
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_technician_operational_summary()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_today_date DATE := (now() AT TIME ZONE 'Asia/Kathmandu')::date;
BEGIN
    IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT public.has_permission('can_view_dashboard') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object(
        'today_patients', (SELECT count(*) FROM public.patients WHERE (created_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'today_orders', (SELECT count(*) FROM public.clinical_orders WHERE (created_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'samples_pending', (SELECT count(*) FROM public.samples WHERE status = 'Pending'),
        'samples_received', (SELECT count(*) FROM public.samples WHERE status = 'Received'),
        'samples_rejected', (SELECT count(*) FROM public.samples WHERE status = 'Rejected'),
        'worklist_pending', (SELECT count(*) FROM public.clinical_order_items WHERE status IN ('SampleReceived', 'ResultDrafted')),
        'result_entry_pending', (SELECT count(*) FROM public.clinical_order_items WHERE status = 'SampleReceived'),
        'awaiting_verification', (
            SELECT count(DISTINCT coi.id)
            FROM public.clinical_order_items coi
            WHERE coi.status NOT IN ('Verified', 'SignedOff')
              AND EXISTS (
                SELECT 1
                FROM public.test_results tr
                WHERE tr.order_item_id = coi.id
                  AND tr.status = 'SubmittedForVerification'
              )
        ),
        'specialist_microbiology_pending', (SELECT count(*) FROM public.clinical_order_items oi JOIN public.tests t ON t.id = oi.test_id WHERE t.code = 'PUS_CULTURE_AND_SENSITIVITY' AND oi.status NOT IN ('Verified', 'SignedOff')),
        'signed_reports_today', (SELECT count(*) FROM public.diagnostic_reports WHERE status = 'SignedOff' AND signed_at IS NOT NULL AND (signed_at AT TIME ZONE 'Asia/Kathmandu')::date = v_today_date),
        'critical_unacknowledged', (SELECT count(*) FROM public.test_results WHERE is_critical AND NOT critical_acknowledged),
        'department_workload', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object('department', x.department, 'count', x.count) ORDER BY x.department), '[]'::JSONB)
              FROM (
                SELECT COALESCE(NULLIF(btrim(department), ''), 'Unassigned') AS department, count(*) AS count
                  FROM public.clinical_order_items
                 WHERE status IN ('Pending', 'SampleCollected', 'SampleReceived', 'ResultDrafted', 'Verified')
                 GROUP BY 1
              ) x
        ),
        'recent_orders', (
            SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC), '[]'::JSONB)
              FROM (
                SELECT o.id, o.order_number, o.status, o.created_at, p.uhid, p.full_name, p.age_years, p.gender
                  FROM public.clinical_orders o
                  JOIN public.patients p ON p.id = o.patient_id
                 ORDER BY o.created_at DESC LIMIT 8
              ) x
        ),
        'critical_items', (
            SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::JSONB)
              FROM (
                SELECT tr.id, tr.parameter_name, tr.display_value, tr.flag
                  FROM public.test_results tr
                 WHERE tr.is_critical AND NOT tr.critical_acknowledged
                 ORDER BY tr.created_at DESC LIMIT 5
              ) x
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_technician_operational_summary() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_technician_operational_summary() TO authenticated;

-- ============================================================================
-- 3. EXTEND PATIENT REGISTRY SEARCH WITH OPTIONAL DATE FILTER
-- ============================================================================
CREATE OR REPLACE FUNCTION public.search_patient_registry(
  p_search TEXT DEFAULT NULL,
  p_active_state TEXT DEFAULT 'Active',
  p_date DATE DEFAULT NULL,
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 50
) RETURNS TABLE(item JSONB)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE term TEXT:=NULLIF(btrim(p_search),''); escaped TEXT;
BEGIN
  IF p_limit<1 OR p_limit>100 THEN RAISE EXCEPTION 'Invalid patient page size.' USING ERRCODE='22023'; END IF;
  IF (p_cursor_created_at IS NULL)<>(p_cursor_id IS NULL) THEN RAISE EXCEPTION 'Incomplete patient cursor.' USING ERRCODE='22023'; END IF;
  IF p_active_state NOT IN ('Active','Archived','All') THEN RAISE EXCEPTION 'Invalid patient state.' USING ERRCODE='22023'; END IF;
  escaped:=replace(replace(replace(lower(term),'\','\\'),'%','\%'),'_','\_');
  RETURN QUERY SELECT jsonb_build_object(
    'id',p.id,'uhid',p.uhid,'mobile',p.mobile,'title',p.title,'full_name',p.full_name,
    'gender',p.gender,'dob',p.dob,'age_years',p.age_years,'age_months',p.age_months,
    'age_days',p.age_days,'address',p.address,'email',p.email,'identification_no',p.identification_no,
    'is_active',p.is_active,'archived_at',p.archived_at,'created_at',p.created_at
  ) FROM public.patients p
  WHERE (p_cursor_created_at IS NULL OR (p.created_at,p.id)<(p_cursor_created_at,p_cursor_id))
    AND (p_active_state='All' OR (p_active_state='Active' AND p.is_active) OR (p_active_state='Archived' AND NOT p.is_active))
    AND (p_date IS NULL OR (p.created_at AT TIME ZONE 'Asia/Kathmandu')::date=p_date)
    AND (term IS NULL OR p.uhid=term OR p.mobile=regexp_replace(term,'[^0-9]','','g')
      OR lower(p.full_name) LIKE '%'||escaped||'%' ESCAPE '\')
  ORDER BY p.created_at DESC,p.id DESC LIMIT p_limit+1;
END $$;

REVOKE ALL ON FUNCTION public.search_patient_registry(TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.search_patient_registry(TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) TO authenticated;
COMMENT ON FUNCTION public.search_patient_registry(TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) IS 'RLS-preserving patient search and keyset pagination with optional date filter.';

-- ============================================================================
-- 4. ALIGN WORKLIST SEARCH PENDING VIEW EXACTLY TO SAMPLE_RECEIVED / RESULT_DRAFTED
-- ============================================================================
CREATE OR REPLACE FUNCTION public.search_laboratory_worklist(
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
      OR (p_view='Pending' AND coi.status IN ('SampleReceived','ResultDrafted'))
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
END;
$$;

REVOKE ALL ON FUNCTION public.search_laboratory_worklist(TEXT,TEXT,TEXT,DATE,TEXT,TIMESTAMPTZ,UUID,INT) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.search_laboratory_worklist(TEXT,TEXT,TEXT,DATE,TEXT,TIMESTAMPTZ,UUID,INT) TO authenticated;
COMMENT ON FUNCTION public.search_laboratory_worklist(TEXT,TEXT,TEXT,DATE,TEXT,TIMESTAMPTZ,UUID,INT) IS 'RLS-preserving laboratory worklist search with exact Pending status alignment.';
