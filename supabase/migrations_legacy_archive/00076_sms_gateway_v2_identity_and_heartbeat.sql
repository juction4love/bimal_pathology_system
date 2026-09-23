-- Gateway 2.0 additive identity, heartbeat and guarded RPC boundary.
-- Gateway 1.x RPCs and all existing queue rows remain unchanged for rollback.

ALTER TABLE public.sms_queue_items
  ADD COLUMN IF NOT EXISTS lease_instance_id UUID;

CREATE TABLE IF NOT EXISTS public.sms_gateway_instances (
  instance_id UUID PRIMARY KEY,
  auth_user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE RESTRICT,
  hostname TEXT NOT NULL CHECK (length(btrim(hostname)) BETWEEN 1 AND 255),
  gateway_version TEXT NOT NULL CHECK (length(btrim(gateway_version)) BETWEEN 1 AND 50),
  provider_name TEXT NOT NULL CHECK (length(btrim(provider_name)) BETWEEN 1 AND 80),
  service_started_at TIMESTAMPTZ,
  last_heartbeat_at TIMESTAMPTZ,
  last_successful_queue_access_at TIMESTAMPTZ,
  last_provider_success_at TIMESTAMPTZ,
  provider_health TEXT NOT NULL DEFAULT 'Unknown'
    CHECK (provider_health IN ('Unknown','Healthy','Degraded','Unavailable','ConfigurationError')),
  safe_last_error_code TEXT,
  active_job_count INT NOT NULL DEFAULT 0 CHECK (active_job_count >= 0),
  claiming_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE public.sms_queue_items ADD CONSTRAINT sms_queue_items_lease_instance_id_fkey
    FOREIGN KEY (lease_instance_id) REFERENCES public.sms_gateway_instances(instance_id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS sms_gateway_instances_heartbeat_idx
  ON public.sms_gateway_instances(last_heartbeat_at DESC);
CREATE INDEX IF NOT EXISTS sms_queue_items_lease_instance_idx
  ON public.sms_queue_items(lease_instance_id)
  WHERE status='Processing';

ALTER TABLE public.sms_gateway_instances ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sms_gateway_instances FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.sms_queue_items FROM PUBLIC, anon;

CREATE OR REPLACE FUNCTION public.assert_sms_gateway_v2_identity(p_instance_id UUID)
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE registered public.sms_gateway_instances%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Gateway authentication required.' USING ERRCODE='42501'; END IF;
  SELECT * INTO registered FROM public.sms_gateway_instances WHERE instance_id=p_instance_id;
  IF NOT FOUND OR registered.auth_user_id<>auth.uid() OR NOT registered.is_enabled THEN
    RAISE EXCEPTION 'Gateway identity is not authorized.' USING ERRCODE='42501';
  END IF;
  IF EXISTS(SELECT 1 FROM public.user_profiles WHERE id=auth.uid() AND is_active) THEN
    RAISE EXCEPTION 'Gateway identity must not have an active LIS staff profile.' USING ERRCODE='42501';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.register_sms_gateway_v2_instance(
  p_instance_id UUID,p_auth_user_id UUID,p_hostname TEXT,p_gateway_version TEXT,p_provider_name TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_instance_id IS NULL OR p_auth_user_id IS NULL THEN RAISE EXCEPTION 'Instance and Auth user are required.' USING ERRCODE='22023'; END IF;
  IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_auth_user_id) THEN RAISE EXCEPTION 'Gateway Auth user does not exist.' USING ERRCODE='P0002'; END IF;
  IF EXISTS(SELECT 1 FROM public.user_profiles WHERE id=p_auth_user_id AND is_active) THEN
    RAISE EXCEPTION 'Gateway Auth user must not be an active LIS staff user.' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.sms_gateway_instances(instance_id,auth_user_id,hostname,gateway_version,provider_name)
  VALUES(p_instance_id,p_auth_user_id,btrim(p_hostname),btrim(p_gateway_version),btrim(p_provider_name))
  ON CONFLICT(instance_id) DO UPDATE SET auth_user_id=EXCLUDED.auth_user_id,hostname=EXCLUDED.hostname,
    gateway_version=EXCLUDED.gateway_version,provider_name=EXCLUDED.provider_name,updated_at=now();
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,new_data)
  VALUES(auth.uid(),'SMS_GATEWAY_V2_REGISTERED','SmsGatewayInstance',p_instance_id::TEXT,
    jsonb_build_object('auth_user_id',p_auth_user_id,'hostname',btrim(p_hostname),'version',btrim(p_gateway_version),'provider',btrim(p_provider_name)));
  RETURN jsonb_build_object('success',true,'instance_id',p_instance_id,'claiming_enabled',false);
END $$;

CREATE OR REPLACE FUNCTION public.set_sms_gateway_v2_claiming(p_instance_id UUID,p_enabled BOOLEAN,p_confirmation TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_confirmation<>(CASE WHEN p_enabled THEN 'ENABLE_SMS_GATEWAY_V2_CLAIMING' ELSE 'DISABLE_SMS_GATEWAY_V2_CLAIMING' END) THEN
    RAISE EXCEPTION 'Exact claiming confirmation is required.' USING ERRCODE='22023';
  END IF;
  IF p_enabled AND EXISTS(SELECT 1 FROM public.sms_queue_items WHERE status='Processing') THEN
    RAISE EXCEPTION 'SMS_GATEWAY_SWITCH_BLOCKED_BY_PROCESSING_ROWS' USING ERRCODE='55000';
  END IF;
  UPDATE public.sms_gateway_instances SET claiming_enabled=p_enabled,updated_at=now() WHERE instance_id=p_instance_id AND is_enabled;
  IF NOT FOUND THEN RAISE EXCEPTION 'Gateway instance not found or disabled.' USING ERRCODE='P0002'; END IF;
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,new_data)
  VALUES(auth.uid(),'SMS_GATEWAY_V2_CLAIMING_CHANGED','SmsGatewayInstance',p_instance_id::TEXT,jsonb_build_object('claiming_enabled',p_enabled));
  RETURN jsonb_build_object('success',true,'instance_id',p_instance_id,'claiming_enabled',p_enabled);
END $$;

CREATE OR REPLACE FUNCTION public.set_sms_gateway_v2_enabled(p_instance_id UUID,p_enabled BOOLEAN,p_confirmation TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_confirmation<>(CASE WHEN p_enabled THEN 'ENABLE_SMS_GATEWAY_V2_INSTANCE' ELSE 'DISABLE_SMS_GATEWAY_V2_INSTANCE' END) THEN
    RAISE EXCEPTION 'Exact instance-state confirmation is required.' USING ERRCODE='22023';
  END IF;
  UPDATE public.sms_gateway_instances SET is_enabled=p_enabled,
    claiming_enabled=CASE WHEN p_enabled THEN claiming_enabled ELSE FALSE END,updated_at=now()
  WHERE instance_id=p_instance_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Gateway instance not found.' USING ERRCODE='P0002'; END IF;
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,new_data)
  VALUES(auth.uid(),'SMS_GATEWAY_V2_INSTANCE_STATE_CHANGED','SmsGatewayInstance',p_instance_id::TEXT,
    jsonb_build_object('is_enabled',p_enabled,'claiming_enabled',CASE WHEN p_enabled THEN NULL ELSE FALSE END));
  RETURN jsonb_build_object('success',true,'instance_id',p_instance_id,'is_enabled',p_enabled);
END $$;

CREATE OR REPLACE FUNCTION public.sms_gateway_v2_preflight(p_instance_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE gateway public.sms_gateway_instances%ROWTYPE;
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  SELECT * INTO gateway FROM public.sms_gateway_instances WHERE instance_id=p_instance_id;
  RETURN jsonb_build_object('success',true,'instance_id',gateway.instance_id,'claiming_enabled',gateway.claiming_enabled,
    'provider_name',gateway.provider_name,'gateway_version',gateway.gateway_version);
END $$;

CREATE OR REPLACE FUNCTION public.heartbeat_sms_gateway_v2(
  p_instance_id UUID,p_hostname TEXT,p_gateway_version TEXT,p_provider_name TEXT,p_service_started_at TIMESTAMPTZ,
  p_last_successful_queue_access_at TIMESTAMPTZ,p_last_provider_success_at TIMESTAMPTZ,p_provider_health TEXT,
  p_safe_last_error_code TEXT,p_active_job_count INT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  IF p_provider_health NOT IN ('Unknown','Healthy','Degraded','Unavailable','ConfigurationError') OR p_active_job_count<0 OR
     length(COALESCE(p_safe_last_error_code,''))>100 THEN RAISE EXCEPTION 'Invalid safe heartbeat payload.' USING ERRCODE='22023'; END IF;
  UPDATE public.sms_gateway_instances SET hostname=btrim(p_hostname),gateway_version=btrim(p_gateway_version),provider_name=btrim(p_provider_name),
    service_started_at=p_service_started_at,last_heartbeat_at=now(),last_successful_queue_access_at=p_last_successful_queue_access_at,
    last_provider_success_at=p_last_provider_success_at,provider_health=p_provider_health,safe_last_error_code=NULLIF(btrim(p_safe_last_error_code),''),
    active_job_count=p_active_job_count,updated_at=now() WHERE instance_id=p_instance_id;
  RETURN jsonb_build_object('success',true,'server_time',now());
END $$;

CREATE OR REPLACE FUNCTION public.claim_sms_gateway_v2_batch(
  p_instance_id UUID,p_worker_id UUID,p_lease_seconds INT DEFAULT 300,p_batch_size INT DEFAULT 1)
RETURNS TABLE(id UUID,sms_type VARCHAR,recipient_phone VARCHAR,message_body TEXT,retry_count INT,max_attempts INT,idempotency_key VARCHAR,lease_owner UUID)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  IF NOT EXISTS(SELECT 1 FROM public.sms_gateway_instances WHERE instance_id=p_instance_id AND claiming_enabled) THEN
    RAISE EXCEPTION 'Gateway v2 claiming is disabled.' USING ERRCODE='55000';
  END IF;
  IF p_worker_id IS NULL OR p_lease_seconds NOT BETWEEN 60 AND 900 OR p_batch_size NOT BETWEEN 1 AND 10 THEN
    RAISE EXCEPTION 'Invalid claim bounds.' USING ERRCODE='22023';
  END IF;
  RETURN QUERY WITH candidates AS (
    SELECT q.id FROM public.sms_queue_items q WHERE q.status IN('Pending','Failed') AND q.scheduled_at<=now() AND q.retry_count<q.max_attempts
    ORDER BY q.scheduled_at,q.created_at,q.id FOR UPDATE SKIP LOCKED LIMIT p_batch_size
  ), claimed AS (
    UPDATE public.sms_queue_items q SET status='Processing',lease_owner=p_worker_id,lease_instance_id=p_instance_id,
      lease_expires_at=now()+make_interval(secs=>p_lease_seconds),provider_call_started_at=NULL,error_message=NULL,error_classification=NULL,updated_at=now()
    FROM candidates c WHERE q.id=c.id RETURNING q.*
  ) SELECT q.id,q.sms_type,q.recipient_phone,q.message_body,q.retry_count,q.max_attempts,q.idempotency_key,q.lease_owner FROM claimed q;
END $$;

CREATE OR REPLACE FUNCTION public.mark_sms_gateway_v2_provider_call_started(p_instance_id UUID,p_sms_id UUID,p_worker_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  UPDATE public.sms_queue_items SET provider_call_started_at=now(),updated_at=now()
  WHERE id=p_sms_id AND status='Processing' AND lease_instance_id=p_instance_id AND lease_owner=p_worker_id
    AND lease_expires_at>now() AND provider_call_started_at IS NULL;
  RETURN FOUND;
END $$;

CREATE OR REPLACE FUNCTION public.complete_sms_gateway_v2_item(
  p_instance_id UUID,p_sms_id UUID,p_worker_id UUID,p_accepted BOOLEAN,p_provider_msg_id TEXT DEFAULT NULL,
  p_provider_response JSONB DEFAULT NULL,p_provider_response_code TEXT DEFAULT NULL,p_error_msg TEXT DEFAULT NULL,
  p_error_classification TEXT DEFAULT NULL,p_retryable BOOLEAN DEFAULT FALSE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE q public.sms_queue_items%ROWTYPE;attempts INT;next_status TEXT;
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  SELECT * INTO q FROM public.sms_queue_items WHERE id=p_sms_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SMS queue item not found.' USING ERRCODE='P0002'; END IF;
  IF q.status='Sent' THEN RETURN jsonb_build_object('success',true,'status','Sent','already_completed',true); END IF;
  IF q.status<>'Processing' OR q.lease_owner IS DISTINCT FROM p_worker_id OR q.lease_instance_id IS DISTINCT FROM p_instance_id THEN
    RAISE EXCEPTION 'SMS lease ownership conflict.' USING ERRCODE='40001'; END IF;
  IF q.provider_call_started_at IS NULL THEN RAISE EXCEPTION 'Provider call was not marked as started.' USING ERRCODE='55000'; END IF;
  IF p_accepted THEN
    UPDATE public.sms_queue_items SET status='Sent',sent_at=now(),final_state_at=now(),delivery_attempt_count=delivery_attempt_count+1,
      provider_message_id=p_provider_msg_id,provider_response_json=p_provider_response,provider_response_code=p_provider_response_code,
      error_message=NULL,error_classification=NULL,lease_owner=NULL,lease_instance_id=NULL,lease_expires_at=NULL,updated_at=now() WHERE id=p_sms_id;
    INSERT INTO public.audit_logs(action,entity_type,entity_id,new_data) VALUES('SMS_SENT','SmsQueueItem',p_sms_id::TEXT,jsonb_build_object('provider_message_id',p_provider_msg_id,'gateway_instance_id',p_instance_id));
    RETURN jsonb_build_object('success',true,'status','Sent');
  END IF;
  attempts:=q.retry_count+1;
  next_status:=CASE WHEN NOT p_retryable OR attempts>=q.max_attempts THEN 'DeadLetter' ELSE 'Failed' END;
  UPDATE public.sms_queue_items SET status=next_status,retry_count=attempts,delivery_attempt_count=delivery_attempt_count+1,
    scheduled_at=CASE WHEN next_status='Failed' THEN now()+make_interval(secs=>CASE attempts WHEN 1 THEN 120 WHEN 2 THEN 600 WHEN 3 THEN 1800 ELSE 3600 END) ELSE scheduled_at END,
    provider_response_json=p_provider_response,provider_response_code=p_provider_response_code,error_message=left(COALESCE(p_error_msg,'Delivery failed'),500),
    error_classification=COALESCE(p_error_classification,CASE WHEN p_retryable THEN 'RetryableProviderFailure' ELSE 'PermanentProviderFailure' END),
    final_state_at=CASE WHEN next_status='DeadLetter' THEN now() ELSE NULL END,lease_owner=NULL,lease_instance_id=NULL,lease_expires_at=NULL,updated_at=now() WHERE id=p_sms_id;
  INSERT INTO public.audit_logs(action,entity_type,entity_id,new_data) VALUES('SMS_FAILED','SmsQueueItem',p_sms_id::TEXT,
    jsonb_build_object('attempt',attempts,'status',next_status,'classification',p_error_classification,'gateway_instance_id',p_instance_id));
  RETURN jsonb_build_object('success',true,'status',next_status,'attempt',attempts);
END $$;

CREATE OR REPLACE FUNCTION public.reject_sms_gateway_v2_local_validation(
  p_instance_id UUID,p_sms_id UUID,p_worker_id UUID,p_error_code TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE changed INT;
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  IF p_error_code NOT IN ('INVALID_NEPAL_MOBILE','EMPTY_MESSAGE','SEGMENT_LIMIT_EXCEEDED') THEN
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

CREATE OR REPLACE FUNCTION public.recover_stale_sms_gateway_v2_items(p_instance_id UUID,p_stale_after_seconds INT DEFAULT 300)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE recovered INT:=0;quarantined INT:=0;
BEGIN
  PERFORM public.assert_sms_gateway_v2_identity(p_instance_id);
  IF NOT EXISTS(SELECT 1 FROM public.sms_gateway_instances WHERE instance_id=p_instance_id AND claiming_enabled) THEN
    RAISE EXCEPTION 'Gateway v2 claiming is disabled.' USING ERRCODE='55000';
  END IF;
  IF p_stale_after_seconds NOT BETWEEN 60 AND 3600 THEN RAISE EXCEPTION 'Stale threshold must be between 60 and 3600 seconds.' USING ERRCODE='22023'; END IF;
  WITH stale AS (SELECT id,provider_call_started_at FROM public.sms_queue_items WHERE status='Processing' AND
    COALESCE(lease_expires_at,updated_at+make_interval(secs=>p_stale_after_seconds))<=now() FOR UPDATE SKIP LOCKED), changed AS (
    UPDATE public.sms_queue_items q SET status=CASE WHEN s.provider_call_started_at IS NULL THEN 'Pending' ELSE 'DeadLetter' END,
      retry_count=CASE WHEN s.provider_call_started_at IS NULL THEN q.retry_count ELSE LEAST(q.retry_count+1,q.max_attempts) END,
      scheduled_at=CASE WHEN s.provider_call_started_at IS NULL THEN now() ELSE q.scheduled_at END,
      error_classification=CASE WHEN s.provider_call_started_at IS NULL THEN 'LeaseExpiredBeforeProviderCall' ELSE 'ProviderOutcomeUnknown' END,
      error_message=CASE WHEN s.provider_call_started_at IS NULL THEN 'Gateway lease expired before provider call; safely returned to queue.' ELSE 'Gateway stopped after provider call began; automatic resend blocked because provider outcome is unknown.' END,
      final_state_at=CASE WHEN s.provider_call_started_at IS NULL THEN NULL ELSE now() END,lease_owner=NULL,lease_instance_id=NULL,lease_expires_at=NULL,updated_at=now()
    FROM stale s WHERE q.id=s.id RETURNING q.status)
  SELECT count(*) FILTER(WHERE status='Pending'),count(*) FILTER(WHERE status='DeadLetter') INTO recovered,quarantined FROM changed;
  RETURN jsonb_build_object('success',true,'recovered',recovered,'deadlettered',quarantined);
END $$;

CREATE OR REPLACE FUNCTION public.get_sms_gateway_v2_health()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE counts JSONB;instances JSONB;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_permission('can_manage_users') OR public.is_super_admin()) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  SELECT jsonb_build_object('pending_count',count(*) FILTER(WHERE status='Pending'),'failed_count',count(*) FILTER(WHERE status='Failed'),
    'deadletter_count',count(*) FILTER(WHERE status='DeadLetter'),'stale_processing_count',count(*) FILTER(WHERE status='Processing' AND lease_expires_at<=now()),
    'oldest_pending_at',min(created_at) FILTER(WHERE status='Pending')) INTO counts FROM public.sms_queue_items;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('instance_id',instance_id,'hostname',hostname,'gateway_version',gateway_version,'provider_name',provider_name,
    'service_started_at',service_started_at,'last_heartbeat_at',last_heartbeat_at,'last_successful_queue_access_at',last_successful_queue_access_at,
    'last_provider_success_at',last_provider_success_at,'provider_health',provider_health,'safe_last_error_code',safe_last_error_code,
    'active_job_count',active_job_count,'claiming_enabled',claiming_enabled,'is_enabled',is_enabled,
    'online',last_heartbeat_at>=now()-interval '2 minutes') ORDER BY created_at),'[]'::JSONB) INTO instances FROM public.sms_gateway_instances;
  RETURN jsonb_build_object('instances',instances,'queue',counts,'server_time',now());
END $$;

REVOKE ALL ON FUNCTION public.assert_sms_gateway_v2_identity(UUID),public.register_sms_gateway_v2_instance(UUID,UUID,TEXT,TEXT,TEXT),
  public.set_sms_gateway_v2_claiming(UUID,BOOLEAN,TEXT),public.set_sms_gateway_v2_enabled(UUID,BOOLEAN,TEXT),public.sms_gateway_v2_preflight(UUID),
  public.heartbeat_sms_gateway_v2(UUID,TEXT,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TIMESTAMPTZ,TEXT,TEXT,INT),
  public.claim_sms_gateway_v2_batch(UUID,UUID,INT,INT),public.mark_sms_gateway_v2_provider_call_started(UUID,UUID,UUID),
  public.reject_sms_gateway_v2_local_validation(UUID,UUID,UUID,TEXT),
  public.complete_sms_gateway_v2_item(UUID,UUID,UUID,BOOLEAN,TEXT,JSONB,TEXT,TEXT,TEXT,BOOLEAN),
  public.recover_stale_sms_gateway_v2_items(UUID,INT),public.get_sms_gateway_v2_health() FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.sms_gateway_v2_preflight(UUID),
  public.heartbeat_sms_gateway_v2(UUID,TEXT,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TIMESTAMPTZ,TEXT,TEXT,INT),
  public.claim_sms_gateway_v2_batch(UUID,UUID,INT,INT),public.mark_sms_gateway_v2_provider_call_started(UUID,UUID,UUID),
  public.reject_sms_gateway_v2_local_validation(UUID,UUID,UUID,TEXT),
  public.complete_sms_gateway_v2_item(UUID,UUID,UUID,BOOLEAN,TEXT,JSONB,TEXT,TEXT,TEXT,BOOLEAN),
  public.recover_stale_sms_gateway_v2_items(UUID,INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_sms_gateway_v2_instance(UUID,UUID,TEXT,TEXT,TEXT),
  public.set_sms_gateway_v2_claiming(UUID,BOOLEAN,TEXT),public.set_sms_gateway_v2_enabled(UUID,BOOLEAN,TEXT),public.get_sms_gateway_v2_health() TO authenticated;

COMMENT ON TABLE public.sms_gateway_instances IS 'Operational Gateway 2.0 identities and heartbeat metadata only; contains no patient or SMS content.';
