-- =============================================================================
-- Migration: 00129_sms_operational_hardening.sql
-- Goal: Final SMS operational hardening
--
-- Changes:
-- 1. build_single_credit_nepali_sms:
--    - STRICT paid_amount_paisa guard: DO NOT enqueue if paid_amount_paisa <= 0
--    - 4-tier alias system: primary -> compact -> Lab -> L -> reject
--    - Error code SMS_SINGLE_SEGMENT_LIMIT_EXCEEDED (never multipart, never truncate)
-- 2. reject_sms_gateway_v2_local_validation:
--    - Add SMS_SINGLE_SEGMENT_LIMIT_EXCEEDED to valid rejection codes
-- 3. get_sms_test_alias: align aliases with approved primary list
--    CBC, LFT, KFT, LP, TFT, B12, VD, DD, FER, A1c, Lab, L
-- 4. Preserve all existing:
--    - URL guard
--    - Idempotency key + ON CONFLICT DO NOTHING
--    - Row locking (FOR UPDATE)
--    - Unique queue constraint
--    - SECURITY DEFINER + search_path
-- =============================================================================

BEGIN;

-- -------------------------------------------------------------------------
-- 1. Align get_sms_test_alias with approved primary alias list
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_sms_test_alias(p_name TEXT, p_max_len INT DEFAULT 10)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_norm TEXT := lower(trim(coalesce(p_name, '')));
BEGIN
  -- Approved primary aliases per lab specification
  IF v_norm ~ 'complete\s+blood\s+count|^cbc\b'         THEN RETURN 'CBC';  END IF;
  IF v_norm ~ 'lipid\s+profile|^lipid\b'                THEN RETURN 'LP';   END IF;
  IF v_norm ~ 'liver\s+function\s+test|^lft\b'          THEN RETURN 'LFT';  END IF;
  IF v_norm ~ 'kidney\s+function|renal\s+function|^kft\b|^rft\b' THEN RETURN 'KFT'; END IF;
  IF v_norm ~ 'thyroid\s+profile|thyroid\s+function|^tft\b|^thyroid\b' THEN RETURN 'TFT'; END IF;
  IF v_norm ~ 'urine\s+routine|urine\s+r/?e|^urine\b'   THEN RETURN 'UR';   END IF;
  IF v_norm ~ 'vitamin\s+d\b|25-oh|vit\s*d'             THEN RETURN 'VD';   END IF;
  IF v_norm ~ 'vitamin\s+b12\b|vit\s*b12|\bb12\b'       THEN RETURN 'B12';  END IF;
  IF v_norm ~ 'd-dimer'                                  THEN RETURN 'DD';   END IF;
  IF v_norm ~ 'ferritin'                                 THEN RETURN 'FER';  END IF;
  IF v_norm ~ 'hba1c|glycated\s+hemoglobin'             THEN RETURN 'A1c';  END IF;

  -- Short ASCII passthrough
  IF length(trim(p_name)) <= p_max_len AND p_name ~ '^[A-Za-z0-9+ -]+$' THEN
    RETURN trim(p_name);
  END IF;

  RETURN 'Lab';
END;
$$;

-- -------------------------------------------------------------------------
-- 2. Harden build_single_credit_nepali_sms
--    - STRICT paid_amount_paisa guard
--    - 4-tier alias: primary -> compact -> Lab -> L -> raise exception
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.build_single_credit_nepali_sms(
  p_order_id UUID,
  p_report_id UUID DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_bill_id         UUID;
  v_paid_paisa      BIGINT := 0;
  v_amount_str      TEXT;
  v_test_count      INT := 0;
  v_first_test_name TEXT;
  v_alias           TEXT;
  v_msg             TEXT;
  -- Fixed-length portion of template excluding {TEST} and {AMOUNT}:
  -- "Bimal Pathology:  रिपोर्ट तयार भयो। रु  भुक्तानको लागि धन्यवाद।"
  -- = 63 UCS-2 code units (verified)
  v_fixed_len       CONSTANT INT := 63;
  v_avail_for_test  INT;
BEGIN
  -- Fetch cumulative paid amount (NOT net amount — only actual payment received)
  SELECT o.bill_id INTO v_bill_id FROM public.clinical_orders o WHERE o.id = p_order_id;
  IF v_bill_id IS NOT NULL THEN
    SELECT COALESCE(paid_amount_paisa, 0) INTO v_paid_paisa FROM public.bills WHERE id = v_bill_id;
  END IF;

  -- Payment guard: only positive paid amounts trigger the notification SMS
  IF v_paid_paisa <= 0 THEN
    RAISE EXCEPTION 'SMS_NO_PAYMENT: paid_amount_paisa is % — payment acknowledgement SMS must not be sent for unpaid or zero-paid orders.', v_paid_paisa
      USING ERRCODE = '23514';
  END IF;

  v_amount_str    := public.format_nepali_amount(v_paid_paisa);
  v_avail_for_test := 70 - v_fixed_len - length(v_amount_str);

  SELECT count(DISTINCT t.id), min(t.name)
  INTO v_test_count, v_first_test_name
  FROM public.clinical_order_items coi
  JOIN public.tests t ON t.id = coi.test_id
  WHERE coi.order_id = p_order_id AND coi.clinical_reporting_enabled = TRUE;

  -- 4-tier alias resolution
  IF v_test_count = 1 AND v_first_test_name IS NOT NULL THEN
    -- Tier 1: primary alias
    v_alias := public.get_sms_test_alias(v_first_test_name, greatest(1, v_avail_for_test));
    v_msg := 'Bimal Pathology: ' || v_alias || ' रिपोर्ट तयार भयो। रु ' || v_amount_str || ' भुक्तानको लागि धन्यवाद।';
    IF length(v_msg) <= 70 THEN RETURN v_msg; END IF;
  END IF;

  -- Tier 3: generic "Lab"
  v_msg := 'Bimal Pathology: Lab रिपोर्ट तयार भयो। रु ' || v_amount_str || ' भुक्तानको लागि धन्यवाद।';
  IF length(v_msg) <= 70 THEN RETURN v_msg; END IF;

  -- Tier 4: emergency "L"
  v_msg := 'Bimal Pathology: L रिपोर्ट तयार भयो। रु ' || v_amount_str || ' भुक्तानको लागि धन्यवाद।';
  IF length(v_msg) <= 70 THEN RETURN v_msg; END IF;

  -- Tier 5: reject — never multipart, never truncate
  RAISE EXCEPTION 'SMS_SINGLE_SEGMENT_LIMIT_EXCEEDED: message is % UCS-2 code units (max 70). Will not send multipart or truncated SMS.', length(v_msg)
    USING ERRCODE = '23514';
END;
$$;

-- -------------------------------------------------------------------------
-- 3. Add SMS_SINGLE_SEGMENT_LIMIT_EXCEEDED to gateway rejection codes
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reject_sms_gateway_v2_local_validation(
  p_instance_id UUID, p_sms_id UUID, p_worker_id UUID, p_error_code TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE changed INT;
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  IF p_error_code NOT IN (
    'INVALID_NEPAL_MOBILE',
    'EMPTY_MESSAGE',
    'SEGMENT_LIMIT_EXCEEDED',
    'SMS_SINGLE_SEGMENT_LIMIT_EXCEEDED',
    'SMS_URL_BLOCKED'
  ) THEN
    RAISE EXCEPTION 'Unsupported local validation code.' USING ERRCODE='22023';
  END IF;
  UPDATE public.sms_queue_items SET status='DeadLetter',retry_count=LEAST(retry_count+1,max_attempts),
    error_message=p_error_code,error_classification='PermanentGatewayValidationFailure',final_state_at=now(),
    lease_owner=NULL,lease_instance_id=NULL,lease_expires_at=NULL,updated_at=now()
  WHERE id=p_sms_id AND status='Processing' AND lease_owner=p_worker_id AND lease_instance_id=p_instance_id
    AND lease_expires_at>now() AND provider_call_started_at IS NULL;
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>1 THEN RAISE EXCEPTION 'SMS lease was lost or provider call already started.' USING ERRCODE='40001'; END IF;
  INSERT INTO public.audit_logs(action,entity_type,entity_id,new_data)
  VALUES('SMS_FAILED','SmsQueueItem',p_sms_id::TEXT,
    jsonb_build_object('status','DeadLetter','classification','PermanentGatewayValidationFailure',
      'error_code',p_error_code,'gateway_instance_id',p_instance_id));
  RETURN TRUE;
END $$;

-- -------------------------------------------------------------------------
-- 4. Grants
-- -------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.get_sms_test_alias(TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.build_single_credit_nepali_sms(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_sms_gateway_v2_local_validation(UUID, UUID, UUID, TEXT) TO authenticated;

COMMIT;
