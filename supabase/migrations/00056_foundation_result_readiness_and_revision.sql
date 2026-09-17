-- Foundation correction: one collection-readiness authority and optimistic
-- result concurrency. Forward-only; existing signed clinical rows are not
-- rewritten. Cloud SMS is deliberately outside this migration.

ALTER TABLE public.clinical_order_items
  ADD COLUMN result_revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE public.clinical_order_items
  ADD CONSTRAINT clinical_order_items_result_revision_nonnegative
  CHECK (result_revision >= 0);

COMMENT ON COLUMN public.clinical_order_items.result_revision IS
'Server-authoritative optimistic-concurrency revision for the complete result set of this order item.';

CREATE OR REPLACE FUNCTION public.clinical_result_collection_readiness(p_order_item_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  item public.clinical_order_items%ROWTYPE;
  sample public.samples%ROWTYPE;
  ready BOOLEAN := FALSE;
  reason TEXT;
BEGIN
  SELECT * INTO item FROM public.clinical_order_items WHERE id=p_order_item_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ready',FALSE,'code','RESULT_ITEM_NOT_FOUND');
  END IF;
  IF NOT item.clinical_reporting_enabled THEN
    RETURN jsonb_build_object('ready',FALSE,'code','RESULT_REPORTING_DISABLED');
  END IF;
  IF NOT item.collection_required THEN
    RETURN jsonb_build_object('ready',TRUE,'code','RESULT_COLLECTION_NOT_REQUIRED');
  END IF;
  IF item.sample_id IS NULL THEN
    RETURN jsonb_build_object('ready',FALSE,'code','RESULT_COLLECTION_NOT_READY','reason','SAMPLE_MISSING');
  END IF;

  SELECT * INTO sample FROM public.samples WHERE id=item.sample_id;
  IF NOT FOUND OR sample.order_id<>item.order_id THEN reason:='SAMPLE_ORDER_MISMATCH';
  ELSIF sample.status IN ('Pending','Rejected','Recollected') THEN reason:='SAMPLE_'||upper(sample.status::TEXT);
  ELSIF sample.status NOT IN ('Collected','Received','Processing','Completed') THEN reason:='SAMPLE_STATE_INVALID';
  ELSIF sample.collected_at IS NULL THEN reason:='COLLECTION_TIMESTAMP_MISSING';
  ELSIF sample.collected_by IS NULL OR NULLIF(btrim(COALESCE(sample.collected_by_name,'')),'') IS NULL
        OR NOT EXISTS(SELECT 1 FROM public.user_profiles u WHERE u.id=sample.collected_by) THEN
    reason:='COLLECTOR_IDENTITY_INVALID';
  ELSE ready:=TRUE;
  END IF;

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'ready',ready,
    'code',CASE WHEN ready THEN 'RESULT_COLLECTION_READY' ELSE 'RESULT_COLLECTION_NOT_READY' END,
    'reason',reason,
    'sample_id',sample.id,
    'sample_status',sample.status,
    'result_revision',item.result_revision
  ));
END $$;

CREATE OR REPLACE FUNCTION public.assert_clinical_result_ready(p_order_item_id UUID)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE state JSONB;
BEGIN
  state:=public.clinical_result_collection_readiness(p_order_item_id);
  IF NOT COALESCE((state->>'ready')::BOOLEAN,FALSE) THEN
    RAISE EXCEPTION USING
      ERRCODE='55000',
      MESSAGE=COALESCE(state->>'code','RESULT_COLLECTION_NOT_READY'),
      DETAIL=state::TEXT;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.guard_clinical_result_write()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public.assert_clinical_result_ready(NEW.order_item_id);
  RETURN NEW;
END $$;

-- The previously public mutation implementation becomes a private internal
-- primitive. Only the revision-aware wrapper below is exposed to clients.
ALTER FUNCTION public.save_test_results(UUID,JSONB,public.result_status_enum,UUID,TEXT)
  RENAME TO save_test_results_unversioned_internal;
REVOKE ALL ON FUNCTION public.save_test_results_unversioned_internal(UUID,JSONB,public.result_status_enum,UUID,TEXT)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.save_test_results(
  p_order_item_id UUID,
  p_results JSONB,
  p_target_status public.result_status_enum,
  p_amended_from_report_id UUID,
  p_amendment_reason TEXT,
  p_expected_revision BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE item public.clinical_order_items%ROWTYPE; response JSONB; next_revision BIGINT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE='42501'; END IF;
  IF p_expected_revision IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='RESULT_EXPECTED_REVISION_REQUIRED';
  END IF;
  SELECT * INTO item FROM public.clinical_order_items WHERE id=p_order_item_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Result work item was not found.' USING ERRCODE='P0002'; END IF;
  PERFORM public.assert_clinical_result_ready(p_order_item_id);
  IF item.result_revision<>p_expected_revision THEN
    RAISE EXCEPTION USING
      ERRCODE='PT409',
      MESSAGE='RESULT_REVISION_CONFLICT',
      DETAIL=jsonb_build_object('expected_revision',p_expected_revision,'current_revision',item.result_revision)::TEXT;
  END IF;

  response:=public.save_test_results_unversioned_internal(
    p_order_item_id,p_results,p_target_status,p_amended_from_report_id,p_amendment_reason
  );
  UPDATE public.clinical_order_items
  SET result_revision=result_revision+1
  WHERE id=p_order_item_id
  RETURNING result_revision INTO next_revision;
  RETURN response||jsonb_build_object('result_revision',next_revision);
END $$;

REVOKE ALL ON FUNCTION public.save_test_results(UUID,JSONB,public.result_status_enum,UUID,TEXT,BIGINT)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_test_results(UUID,JSONB,public.result_status_enum,UUID,TEXT,BIGINT)
  TO authenticated;
REVOKE ALL ON FUNCTION public.clinical_result_collection_readiness(UUID),public.assert_clinical_result_ready(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

-- Readiness is the same authority used by result writes. Sample state never
-- changes result, verification or report state; it only gates eligibility.
CREATE OR REPLACE FUNCTION public.check_order_report_readiness(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE reportable_count INT:=0; verified_count INT:=0; collection_not_ready_count INT:=0;
  unverified_items JSONB:='[]'; collection_not_ready_items JSONB:='[]';
  unack_count INT:=0; unack_items JSONB:='[]'; item RECORD; res RECORD; state JSONB;
BEGIN
  IF NOT public.is_active_user() OR NOT(public.has_permission('can_enter_results') OR public.has_permission('can_verify_results') OR public.has_permission('can_sign_reports')) THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;
  FOR item IN SELECT coi.id,coi.test_name,coi.department,coi.status FROM public.clinical_order_items coi
    WHERE coi.order_id=p_order_id AND coi.clinical_reporting_enabled
      AND coi.reporting_type IN ('InHouse','OutsourceWithBimalReport') LOOP
    reportable_count:=reportable_count+1;
    state:=public.clinical_result_collection_readiness(item.id);
    IF NOT COALESCE((state->>'ready')::BOOLEAN,FALSE) THEN
      collection_not_ready_count:=collection_not_ready_count+1;
      collection_not_ready_items:=collection_not_ready_items||jsonb_build_object('order_item_id',item.id,'test_name',item.test_name,'readiness',state);
    END IF;
    IF item.status IN ('Verified','SignedOff') THEN verified_count:=verified_count+1;
    ELSE unverified_items:=unverified_items||jsonb_build_object('order_item_id',item.id,'test_name',item.test_name,'department',item.department,'status',item.status); END IF;
  END LOOP;
  FOR res IN SELECT tr.id,tr.parameter_name,tr.display_value,tr.unit,tr.flag,tr.critical_acknowledged,coi.test_name
    FROM public.test_results tr JOIN public.clinical_order_items coi ON coi.id=tr.order_item_id
    WHERE coi.order_id=p_order_id AND coi.clinical_reporting_enabled
      AND (tr.is_critical OR tr.flag IN ('CriticalLow','CriticalHigh')) AND NOT tr.critical_acknowledged LOOP
    unack_count:=unack_count+1;
    unack_items:=unack_items||jsonb_build_object('result_id',res.id,'test_name',res.test_name,'parameter_name',res.parameter_name,'display_value',res.display_value,'unit',res.unit,'flag',res.flag);
  END LOOP;
  RETURN jsonb_build_object(
    'is_ready',reportable_count>0 AND verified_count=reportable_count AND collection_not_ready_count=0 AND unack_count=0,
    'reportable_count',reportable_count,'verified_count',verified_count,
    'unverified_count',reportable_count-verified_count,'unverified_items',unverified_items,
    'collection_not_ready_count',collection_not_ready_count,'collection_not_ready_items',collection_not_ready_items,
    'unacknowledged_critical_count',unack_count,'unacknowledged_critical_items',unack_items
  );
END $$;

REVOKE ALL ON FUNCTION public.check_order_report_readiness(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.check_order_report_readiness(UUID) TO authenticated;

COMMENT ON FUNCTION public.clinical_result_collection_readiness(UUID) IS
'Single authoritative sample/result eligibility predicate. It never advances result, verification or report lifecycle state.';
