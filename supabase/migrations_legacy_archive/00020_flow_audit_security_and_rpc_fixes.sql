-- Bimal Pathology Cloud LIS
-- Flow-audit fixes: forward-only, data-preserving, and backward-compatible.

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
