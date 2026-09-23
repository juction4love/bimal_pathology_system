-- Bimal Pathology: inactive identities have zero application permissions.
-- Forward-only production migration. Production 00000-00050 remain immutable.

-- A failed staging-only compatibility experiment temporarily restored this
-- legacy grant in isolated staging. Production never applied that experiment.
-- Revoke defensively so clean installs and the reconciled staging environment
-- converge on the secured 00050 billing architecture.
REVOKE EXECUTE ON FUNCTION public.create_patient_bill_and_order(
    JSONB,
    JSONB,
    JSONB[],
    JSONB
) FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.create_patient_bill_and_order(
    JSONB,
    JSONB,
    JSONB[],
    JSONB,
    TEXT
) FROM PUBLIC, anon, authenticated;

-- Payment Confirmation is inserted transactionally by the billing/payment
-- authorities. Manual browser queueing is obsolete and must remain closed.
REVOKE EXECUTE ON FUNCTION public.queue_bill_sms(UUID)
FROM PUBLIC, anon, authenticated;

-- Atomic sign-off plus secure-link/ReportReady queueing is the only browser
-- sign-off path. The queue wrapper remains able to call this owner-internal
-- worker while authenticated clients cannot bypass notification creation.
REVOKE EXECUTE ON FUNCTION public.sign_and_freeze_diagnostic_report(
    UUID,
    UUID,
    UUID,
    TEXT,
    UUID
) FROM PUBLIC, anon, authenticated;

-- The historical acknowledge_critical_result RPC was already revoked and
-- dropped by 00047; do not recreate that obsolete mutation surface.

-- The guarded 00048 user-access RPC and the Auth provisioning trigger remain
-- authoritative. Browser clients must not bypass atomic role replacement,
-- last-super-admin protection, or server-authored audit evidence.
REVOKE INSERT, UPDATE, DELETE ON public.user_profiles FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.user_roles FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.user_direct_permissions FROM authenticated;

-- Role identities are fixed application master data in the current release;
-- only the guarded matrix-replacement RPC may mutate their permissions.
-- Audit rows are server-authored evidence and are never client-writable.
REVOKE INSERT, UPDATE, DELETE ON public.roles FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.audit_logs FROM authenticated;

-- Some isolated environments received an earlier 00050 build before the
-- amendment-compatible order-state contract was added. Production history is
-- immutable, so converge forward-only and do nothing when the constraint is
-- already compatible.
DO $clinical_order_status_compatibility$
DECLARE
    v_allows_in_progress BOOLEAN;
BEGIN
    SELECT COALESCE(
        position('InProgress' IN pg_get_constraintdef(c.oid)) > 0,
        FALSE
    )
    INTO v_allows_in_progress
    FROM pg_constraint c
    WHERE c.conrelid = 'public.clinical_orders'::REGCLASS
      AND c.conname = 'clinical_orders_status_check'
      AND c.contype = 'c';

    IF NOT COALESCE(v_allows_in_progress, FALSE) THEN
        ALTER TABLE public.clinical_orders
            DROP CONSTRAINT IF EXISTS clinical_orders_status_check;
        ALTER TABLE public.clinical_orders
            ADD CONSTRAINT clinical_orders_status_check
            CHECK (status IN (
                'Registered',
                'InLab',
                'InProgress',
                'PartiallyCompleted',
                'Completed',
                'SignedOff'
            ));
    END IF;
END;
$clinical_order_status_compatibility$;

CREATE OR REPLACE FUNCTION public.is_active_user()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT auth.uid() IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM public.user_profiles up
           WHERE up.id = auth.uid()
             AND up.is_active = TRUE
       )
$$;

REVOKE ALL ON FUNCTION public.is_active_user() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_active_user() TO authenticated;

CREATE OR REPLACE FUNCTION public.has_permission(p_permission_key VARCHAR)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_has_perm BOOLEAN;
BEGIN
    -- This check precedes super-admin, direct-grant, and role evaluation. An
    -- inactive or missing application profile has no application permission,
    -- even if stale role/direct-permission rows still exist.
    IF NOT public.is_active_user() THEN
        RETURN FALSE;
    END IF;

    IF public.is_super_admin() THEN
        RETURN TRUE;
    END IF;

    SELECT udp.is_granted
    INTO v_has_perm
    FROM public.user_direct_permissions udp
    WHERE udp.user_id = auth.uid()
      AND udp.permission_key = p_permission_key;

    IF v_has_perm IS NOT NULL THEN
        RETURN v_has_perm;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM public.user_roles ur
        JOIN public.role_permissions rp ON rp.role_id = ur.role_id
        WHERE ur.user_id = auth.uid()
          AND rp.permission_key = p_permission_key
    );
END;
$$;

REVOKE ALL ON FUNCTION public.has_permission(VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_permission(VARCHAR) TO authenticated;

COMMENT ON FUNCTION public.has_permission(VARCHAR) IS
    'Common application authorization gate. Inactive or missing user profiles always receive FALSE before super-admin, direct-grant, or role evaluation.';

-- Generic authenticated master-data reads must also require an active profile;
-- they do not call has_permission because every active laboratory user may read
-- these lookup records.
DROP POLICY IF EXISTS "roles_select" ON public.roles;
CREATE POLICY "roles_select" ON public.roles FOR SELECT TO authenticated
USING (public.is_active_user());

DROP POLICY IF EXISTS "role_permissions_select" ON public.role_permissions;
CREATE POLICY "role_permissions_select" ON public.role_permissions FOR SELECT TO authenticated
USING (public.is_active_user());

DROP POLICY IF EXISTS "user_roles_select" ON public.user_roles;
CREATE POLICY "user_roles_select" ON public.user_roles FOR SELECT TO authenticated
USING (public.is_active_user() AND (
    user_id = auth.uid()
    OR public.has_permission('can_manage_roles')
    OR public.has_permission('can_manage_users')
));

DROP POLICY IF EXISTS "user_direct_permissions_select" ON public.user_direct_permissions;
CREATE POLICY "user_direct_permissions_select" ON public.user_direct_permissions FOR SELECT TO authenticated
USING (public.is_active_user() AND (
    user_id = auth.uid()
    OR public.has_permission('can_manage_roles')
    OR public.has_permission('can_manage_users')
));

DROP POLICY IF EXISTS "tests_select" ON public.tests;
CREATE POLICY "tests_select" ON public.tests FOR SELECT TO authenticated
USING (public.is_active_user());

DROP POLICY IF EXISTS "parameters_select" ON public.parameters;
CREATE POLICY "parameters_select" ON public.parameters FOR SELECT TO authenticated
USING (public.is_active_user());

DROP POLICY IF EXISTS "ref_ranges_select" ON public.reference_ranges;
CREATE POLICY "ref_ranges_select" ON public.reference_ranges FOR SELECT TO authenticated
USING (public.is_active_user());

DROP POLICY IF EXISTS "referring_doctors_select" ON public.referring_doctors;
CREATE POLICY "referring_doctors_select" ON public.referring_doctors FOR SELECT TO authenticated
USING (public.is_active_user());

DROP POLICY IF EXISTS "reporting_personnel_select" ON public.reporting_personnel;
CREATE POLICY "reporting_personnel_select" ON public.reporting_personnel FOR SELECT TO authenticated
USING (public.is_active_user());

DROP POLICY IF EXISTS test_categories_read ON public.test_categories;
CREATE POLICY test_categories_read ON public.test_categories FOR SELECT TO authenticated
USING (public.is_active_user());

DROP POLICY IF EXISTS catalogue_calculations_read ON public.catalogue_calculation_definitions;
CREATE POLICY catalogue_calculations_read ON public.catalogue_calculation_definitions FOR SELECT TO authenticated
USING (public.is_active_user());

DROP POLICY IF EXISTS packages_read ON public.health_packages;
CREATE POLICY packages_read ON public.health_packages FOR SELECT TO authenticated
USING (public.is_active_user());

DROP POLICY IF EXISTS package_components_read ON public.health_package_components;
CREATE POLICY package_components_read ON public.health_package_components FOR SELECT TO authenticated
USING (public.is_active_user());

-- The 00007 bootstrap RPC is obsolete after trigger-authoritative provisioning
-- in 00048. It must not let an arbitrary authenticated identity self-provision.
REVOKE EXECUTE ON FUNCTION public.bootstrap_first_admin() FROM PUBLIC, anon, authenticated;

-- Readiness exposes clinical item/result detail, so authenticated alone is not
-- sufficient. Sign-off calls remain valid because signers hold can_sign_reports.
CREATE OR REPLACE FUNCTION public.check_order_report_readiness(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_reportable_count INT := 0;
    v_verified_count INT := 0;
    v_unverified_items JSONB := '[]'::JSONB;
    v_unack_critical_count INT := 0;
    v_unack_critical_items JSONB := '[]'::JSONB;
    v_item RECORD;
    v_res RECORD;
BEGIN
    IF NOT public.is_active_user() OR NOT (
        public.has_permission('can_enter_results')
        OR public.has_permission('can_verify_results')
        OR public.has_permission('can_sign_reports')
    ) THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;

    FOR v_item IN
        SELECT coi.id, coi.test_name, coi.department, coi.reporting_type, coi.status
        FROM public.clinical_order_items coi
        WHERE coi.order_id = p_order_id
          AND coi.reporting_type IN ('InHouse', 'OutsourceWithBimalReport')
    LOOP
        v_reportable_count := v_reportable_count + 1;
        IF v_item.status IN ('Verified', 'SignedOff') THEN
            v_verified_count := v_verified_count + 1;
        ELSE
            v_unverified_items := v_unverified_items || jsonb_build_object(
                'order_item_id', v_item.id, 'test_name', v_item.test_name,
                'department', v_item.department, 'status', v_item.status
            );
        END IF;
    END LOOP;

    FOR v_res IN
        SELECT tr.id, tr.parameter_name, tr.display_value, tr.unit, tr.flag,
               tr.critical_acknowledged, coi.test_name
        FROM public.test_results tr
        JOIN public.clinical_order_items coi ON coi.id = tr.order_item_id
        WHERE coi.order_id = p_order_id
          AND (tr.is_critical = TRUE OR tr.flag IN ('CriticalLow', 'CriticalHigh'))
          AND tr.critical_acknowledged = FALSE
    LOOP
        v_unack_critical_count := v_unack_critical_count + 1;
        v_unack_critical_items := v_unack_critical_items || jsonb_build_object(
            'result_id', v_res.id, 'test_name', v_res.test_name,
            'parameter_name', v_res.parameter_name, 'display_value', v_res.display_value,
            'unit', v_res.unit, 'flag', v_res.flag
        );
    END LOOP;

    RETURN jsonb_build_object(
        'is_ready', v_reportable_count > 0
                    AND v_verified_count = v_reportable_count
                    AND v_unack_critical_count = 0,
        'reportable_count', v_reportable_count,
        'verified_count', v_verified_count,
        'unverified_count', v_reportable_count - v_verified_count,
        'unverified_items', v_unverified_items,
        'unacknowledged_critical_count', v_unack_critical_count,
        'unacknowledged_critical_items', v_unack_critical_items
    );
END;
$$;
REVOKE ALL ON FUNCTION public.check_order_report_readiness(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_order_report_readiness(UUID) TO authenticated;

-- Remove the historical inactive-admin/email fallback. The common permission
-- gate is now the sole financial authorization authority.
CREATE OR REPLACE FUNCTION public.get_dashboard_collection_summary()
RETURNS TABLE (
    today_collection_paisa BIGINT,
    month_collection_paisa BIGINT,
    total_collection_paisa BIGINT,
    today_count INT,
    month_count INT,
    total_count INT,
    month_label TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_today_start TIMESTAMPTZ;
    v_month_start TIMESTAMPTZ;
    v_month_name TEXT;
BEGIN
    IF NOT public.has_permission('can_view_financials') THEN
        RAISE EXCEPTION 'Access Denied: User lacks can_view_financials permission' USING ERRCODE = '42501';
    END IF;
    v_today_start := date_trunc('day', now() AT TIME ZONE 'Asia/Kathmandu') AT TIME ZONE 'Asia/Kathmandu';
    v_month_start := date_trunc('month', now() AT TIME ZONE 'Asia/Kathmandu') AT TIME ZONE 'Asia/Kathmandu';
    v_month_name := to_char(now() AT TIME ZONE 'Asia/Kathmandu', 'FMMonth YYYY');
    RETURN QUERY
    SELECT
        COALESCE(sum(CASE WHEN pt.created_at >= v_today_start THEN pt.amount_paisa ELSE 0 END), 0)::BIGINT,
        COALESCE(sum(CASE WHEN pt.created_at >= v_month_start THEN pt.amount_paisa ELSE 0 END), 0)::BIGINT,
        COALESCE(sum(pt.amount_paisa), 0)::BIGINT,
        COALESCE(count(CASE WHEN pt.created_at >= v_today_start THEN 1 END), 0)::INT,
        COALESCE(count(CASE WHEN pt.created_at >= v_month_start THEN 1 END), 0)::INT,
        COALESCE(count(*), 0)::INT,
        v_month_name
    FROM public.payment_transactions pt;
END;
$$;
REVOKE ALL ON FUNCTION public.get_dashboard_collection_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_dashboard_collection_summary() TO authenticated;

-- Critical-value communication is a distinct clinical authority. Result entry
-- or verification permission alone must not acknowledge a critical alert.
CREATE OR REPLACE FUNCTION public.record_critical_value_acknowledgement(
    p_order_item_id UUID,
    p_notification_method TEXT,
    p_notified_person TEXT,
    p_comment TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_item public.clinical_order_items%ROWTYPE;
    v_user_name TEXT;
BEGIN
    IF NOT public.has_permission('can_acknowledge_critical') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;
    IF NULLIF(btrim(p_notified_person), '') IS NULL THEN
        RAISE EXCEPTION 'The notified clinician or ward staff is required.' USING ERRCODE = '22023';
    END IF;
    IF p_notification_method NOT IN (
        'Direct Phone Call', 'In-Person Verbal Alert',
        'Hospital Intercom', 'Official WhatsApp / SMS'
    ) THEN
        RAISE EXCEPTION 'A supported notification method is required.' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_item FROM public.clinical_order_items
    WHERE id = p_order_item_id FOR UPDATE;
    IF NOT FOUND OR v_item.status = 'SignedOff' THEN
        RAISE EXCEPTION 'This result can no longer be modified.' USING ERRCODE = '55000';
    END IF;
    SELECT COALESCE(full_name, 'Lab Staff') INTO v_user_name
    FROM public.user_profiles WHERE id = auth.uid();
    INSERT INTO public.audit_logs(user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES (
        auth.uid(), v_user_name, 'CRITICAL_VALUE_ACKNOWLEDGED',
        'ClinicalOrderItem', p_order_item_id::TEXT,
        jsonb_strip_nulls(jsonb_build_object(
            'notification_method', p_notification_method,
            'notified_person', left(btrim(p_notified_person), 255),
            'comment', NULLIF(left(btrim(COALESCE(p_comment, '')), 1000), '')
        ))
    );
    RETURN jsonb_build_object('success', TRUE);
END;
$$;
REVOKE ALL ON FUNCTION public.record_critical_value_acknowledgement(UUID, TEXT, TEXT, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_critical_value_acknowledgement(UUID, TEXT, TEXT, TEXT)
TO authenticated;

-- Result payloads are client-supplied even though save_test_results is the
-- authoritative writer. Enforce that a new critical acknowledgement is backed
-- by the dedicated permission and a preceding, server-authored audit event by
-- the same actor. Once acknowledged, later verification preserves the original
-- acknowledgement identity instead of replacing it with the verifier.
CREATE OR REPLACE FUNCTION public.enforce_critical_acknowledgement_authority()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_was_acknowledged BOOLEAN := FALSE;
    v_not_before TIMESTAMPTZ := '-infinity'::TIMESTAMPTZ;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        v_was_acknowledged := COALESCE(OLD.critical_acknowledged, FALSE);
        v_not_before := COALESCE(OLD.updated_at, '-infinity'::TIMESTAMPTZ);

        IF v_was_acknowledged
           AND COALESCE(NEW.critical_acknowledged, FALSE) THEN
            NEW.critical_acknowledged_by := OLD.critical_acknowledged_by;
            NEW.critical_acknowledged_at := OLD.critical_acknowledged_at;
            RETURN NEW;
        END IF;
    END IF;

    IF COALESCE(NEW.critical_acknowledged, FALSE)
       AND NOT v_was_acknowledged
       AND (COALESCE(NEW.is_critical, FALSE)
            OR NEW.flag IN ('CriticalLow', 'CriticalHigh')) THEN
        IF NOT public.has_permission('can_acknowledge_critical') THEN
            RAISE EXCEPTION 'Critical acknowledgement permission is required.'
                USING ERRCODE = '42501';
        END IF;
        IF NEW.critical_acknowledged_by IS DISTINCT FROM auth.uid()
           OR NEW.critical_acknowledged_at IS NULL THEN
            RAISE EXCEPTION 'Critical acknowledgement actor metadata is invalid.'
                USING ERRCODE = '23514';
        END IF;
        IF NOT EXISTS (
            SELECT 1
            FROM public.audit_logs a
            WHERE a.action = 'CRITICAL_VALUE_ACKNOWLEDGED'
              AND a.entity_type = 'ClinicalOrderItem'
              AND a.entity_id = NEW.order_item_id::TEXT
              AND a.user_id = auth.uid()
              AND a.timestamp >= v_not_before
              AND a.timestamp <= clock_timestamp()
        ) THEN
            RAISE EXCEPTION 'Document the critical notification before saving its acknowledgement.'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_critical_acknowledgement_authority_trigger
ON public.test_results;
CREATE TRIGGER enforce_critical_acknowledgement_authority_trigger
BEFORE INSERT OR UPDATE ON public.test_results
FOR EACH ROW
EXECUTE FUNCTION public.enforce_critical_acknowledgement_authority();

REVOKE ALL ON FUNCTION public.enforce_critical_acknowledgement_authority()
FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.enforce_critical_acknowledgement_authority() IS
    'Requires a same-actor server audit before false-to-true critical acknowledgement and preserves existing acknowledgement identity. A changed amendment value that remains acknowledged is not automatically forced back to unacknowledged; that re-ack policy remains a separate clinical workflow decision.';

-- Safe deletion for an unused category. Referenced categories are retained and
-- must be archived after their tests are moved/archived.
CREATE OR REPLACE FUNCTION public.catalogue_delete_category(
    p_category_id UUID,
    p_expected_version BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_category public.test_categories%ROWTYPE;
BEGIN
    PERFORM public.catalogue_require_manager();
    SELECT * INTO v_category FROM public.test_categories
    WHERE id = p_category_id FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;
    IF p_expected_version IS NULL OR v_category.row_version <> p_expected_version THEN
        RAISE EXCEPTION 'Category changed. Refresh and try again.' USING ERRCODE = 'PT409';
    END IF;
    IF EXISTS (SELECT 1 FROM public.tests WHERE category_id = p_category_id) THEN
        RAISE EXCEPTION 'Referenced categories cannot be deleted. Move or archive their tests first.' USING ERRCODE = '23503';
    END IF;
    INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data)
    VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_CATEGORY_DELETED','TestCategory',p_category_id::TEXT,to_jsonb(v_category));
    DELETE FROM public.test_categories WHERE id = p_category_id;
END;
$$;
REVOKE ALL ON FUNCTION public.catalogue_delete_category(UUID, BIGINT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_delete_category(UUID, BIGINT) TO authenticated;

-- Persist the package pricing/search metadata added by 00050. The original
-- save RPC accepted these columns in schema/search but silently discarded them.
-- Package membership never changes a component test's standalone price policy.
CREATE OR REPLACE FUNCTION public.catalogue_save_package(
    p_package JSONB,
    p_components UUID[],
    p_expected_version BIGINT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_existing public.health_packages%ROWTYPE;
    v_old JSONB;
    v_result_id UUID;
    v_component UUID;
    v_position INT := 0;
    v_components UUID[] := COALESCE(p_components, ARRAY[]::UUID[]);
    v_pricing_policy public.catalogue_pricing_policy_enum;
    v_search_aliases TEXT[];
    v_price_paisa BIGINT;
    v_code TEXT;
    v_name TEXT;
BEGIN
    PERFORM public.catalogue_require_manager();

    IF COALESCE(jsonb_typeof(p_package), 'null') <> 'object' THEN
        RAISE EXCEPTION 'Package configuration must be a JSON object.' USING ERRCODE = '22023';
    END IF;
    IF p_package ? 'search_aliases'
       AND jsonb_typeof(p_package->'search_aliases') <> 'array' THEN
        RAISE EXCEPTION 'Package search aliases must be an array.' USING ERRCODE = '22023';
    END IF;

    v_code := upper(btrim(COALESCE(p_package->>'code', '')));
    v_name := btrim(COALESCE(p_package->>'name', ''));
    v_price_paisa := COALESCE(NULLIF(p_package->>'price_paisa', '')::BIGINT, 0);
    v_pricing_policy := COALESCE(
        NULLIF(p_package->>'pricing_policy', '')::public.catalogue_pricing_policy_enum,
        'Fixed'::public.catalogue_pricing_policy_enum
    );

    IF v_code = '' OR v_name = '' THEN
        RAISE EXCEPTION 'Package code and name are required.' USING ERRCODE = '22023';
    END IF;
    IF v_price_paisa < 0 THEN
        RAISE EXCEPTION 'Package price cannot be negative.' USING ERRCODE = '23514';
    END IF;
    IF cardinality(v_components) <> (
        SELECT count(DISTINCT component_id)::INT
        FROM unnest(v_components) AS component_id
    ) THEN
        RAISE EXCEPTION 'Package components must be unique.' USING ERRCODE = '23505';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM unnest(v_components) AS requested(test_id)
        LEFT JOIN public.tests t ON t.id = requested.test_id
        WHERE t.id IS NULL OR t.lifecycle_status <> 'Active' OR NOT t.is_active
    ) THEN
        RAISE EXCEPTION 'Packages may contain only active canonical tests/profiles.' USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(array_agg(alias_value ORDER BY alias_value), ARRAY[]::TEXT[])
    INTO v_search_aliases
    FROM (
        SELECT DISTINCT lower(btrim(alias_text)) AS alias_value
        FROM jsonb_array_elements_text(
            CASE
                WHEN jsonb_typeof(p_package->'search_aliases') = 'array'
                    THEN p_package->'search_aliases'
                ELSE '[]'::JSONB
            END
        ) AS aliases(alias_text)
        WHERE btrim(alias_text) <> ''
    ) normalized_aliases;

    IF NULLIF(p_package->>'id', '') IS NOT NULL THEN
        SELECT * INTO v_existing
        FROM public.health_packages
        WHERE id = (p_package->>'id')::UUID
        FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Package no longer exists.' USING ERRCODE = 'P0002';
        END IF;
        IF p_expected_version IS NULL OR v_existing.row_version <> p_expected_version THEN
            RAISE EXCEPTION 'Package changed. Refresh and try again.' USING ERRCODE = 'PT409';
        END IF;

        v_old := to_jsonb(v_existing);
        UPDATE public.health_packages
        SET code = v_code,
            name = v_name,
            description = NULLIF(btrim(p_package->>'description'), ''),
            price_paisa = v_price_paisa,
            pricing_policy = v_pricing_policy,
            search_aliases = v_search_aliases,
            row_version = row_version + 1,
            updated_at = NOW()
        WHERE id = v_existing.id
        RETURNING id INTO v_result_id;

        DELETE FROM public.health_package_components
        WHERE package_id = v_result_id;
    ELSE
        INSERT INTO public.health_packages(
            code, name, description, price_paisa, pricing_policy,
            search_aliases, lifecycle_status
        ) VALUES (
            v_code, v_name, NULLIF(btrim(p_package->>'description'), ''),
            v_price_paisa, v_pricing_policy, v_search_aliases, 'Draft'
        )
        RETURNING id INTO v_result_id;
    END IF;

    FOREACH v_component IN ARRAY v_components LOOP
        v_position := v_position + 1;
        INSERT INTO public.health_package_components(package_id, test_id, display_order)
        VALUES (v_result_id, v_component, v_position);
    END LOOP;

    INSERT INTO public.audit_logs(
        user_id, user_name, action, entity_type, entity_id, old_data, new_data
    ) VALUES (
        auth.uid(), public.catalogue_actor_name(), 'CATALOGUE_PACKAGE_SAVED',
        'HealthPackage', v_result_id::TEXT, v_old,
        jsonb_build_object(
            'package', (SELECT to_jsonb(p) FROM public.health_packages p WHERE p.id = v_result_id),
            'components', to_jsonb(v_components)
        )
    );

    RETURN v_result_id;
END;
$$;
REVOKE ALL ON FUNCTION public.catalogue_save_package(JSONB, UUID[], BIGINT)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_save_package(JSONB, UUID[], BIGINT)
TO authenticated;

-- A package with a negotiated/manual policy may be active with no master rate:
-- billing still requires a positive agreed rate. Fixed packages require their
-- authoritative positive rate. Every active package must expand only to unique,
-- active, clinically configured, supported component tests/profiles.
CREATE OR REPLACE FUNCTION public.catalogue_set_package_lifecycle(
    p_package_id UUID,
    p_status public.catalogue_lifecycle_enum,
    p_expected_version BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_package public.health_packages%ROWTYPE;
BEGIN
    PERFORM public.catalogue_require_manager();
    SELECT * INTO v_package
    FROM public.health_packages
    WHERE id=p_package_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Package no longer exists.' USING ERRCODE='P0002';
    END IF;
    IF p_expected_version IS NULL OR v_package.row_version<>p_expected_version THEN
        RAISE EXCEPTION 'Package changed. Refresh and try again.' USING ERRCODE='PT409';
    END IF;

    IF p_status='Active' THEN
        IF NOT EXISTS(
            SELECT 1 FROM public.health_package_components c
            WHERE c.package_id=p_package_id
        ) THEN
            RAISE EXCEPTION 'An active package requires at least one component.' USING ERRCODE='23514';
        END IF;
        IF EXISTS(
            SELECT 1
            FROM public.health_package_components c
            LEFT JOIN public.tests t ON t.id=c.test_id
            WHERE c.package_id=p_package_id
              AND (
                  t.id IS NULL
                  OR t.lifecycle_status<>'Active'
                  OR NOT t.is_active
                  OR NOT t.workflow_supported
                  OR t.clinical_configuration_status NOT IN ('Configured','Ready for Activation')
              )
        ) THEN
            RAISE EXCEPTION 'Every package component must be active, clinically configured, and workflow-supported.' USING ERRCODE='23514';
        END IF;
        IF v_package.pricing_policy='Fixed' AND v_package.price_paisa<=0 THEN
            RAISE EXCEPTION 'A fixed package requires a positive authoritative price.' USING ERRCODE='23514';
        END IF;
    END IF;

    UPDATE public.health_packages
    SET lifecycle_status=p_status,
        row_version=row_version+1,
        updated_at=NOW(),
        archived_at=CASE WHEN p_status='Archived' THEN NOW() ELSE NULL END,
        archived_by=CASE WHEN p_status='Archived' THEN auth.uid() ELSE NULL END
    WHERE id=p_package_id;

    INSERT INTO public.audit_logs(
        user_id,user_name,action,entity_type,entity_id,old_data,new_data
    ) VALUES (
        auth.uid(),public.catalogue_actor_name(),
        'CATALOGUE_PACKAGE_'||upper(p_status::TEXT),
        'HealthPackage',p_package_id::TEXT,to_jsonb(v_package),
        (SELECT to_jsonb(p) FROM public.health_packages p WHERE p.id=p_package_id)
    );
END;
$$;
REVOKE ALL ON FUNCTION public.catalogue_set_package_lifecycle(
    UUID, public.catalogue_lifecycle_enum, BIGINT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_set_package_lifecycle(
    UUID, public.catalogue_lifecycle_enum, BIGINT
) TO authenticated;

-- Package expansion is resolved before component price checks. A package may
-- allocate its fixed or explicitly agreed price across components (including
-- zero-valued component snapshots) without weakening standalone price policy.
CREATE OR REPLACE FUNCTION public.create_patient_bill_order_with_packages(
    p_patient_data JSONB,
    p_bill_data JSONB,
    p_items_data JSONB[],
    p_payment_data JSONB,
    p_idempotency_key TEXT,
    p_packages JSONB DEFAULT '[]'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    response JSONB;
    bill_uuid UUID;
    pkg JSONB;
    component UUID;
    selection_uuid UUID;
    expected_ids UUID[];
    supplied_ids UUID[] := ARRAY(SELECT DISTINCT (x->>'test_id')::UUID FROM unnest(p_items_data) x);
    package_seen UUID[] := ARRAY[]::UUID[];
    requested_package_ids UUID[] := ARRAY[]::UUID[];
    existing_package_ids UUID[];
    temporary_manual_price_ids UUID[] := ARRAY[]::UUID[];
    package_row public.health_packages%ROWTYPE;
    agreed_price BIGINT;
    component_price_sum BIGINT;
    packages_payload JSONB := COALESCE(p_packages, '[]'::JSONB);
    is_replay BOOLEAN := FALSE;
BEGIN
    IF NOT public.has_permission('can_create_bill') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
    END IF;
    IF jsonb_typeof(packages_payload) <> 'array' THEN
        RAISE EXCEPTION 'Package selections must be a JSON array.' USING ERRCODE='22023';
    END IF;
    IF cardinality(p_items_data) IS NULL OR cardinality(p_items_data) = 0 THEN
        RAISE EXCEPTION 'At least one billable catalogue item is required.' USING ERRCODE='23514';
    END IF;
    IF cardinality(p_items_data) <> cardinality(supplied_ids) THEN
        RAISE EXCEPTION 'A canonical test/profile may be selected only once.' USING ERRCODE='23505';
    END IF;
    IF EXISTS(
        SELECT 1 FROM unnest(p_items_data) item
        LEFT JOIN public.tests t ON t.id=(item->>'test_id')::UUID
        WHERE t.id IS NULL OR t.lifecycle_status<>'Active' OR NOT t.is_active
           OR NOT t.workflow_supported
           OR t.clinical_configuration_status NOT IN ('Configured','Ready for Activation')
    ) THEN
        RAISE EXCEPTION 'Only active, clinically configured, supported catalogue tests may be billed.' USING ERRCODE='23514';
    END IF;

    FOR pkg IN SELECT * FROM jsonb_array_elements(packages_payload) LOOP
        IF jsonb_typeof(pkg) <> 'object'
           OR NULLIF(pkg->>'package_id', '') IS NULL
           OR jsonb_typeof(pkg->'component_ids') <> 'array'
           OR NULLIF(pkg->>'agreed_price_paisa', '') IS NULL THEN
            RAISE EXCEPTION 'Each package requires an id, ordered components, and an agreed price.' USING ERRCODE='22023';
        END IF;

        SELECT * INTO package_row
        FROM public.health_packages
        WHERE id=(pkg->>'package_id')::UUID
          AND lifecycle_status='Active'
        FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Only active packages may be billed.' USING ERRCODE='23514';
        END IF;
        IF package_row.id=ANY(requested_package_ids) THEN
            RAISE EXCEPTION 'A package may be selected only once.' USING ERRCODE='23505';
        END IF;
        requested_package_ids:=array_append(requested_package_ids,package_row.id);

        SELECT array_agg(c.test_id ORDER BY c.display_order) INTO expected_ids
        FROM public.health_package_components c
        WHERE c.package_id=package_row.id;
        IF expected_ids IS NULL OR expected_ids<>ARRAY(
            SELECT requested.value::UUID
            FROM jsonb_array_elements_text(pkg->'component_ids') AS requested(value)
        ) THEN
            RAISE EXCEPTION 'Package definition changed. Refresh billing catalogue.' USING ERRCODE='PT409';
        END IF;

        agreed_price:=(pkg->>'agreed_price_paisa')::BIGINT;
        IF agreed_price<=0 THEN
            RAISE EXCEPTION 'A package requires an explicit positive agreed price.' USING ERRCODE='23514';
        END IF;
        IF package_row.pricing_policy='Fixed'
           AND agreed_price<>package_row.price_paisa THEN
            RAISE EXCEPTION 'A fixed package price cannot be overridden.' USING ERRCODE='42501';
        END IF;

        FOREACH component IN ARRAY expected_ids LOOP
            IF component=ANY(package_seen) THEN
                RAISE EXCEPTION 'A component test may be expanded only once.' USING ERRCODE='23505';
            END IF;
            IF NOT component=ANY(supplied_ids) THEN
                RAISE EXCEPTION 'Package component is missing from bill items.' USING ERRCODE='23514';
            END IF;
            package_seen:=array_append(package_seen,component);
        END LOOP;

        IF EXISTS(
            SELECT 1
            FROM unnest(p_items_data) item
            WHERE (item->>'test_id')::UUID=ANY(expected_ids)
              AND (
                  item->>'unit_price_paisa' IS NULL
                  OR (item->>'unit_price_paisa')::BIGINT<0
              )
        ) THEN
            RAISE EXCEPTION 'Every package component requires a non-negative allocated price.' USING ERRCODE='23514';
        END IF;
        SELECT COALESCE(sum((item->>'unit_price_paisa')::BIGINT),0)
        INTO component_price_sum
        FROM unnest(p_items_data) item
        WHERE (item->>'test_id')::UUID=ANY(expected_ids);
        IF component_price_sum<>agreed_price THEN
            RAISE EXCEPTION 'Package component prices must equal the agreed package price.' USING ERRCODE='23514';
        END IF;
    END LOOP;

    IF EXISTS(
        SELECT 1 FROM unnest(p_items_data) item
        JOIN public.tests t ON t.id=(item->>'test_id')::UUID
        WHERE NOT t.id=ANY(package_seen)
          AND COALESCE((item->>'unit_price_paisa')::BIGINT,t.price_paisa)=0
          AND (NOT t.allow_zero_price_billing OR NOT COALESCE((item->>'zero_price_acknowledged')::BOOLEAN,FALSE))
    ) THEN
        RAISE EXCEPTION 'Zero-price billing requires catalogue authorization and explicit operator acknowledgement.' USING ERRCODE='23514';
    END IF;
    IF EXISTS(
        SELECT 1 FROM unnest(p_items_data) item
        JOIN public.tests t ON t.id=(item->>'test_id')::UUID
        WHERE NOT t.id=ANY(package_seen)
          AND NOT t.price_configured AND t.pricing_policy NOT IN ('PricePending','Manual')
    ) THEN
        RAISE EXCEPTION 'A configured catalogue price is required for this pricing policy.' USING ERRCODE='23514';
    END IF;
    IF EXISTS(
        SELECT 1 FROM unnest(p_items_data) item
        JOIN public.tests t ON t.id=(item->>'test_id')::UUID
        WHERE t.pricing_policy='Fixed' AND NOT t.id=ANY(package_seen)
          AND COALESCE((item->>'unit_price_paisa')::BIGINT,-1)<>t.price_paisa
    ) THEN
        RAISE EXCEPTION 'Fixed catalogue prices cannot be overridden during billing.' USING ERRCODE='42501';
    END IF;
    IF EXISTS(
        SELECT 1 FROM unnest(p_items_data) item
        JOIN public.tests t ON t.id=(item->>'test_id')::UUID
        WHERE NOT t.id=ANY(package_seen)
          AND t.pricing_policy IN ('Negotiable','PricePending','Manual')
          AND ((item->>'unit_price_paisa') IS NULL OR (item->>'unit_price_paisa')::BIGINT<0)
    ) THEN
        RAISE EXCEPTION 'Negotiable, pending, and manual items require a valid agreed rate.' USING ERRCODE='23514';
    END IF;
    -- The established billing worker consumes an allocated item rate only when
    -- allow_manual_price is true. Package allocation is not a standalone test
    -- price override, so make that flag true only inside this transaction and
    -- restore its original state before returning. Row locks serialize package
    -- allocation with catalogue edits; other transactions never observe the
    -- uncommitted compatibility state. Any exception rolls it back atomically.
    IF cardinality(package_seen)>0 THEN
        PERFORM 1
        FROM public.tests t
        WHERE t.id=ANY(package_seen)
        ORDER BY t.id
        FOR UPDATE;

        SELECT COALESCE(array_agg(t.id ORDER BY t.id),ARRAY[]::UUID[])
        INTO temporary_manual_price_ids
        FROM public.tests t
        WHERE t.id=ANY(package_seen)
          AND NOT t.allow_manual_price;

        IF cardinality(temporary_manual_price_ids)>0 THEN
            UPDATE public.tests
            SET allow_manual_price=TRUE
            WHERE id=ANY(temporary_manual_price_ids);
        END IF;
    END IF;

    response:=public.create_patient_bill_and_order(
        p_patient_data,p_bill_data,p_items_data,p_payment_data,p_idempotency_key
    );

    IF cardinality(temporary_manual_price_ids)>0 THEN
        UPDATE public.tests
        SET allow_manual_price=FALSE
        WHERE id=ANY(temporary_manual_price_ids);
    END IF;

    bill_uuid:=(response->>'bill_id')::UUID;
    is_replay:=COALESCE((response->>'idempotency_replay')::BOOLEAN,FALSE);

    -- The established five-argument request hash predates packages. On replay,
    -- never attach a changed package selection to an existing bill: require an
    -- exact match with the snapshot committed by the original wrapper call.
    IF is_replay THEN
        SELECT COALESCE(array_agg(s.package_id ORDER BY s.package_id),ARRAY[]::UUID[])
        INTO existing_package_ids
        FROM public.bill_package_selections s
        WHERE s.bill_id=bill_uuid;
        IF existing_package_ids<>ARRAY(
            SELECT requested_id FROM unnest(requested_package_ids) requested_id ORDER BY requested_id
        ) THEN
            RAISE EXCEPTION 'Billing request key was already used with different package selections.' USING ERRCODE='22023';
        END IF;
        FOR pkg IN SELECT * FROM jsonb_array_elements(packages_payload) LOOP
            IF NOT EXISTS(
                SELECT 1
                FROM public.bill_package_selections s
                WHERE s.bill_id=bill_uuid
                  AND s.package_id=(pkg->>'package_id')::UUID
                  AND s.package_price_paisa=(pkg->>'agreed_price_paisa')::BIGINT
            ) OR ARRAY(
                SELECT c.test_id
                FROM public.bill_package_components c
                JOIN public.health_package_components current_component
                  ON current_component.package_id=(pkg->>'package_id')::UUID
                 AND current_component.test_id=c.test_id
                JOIN public.bill_package_selections s
                  ON s.id=c.bill_package_selection_id
                WHERE s.bill_id=bill_uuid
                  AND s.package_id=(pkg->>'package_id')::UUID
                ORDER BY current_component.display_order
            )<>ARRAY(
                SELECT requested.value::UUID
                FROM jsonb_array_elements_text(pkg->'component_ids') AS requested(value)
            ) THEN
                RAISE EXCEPTION 'Billing request key was already used with different package details.' USING ERRCODE='22023';
            END IF;
        END LOOP;
        RETURN response||jsonb_build_object('packages_recorded',jsonb_array_length(packages_payload));
    END IF;

    FOR pkg IN SELECT * FROM jsonb_array_elements(packages_payload) LOOP
        selection_uuid:=NULL;
        INSERT INTO public.bill_package_selections(bill_id,package_id,package_code_snapshot,package_name_snapshot,package_price_paisa)
        SELECT bill_uuid,p.id,p.code,p.name,(pkg->>'agreed_price_paisa')::BIGINT FROM public.health_packages p
        WHERE p.id=(pkg->>'package_id')::UUID
        ON CONFLICT(bill_id,package_id) DO NOTHING RETURNING id INTO selection_uuid;
        IF selection_uuid IS NOT NULL THEN
            INSERT INTO public.bill_package_components(bill_package_selection_id,bill_item_id,test_id)
            SELECT selection_uuid,bi.id,bi.test_id FROM public.bill_items bi
            WHERE bi.bill_id=bill_uuid
              AND bi.test_id=ANY(ARRAY(SELECT x::UUID FROM jsonb_array_elements_text(pkg->'component_ids') x));
        END IF;
    END LOOP;
    RETURN response||jsonb_build_object('packages_recorded',jsonb_array_length(packages_payload));
END;
$$;
REVOKE ALL ON FUNCTION public.create_patient_bill_order_with_packages(JSONB,JSONB,JSONB[],JSONB,TEXT,JSONB)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_order_with_packages(JSONB,JSONB,JSONB[],JSONB,TEXT,JSONB)
TO authenticated;
