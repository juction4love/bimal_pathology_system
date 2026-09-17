-- Production-grade pathology receivables. Forward-only and data-preserving.
-- Bills state charges; immutable payment rows state cash actually received.

CREATE TABLE public.payment_idempotency_requests (
  caller_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
  idempotency_key TEXT NOT NULL CHECK (length(btrim(idempotency_key)) BETWEEN 1 AND 200),
  request_hash VARCHAR(64) NOT NULL,
  response_json JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  PRIMARY KEY (caller_id, idempotency_key)
);
ALTER TABLE public.payment_idempotency_requests ENABLE ROW LEVEL SECURITY;

-- Authenticated clients may read financial tables through existing RLS but all
-- writes must go through the permission-checked transactional RPCs.
DROP POLICY IF EXISTS "bills_insert" ON public.bills;
DROP POLICY IF EXISTS "bill_items_insert" ON public.bill_items;
DROP POLICY IF EXISTS "payments_insert" ON public.payment_transactions;
REVOKE INSERT, UPDATE, DELETE ON public.bills, public.bill_items, public.payment_transactions FROM authenticated;

CREATE OR REPLACE FUNCTION public.guard_payment_immutability()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  RAISE EXCEPTION 'Committed payment transactions are immutable; use an explicit reversal workflow when available.' USING ERRCODE='55000';
END;
$$;
CREATE TRIGGER trg_payment_transactions_immutable
BEFORE UPDATE OR DELETE ON public.payment_transactions
FOR EACH ROW EXECUTE FUNCTION public.guard_payment_immutability();
REVOKE ALL ON FUNCTION public.guard_payment_immutability() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.receive_bill_payment(
  p_bill_id UUID,
  p_amount_paisa BIGINT,
  p_payment_mode public.payment_mode_enum,
  p_transaction_reference TEXT,
  p_remarks TEXT,
  p_idempotency_key TEXT
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_key TEXT := btrim(COALESCE(p_idempotency_key,''));
  v_hash TEXT;
  v_existing public.payment_idempotency_requests%ROWTYPE;
  v_bill public.bills%ROWTYPE;
  v_payment public.payment_transactions%ROWTYPE;
  v_patient public.patients%ROWTYPE;
  v_lab_no TEXT;
  v_phone TEXT;
  v_message TEXT;
  v_sms_id UUID;
  v_sms_status TEXT := 'Payment committed; notification unavailable';
  v_new_paid BIGINT;
  v_new_due BIGINT;
  v_new_status public.payment_status_enum;
  v_response JSONB;
BEGIN
  IF v_caller IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF v_key='' OR length(v_key)>200 THEN RAISE EXCEPTION 'A valid payment request key is required.' USING ERRCODE='22023'; END IF;
  IF p_amount_paisa IS NULL OR p_amount_paisa<=0 THEN RAISE EXCEPTION 'Payment amount must be greater than zero.' USING ERRCODE='22023'; END IF;
  IF p_payment_mode IS NULL THEN RAISE EXCEPTION 'Payment method is required.' USING ERRCODE='22023'; END IF;
  IF p_payment_mode <> 'Cash' AND public.patient_clean_text(p_transaction_reference)='' THEN RAISE EXCEPTION 'Transaction reference is required for non-cash payments.' USING ERRCODE='22023'; END IF;
  IF length(COALESCE(p_transaction_reference,''))>100 THEN RAISE EXCEPTION 'Transaction reference is too long.' USING ERRCODE='22023'; END IF;

  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('bill_id',p_bill_id,'amount_paisa',p_amount_paisa,'payment_mode',p_payment_mode,'transaction_reference',NULLIF(public.patient_clean_text(p_transaction_reference),''),'remarks',NULLIF(public.patient_clean_text(p_remarks),''))::TEXT,'UTF8'),'sha256'),'hex');
  INSERT INTO public.payment_idempotency_requests(caller_id,idempotency_key,request_hash) VALUES(v_caller,v_key,v_hash) ON CONFLICT DO NOTHING;
  SELECT * INTO v_existing FROM public.payment_idempotency_requests WHERE caller_id=v_caller AND idempotency_key=v_key FOR UPDATE;
  IF v_existing.request_hash<>v_hash THEN RAISE EXCEPTION 'Payment request key was already used for different data.' USING ERRCODE='22023'; END IF;
  IF v_existing.response_json IS NOT NULL THEN RETURN v_existing.response_json||jsonb_build_object('idempotency_replay',TRUE); END IF;

  SELECT * INTO v_bill FROM public.bills WHERE id=p_bill_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Bill not found.' USING ERRCODE='P0002'; END IF;
  IF v_bill.due_amount_paisa<=0 OR v_bill.payment_status='Paid' THEN RAISE EXCEPTION 'This bill has no outstanding balance.' USING ERRCODE='22023'; END IF;
  IF p_amount_paisa>v_bill.due_amount_paisa THEN RAISE EXCEPTION 'Payment cannot exceed the outstanding balance of % paisa.',v_bill.due_amount_paisa USING ERRCODE='22023'; END IF;

  INSERT INTO public.payment_transactions(bill_id,receipt_number,amount_paisa,payment_mode,transaction_reference,remarks,received_by,received_by_name)
  VALUES(v_bill.id,'RCP-'||TO_CHAR(NOW() AT TIME ZONE 'Asia/Kathmandu','YYYY')||'-'||LPAD(NEXTVAL('receipt_seq')::TEXT,6,'0'),p_amount_paisa,p_payment_mode,NULLIF(public.patient_clean_text(p_transaction_reference),''),NULLIF(public.patient_clean_text(p_remarks),''),v_caller,public.patient_actor_name()) RETURNING * INTO v_payment;

  v_new_paid:=v_bill.paid_amount_paisa+p_amount_paisa;
  v_new_due:=v_bill.net_amount_paisa-v_new_paid;
  v_new_status:=CASE WHEN v_new_due=0 THEN 'Paid'::public.payment_status_enum ELSE 'Partial'::public.payment_status_enum END;
  UPDATE public.bills SET paid_amount_paisa=v_new_paid,due_amount_paisa=v_new_due,payment_status=v_new_status,updated_at=NOW() WHERE id=v_bill.id;

  SELECT * INTO v_patient FROM public.patients WHERE id=v_bill.patient_id;
  SELECT order_number INTO v_lab_no FROM public.clinical_orders WHERE bill_id=v_bill.id ORDER BY created_at,id LIMIT 1;
  v_lab_no:=COALESCE(v_lab_no,v_bill.bill_number);
  v_phone:=regexp_replace(COALESCE(v_patient.mobile,''),'[^0-9]','','g');
  IF v_phone LIKE '977%' AND length(v_phone)=13 THEN v_phone:=substring(v_phone FROM 4); END IF;
  BEGIN
    IF v_phone~'^(97|98)[0-9]{8}$' THEN
      v_message:='Bimal Pathology: Payment of NPR '||(p_amount_paisa/100)::TEXT||'.'||lpad((p_amount_paisa%100)::TEXT,2,'0')||' received for Lab No: '||v_lab_no||'. Thank you.';
      INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,bill_id)
      VALUES('BillRegistration',v_phone,v_patient.full_name,v_message,'Pending','PAYMENT_CONFIRMATION:'||v_payment.id::TEXT,v_bill.id)
      ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO v_sms_id;
      v_sms_status:=CASE WHEN v_sms_id IS NULL THEN 'Payment notification already queued' ELSE 'Payment notification queued' END;
    ELSE v_sms_status:='SMS skipped: invalid or missing Nepal mobile'; END IF;
  EXCEPTION WHEN OTHERS THEN
    v_sms_status:='Payment committed; notification unavailable';
    INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(v_caller,public.patient_actor_name(),'PAYMENT_SMS_QUEUE_FAILED','PaymentTransaction',v_payment.id::TEXT,jsonb_build_object('bill_id',v_bill.id));
  END;

  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
  VALUES(v_caller,public.patient_actor_name(),'PAYMENT_RECEIVED','PaymentTransaction',v_payment.id::TEXT,jsonb_build_object('bill_id',v_bill.id,'amount_paisa',p_amount_paisa,'payment_mode',p_payment_mode,'new_status',v_new_status));
  v_response:=jsonb_build_object('payment_id',v_payment.id,'receipt_number',v_payment.receipt_number,'bill_id',v_bill.id,'bill_number',v_bill.bill_number,'lab_no',v_lab_no,'amount_paisa',p_amount_paisa,'paid_amount_paisa',v_new_paid,'due_amount_paisa',v_new_due,'payment_status',v_new_status,'sms_queued',v_sms_id IS NOT NULL,'sms_status',v_sms_status);
  UPDATE public.payment_idempotency_requests SET response_json=v_response,completed_at=NOW() WHERE caller_id=v_caller AND idempotency_key=v_key;
  RETURN v_response||jsonb_build_object('idempotency_replay',FALSE);
END;
$$;
REVOKE ALL ON FUNCTION public.receive_bill_payment(UUID,BIGINT,public.payment_mode_enum,TEXT,TEXT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.receive_bill_payment(UUID,BIGINT,public.payment_mode_enum,TEXT,TEXT,TEXT) TO authenticated;

-- Validate new-bill digital references before the authoritative worker starts.
-- Patch the latest five-argument wrapper without duplicating the long worker.
DO $payment_reference_guard$
DECLARE v_sig REGPROCEDURE:='public.create_patient_bill_and_order(jsonb,jsonb,jsonb[],jsonb,text)'::REGPROCEDURE;v_def TEXT;v_fixed TEXT;
BEGIN
 SELECT pg_get_functiondef(v_sig) INTO v_def;v_fixed:=replace(v_def,E'BEGIN\n    IF v_caller IS NULL THEN',E'BEGIN\n    IF COALESCE((p_bill_data->>''paid_amount_paisa'')::BIGINT,0)>0 AND p_payment_data IS NULL THEN RAISE EXCEPTION ''Payment details are required when an amount is received.'' USING ERRCODE=''22023''; END IF;\n    IF COALESCE((p_bill_data->>''paid_amount_paisa'')::BIGINT,0)>0 AND COALESCE(p_payment_data->>''payment_mode'','''')<>''Cash'' AND public.patient_clean_text(p_payment_data->>''transaction_reference'')='''' THEN RAISE EXCEPTION ''Transaction reference is required for non-cash payments.'' USING ERRCODE=''22023''; END IF;\n    IF v_caller IS NULL THEN');
 IF v_fixed=v_def THEN RAISE EXCEPTION 'Billing payment-reference patch mismatch; refusing partial migration.';END IF;EXECUTE v_fixed;
END;$payment_reference_guard$;

-- Replace the wrapper explicitly so initial-payment SMS enqueue failures cannot
-- roll back the already-valid patient/bill/payment/order transaction.
CREATE OR REPLACE FUNCTION public.create_patient_bill_and_order(p_patient_data JSONB,p_bill_data JSONB,p_items_data JSONB[],p_payment_data JSONB,p_idempotency_key TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions,pg_temp AS $$
DECLARE v_caller UUID:=auth.uid();v_key TEXT:=btrim(COALESCE(p_idempotency_key,''));v_hash TEXT;v_existing public.billing_idempotency_requests%ROWTYPE;v_response JSONB;v_payment public.payment_transactions%ROWTYPE;v_bill public.bills%ROWTYPE;v_patient public.patients%ROWTYPE;v_phone TEXT;v_lab_no TEXT;v_message TEXT;v_sms_id UUID;v_sms_status TEXT:='No payment notification required';
BEGIN
 IF v_caller IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';END IF;
 IF v_key='' OR length(v_key)>200 THEN RAISE EXCEPTION 'A valid billing request key is required.' USING ERRCODE='22023';END IF;
 IF COALESCE((p_bill_data->>'paid_amount_paisa')::BIGINT,0)>0 AND p_payment_data IS NULL THEN RAISE EXCEPTION 'Payment details are required when an amount is received.' USING ERRCODE='22023';END IF;
 IF COALESCE((p_bill_data->>'paid_amount_paisa')::BIGINT,0)>0 AND COALESCE(p_payment_data->>'payment_mode','')<>'Cash' AND public.patient_clean_text(p_payment_data->>'transaction_reference')='' THEN RAISE EXCEPTION 'Transaction reference is required for non-cash payments.' USING ERRCODE='22023';END IF;
 v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('patient',p_patient_data,'bill',p_bill_data,'items',to_jsonb(p_items_data),'payment',p_payment_data)::TEXT,'UTF8'),'sha256'),'hex');
 INSERT INTO public.billing_idempotency_requests(caller_id,idempotency_key,request_hash)VALUES(v_caller,v_key,v_hash)ON CONFLICT(caller_id,idempotency_key)DO NOTHING;
 SELECT * INTO v_existing FROM public.billing_idempotency_requests WHERE caller_id=v_caller AND idempotency_key=v_key FOR UPDATE;
 IF v_existing.request_hash<>v_hash THEN RAISE EXCEPTION 'Billing request key was already used for different data.' USING ERRCODE='22023';END IF;
 IF v_existing.response_json IS NOT NULL THEN RETURN v_existing.response_json||jsonb_build_object('idempotency_replay',TRUE);END IF;
 v_response:=public.create_patient_bill_and_order(p_patient_data,p_bill_data,p_items_data,p_payment_data);
 SELECT * INTO v_bill FROM public.bills WHERE id=(v_response->>'bill_id')::UUID;
 SELECT * INTO v_payment FROM public.payment_transactions WHERE bill_id=v_bill.id ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN
  SELECT * INTO v_patient FROM public.patients WHERE id=v_bill.patient_id;
  v_phone:=regexp_replace(COALESCE(v_patient.mobile,''),'[^0-9]','','g');IF v_phone LIKE '977%' AND length(v_phone)=13 THEN v_phone:=substring(v_phone FROM 4);END IF;
  v_lab_no:=COALESCE(NULLIF(v_response->>'order_number',''),v_response->>'bill_number');
  BEGIN
   IF v_phone~'^(97|98)[0-9]{8}$' THEN
    v_message:='Bimal Pathology: Payment of NPR '||(v_payment.amount_paisa/100)::TEXT||'.'||lpad((v_payment.amount_paisa%100)::TEXT,2,'0')||' received for Lab No: '||v_lab_no||'. Thank you.';
    INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,bill_id)VALUES('BillRegistration',v_phone,v_patient.full_name,v_message,'Pending','PAYMENT_CONFIRMATION:'||v_payment.id::TEXT,v_bill.id)ON CONFLICT(idempotency_key)DO NOTHING RETURNING id INTO v_sms_id;
    v_sms_status:=CASE WHEN v_sms_id IS NULL THEN 'Payment notification already queued' ELSE 'Payment notification queued' END;
   ELSE v_sms_status:='SMS skipped: invalid or missing Nepal mobile';END IF;
  EXCEPTION WHEN OTHERS THEN v_sms_status:='Payment committed; notification unavailable';INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)VALUES(v_caller,public.patient_actor_name(),'PAYMENT_SMS_QUEUE_FAILED','PaymentTransaction',v_payment.id::TEXT,jsonb_build_object('bill_id',v_bill.id));END;
 END IF;
 v_response:=v_response||jsonb_build_object('sms_queued',v_sms_id IS NOT NULL,'sms_status',v_sms_status);
 UPDATE public.billing_idempotency_requests SET response_json=v_response,completed_at=NOW()WHERE caller_id=v_caller AND idempotency_key=v_key;
 RETURN v_response||jsonb_build_object('idempotency_replay',FALSE);
END;$$;
REVOKE ALL ON FUNCTION public.create_patient_bill_and_order(JSONB,JSONB,JSONB[],JSONB,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB,JSONB,JSONB[],JSONB,TEXT) TO authenticated;

REVOKE ALL ON TABLE public.payment_idempotency_requests FROM PUBLIC,anon,authenticated;
COMMENT ON FUNCTION public.receive_bill_payment IS 'Locked, idempotent, integer-paisa additional receipt with immutable payment row and one PAYMENT_CONFIRMATION SMS using the current patient mobile.';
