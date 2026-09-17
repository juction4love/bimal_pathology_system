-- Bimal Pathology Cloud LIS
-- Final flow-integrity fixes: forward-only, data-preserving, and backward-compatible.

/*
 * Migration 00020 is already applied on the linked production project. Its
 * source is retained below as deployment context only; executable 00021 SQL
 * begins at the durable billing idempotency section.

-- Migration 00018 accidentally referenced user_profiles.user_id in the two
-- current RPC definitions. user_profiles is keyed by id. Patch only that
-- predicate while preserving the complete deployed function bodies.
DO $audit_fix$
DECLARE
    v_signature REGPROCEDURE;
    v_definition TEXT;
    v_fixed TEXT;
BEGIN
    FOREACH v_signature IN ARRAY ARRAY[
        'public.create_patient_bill_and_order(jsonb,jsonb,jsonb[],jsonb)'::REGPROCEDURE,
        'public.update_outsource_sample_status(uuid,outsource_sample_status_enum,text,jsonb)'::REGPROCEDURE
    ] LOOP
        SELECT pg_get_functiondef(v_signature) INTO v_definition;
        v_fixed := regexp_replace(
            v_definition,
            'WHERE[[:space:]]+\(?user_id[[:space:]]*=[[:space:]]*auth\.uid\(\)\)?',
            'WHERE id = auth.uid()',
            'gi'
        );

        IF v_fixed = v_definition THEN
            RAISE EXCEPTION 'Expected user_profiles.user_id predicate not found in %', v_signature;
        END IF;

        EXECUTE v_fixed;
    END LOOP;
END;
$audit_fix$;

-- Outsource tracking is permission-controlled. Billing creates tracking rows
-- through its SECURITY DEFINER RPC; clients must not insert/update tracking or
-- forge immutable event history directly.
DROP POLICY IF EXISTS "Allow authenticated read outsource samples" ON public.outsource_samples;
CREATE POLICY "Authorized staff can read outsource samples"
ON public.outsource_samples
FOR SELECT TO authenticated
USING (public.has_permission('can_manage_outsource_tracking'));

DROP POLICY IF EXISTS "Allow authenticated insert outsource samples" ON public.outsource_samples;
DROP POLICY IF EXISTS "Allow authenticated update outsource samples" ON public.outsource_samples;

DROP POLICY IF EXISTS "Allow authenticated read outsource events" ON public.outsource_sample_events;
CREATE POLICY "Authorized staff can read outsource events"
ON public.outsource_sample_events
FOR SELECT TO authenticated
USING (public.has_permission('can_manage_outsource_tracking'));

DROP POLICY IF EXISTS "Allow authenticated insert outsource events" ON public.outsource_sample_events;

-- The transition RPC remains the only client mutation path and enforces the
-- same permission server-side, independently of UI visibility.
CREATE OR REPLACE FUNCTION public.require_outsource_tracking_permission()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL OR NOT public.has_permission('can_manage_outsource_tracking') THEN
        RAISE EXCEPTION 'Access denied: can_manage_outsource_tracking permission required.';
    END IF;
END;
$$;

-- Add a permission gate without duplicating the long status-transition body.
-- The trigger executes before every outsource row mutation, including the
-- SECURITY DEFINER transition RPC and the billing RPC.
CREATE OR REPLACE FUNCTION public.guard_outsource_sample_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Billing RPC callers have can_create_bill; operational transitions require
    -- can_manage_outsource_tracking. Service-role maintenance has auth.uid null
    -- and is allowed only because it bypasses RLS and invokes trusted code.
    IF auth.uid() IS NOT NULL THEN
        IF TG_OP = 'INSERT'
           AND NOT public.has_permission('can_create_bill')
           AND NOT public.has_permission('can_manage_outsource_tracking') THEN
            RAISE EXCEPTION 'Access denied for outsource tracking creation.';
        ELSIF TG_OP = 'UPDATE'
           AND NOT public.has_permission('can_manage_outsource_tracking') THEN
            RAISE EXCEPTION 'Access denied for outsource tracking mutation.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_outsource_sample_write_trigger ON public.outsource_samples;
CREATE TRIGGER guard_outsource_sample_write_trigger
BEFORE INSERT OR UPDATE ON public.outsource_samples
FOR EACH ROW EXECUTE FUNCTION public.guard_outsource_sample_write();

-- SMS claim/status functions are worker internals. Ordinary authenticated
-- browser sessions must not claim queue rows or forge provider outcomes.
REVOKE EXECUTE ON FUNCTION public.claim_sms_batch(INT) FROM authenticated, anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_sms_status(UUID, VARCHAR, VARCHAR, JSONB, TEXT, BOOLEAN)
FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_sms_batch(INT) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_sms_status(UUID, VARCHAR, VARCHAR, JSONB, TEXT, BOOLEAN)
TO service_role;

-- The dashboard summary already rejects anonymous callers internally; remove
-- the unnecessary anonymous EXECUTE surface as defense in depth.
REVOKE EXECUTE ON FUNCTION public.get_dashboard_collection_summary() FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_dashboard_collection_summary() TO authenticated;

-- Correct result workflow transition checks. The old WITH CHECK evaluated the
-- new status too narrowly, blocking Draft -> Submitted for entry users and
-- Submitted -> Verified for verifier-only users.
DROP POLICY IF EXISTS "test_results_update" ON public.test_results;
CREATE POLICY "test_results_update" ON public.test_results
FOR UPDATE TO authenticated
USING (
    (status IN ('Draft', 'ReturnedForCorrection') AND public.has_permission('can_enter_results'))
    OR (status = 'SubmittedForVerification' AND public.has_permission('can_verify_results'))
    OR public.has_permission('can_sign_reports')
)
WITH CHECK (
    (status IN ('Draft', 'SubmittedForVerification') AND public.has_permission('can_enter_results'))
    OR (status IN ('SubmittedForVerification', 'Verified', 'ReturnedForCorrection')
        AND public.has_permission('can_verify_results'))
    OR public.has_permission('can_sign_reports')
);

-- Enforce personnel eligibility even if the sign-off RPC is called directly.
CREATE OR REPLACE FUNCTION public.guard_diagnostic_report_personnel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.reporting_personnel
        WHERE id = NEW.performed_by_personnel_id AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'Performed-by reporting personnel must be active.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.reporting_personnel
        WHERE id = NEW.signed_by_personnel_id
          AND is_active = TRUE
          AND can_sign_reports = TRUE
    ) THEN
        RAISE EXCEPTION 'Authorizing reporting personnel must be active and eligible to sign.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_diagnostic_report_personnel_trigger ON public.diagnostic_reports;
CREATE TRIGGER guard_diagnostic_report_personnel_trigger
BEFORE INSERT ON public.diagnostic_reports
FOR EACH ROW EXECUTE FUNCTION public.guard_diagnostic_report_personnel();

*/

-- Repair sequence references introduced by migrations 00013/00017/00018.
-- The deployed schema owns lab_order_seq and sample_seq; preserve the existing
-- LAB-/BC- formatting while pointing the function at the real sequences.
DO $billing_sequence_fix$
DECLARE
    v_signature REGPROCEDURE :=
        'public.create_patient_bill_and_order(jsonb,jsonb,jsonb[],jsonb)'::REGPROCEDURE;
    v_definition TEXT;
    v_fixed TEXT;
BEGIN
    SELECT pg_get_functiondef(v_signature) INTO v_definition;
    v_fixed := replace(v_definition, 'clinical_order_seq', 'lab_order_seq');
    v_fixed := replace(v_fixed, 'sample_barcode_seq', 'sample_seq');

    IF v_fixed = v_definition THEN
        RAISE EXCEPTION 'Expected invalid billing sequence references were not found.';
    END IF;

    EXECUTE v_fixed;
END;
$billing_sequence_fix$;

-- ============================================================================
-- Durable billing request idempotency
-- ============================================================================
-- The row and the business transaction are committed together. Any exception
-- rolls both back, so a failed request never leaves a poisoned key.
CREATE TABLE IF NOT EXISTS public.billing_idempotency_requests (
    caller_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
    idempotency_key TEXT NOT NULL,
    request_hash TEXT NOT NULL,
    response_json JSONB,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT billing_idempotency_key_not_blank CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT billing_idempotency_key_length CHECK (length(idempotency_key) <= 200),
    PRIMARY KEY (caller_id, idempotency_key)
);

ALTER TABLE public.billing_idempotency_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.billing_idempotency_requests FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_patient_bill_and_order(
    p_patient_data JSONB,
    p_bill_data JSONB,
    p_items_data JSONB[],
    p_payment_data JSONB,
    p_idempotency_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_key TEXT := btrim(COALESCE(p_idempotency_key, ''));
    v_hash TEXT;
    v_existing public.billing_idempotency_requests%ROWTYPE;
    v_response JSONB;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.has_permission('can_create_bill') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;
    IF v_key = '' OR length(v_key) > 200 THEN
        RAISE EXCEPTION 'A valid billing request key is required.' USING ERRCODE = '22023';
    END IF;

    v_hash := encode(extensions.digest(
        convert_to(jsonb_build_object(
            'patient', p_patient_data,
            'bill', p_bill_data,
            'items', to_jsonb(p_items_data),
            'payment', p_payment_data
        )::TEXT, 'UTF8'),
        'sha256'
    ), 'hex');

    INSERT INTO public.billing_idempotency_requests(caller_id, idempotency_key, request_hash)
    VALUES (v_caller, v_key, v_hash)
    ON CONFLICT (caller_id, idempotency_key) DO NOTHING;

    SELECT * INTO v_existing
    FROM public.billing_idempotency_requests
    WHERE caller_id = v_caller AND idempotency_key = v_key
    FOR UPDATE;

    IF v_existing.request_hash <> v_hash THEN
        RAISE EXCEPTION 'Billing request key was already used for different data.' USING ERRCODE = '22023';
    END IF;
    IF v_existing.response_json IS NOT NULL THEN
        RETURN v_existing.response_json || jsonb_build_object('idempotency_replay', TRUE);
    END IF;

    -- Calls the established four-argument transaction, preserving all existing
    -- patient, invoice, receipt, order, sample, barcode, and numbering behavior.
    v_response := public.create_patient_bill_and_order(
        p_patient_data, p_bill_data, p_items_data, p_payment_data
    );

    UPDATE public.billing_idempotency_requests
    SET response_json = v_response,
        completed_at = NOW()
    WHERE caller_id = v_caller AND idempotency_key = v_key;

    RETURN v_response || jsonb_build_object('idempotency_replay', FALSE);
END;
$$;

-- Do not leave the legacy non-idempotent overload callable by browser users.
REVOKE EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB, TEXT)
TO authenticated;

-- ============================================================================
-- Atomic ordinary-sample lifecycle
-- ============================================================================
CREATE OR REPLACE FUNCTION public.transition_sample_lifecycle(
    p_sample_id UUID,
    p_to_status sample_status_enum,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_sample public.samples%ROWTYPE;
    v_actor public.user_profiles%ROWTYPE;
    v_now TIMESTAMPTZ := NOW();
    v_new_sample_id UUID;
    v_new_barcode TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_actor
    FROM public.user_profiles
    WHERE id = auth.uid() AND is_active = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account is inactive or unavailable.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_sample FROM public.samples WHERE id = p_sample_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sample not found.' USING ERRCODE = 'P0002';
    END IF;

    IF p_to_status = 'Collected' THEN
        IF NOT public.has_permission('can_collect_sample') THEN
            RAISE EXCEPTION 'Permission denied for sample collection.' USING ERRCODE = '42501';
        END IF;
        IF v_sample.status <> 'Pending' THEN
            RAISE EXCEPTION 'Invalid sample transition: only Pending samples can be collected.' USING ERRCODE = '22023';
        END IF;
        UPDATE public.samples SET status = 'Collected', collected_at = v_now,
            collected_by = v_actor.id, collected_by_name = v_actor.full_name, updated_at = v_now
        WHERE id = v_sample.id;
        UPDATE public.clinical_order_items SET status = 'SampleCollected', updated_at = v_now
        WHERE sample_id = v_sample.id AND status = 'Pending';

    ELSIF p_to_status = 'Received' THEN
        IF NOT public.has_permission('can_receive_sample') THEN
            RAISE EXCEPTION 'Permission denied for sample receipt.' USING ERRCODE = '42501';
        END IF;
        IF v_sample.status <> 'Collected' THEN
            RAISE EXCEPTION 'Invalid sample transition: only Collected samples can be received.' USING ERRCODE = '22023';
        END IF;
        UPDATE public.samples SET status = 'Received', received_at = v_now,
            received_by = v_actor.id, received_by_name = v_actor.full_name, updated_at = v_now
        WHERE id = v_sample.id;
        UPDATE public.clinical_order_items SET status = 'SampleReceived', updated_at = v_now
        WHERE sample_id = v_sample.id AND status = 'SampleCollected';

    ELSIF p_to_status = 'Rejected' THEN
        IF NOT public.has_permission('can_reject_sample') THEN
            RAISE EXCEPTION 'Permission denied for sample rejection.' USING ERRCODE = '42501';
        END IF;
        IF v_sample.status NOT IN ('Pending', 'Collected', 'Received') THEN
            RAISE EXCEPTION 'Invalid sample transition: this sample cannot be rejected.' USING ERRCODE = '22023';
        END IF;
        IF btrim(COALESCE(p_reason, '')) = '' THEN
            RAISE EXCEPTION 'A rejection reason is required.' USING ERRCODE = '22023';
        END IF;
        UPDATE public.samples SET status = 'Rejected', rejected_at = v_now,
            rejected_by = v_actor.id, rejected_by_name = v_actor.full_name,
            rejection_reason = btrim(p_reason), updated_at = v_now
        WHERE id = v_sample.id;

    ELSIF p_to_status = 'Pending' THEN
        -- Rejected -> Pending means create a new recollection specimen; clinical
        -- history on the rejected row is never rewritten.
        IF NOT public.has_permission('can_collect_sample') THEN
            RAISE EXCEPTION 'Permission denied for recollection.' USING ERRCODE = '42501';
        END IF;
        IF v_sample.status <> 'Rejected' THEN
            RAISE EXCEPTION 'Invalid sample transition: only Rejected samples can be recollected.' USING ERRCODE = '22023';
        END IF;
        v_new_barcode := 'SMP-' || to_char(CURRENT_DATE, 'YYYY') || '-' || lpad(nextval('sample_seq')::TEXT, 5, '0');
        INSERT INTO public.samples(
            barcode, order_id, patient_id, specimen_type, container_type,
            status, recollected_from_sample_id
        ) VALUES (
            v_new_barcode, v_sample.order_id, v_sample.patient_id,
            v_sample.specimen_type, v_sample.container_type, 'Pending', v_sample.id
        ) RETURNING id INTO v_new_sample_id;
        UPDATE public.clinical_order_items SET sample_id = v_new_sample_id,
            status = 'Pending', updated_at = v_now
        WHERE sample_id = v_sample.id AND status <> 'SignedOff';
        INSERT INTO public.sample_lifecycle_events(
            sample_id, from_status, to_status, reason, performed_by, performed_by_name, timestamp
        ) VALUES (
            v_new_sample_id, 'Pending', 'Pending',
            COALESCE(NULLIF(btrim(p_reason), ''), 'Recollection ordered for rejected sample ' || v_sample.barcode),
            v_actor.id, v_actor.full_name, v_now
        );
        RETURN jsonb_build_object('success', TRUE, 'sample_id', v_new_sample_id,
            'barcode', v_new_barcode, 'status', 'Pending', 'recollected_from_sample_id', v_sample.id);
    ELSE
        RAISE EXCEPTION 'Unsupported sample transition.' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.sample_lifecycle_events(
        sample_id, from_status, to_status, reason, performed_by, performed_by_name, timestamp
    ) VALUES (
        v_sample.id, v_sample.status, p_to_status, NULLIF(btrim(COALESCE(p_reason, '')), ''),
        v_actor.id, v_actor.full_name, v_now
    );

    RETURN jsonb_build_object('success', TRUE, 'sample_id', v_sample.id,
        'barcode', v_sample.barcode, 'from_status', v_sample.status, 'status', p_to_status);
END;
$$;

DROP POLICY IF EXISTS "samples_insert" ON public.samples;
DROP POLICY IF EXISTS "samples_update" ON public.samples;
DROP POLICY IF EXISTS "sample_lifecycle_insert" ON public.sample_lifecycle_events;
REVOKE INSERT, UPDATE, DELETE ON public.samples FROM authenticated, anon;
REVOKE INSERT, UPDATE, DELETE ON public.sample_lifecycle_events FROM authenticated, anon;
REVOKE ALL ON FUNCTION public.transition_sample_lifecycle(UUID, sample_status_enum, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transition_sample_lifecycle(UUID, sample_status_enum, TEXT) TO authenticated;

-- ============================================================================
-- Report lineage uniqueness and concurrent sign-off serialization
-- ============================================================================
-- Abort before adding the constraint if production contains an anomaly. No
-- clinical row is modified or deleted; the conflicting lineages must be
-- reviewed manually and the migration rerun.
DO $report_version_guard$
DECLARE
    v_anomalies JSONB;
BEGIN
    SELECT jsonb_agg(jsonb_build_object('order_id', order_id, 'version', version, 'count', row_count))
    INTO v_anomalies
    FROM (
        SELECT order_id, version, count(*) AS row_count
        FROM public.diagnostic_reports
        GROUP BY order_id, version
        HAVING count(*) > 1
        ORDER BY order_id, version
        LIMIT 20
    ) anomalies;
    IF v_anomalies IS NOT NULL THEN
        RAISE EXCEPTION 'Duplicate diagnostic report versions require manual clinical review: %', v_anomalies;
    END IF;
END;
$report_version_guard$;

ALTER TABLE public.diagnostic_reports
    ADD CONSTRAINT diagnostic_reports_order_version_unique UNIQUE (order_id, version);

CREATE OR REPLACE FUNCTION public.lock_diagnostic_report_lineage()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.order_id::TEXT, 0));
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS lock_diagnostic_report_lineage_trigger ON public.diagnostic_reports;
CREATE TRIGGER lock_diagnostic_report_lineage_trigger
BEFORE INSERT ON public.diagnostic_reports
FOR EACH ROW EXECUTE FUNCTION public.lock_diagnostic_report_lineage();

-- Public report payloads contain the immutable snapshot required by the client;
-- private object paths are internal implementation details and are not exposed.
CREATE OR REPLACE FUNCTION public.resolve_public_report_by_token(p_token_hash VARCHAR(128))
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_token public.public_report_tokens%ROWTYPE;
    v_report public.diagnostic_reports%ROWTYPE;
BEGIN
    IF p_token_hash IS NULL OR btrim(p_token_hash) = '' THEN
        RETURN jsonb_build_object('valid', FALSE, 'error', 'Token is required.');
    END IF;
    SELECT * INTO v_token FROM public.public_report_tokens WHERE token_hash = btrim(p_token_hash) FOR UPDATE;
    IF NOT FOUND OR v_token.is_active IS NOT TRUE OR v_token.revoked_at IS NOT NULL OR v_token.expires_at < NOW() THEN
        RETURN jsonb_build_object('valid', FALSE, 'error', 'Invalid or expired report link.');
    END IF;
    SELECT * INTO v_report FROM public.diagnostic_reports WHERE id = v_token.diagnostic_report_id;
    IF NOT FOUND OR v_report.status NOT IN ('SignedOff', 'Amended') THEN
        RETURN jsonb_build_object('valid', FALSE, 'error', 'Report is not available.');
    END IF;
    UPDATE public.public_report_tokens SET access_count = access_count + 1, last_accessed_at = NOW()
    WHERE id = v_token.id;
    INSERT INTO public.audit_logs(action, entity_type, entity_id, new_data)
    VALUES ('PUBLIC_REPORT_VIEWED', 'DiagnosticReport', v_report.report_number,
        jsonb_build_object('token_id', v_token.id, 'report_id', v_report.id,
            'version', v_report.version, 'access_count', v_token.access_count + 1));
    RETURN jsonb_build_object(
        'valid', TRUE, 'report_number', v_report.report_number, 'version', v_report.version,
        'is_amendment', v_report.is_amendment, 'amendment_reason', v_report.amendment_reason,
        'signed_at', v_report.signed_at, 'integrity_hash', v_report.integrity_hash,
        'snapshot', v_report.clinical_snapshot_json
    );
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_public_report_by_token(VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_public_report_by_token(VARCHAR) TO anon, authenticated;
