-- Deferred migration 00070: Cloud SMS coordination. Windows Gateway remains the production default.
-- Historical SMS rows and existing gateway RPCs are intentionally untouched.

DO $$ BEGIN
  CREATE TYPE public.sms_dispatch_mode_enum AS ENUM ('WindowsGateway','CloudflareWorker');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.sms_dispatch_configuration (
  singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
  dispatch_mode public.sms_dispatch_mode_enum NOT NULL DEFAULT 'WindowsGateway',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL
);
INSERT INTO public.sms_dispatch_configuration(singleton,dispatch_mode)
VALUES(TRUE,'WindowsGateway') ON CONFLICT(singleton) DO NOTHING;

ALTER TABLE public.sms_queue_items
  ADD COLUMN IF NOT EXISTS cloud_lease_owner UUID,
  ADD COLUMN IF NOT EXISTS cloud_lease_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cloud_claimed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cloud_delivery_started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_attempt_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_sms_cloud_lease
  ON public.sms_queue_items(cloud_lease_expires_at)
  WHERE status='Processing' AND cloud_lease_owner IS NOT NULL;

ALTER TABLE public.sms_dispatch_configuration ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sms_dispatch_configuration FROM PUBLIC,anon,authenticated;
REVOKE UPDATE(cloud_lease_owner,cloud_lease_expires_at,cloud_claimed_at,cloud_delivery_started_at,last_attempt_at)
  ON public.sms_queue_items FROM authenticated;

CREATE OR REPLACE FUNCTION public.get_sms_dispatch_mode()
RETURNS public.sms_dispatch_mode_enum LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,pg_temp AS $$
  SELECT dispatch_mode FROM public.sms_dispatch_configuration WHERE singleton;
$$;

CREATE OR REPLACE FUNCTION public.set_sms_dispatch_mode(
  p_mode public.sms_dispatch_mode_enum,p_confirmation TEXT
) RETURNS public.sms_dispatch_mode_enum
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE previous public.sms_dispatch_mode_enum; actor_name TEXT;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_permission('can_manage_users') OR public.is_super_admin()) THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;
  IF p_confirmation<>('SET_SMS_DISPATCH_MODE_'||p_mode::TEXT) THEN
    RAISE EXCEPTION 'Exact dispatch-mode confirmation is required.' USING ERRCODE='22023';
  END IF;
  SELECT dispatch_mode INTO previous FROM public.sms_dispatch_configuration WHERE singleton FOR UPDATE;
  IF previous IS DISTINCT FROM p_mode AND EXISTS(
    SELECT 1 FROM public.sms_queue_items WHERE status='Processing'
  ) THEN
    RAISE EXCEPTION 'SMS_DISPATCH_SWITCH_BLOCKED_BY_INFLIGHT_ITEMS' USING ERRCODE='55000';
  END IF;
  SELECT COALESCE(full_name,email,'Administrator') INTO actor_name FROM public.user_profiles WHERE id=auth.uid();
  UPDATE public.sms_dispatch_configuration SET dispatch_mode=p_mode,updated_at=NOW(),updated_by=auth.uid() WHERE singleton;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data)
  VALUES(auth.uid(),actor_name,'SMS_DISPATCH_MODE_CHANGED','SmsDispatchConfiguration','singleton',
    jsonb_build_object('dispatch_mode',previous),jsonb_build_object('dispatch_mode',p_mode));
  RETURN p_mode;
END $$;

-- Converge the existing Windows Gateway claim onto the same singleton owner
-- switch. The explicit UUID contract is preserved for rollback compatibility.
CREATE OR REPLACE FUNCTION public.claim_sms_gateway_item(p_sms_id UUID)
RETURNS TABLE(id UUID,sms_type VARCHAR,recipient_phone VARCHAR,message_body TEXT,
  retry_count INT,max_attempts INT,idempotency_key VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_sms_id IS NULL THEN RAISE EXCEPTION 'An explicit SMS queue UUID is required.' USING ERRCODE='22023'; END IF;
  IF public.get_sms_dispatch_mode()<>'WindowsGateway' THEN
    RAISE EXCEPTION 'Windows SMS gateway is not the active dispatcher.' USING ERRCODE='55000';
  END IF;
  RETURN QUERY WITH candidate AS (
    SELECT q.id FROM public.sms_queue_items q WHERE q.id=p_sms_id AND q.status='Pending'
      AND q.scheduled_at<=NOW() AND q.retry_count<q.max_attempts FOR UPDATE SKIP LOCKED
  ) UPDATE public.sms_queue_items q SET status='Processing',updated_at=NOW()
    FROM candidate c WHERE q.id=c.id
    RETURNING q.id,q.sms_type,q.recipient_phone,q.message_body,q.retry_count,q.max_attempts,q.idempotency_key;
END $$;

REVOKE ALL ON FUNCTION public.claim_sms_gateway_item(UUID) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_sms_gateway_item(UUID) TO service_role;

CREATE OR REPLACE FUNCTION public.begin_cloud_sms_delivery(p_sms_id UUID,p_lease_owner UUID)
RETURNS TABLE(id UUID,sms_type VARCHAR,recipient_phone VARCHAR,message_body TEXT,idempotency_key VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  RETURN QUERY UPDATE public.sms_queue_items q SET cloud_delivery_started_at=NOW(),updated_at=NOW()
    WHERE q.id=p_sms_id AND q.status='Processing' AND q.cloud_lease_owner=p_lease_owner
      AND q.cloud_lease_expires_at>NOW() AND q.cloud_delivery_started_at IS NULL
    RETURNING q.id,q.sms_type,q.recipient_phone,q.message_body,q.idempotency_key;
END $$;

CREATE OR REPLACE FUNCTION public.claim_cloud_sms_batch(
  p_batch_size INT DEFAULT 10,p_lease_seconds INT DEFAULT 120
) RETURNS TABLE(id UUID,sms_type VARCHAR,recipient_phone VARCHAR,message_body TEXT,
  retry_count INT,max_attempts INT,idempotency_key VARCHAR,lease_owner UUID,lease_expires_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE owner UUID:=gen_random_uuid();
BEGIN
  IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF public.get_sms_dispatch_mode()<>'CloudflareWorker' THEN
    RAISE EXCEPTION 'Cloud SMS dispatcher is disabled.' USING ERRCODE='55000';
  END IF;
  IF p_batch_size<1 OR p_batch_size>25 OR p_lease_seconds<30 OR p_lease_seconds>300 THEN
    RAISE EXCEPTION 'Invalid cloud claim bounds.' USING ERRCODE='22023';
  END IF;
  RETURN QUERY WITH candidates AS (
    SELECT q.id FROM public.sms_queue_items q
    WHERE q.status='Pending' AND q.scheduled_at<=NOW() AND q.retry_count<q.max_attempts
    ORDER BY q.scheduled_at,q.created_at LIMIT p_batch_size FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE public.sms_queue_items q SET status='Processing',cloud_lease_owner=owner,
      cloud_claimed_at=NOW(),cloud_lease_expires_at=NOW()+make_interval(secs=>p_lease_seconds),
      last_attempt_at=NOW(),updated_at=NOW()
    FROM candidates c WHERE q.id=c.id
    RETURNING q.*
  ) SELECT q.id,q.sms_type,q.recipient_phone,q.message_body,q.retry_count,q.max_attempts,
      q.idempotency_key,owner,q.cloud_lease_expires_at FROM claimed q;
END $$;

CREATE OR REPLACE FUNCTION public.complete_cloud_sms_attempt(
  p_sms_id UUID,p_lease_owner UUID,p_sent BOOLEAN,p_provider_msg_id VARCHAR DEFAULT NULL,
  p_provider_response JSONB DEFAULT NULL,p_error_msg TEXT DEFAULT NULL,
  p_is_permanent_failure BOOLEAN DEFAULT FALSE,p_safe_to_retry BOOLEAN DEFAULT FALSE
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE q public.sms_queue_items%ROWTYPE; attempts INT; new_status VARCHAR(50); delay_seconds INT;
BEGIN
  IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  SELECT * INTO q FROM public.sms_queue_items WHERE id=p_sms_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SMS item not found.' USING ERRCODE='P0002'; END IF;
  IF q.status='Sent' THEN RETURN jsonb_build_object('status','Sent','already_completed',TRUE); END IF;
  IF q.status<>'Processing' OR q.cloud_lease_owner IS DISTINCT FROM p_lease_owner THEN
    RAISE EXCEPTION 'Cloud SMS lease is not owned by this attempt.' USING ERRCODE='55000';
  END IF;
  IF p_sent THEN
    UPDATE public.sms_queue_items SET status='Sent',sent_at=NOW(),provider_message_id=p_provider_msg_id,
      provider_response_json=p_provider_response,error_message=NULL,cloud_lease_owner=NULL,
      cloud_lease_expires_at=NULL,cloud_delivery_started_at=NULL,updated_at=NOW() WHERE id=p_sms_id;
    new_status:='Sent';
  ELSE
    attempts:=q.retry_count+1;
    IF p_is_permanent_failure OR attempts>=q.max_attempts OR NOT p_safe_to_retry THEN
      new_status:='DeadLetter'; delay_seconds:=0;
    ELSE
      new_status:='Pending';
      delay_seconds:=CASE attempts WHEN 1 THEN 120 WHEN 2 THEN 600 WHEN 3 THEN 1800 ELSE 3600 END;
    END IF;
    UPDATE public.sms_queue_items SET status=new_status,retry_count=attempts,
      scheduled_at=CASE WHEN new_status='Pending' THEN NOW()+make_interval(secs=>delay_seconds) ELSE scheduled_at END,
      provider_response_json=p_provider_response,error_message=left(p_error_msg,2000),
      cloud_lease_owner=NULL,cloud_lease_expires_at=NULL,cloud_delivery_started_at=NULL,updated_at=NOW() WHERE id=p_sms_id;
  END IF;
  INSERT INTO public.audit_logs(action,entity_type,entity_id,new_data) VALUES(
    CASE WHEN new_status='Sent' THEN 'SMS_SENT' ELSE 'SMS_FAILED' END,'SmsQueueItem',p_sms_id::TEXT,
    jsonb_build_object('dispatch_mode','CloudflareWorker','status',new_status,'attempt',COALESCE(attempts,q.retry_count)));
  RETURN jsonb_build_object('status',new_status,'already_completed',FALSE);
END $$;

CREATE OR REPLACE FUNCTION public.recover_stale_cloud_sms_items(p_stale_after_seconds INT DEFAULT 300)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE quarantined INT; recovered INT;
BEGIN
  IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_stale_after_seconds<60 OR p_stale_after_seconds>3600 THEN RAISE EXCEPTION 'Invalid stale threshold.' USING ERRCODE='22023'; END IF;
  WITH stale AS (SELECT id,cloud_delivery_started_at FROM public.sms_queue_items WHERE status='Processing'
    AND cloud_lease_owner IS NOT NULL AND cloud_lease_expires_at<=NOW()
    AND updated_at<=NOW()-make_interval(secs=>p_stale_after_seconds) FOR UPDATE SKIP LOCKED), changed AS (
    UPDATE public.sms_queue_items q SET status=CASE WHEN s.cloud_delivery_started_at IS NULL THEN 'Pending' ELSE 'DeadLetter' END,
      retry_count=LEAST(retry_count+1,max_attempts),scheduled_at=CASE WHEN s.cloud_delivery_started_at IS NULL THEN NOW()+INTERVAL '2 minutes' ELSE scheduled_at END,
      error_message=CASE WHEN s.cloud_delivery_started_at IS NULL THEN 'Cloud queue handoff lease expired before provider delivery; safely retrying.' ELSE 'Cloud dispatcher lease expired after provider delivery began; outcome is unknown and automatic resend is blocked.' END,
      cloud_lease_owner=NULL,cloud_lease_expires_at=NULL,cloud_delivery_started_at=NULL,updated_at=NOW() FROM stale s WHERE q.id=s.id RETURNING q.status
  ) SELECT count(*) FILTER(WHERE status='DeadLetter'),count(*) FILTER(WHERE status='Pending') INTO quarantined,recovered FROM changed;
  RETURN jsonb_build_object('deadlettered',quarantined,'recovered',recovered);
END $$;

REVOKE ALL ON FUNCTION public.get_sms_dispatch_mode(),public.set_sms_dispatch_mode(public.sms_dispatch_mode_enum,TEXT),
  public.claim_cloud_sms_batch(INT,INT),public.complete_cloud_sms_attempt(UUID,UUID,BOOLEAN,VARCHAR,JSONB,TEXT,BOOLEAN,BOOLEAN),
  public.begin_cloud_sms_delivery(UUID,UUID),public.recover_stale_cloud_sms_items(INT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_sms_dispatch_mode(),public.claim_cloud_sms_batch(INT,INT),
  public.complete_cloud_sms_attempt(UUID,UUID,BOOLEAN,VARCHAR,JSONB,TEXT,BOOLEAN,BOOLEAN),
  public.begin_cloud_sms_delivery(UUID,UUID),public.recover_stale_cloud_sms_items(INT) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_sms_dispatch_mode(),public.set_sms_dispatch_mode(public.sms_dispatch_mode_enum,TEXT) TO authenticated;
