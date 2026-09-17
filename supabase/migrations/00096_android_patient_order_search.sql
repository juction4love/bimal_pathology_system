-- 00096_android_patient_order_search.sql
-- Query-only patient order search. The patient scope is always derived from auth.uid().

CREATE OR REPLACE FUNCTION public.search_my_report_orders(
  p_query TEXT,
  p_limit INT DEFAULT 25,
  p_offset INT DEFAULT 0
) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_uid UUID;
  v_patient_id UUID;
  v_query TEXT;
  v_orders JSONB;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;

  -- Do not accept patient, UHID, or mobile identifiers from the client.
  SELECT patient_id INTO v_patient_id
  FROM public.patient_app_identities
  WHERE auth_user_id = v_uid AND status = 'LINKED';

  IF v_patient_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  v_query := btrim(coalesce(p_query, ''));
  IF v_query = '' THEN RETURN '[]'::jsonb; END IF;

  p_limit := least(greatest(coalesce(p_limit, 25), 1), 50);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  SELECT coalesce(jsonb_agg(x.row_data), '[]'::jsonb)
  INTO v_orders
  FROM (
    SELECT jsonb_build_object(
      'order_id', o.id,
      'order_number', o.order_number,
      'order_date_ad', o.order_date_ad,
      'order_date_bs', o.order_date_bs,
      'created_at', o.created_at,
      'total_groups', coalesce(grp.total_groups, 0),
      'ready_groups', coalesce(grp.ready_groups, 0),
      'overall_status', CASE
        WHEN coalesce(grp.total_groups, 0) = 0 THEN 'Pending'
        WHEN grp.ready_groups = grp.total_groups THEN 'Ready'
        WHEN grp.ready_groups > 0 THEN 'Partially Ready'
        ELSE 'Pending'
      END
    ) AS row_data
    FROM public.clinical_orders o
    LEFT JOIN LATERAL (
      SELECT
        count(g.id)::int AS total_groups,
        count(g.id) FILTER (
          WHERE EXISTS (
            SELECT 1
            FROM public.diagnostic_reports dr
            JOIN public.report_pdf_artifacts a ON a.diagnostic_report_id = dr.id
            WHERE dr.report_group_id = g.id
              AND dr.status IN ('SignedOff', 'Amended')
              AND a.generation_status = 'Ready'
          )
        )::int AS ready_groups
      FROM public.clinical_report_groups g
      WHERE g.order_id = o.id
    ) grp ON true
    WHERE o.patient_id = v_patient_id
      AND (
        o.order_number ILIKE '%' || v_query || '%'
        OR o.order_date_ad::TEXT ILIKE '%' || v_query || '%'
        OR coalesce(o.order_date_bs, '') ILIKE '%' || v_query || '%'
        OR EXISTS (
          SELECT 1
          FROM public.clinical_order_items oi
          WHERE oi.order_id = o.id
            AND coalesce(oi.test_name, '') ILIKE '%' || v_query || '%'
        )
      )
    ORDER BY o.order_date_ad DESC, o.created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) x;

  RETURN v_orders;
END;
$$;

REVOKE ALL ON FUNCTION public.search_my_report_orders(TEXT, INT, INT)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.search_my_report_orders(TEXT, INT, INT)
  TO authenticated;
