-- Keep the approved panel-service rate authoritative when expanding a panel
-- into its canonical component tests. The underlying billing worker normally
-- replaces client prices with standalone catalogue prices; panel components
-- therefore need the same transaction-local override already used by package
-- billing. Row locks make this safe under concurrent billing, and the catalogue
-- flags are restored before commit (or automatically by transaction rollback).
CREATE OR REPLACE FUNCTION public.create_patient_bill_order_with_panel_service(
  p_patient_data JSONB,
  p_bill_data JSONB,
  p_payment_data JSONB,
  p_idempotency_key TEXT,
  p_panel_service_id UUID,
  p_expected_panel_version BIGINT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  svc public.catalogue_panel_services%ROWTYPE;
  pnl public.catalogue_panels%ROWTYPE;
  rate public.catalogue_rate_versions%ROWTYPE;
  items JSONB[];
  response JSONB;
  bill_uuid UUID;
  selection_uuid UUID;
  component_snapshot JSONB;
  component_ids UUID[];
  temporary_manual_price_ids UUID[]:=ARRAY[]::UUID[];
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;

  SELECT * INTO svc
  FROM public.catalogue_panel_services
  WHERE id=p_panel_service_id AND lifecycle_status='Active'
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Panel service is inactive or missing.' USING ERRCODE='23503';
  END IF;

  SELECT * INTO pnl
  FROM public.catalogue_panels
  WHERE id=svc.panel_id AND lifecycle_status='Active'
  FOR SHARE;
  IF pnl.row_version<>p_expected_panel_version THEN
    RAISE EXCEPTION 'Panel definition changed. Refresh billing catalogue.' USING ERRCODE='PT409';
  END IF;

  SELECT * INTO rate
  FROM public.catalogue_rate_versions
  WHERE panel_service_id=svc.id
    AND status='Active'
    AND price_paisa IS NOT NULL
    AND COALESCE(effective_from,now())<=now()
    AND (effective_to IS NULL OR effective_to>now())
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Price not specified. A Super Admin must activate a panel rate before billing.' USING ERRCODE='23514';
  END IF;

  IF EXISTS(
    SELECT 1 FROM public.catalogue_panel_service_components(svc.id) c
    WHERE c.readiness<>'Ready'
  ) THEN
    RAISE EXCEPTION 'Result Structure Incomplete. Configure Result Structure before billing this panel.' USING ERRCODE='23514';
  END IF;

  SELECT
    array_agg(
      jsonb_build_object(
        'test_id',c.test_id,
        'unit_price_paisa',CASE WHEN c.display_order=min_ord THEN rate.price_paisa ELSE 0 END,
        'discount_paisa',0,
        'zero_price_acknowledged',TRUE
      ) ORDER BY c.display_order
    ),
    jsonb_agg(
      jsonb_build_object(
        'test_id',c.test_id,
        'test_code',c.test_code,
        'test_name',c.test_name,
        'display_order',c.display_order
      ) ORDER BY c.display_order
    ),
    array_agg(c.test_id ORDER BY c.test_id)
  INTO items,component_snapshot,component_ids
  FROM public.catalogue_panel_service_components(svc.id) c
  CROSS JOIN (
    SELECT min(display_order) min_ord
    FROM public.catalogue_panel_service_components(svc.id)
  ) x;

  IF items IS NULL THEN
    RAISE EXCEPTION 'Panel has no canonical component tests.' USING ERRCODE='23514';
  END IF;

  PERFORM 1
  FROM public.tests t
  WHERE t.id=ANY(component_ids)
  ORDER BY t.id
  FOR UPDATE;

  SELECT COALESCE(array_agg(t.id ORDER BY t.id),ARRAY[]::UUID[])
  INTO temporary_manual_price_ids
  FROM public.tests t
  WHERE t.id=ANY(component_ids) AND NOT t.allow_manual_price;

  IF cardinality(temporary_manual_price_ids)>0 THEN
    UPDATE public.tests SET allow_manual_price=TRUE
    WHERE id=ANY(temporary_manual_price_ids);
  END IF;

  response:=public.create_patient_bill_and_order(
    p_patient_data,p_bill_data,items,p_payment_data,p_idempotency_key
  );
  bill_uuid:=(response->>'bill_id')::UUID;

  IF cardinality(temporary_manual_price_ids)>0 THEN
    UPDATE public.tests SET allow_manual_price=FALSE
    WHERE id=ANY(temporary_manual_price_ids);
  END IF;

  INSERT INTO public.bill_panel_selections(
    bill_id,panel_service_id,panel_id,service_code_snapshot,panel_name_snapshot,
    panel_price_paisa,rate_version_id,component_snapshot
  ) VALUES(
    bill_uuid,svc.id,pnl.id,svc.code,pnl.name,rate.price_paisa,rate.id,component_snapshot
  ) RETURNING id INTO selection_uuid;

  INSERT INTO public.bill_panel_components(
    bill_panel_selection_id,bill_item_id,test_id,display_order
  )
  SELECT selection_uuid,bi.id,bi.test_id,(x->>'display_order')::INT
  FROM jsonb_array_elements(component_snapshot) x
  JOIN public.bill_items bi
    ON bi.bill_id=bill_uuid AND bi.test_id=(x->>'test_id')::UUID;

  RETURN response||jsonb_build_object(
    'panel_selection_id',selection_uuid,
    'panel_service_id',svc.id,
    'rate_version_id',rate.id
  );
END
$$;

REVOKE ALL ON FUNCTION public.create_patient_bill_order_with_panel_service(
  JSONB,JSONB,JSONB,TEXT,UUID,BIGINT
) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_order_with_panel_service(
  JSONB,JSONB,JSONB,TEXT,UUID,BIGINT
) TO authenticated;

COMMENT ON FUNCTION public.create_patient_bill_order_with_panel_service(
  JSONB,JSONB,JSONB,TEXT,UUID,BIGINT
) IS 'Atomic panel billing using the active immutable panel rate while preserving canonical component traceability.';
