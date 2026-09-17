-- Converge operational registries on bounded RLS-preserving server search.
-- Forward-only after production-applied 00072. No clinical, SMS, or artifact mutation.

CREATE INDEX IF NOT EXISTS patients_registry_cursor_idx ON public.patients(created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS samples_accession_cursor_idx ON public.samples(created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS bills_registry_cursor_idx ON public.bills(created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS diagnostic_reports_signed_cursor_idx ON public.diagnostic_reports(signed_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS bills_patient_name_snapshot_trgm_idx ON public.bills USING gin(lower(patient_name_snapshot) gin_trgm_ops);
CREATE INDEX IF NOT EXISTS diagnostic_reports_report_number_lower_idx ON public.diagnostic_reports(lower(report_number));

CREATE FUNCTION public.search_patient_registry(
  p_search TEXT DEFAULT NULL,
  p_active_state TEXT DEFAULT 'Active',
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
    AND (term IS NULL OR p.uhid=term OR p.mobile=regexp_replace(term,'[^0-9]','','g')
      OR lower(p.full_name) LIKE '%'||escaped||'%' ESCAPE '\')
  ORDER BY p.created_at DESC,p.id DESC LIMIT p_limit+1;
END $$;

CREATE FUNCTION public.search_sample_accessioning(
  p_search TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_specimen TEXT DEFAULT NULL,
  p_date DATE DEFAULT NULL,
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 50
) RETURNS TABLE(item JSONB)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE term TEXT:=NULLIF(btrim(p_search),''); escaped TEXT;
BEGIN
  IF p_limit<1 OR p_limit>100 THEN RAISE EXCEPTION 'Invalid sample page size.' USING ERRCODE='22023'; END IF;
  IF (p_cursor_created_at IS NULL)<>(p_cursor_id IS NULL) THEN RAISE EXCEPTION 'Incomplete sample cursor.' USING ERRCODE='22023'; END IF;
  escaped:=replace(replace(replace(lower(term),'\','\\'),'%','\%'),'_','\_');
  RETURN QUERY SELECT jsonb_build_object(
    'id',s.id,'barcode',s.barcode,'order_id',s.order_id,'patient_id',s.patient_id,
    'specimen_type',s.specimen_type,'container_type',s.container_type,'status',s.status,
    'collected_at',s.collected_at,'collected_by_name',s.collected_by_name,
    'received_at',s.received_at,'received_by_name',s.received_by_name,
    'rejected_at',s.rejected_at,'rejection_reason',s.rejection_reason,
    'recollected_from_sample_id',s.recollected_from_sample_id,'created_at',s.created_at,
    'order',jsonb_build_object('order_number',o.order_number,'order_date_bs',o.order_date_bs),
    'patient',jsonb_build_object('uhid',p.uhid,'full_name',p.full_name,'mobile',p.mobile,'gender',p.gender,'age_years',p.age_years),
    'items',COALESCE(items.rows,'[]'::jsonb)
  ) FROM public.samples s
  JOIN public.clinical_orders o ON o.id=s.order_id
  JOIN public.patients p ON p.id=s.patient_id
  LEFT JOIN LATERAL (SELECT jsonb_agg(jsonb_build_object('id',coi.id,'test_name',coi.test_name,'department',coi.department,'reporting_type',coi.reporting_type) ORDER BY coi.created_at,coi.id) rows FROM public.clinical_order_items coi WHERE coi.sample_id=s.id) items ON TRUE
  WHERE (p_cursor_created_at IS NULL OR (s.created_at,s.id)<(p_cursor_created_at,p_cursor_id))
    AND (p_status IS NULL OR p_status='' OR s.status::text=p_status)
    AND (p_specimen IS NULL OR p_specimen='' OR s.specimen_type=p_specimen)
    AND (p_date IS NULL OR o.order_date_ad=p_date)
    AND (term IS NULL OR s.barcode=term OR o.order_number=upper(term) OR p.uhid=term
      OR lower(p.full_name) LIKE '%'||escaped||'%' ESCAPE '\')
  ORDER BY s.created_at DESC,s.id DESC LIMIT p_limit+1;
END $$;

CREATE FUNCTION public.search_bill_registry(
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
  LEFT JOIN LATERAL (SELECT jsonb_agg(jsonb_build_object('id',bi.id,'test_name_snapshot',bi.test_name_snapshot,'test_code_snapshot',bi.test_code_snapshot,'reporting_type',bi.reporting_type,'unit_price_paisa',bi.unit_price_paisa) ORDER BY bi.created_at,bi.id) rows FROM public.bill_items bi WHERE bi.bill_id=b.id) items ON TRUE
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

CREATE FUNCTION public.search_report_registry(
  p_search TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_amendment_state TEXT DEFAULT 'All',
  p_date DATE DEFAULT NULL,
  p_cursor_signed_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 50
) RETURNS TABLE(item JSONB)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE term TEXT:=NULLIF(btrim(p_search),''); escaped TEXT;
BEGIN
  IF p_limit<1 OR p_limit>100 THEN RAISE EXCEPTION 'Invalid report page size.' USING ERRCODE='22023'; END IF;
  IF (p_cursor_signed_at IS NULL)<>(p_cursor_id IS NULL) THEN RAISE EXCEPTION 'Incomplete report cursor.' USING ERRCODE='22023'; END IF;
  IF p_amendment_state NOT IN ('All','Original','Amended') THEN RAISE EXCEPTION 'Invalid amendment state.' USING ERRCODE='22023'; END IF;
  escaped:=replace(replace(replace(lower(term),'\','\\'),'%','\%'),'_','\_');
  RETURN QUERY SELECT jsonb_build_object(
    'id',r.id,'order_id',r.order_id,'patient_id',r.patient_id,'report_number',r.report_number,
    'version',r.version,'is_amendment',r.is_amendment,'amendment_reason',r.amendment_reason,
    'amended_from_report_id',r.amended_from_report_id,'status',r.status,'integrity_hash',r.integrity_hash,
    'performed_by_personnel_name',r.performed_by_personnel_name,'signed_by_personnel_name',r.signed_by_personnel_name,
    'signed_at',r.signed_at,'pdf_storage_path',r.pdf_storage_path,'clinical_snapshot_json',r.clinical_snapshot_json,
    'patient',jsonb_build_object('uhid',p.uhid,'full_name',p.full_name,'mobile',p.mobile),
    'order',jsonb_build_object('order_number',o.order_number)
  ) FROM public.diagnostic_reports r
  JOIN public.patients p ON p.id=r.patient_id JOIN public.clinical_orders o ON o.id=r.order_id
  WHERE (p_cursor_signed_at IS NULL OR (r.signed_at,r.id)<(p_cursor_signed_at,p_cursor_id))
    AND (p_status IS NULL OR p_status='' OR r.status=p_status)
    AND (p_amendment_state='All' OR (p_amendment_state='Original' AND NOT r.is_amendment) OR (p_amendment_state='Amended' AND r.is_amendment))
    AND (p_date IS NULL OR (r.signed_at AT TIME ZONE 'Asia/Kathmandu')::date=p_date)
    AND (term IS NULL OR lower(r.report_number)=lower(term) OR o.order_number=upper(term) OR p.uhid=term
      OR lower(p.full_name) LIKE '%'||escaped||'%' ESCAPE '\')
  ORDER BY r.signed_at DESC,r.id DESC LIMIT p_limit+1;
END $$;

CREATE FUNCTION public.search_dashboard_orders(
  p_search TEXT DEFAULT NULL,
  p_workflow TEXT DEFAULT 'Today',
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 30
) RETURNS TABLE(item JSONB)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE term TEXT:=NULLIF(btrim(p_search),''); escaped TEXT;
BEGIN
  IF p_limit<1 OR p_limit>50 THEN RAISE EXCEPTION 'Invalid dashboard page size.' USING ERRCODE='22023'; END IF;
  IF (p_cursor_created_at IS NULL)<>(p_cursor_id IS NULL) THEN RAISE EXCEPTION 'Incomplete dashboard cursor.' USING ERRCODE='22023'; END IF;
  IF p_workflow NOT IN ('Today','Pending','Processing','AwaitingVerification','ReportReady') THEN RAISE EXCEPTION 'Invalid dashboard workflow.' USING ERRCODE='22023'; END IF;
  escaped:=replace(replace(replace(lower(term),'\','\\'),'%','\%'),'_','\_');
  RETURN QUERY SELECT jsonb_build_object(
    'id',o.id,'order_number',o.order_number,'status',o.status,'created_at',o.created_at,'bill_id',o.bill_id,
    'patient',jsonb_build_object('uhid',p.uhid,'full_name',p.full_name,'mobile',p.mobile,'age_years',p.age_years,'gender',p.gender),
    'bill',jsonb_build_object('bill_number',b.bill_number),'items',COALESCE(items.rows,'[]'::jsonb)
  ) FROM public.clinical_orders o JOIN public.patients p ON p.id=o.patient_id JOIN public.bills b ON b.id=o.bill_id
  LEFT JOIN LATERAL (SELECT jsonb_agg(jsonb_build_object('id',coi.id,'test_name',coi.test_name,'department',coi.department,'status',coi.status) ORDER BY coi.created_at,coi.id) rows FROM public.clinical_order_items coi WHERE coi.order_id=o.id) items ON TRUE
  WHERE (p_cursor_created_at IS NULL OR (o.created_at,o.id)<(p_cursor_created_at,p_cursor_id))
    AND (term IS NULL OR o.order_number=upper(term) OR b.bill_number=upper(term) OR p.uhid=term
      OR p.mobile=regexp_replace(term,'[^0-9]','','g') OR lower(p.full_name) LIKE '%'||escaped||'%' ESCAPE '\'
      OR EXISTS(SELECT 1 FROM public.clinical_order_items coi WHERE coi.order_id=o.id AND lower(coi.test_name) LIKE '%'||escaped||'%' ESCAPE '\'))
    AND (p_workflow<>'Today' OR (o.created_at AT TIME ZONE 'Asia/Kathmandu')::date=(now() AT TIME ZONE 'Asia/Kathmandu')::date)
    AND (p_workflow<>'Pending' OR EXISTS(SELECT 1 FROM public.samples s WHERE s.order_id=o.id AND s.status IN ('Pending','Collected')))
    AND (p_workflow<>'Processing' OR EXISTS(SELECT 1 FROM public.clinical_order_items coi WHERE coi.order_id=o.id AND coi.status IN ('SampleReceived','ResultDrafted')))
    AND (p_workflow<>'AwaitingVerification' OR EXISTS(SELECT 1 FROM public.test_results tr JOIN public.clinical_order_items coi ON coi.id=tr.order_item_id WHERE coi.order_id=o.id AND tr.status='SubmittedForVerification'))
    AND (p_workflow<>'ReportReady' OR EXISTS(SELECT 1 FROM public.clinical_order_items coi WHERE coi.order_id=o.id AND coi.status IN ('Verified','SignedOff')) OR EXISTS(SELECT 1 FROM public.diagnostic_reports r WHERE r.order_id=o.id AND r.status='SignedOff'))
  ORDER BY o.created_at DESC,o.id DESC LIMIT p_limit+1;
END $$;

REVOKE ALL ON FUNCTION public.search_patient_registry(TEXT,TEXT,TIMESTAMPTZ,UUID,INT) FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION public.search_sample_accessioning(TEXT,TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION public.search_bill_registry(TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION public.search_report_registry(TEXT,TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION public.search_dashboard_orders(TEXT,TEXT,TIMESTAMPTZ,UUID,INT) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.search_patient_registry(TEXT,TEXT,TIMESTAMPTZ,UUID,INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_sample_accessioning(TEXT,TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_bill_registry(TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_report_registry(TEXT,TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_dashboard_orders(TEXT,TEXT,TIMESTAMPTZ,UUID,INT) TO authenticated;

COMMENT ON FUNCTION public.search_patient_registry(TEXT,TEXT,TIMESTAMPTZ,UUID,INT) IS 'RLS-preserving patient search and keyset pagination.';
COMMENT ON FUNCTION public.search_sample_accessioning(TEXT,TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) IS 'RLS-preserving sample search and keyset pagination.';
COMMENT ON FUNCTION public.search_bill_registry(TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) IS 'RLS-preserving bill search and keyset pagination.';
COMMENT ON FUNCTION public.search_report_registry(TEXT,TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) IS 'RLS-preserving report search and keyset pagination.';
COMMENT ON FUNCTION public.search_dashboard_orders(TEXT,TEXT,TIMESTAMPTZ,UUID,INT) IS 'RLS-preserving dashboard workflow search without fan-out truncation.';
