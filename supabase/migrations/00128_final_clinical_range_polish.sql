-- ==============================================================================
-- Migration: 00128_final_clinical_range_polish.sql
-- Goal: Final Clinical Reference Range Polish & Server-Side Zero-Parameter Guard
--
-- Scope:
-- 1. Manual Differential Count (5-part microscopy):
--    - HEM-0015 (Neutrophils %): 40.0 - 70.0 %
--    - HEM-0016 (Lymphocytes %): 20.0 - 40.0 %
--    - HEM-0017 (Monocytes %): 2.0 - 10.0 %
--    - HEM-0018 (Eosinophils %): 1.0 - 6.0 %
--    - HEM-0019 (Basophils %): 0.0 - 1.0 %
--
-- 2. Vitamin D, 25-OH (BIO-0053):
--    - Unit: ng/mL
--    - Approved range: 30.0 - 100.0 ng/mL
--    - Approved interpretation: <20 Deficient | 20-30 Insufficient | 30-100 Sufficient
--    - Unapproved interpretations above 100 strictly excluded.
--
-- 3. Vitamin B12 (BIO-0051):
--    - Unit: pg/mL
--    - Approved range: 200.0 - 900.0 pg/mL
--    - Approved interpretation: Borderline: 200 - 300 pg/mL
--    - Inferred unapproved labels strictly excluded.
--
-- 4. Server-Side Zero-Parameter Clinical Ordering Structural Guard:
--    - Enforce at create_patient_bill_order_with_packages boundary that reportable single tests
--      with 0 reporting parameters cannot be ordered.
--    - Whitelist valid profile containers (PRO-0031, PRO-0032, PRO-0033, etc.) and NoReporting items.
--
-- 5. Active Reference Range De-duplication:
--    - Deactivate legacy duplicate rows to guarantee exactly 1 active range per parameter/gender/age band.
--
-- Clinical Invariants:
-- - Zero price changes.
-- - Zero renaming of tests, parameters, or canonical codes.
-- - Zero alteration of historical test results or signed clinical snapshots.
-- - Idempotent, duplicate-safe.
-- ==============================================================================

BEGIN;

DO $$
DECLARE
    v_param_id UUID;
BEGIN

    -- =========================================================================
    -- 1. MANUAL DIFFERENTIAL MICROSCOPY (HEM-0015 .. HEM-0019)
    -- =========================================================================

    -- Neutrophils % (HEM-0015) - 40.0 - 70.0 %
    SELECT p.id INTO v_param_id 
    FROM public.parameters p 
    JOIN public.tests t ON t.id = p.test_id 
    WHERE t.code = 'HEM-0015' AND p.is_active = TRUE 
    LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 40.0, 70.0, '40 - 70 %', '%', 'Manual Microscopy Differential', TRUE, TRUE);
    END IF;

    -- Lymphocytes % (HEM-0016) - 20.0 - 40.0 %
    SELECT p.id INTO v_param_id 
    FROM public.parameters p 
    JOIN public.tests t ON t.id = p.test_id 
    WHERE t.code = 'HEM-0016' AND p.is_active = TRUE 
    LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 20.0, 40.0, '20 - 40 %', '%', 'Manual Microscopy Differential', TRUE, TRUE);
    END IF;

    -- Monocytes % (HEM-0017) - 2.0 - 10.0 %
    SELECT p.id INTO v_param_id 
    FROM public.parameters p 
    JOIN public.tests t ON t.id = p.test_id 
    WHERE t.code = 'HEM-0017' AND p.is_active = TRUE 
    LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 2.0, 10.0, '2 - 10 %', '%', 'Manual Microscopy Differential', TRUE, TRUE);
    END IF;

    -- Eosinophils % (HEM-0018) - 1.0 - 6.0 %
    SELECT p.id INTO v_param_id 
    FROM public.parameters p 
    JOIN public.tests t ON t.id = p.test_id 
    WHERE t.code = 'HEM-0018' AND p.is_active = TRUE 
    LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 1.0, 6.0, '1 - 6 %', '%', 'Manual Microscopy Differential', TRUE, TRUE);
    END IF;

    -- Basophils % (HEM-0019) - 0.0 - 1.0 %
    SELECT p.id INTO v_param_id 
    FROM public.parameters p 
    JOIN public.tests t ON t.id = p.test_id 
    WHERE t.code = 'HEM-0019' AND p.is_active = TRUE 
    LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.0, 1.0, '0 - 1 %', '%', 'Manual Microscopy Differential', TRUE, TRUE);
    END IF;

    -- =========================================================================
    -- 2. VITAMIN D, 25-OH (BIO-0053)
    -- =========================================================================
    SELECT p.id INTO v_param_id 
    FROM public.parameters p 
    JOIN public.tests t ON t.id = p.test_id 
    WHERE t.code = 'BIO-0053' AND p.is_active = TRUE 
    LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 30.0, 100.0, '30 - 100 ng/mL (Sufficient; <20 Deficient, 20-30 Insufficient)', 'ng/mL', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE);
    END IF;

    -- =========================================================================
    -- 3. VITAMIN B12 (BIO-0051)
    -- =========================================================================
    SELECT p.id INTO v_param_id 
    FROM public.parameters p 
    JOIN public.tests t ON t.id = p.test_id 
    WHERE t.code = 'BIO-0051' AND p.is_active = TRUE 
    LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 200.0, 900.0, '200 - 900 pg/mL (Borderline: 200 - 300 pg/mL)', 'pg/mL', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE);
    END IF;

    -- =========================================================================
    -- 4. CLEAN UP LEGACY DUPLICATE ACTIVE REFERENCE RANGES
    -- =========================================================================
    WITH ranked_ranges AS (
        SELECT id, ROW_NUMBER() OVER (
            PARTITION BY parameter_id, gender, age_min_days, age_max_days 
            ORDER BY created_at DESC, id DESC
        ) as rn
        FROM public.reference_ranges
        WHERE is_active = TRUE
    )
    UPDATE public.reference_ranges
    SET is_active = FALSE
    WHERE id IN (
        SELECT id FROM ranked_ranges WHERE rn > 1
    );

END $$;

-- =============================================================================
-- 5. SERVER-SIDE STRUCTURAL ZERO-PARAMETER CLINICAL ORDERING GUARD
-- =============================================================================
CREATE OR REPLACE FUNCTION public.create_patient_bill_order_with_packages(
    p_patient_data JSONB,
    p_bill_data JSONB,
    p_items_data JSONB[],
    p_payment_data JSONB,
    p_idempotency_key TEXT,
    p_packages JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE 
    response JSONB; 
    bill_uuid UUID; 
    pkg JSONB; 
    component UUID; 
    selection_uuid UUID; 
    expected_ids UUID[]; 
    supplied_ids UUID[] := ARRAY(SELECT DISTINCT (x->>'test_id')::UUID FROM unnest(p_items_data) x); 
    package_seen UUID[] := ARRAY[]::UUID[]; 
    manual_ids UUID[] := ARRAY[]::UUID[]; 
    package_row public.health_packages%ROWTYPE; 
    agreed_price BIGINT; 
    component_sum BIGINT;
BEGIN
    IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN 
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; 
    END IF;

    IF cardinality(p_items_data) <> cardinality(supplied_ids) THEN 
        RAISE EXCEPTION 'A canonical service may be selected only once.' USING ERRCODE='23505'; 
    END IF;

    IF EXISTS (
        SELECT 1 
        FROM unnest(p_items_data) i 
        LEFT JOIN public.tests t ON t.id = (i->>'test_id')::UUID 
        WHERE t.id IS NULL OR t.lifecycle_status <> 'Active' OR NOT t.is_active OR NOT t.billing_enabled
    ) THEN 
        RAISE EXCEPTION 'Only active, billing-enabled catalogue services may be billed.' USING ERRCODE='23514'; 
    END IF;

    -- Server-side structural guard: Reject reportable single tests with zero active reporting parameters
    -- (Whitelist valid profile containers with children and NoReporting items)
    IF EXISTS (
        SELECT 1 
        FROM unnest(p_items_data) i
        JOIN public.tests t ON t.id = (i->>'test_id')::UUID
        WHERE t.reporting_type <> 'NoReporting'
          AND t.test_kind <> 'Profile'
          AND t.reporting_model <> 'Profile'
          AND NOT EXISTS (
              SELECT 1 FROM public.catalogue_panel_components cpc 
              WHERE cpc.panel_id = t.id OR cpc.panel_test_id = t.id
          )
          AND NOT EXISTS (
              SELECT 1 FROM public.parameters p 
              WHERE p.test_id = t.id AND p.is_active = TRUE
          )
    ) THEN
        RAISE EXCEPTION 'Configuration Incomplete: Reportable single test with 0 reporting parameters cannot be clinically ordered.' USING ERRCODE='23514';
    END IF;

    IF EXISTS (
        SELECT 1 
        FROM unnest(p_items_data) i 
        WHERE (i->>'unit_price_paisa') IS NULL OR (i->>'unit_price_paisa')::BIGINT < 0
    ) THEN 
        RAISE EXCEPTION 'Every item requires a valid agreed rate.' USING ERRCODE='23514'; 
    END IF;

    IF EXISTS (
        SELECT 1 
        FROM unnest(p_items_data) i 
        JOIN public.tests t ON t.id = (i->>'test_id')::UUID 
        WHERE (i->>'unit_price_paisa')::BIGINT = 0 
          AND (NOT t.allow_zero_price_billing OR NOT COALESCE((i->>'zero_price_acknowledged')::BOOLEAN, FALSE))
    ) THEN 
        RAISE EXCEPTION 'Zero-price billing requires explicit catalogue authorization and acknowledgement.' USING ERRCODE='23514'; 
    END IF;

    FOR pkg IN SELECT value FROM jsonb_array_elements(COALESCE(p_packages, '[]')) LOOP
        SELECT * INTO package_row FROM public.health_packages WHERE id = (pkg->>'package_id')::UUID AND lifecycle_status = 'Active' FOR SHARE; 
        IF NOT FOUND THEN 
            RAISE EXCEPTION 'Only active packages may be billed.' USING ERRCODE='23514'; 
        END IF;

        SELECT array_agg(c.test_id ORDER BY c.display_order) INTO expected_ids 
        FROM public.health_package_components c 
        JOIN public.tests t ON t.id = c.test_id 
        WHERE c.package_id = package_row.id AND t.lifecycle_status = 'Active' AND t.is_active AND t.billing_enabled;

        IF expected_ids IS NULL OR expected_ids <> ARRAY(SELECT x::UUID FROM jsonb_array_elements_text(pkg->'component_ids') x) THEN 
            RAISE EXCEPTION 'Package definition changed. Refresh billing catalogue.' USING ERRCODE='PT409'; 
        END IF;

        agreed_price := (pkg->>'agreed_price_paisa')::BIGINT; 
        IF agreed_price <= 0 THEN 
            RAISE EXCEPTION 'A package requires a positive agreed price.' USING ERRCODE='23514'; 
        END IF;

        FOREACH component IN ARRAY expected_ids LOOP 
            IF component = ANY(package_seen) OR NOT component = ANY(supplied_ids) THEN 
                RAISE EXCEPTION 'Package components are duplicated or missing.' USING ERRCODE='23514'; 
            END IF; 
            package_seen := array_append(package_seen, component); 
        END LOOP;

        SELECT COALESCE(sum((i->>'unit_price_paisa')::BIGINT), 0) INTO component_sum 
        FROM unnest(p_items_data) i 
        WHERE (i->>'test_id')::UUID = ANY(expected_ids); 
        
        IF component_sum <> agreed_price THEN 
            RAISE EXCEPTION 'Package component prices must equal the agreed package price.' USING ERRCODE='23514'; 
        END IF;
    END LOOP;

    PERFORM 1 FROM public.tests t WHERE t.id = ANY(supplied_ids) ORDER BY t.id FOR UPDATE;
    SELECT COALESCE(array_agg(id ORDER BY id), ARRAY[]::UUID[]) INTO manual_ids FROM public.tests WHERE id = ANY(supplied_ids) AND NOT allow_manual_price;
    UPDATE public.tests SET allow_manual_price = TRUE WHERE id = ANY(manual_ids);

    response := public.create_patient_bill_and_order(p_patient_data, p_bill_data, p_items_data, p_payment_data, p_idempotency_key); 
    bill_uuid := (response->>'bill_id')::UUID;

    UPDATE public.bill_items bi SET catalogue_price_paisa_snapshot = t.price_paisa FROM public.tests t WHERE bi.bill_id = bill_uuid AND bi.test_id = t.id;
    UPDATE public.tests SET allow_manual_price = FALSE WHERE id = ANY(manual_ids);

    FOR pkg IN SELECT value FROM jsonb_array_elements(COALESCE(p_packages, '[]')) LOOP
        INSERT INTO public.bill_package_selections(bill_id, package_id, package_code_snapshot, package_name_snapshot, package_price_paisa, catalogue_package_price_paisa)
        SELECT bill_uuid, p.id, p.code, p.name, (pkg->>'agreed_price_paisa')::BIGINT, p.price_paisa 
        FROM public.health_packages p 
        WHERE p.id = (pkg->>'package_id')::UUID
        ON CONFLICT(bill_id, package_id) DO NOTHING RETURNING id INTO selection_uuid;

        IF selection_uuid IS NOT NULL THEN 
            INSERT INTO public.bill_package_components(bill_package_selection_id, bill_item_id, test_id) 
            SELECT selection_uuid, bi.id, bi.test_id 
            FROM public.bill_items bi 
            WHERE bi.bill_id = bill_uuid AND bi.test_id = ANY(ARRAY(SELECT x::UUID FROM jsonb_array_elements_text(pkg->'component_ids') x)); 
        END IF;
    END LOOP;

    RETURN response || jsonb_build_object('packages_recorded', jsonb_array_length(COALESCE(p_packages, '[]')));
END;
$function$;

REVOKE ALL ON FUNCTION public.create_patient_bill_order_with_packages(JSONB, JSONB, JSONB[], JSONB, TEXT, JSONB) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_order_with_packages(JSONB, JSONB, JSONB[], JSONB, TEXT, JSONB) TO authenticated;

COMMIT;
