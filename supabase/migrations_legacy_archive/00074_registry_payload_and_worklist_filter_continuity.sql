-- Correct registry payload/filter continuity after production-applied 00073.
-- Forward-only. No clinical, SMS, authentication, or artifact data mutation.

CREATE OR REPLACE FUNCTION public.search_bill_registry(
  p_search TEXT DEFAULT NULL,
  p_payment_status TEXT DEFAULT NULL,
  p_date DATE DEFAULT NULL,
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 50
) RETURNS TABLE(item JSONB)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE term TEXT:=NULLIF(btrim(p_search),''); escaped TEXT;
BEGIN
  IF p_limit<1 OR p_limit>100 THEN RAISE EXCEPTION 'Invalid bill page size.' USING ERRCODE='22023'; END IF;
  IF (p_cursor_created_at IS NULL)<>(p_cursor_id IS NULL) THEN RAISE EXCEPTION 'Incomplete bill cursor.' USING ERRCODE='22023'; END IF;
  escaped:=replace(replace(replace(lower(term),'\','\\'),'%','\%'),'_','\_');
  RETURN QUERY SELECT jsonb_build_object(
    'id',b.id,'bill_number',b.bill_number,'patient_id',b.patient_id,
    'patient_uhid_snapshot',b.patient_uhid_snapshot,'patient_name_snapshot',b.patient_name_snapshot,
    'patient_mobile_snapshot',b.patient_mobile_snapshot,'patient_age_gender_snapshot',b.patient_age_gender_snapshot,
    'referring_doctor_name_snapshot',b.referring_doctor_name_snapshot,'gross_amount_paisa',b.gross_amount_paisa,
    'discount_amount_paisa',b.discount_amount_paisa,'discount_reason',b.discount_reason,
    'net_amount_paisa',b.net_amount_paisa,'paid_amount_paisa',b.paid_amount_paisa,
    'due_amount_paisa',b.due_amount_paisa,'payment_status',b.payment_status,'remarks',b.remarks,'created_at',b.created_at,
    'bill_items',COALESCE(items.rows,'[]'::jsonb),'payment_transactions',COALESCE(payments.rows,'[]'::jsonb),
    'outsource_samples',COALESCE(outsource.rows,'[]'::jsonb)
  ) FROM public.bills b
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(jsonb_build_object(
      'id',bi.id,'test_name_snapshot',bi.test_name_snapshot,'test_code_snapshot',bi.test_code_snapshot,
      'reporting_type',bi.reporting_type,'unit_price_paisa',bi.unit_price_paisa,
      'item_description',bi.item_description
    ) ORDER BY bi.created_at,bi.id) rows
    FROM public.bill_items bi WHERE bi.bill_id=b.id
  ) items ON TRUE
  LEFT JOIN LATERAL (SELECT jsonb_agg(jsonb_build_object('id',pt.id,'receipt_number',pt.receipt_number,'amount_paisa',pt.amount_paisa,'payment_mode',pt.payment_mode,'transaction_reference',pt.transaction_reference,'created_at',pt.created_at) ORDER BY pt.created_at,pt.id) rows FROM public.payment_transactions pt WHERE pt.bill_id=b.id) payments ON TRUE
  LEFT JOIN LATERAL (SELECT jsonb_agg(jsonb_build_object('id',os.id,'tracking_number',os.tracking_number,'service_description',os.service_description,'specimen_type',os.specimen_type,'status',os.status) ORDER BY os.created_at,os.id) rows FROM public.outsource_samples os WHERE os.bill_id=b.id) outsource ON TRUE
  WHERE (p_cursor_created_at IS NULL OR (b.created_at,b.id)<(p_cursor_created_at,p_cursor_id))
    AND (p_payment_status IS NULL OR p_payment_status='' OR b.payment_status::text=p_payment_status)
    AND (p_date IS NULL OR (b.created_at AT TIME ZONE 'Asia/Kathmandu')::date=p_date)
    AND (term IS NULL OR b.bill_number=upper(term) OR b.patient_uhid_snapshot=term
      OR b.patient_mobile_snapshot=regexp_replace(term,'[^0-9]','','g')
      OR lower(b.patient_name_snapshot) LIKE '%'||escaped||'%' ESCAPE '\'
      OR EXISTS(SELECT 1 FROM public.clinical_orders o WHERE o.bill_id=b.id AND o.order_number=upper(term)))
  ORDER BY b.created_at DESC,b.id DESC LIMIT p_limit+1;
END $$;

CREATE FUNCTION public.list_laboratory_worklist_departments()
RETURNS TABLE(department TEXT)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
  SELECT DISTINCT coi.department
  FROM public.clinical_order_items coi
  WHERE coi.clinical_reporting_enabled = true
    AND coi.reporting_type IN ('InHouse','OutsourceWithBimalReport')
    AND NULLIF(btrim(coi.department),'') IS NOT NULL
  ORDER BY coi.department;
$$;

REVOKE ALL ON FUNCTION public.search_bill_registry(TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION public.list_laboratory_worklist_departments() FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.search_bill_registry(TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_laboratory_worklist_departments() TO authenticated;

COMMENT ON FUNCTION public.search_bill_registry(TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) IS 'RLS-preserving bill search with complete invoice item display evidence.';
COMMENT ON FUNCTION public.list_laboratory_worklist_departments() IS 'RLS-preserving reportable worklist department filter options independent of the current page.';
