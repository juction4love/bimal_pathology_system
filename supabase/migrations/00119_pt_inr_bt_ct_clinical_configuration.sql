-- Migration 00119: PT/INR, BT, and CT Clinical Configuration & Patient Rates
-- 
-- Objectives:
-- 1. PT/INR (COA-0001):
--    - Update canonical identity: Name = 'Prothrombin Time / INR', short_name = 'PT/INR', method = 'Manual Tilt Tube Method'.
--    - Specimen: Citrated Plasma; Container: Sodium Citrate Tube (Blue); Processing: Manual.
--    - Primary parameter: 'Prothrombin Time' (sec, Numeric, Ref: 11.0 – 13.5 sec).
--    - Secondary calculated parameter: 'International Normalized Ratio' (INR, Calculated, Formula: (PT / MNPT) ^ ISI, Ref: 0.8 – 1.2).
--    - Standard patient rate: NPR 500 (50,000 paisa).
-- 2. Bleeding Time (COA-0007):
--    - Canonical identity: Name = 'Bleeding Time', short_name = 'BT', method = 'Duke''s Method'.
--    - Specimen: Capillary Blood; Container: Disposable Blood Lancet / Filter Paper; Processing: Manual.
--    - Primary parameter: 'Bleeding Time' (min, Numeric, Ref: 2 – 7 min for Duke''s Method).
-- 3. Clotting Time (COA-0008):
--    - Canonical identity: Name = 'Clotting Time', short_name = 'CT', method = 'Capillary Tube Method'.
--    - Specimen: Whole Blood; Container: Non-heparinized Glass Capillary Tube; Processing: Manual.
--    - Primary parameter: 'Clotting Time' (min, Numeric, Ref: 3 – 8 min for Capillary Tube Method).
-- 4. BT & CT Combined Patient Service (PRO-0030):
--    - Canonical panel shell: Name = 'Bleeding Time & Clotting Time', short_name = 'BT & CT', price_paisa = 20000 (NPR 200).
--    - Panel components: COA-0007 (BT) & COA-0008 (CT).
--    - Rate: NPR 200 for combined service.
-- 5. Reagent-Specific PT/INR Configuration Table & Governance RPCs:
--    - Table: public.pt_inr_reagent_configs (reagent_name, manufacturer, lot_number, expiry_date, isi, mnpt, effective_from, effective_to, is_active, notes).
--    - RPCs: get_active_pt_inr_config(), save_pt_inr_reagent_config().
--    - Admin-only mutation governance, Lab Technician read-only operational visibility.
-- 6. Rate Versioning:
--    - Update catalogue_rate_versions for COA-0001 (NPR 500) and PRO-0030 (NPR 200).
-- 7. Search Aliases:
--    - Comprehensive English and Nepali search aliases for fast billing & catalogue search.

BEGIN;

-- ============================================================================
-- 1. PT/INR REAGENT CONFIGURATION TABLE & GOVERNANCE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.pt_inr_reagent_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reagent_name TEXT NOT NULL,
    manufacturer TEXT,
    lot_number TEXT,
    expiry_date DATE,
    isi NUMERIC NOT NULL CHECK (isi > 0),
    mnpt NUMERIC NOT NULL CHECK (mnpt > 0),
    effective_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    effective_to TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    notes TEXT,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for active lookup
CREATE INDEX IF NOT EXISTS idx_pt_inr_reagent_configs_active 
ON public.pt_inr_reagent_configs (is_active, effective_from DESC) 
WHERE is_active = TRUE;

-- Enable RLS
ALTER TABLE public.pt_inr_reagent_configs ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "pt_inr_configs_select_policy" ON public.pt_inr_reagent_configs;
DROP POLICY IF EXISTS "pt_inr_configs_insert_admin_only" ON public.pt_inr_reagent_configs;
DROP POLICY IF EXISTS "pt_inr_configs_update_admin_only" ON public.pt_inr_reagent_configs;
DROP POLICY IF EXISTS "pt_inr_configs_delete_admin_only" ON public.pt_inr_reagent_configs;

-- Authenticated users (Admin and Technician) can read reagent configs for clinical operations
CREATE POLICY "pt_inr_configs_select_policy"
ON public.pt_inr_reagent_configs
FOR SELECT
TO authenticated
USING (TRUE);

-- Admin only can insert new reagent configs
CREATE POLICY "pt_inr_configs_insert_admin_only"
ON public.pt_inr_reagent_configs
FOR INSERT
TO authenticated
WITH CHECK (
    public.has_permission('can_manage_catalogue') OR public.is_super_admin()
);

-- Admin only can update reagent configs
CREATE POLICY "pt_inr_configs_update_admin_only"
ON public.pt_inr_reagent_configs
FOR UPDATE
TO authenticated
USING (
    public.has_permission('can_manage_catalogue') OR public.is_super_admin()
)
WITH CHECK (
    public.has_permission('can_manage_catalogue') OR public.is_super_admin()
);

-- Admin only can delete reagent configs
CREATE POLICY "pt_inr_configs_delete_admin_only"
ON public.pt_inr_reagent_configs
FOR DELETE
TO authenticated
USING (
    public.has_permission('can_manage_catalogue') OR public.is_super_admin()
);

-- RPC: Get active PT/INR configuration
CREATE OR REPLACE FUNCTION public.get_active_pt_inr_config()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_config jsonb;
BEGIN
    SELECT row_to_json(c.*)::jsonb INTO v_config
    FROM public.pt_inr_reagent_configs c
    WHERE c.is_active = TRUE
      AND (c.effective_to IS NULL OR c.effective_to > NOW())
    ORDER BY c.effective_from DESC, c.created_at DESC
    LIMIT 1;

    RETURN v_config;
END;
$$;

-- RPC: Save PT/INR configuration (Admin Only)
CREATE OR REPLACE FUNCTION public.save_pt_inr_reagent_config(
    p_reagent_name TEXT,
    p_isi NUMERIC,
    p_mnpt NUMERIC,
    p_manufacturer TEXT DEFAULT NULL,
    p_lot_number TEXT DEFAULT NULL,
    p_expiry_date DATE DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_new_id UUID;
    v_result jsonb;
BEGIN
    -- RBAC check: Admin only
    IF auth.uid() IS NULL OR NOT (public.has_permission('can_manage_catalogue') OR public.is_super_admin()) THEN
        RAISE EXCEPTION 'Access denied: Only administrators can configure PT/INR reagent parameters (MNPT & ISI)' USING ERRCODE = '42501';
    END IF;

    -- Validation
    IF p_reagent_name IS NULL OR TRIM(p_reagent_name) = '' THEN
        RAISE EXCEPTION 'Reagent name is required';
    END IF;
    IF p_isi IS NULL OR p_isi <= 0 THEN
        RAISE EXCEPTION 'ISI must be a positive number greater than 0';
    END IF;
    IF p_mnpt IS NULL OR p_mnpt <= 0 THEN
        RAISE EXCEPTION 'MNPT must be a positive number in seconds greater than 0';
    END IF;

    -- Deactivate all currently active configs (preserve history)
    UPDATE public.pt_inr_reagent_configs
    SET is_active = FALSE,
        effective_to = NOW(),
        updated_at = NOW()
    WHERE is_active = TRUE;

    -- Insert new active config
    INSERT INTO public.pt_inr_reagent_configs (
        reagent_name,
        manufacturer,
        lot_number,
        expiry_date,
        isi,
        mnpt,
        effective_from,
        is_active,
        notes,
        created_by
    ) VALUES (
        TRIM(p_reagent_name),
        NULLIF(TRIM(p_manufacturer), ''),
        NULLIF(TRIM(p_lot_number), ''),
        p_expiry_date,
        p_isi,
        p_mnpt,
        NOW(),
        TRUE,
        NULLIF(TRIM(p_notes), ''),
        auth.uid()
    )
    RETURNING id INTO v_new_id;

    -- Audit logging
    INSERT INTO public.audit_logs (user_id, user_name, action, entity_type, entity_id, new_data)
    VALUES (
        auth.uid(),
        'Administrator',
        'PT_INR_REAGENT_CONFIG_UPDATED',
        'ReagentConfig',
        v_new_id::text,
        jsonb_build_object(
            'reagent_name', p_reagent_name,
            'isi', p_isi,
            'mnpt', p_mnpt,
            'lot_number', p_lot_number,
            'manufacturer', p_manufacturer,
            'expiry_date', p_expiry_date
        )
    );

    SELECT row_to_json(c.*)::jsonb INTO v_result
    FROM public.pt_inr_reagent_configs c
    WHERE c.id = v_new_id;

    RETURN v_result;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.get_active_pt_inr_config() TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_pt_inr_reagent_config(TEXT, NUMERIC, NUMERIC, TEXT, TEXT, DATE, TEXT) TO authenticated;

-- ============================================================================
-- 2. UPDATE CANONICAL TEST IDENTITIES
-- ============================================================================

-- A. PT/INR (COA-0001)
UPDATE public.tests
SET 
    name = 'Prothrombin Time / INR',
    short_name = 'PT/INR',
    department = 'Coagulation',
    category = COALESCE(category, 'Coagulation'),
    specimen_type = 'Citrated Plasma',
    sample_type = 'Citrated Plasma',
    container = 'Sodium Citrate Tube (Blue)',
    container_type = 'Sodium Citrate Tube (Blue)',
    method = 'Manual Tilt Tube Method',
    reporting_type = 'InHouse',
    price_paisa = 50000,
    price_configured = TRUE,
    is_active = TRUE,
    billing_enabled = TRUE,
    clinical_reporting_enabled = TRUE,
    validation_status = 'VALIDATED',
    clinical_configuration_status = 'Configured',
    notes = 'Operational setup: Water Bath 37°C, Glass Test Tube, Commercial PT Reagent, Stopwatch. Normal INR: 0.8–1.2. Therapeutic targets: Warfarin 2.0–3.0, Mech Heart Valve 2.5–3.5.',
    search_aliases = ARRAY['PT', 'PT INR', 'PT/INR', 'Prothrombin Time', 'Prothrombin Time / INR', 'Prothrombin Test', 'COA-0001', 'प्रोध्रोम्बिन टाइम'],
    updated_at = NOW()
WHERE id = '2f8b4df3-40e4-4141-b003-9a124fdc75a8' OR code = 'COA-0001';

-- B. Bleeding Time (COA-0007)
UPDATE public.tests
SET 
    name = 'Bleeding Time',
    short_name = 'BT',
    department = 'Coagulation',
    category = COALESCE(category, 'Coagulation'),
    specimen_type = 'Capillary Blood',
    sample_type = 'Capillary Blood',
    container = 'Disposable Blood Lancet / Filter Paper',
    container_type = 'Disposable Blood Lancet / Filter Paper',
    method = 'Duke''s Method',
    reporting_type = 'InHouse',
    price_paisa = 0,
    price_configured = FALSE,
    is_active = TRUE,
    billing_enabled = TRUE,
    clinical_reporting_enabled = TRUE,
    validation_status = 'VALIDATED',
    clinical_configuration_status = 'Configured',
    notes = 'Duke''s Method: Prick on finger or earlobe, touch blood to filter paper every 30 seconds. Reference interval: 2–7 minutes.',
    search_aliases = ARRAY['BT', 'Bleeding Time', 'Bleeding Time (BT)', 'COA-0007', 'ब्लिडिङ टाइम'],
    updated_at = NOW()
WHERE id = '3531fc7b-db20-4f22-85c2-4a2076763113' OR code = 'COA-0007';

-- C. Clotting Time (COA-0008)
UPDATE public.tests
SET 
    name = 'Clotting Time',
    short_name = 'CT',
    department = 'Coagulation',
    category = COALESCE(category, 'Coagulation'),
    specimen_type = 'Capillary Blood / Whole Blood',
    sample_type = 'Capillary Blood / Whole Blood',
    container = 'Non-heparinized Glass Capillary Tube',
    container_type = 'Non-heparinized Glass Capillary Tube',
    method = 'Capillary Tube Method',
    reporting_type = 'InHouse',
    price_paisa = 0,
    price_configured = FALSE,
    is_active = TRUE,
    billing_enabled = TRUE,
    clinical_reporting_enabled = TRUE,
    validation_status = 'VALIDATED',
    clinical_configuration_status = 'Configured',
    notes = 'Capillary Tube Method: Fill non-heparinized capillary tube, break every 30 seconds until fibrin thread observed. Reference interval: 3–8 minutes.',
    search_aliases = ARRAY['CT', 'Clotting Time', 'Coagulation Time', 'Clotting Time (CT)', 'COA-0008', 'क्लटिङ टाइम'],
    updated_at = NOW()
WHERE id = '1e03e664-18f1-4893-b651-0f25642e83c1' OR code = 'COA-0008';

-- ============================================================================
-- 3. BT & CT COMBINED SERVICE (PRO-0030)
-- ============================================================================

INSERT INTO public.tests (
    code,
    name,
    short_name,
    department,
    subdepartment,
    category,
    category_id,
    test_type,
    specimen_type,
    sample_type,
    container,
    container_type,
    method,
    unit,
    tat_description,
    report_data_type,
    fasting_required,
    is_outsource,
    is_active,
    billing_enabled,
    clinical_reporting_enabled,
    validation_status,
    configuration_status,
    clinical_configuration_status,
    lifecycle_status,
    notes,
    search_aliases,
    price_paisa,
    price_configured,
    allow_zero_price_billing,
    display_order
) VALUES (
    'PRO-0030',
    'Bleeding Time & Clotting Time',
    'BT & CT',
    'Profiles / Packages',
    'Coagulation Profiles',
    'Profiles & Health Packages',
    (SELECT id FROM public.test_categories WHERE name = 'Profiles & Health Packages' LIMIT 1),
    'Panel',
    'Capillary Blood / Whole Blood',
    'Capillary Blood / Whole Blood',
    'Lancet, Filter Paper, Capillary Tube',
    'Lancet, Filter Paper, Capillary Tube',
    'Duke''s Method (BT) & Capillary Tube Method (CT)',
    'Panel',
    'Routine / 30 mins',
    'Panel',
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    FALSE,
    'VALIDATED',
    'CONFIGURED',
    'Configured',
    'Active',
    'Components: Bleeding Time (COA-0007); Clotting Time (COA-0008). Standard combined rate: NPR 200.',
    ARRAY['BT & CT', 'BT CT', 'BT/CT', 'Bleeding Time Clotting Time', 'Bleeding Time & Clotting Time', 'BT and CT', 'PRO-0030', 'ब्लिडिङ एण्ड क्लटिङ टाइम'],
    20000,
    TRUE,
    FALSE,
    30
) ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    short_name = EXCLUDED.short_name,
    department = EXCLUDED.department,
    price_paisa = EXCLUDED.price_paisa,
    price_configured = TRUE,
    is_active = TRUE,
    billing_enabled = TRUE,
    search_aliases = EXCLUDED.search_aliases,
    notes = EXCLUDED.notes,
    updated_at = NOW();

-- Link Panel Components for PRO-0030
DO $$
DECLARE
    v_panel_id UUID;
    v_bt_id UUID;
    v_ct_id UUID;
BEGIN
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0030';
    SELECT id INTO v_bt_id FROM public.tests WHERE code = 'COA-0007';
    SELECT id INTO v_ct_id FROM public.tests WHERE code = 'COA-0008';

    IF v_panel_id IS NOT NULL AND v_bt_id IS NOT NULL AND v_ct_id IS NOT NULL THEN
        -- Delete any previous components for idempotency
        DELETE FROM public.catalogue_panel_components WHERE panel_id = v_panel_id;

        INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required)
        VALUES
            (v_panel_id, v_panel_id, v_bt_id, 1, TRUE),
            (v_panel_id, v_panel_id, v_ct_id, 2, TRUE)
        ON CONFLICT (panel_id, component_test_id) DO UPDATE SET
            display_order = EXCLUDED.display_order,
            is_required = EXCLUDED.is_required;
    END IF;
END $$;

-- ============================================================================
-- 4. PARAMETERS RECONCILIATION
-- ============================================================================

-- A. PT Primary Parameter (sec)
UPDATE public.parameters
SET 
    name = 'Prothrombin Time',
    unit = 'sec',
    value_type = 'Numeric',
    is_active = TRUE,
    is_mandatory = TRUE,
    lifecycle_status = 'Active',
    display_order = 1,
    formula = NULL,
    updated_at = NOW()
WHERE test_id = '2f8b4df3-40e4-4141-b003-9a124fdc75a8' AND (code = 'COA-0001' OR name ILIKE '%Prothrombin%');

-- B. INR Calculated Parameter for COA-0001
DO $$
DECLARE
    v_pt_test_id UUID := '2f8b4df3-40e4-4141-b003-9a124fdc75a8';
    v_inr_param_id UUID;
BEGIN
    SELECT id INTO v_inr_param_id
    FROM public.parameters
    WHERE test_id = v_pt_test_id AND (code = 'INR' OR name = 'International Normalized Ratio');

    IF v_inr_param_id IS NULL THEN
        INSERT INTO public.parameters (
            test_id,
            code,
            name,
            unit,
            value_type,
            formula,
            display_order,
            is_mandatory,
            is_active,
            lifecycle_status
        ) VALUES (
            v_pt_test_id,
            'INR',
            'International Normalized Ratio',
            '',
            'Calculated',
            '(PT / MNPT) ^ ISI',
            2,
            TRUE,
            TRUE,
            'Active'
        );
    ELSE
        UPDATE public.parameters
        SET 
            name = 'International Normalized Ratio',
            unit = '',
            value_type = 'Calculated',
            formula = '(PT / MNPT) ^ ISI',
            display_order = 2,
            is_mandatory = TRUE,
            is_active = TRUE,
            lifecycle_status = 'Active',
            updated_at = NOW()
        WHERE id = v_inr_param_id;
    END IF;
END $$;

-- C. BT Primary Parameter (min)
UPDATE public.parameters
SET 
    name = 'Bleeding Time',
    unit = 'min',
    value_type = 'Numeric',
    is_active = TRUE,
    is_mandatory = TRUE,
    lifecycle_status = 'Active',
    display_order = 1,
    formula = NULL,
    updated_at = NOW()
WHERE test_id = '3531fc7b-db20-4f22-85c2-4a2076763113' AND (code = 'COA-0007' OR name ILIKE '%Bleeding%');

-- D. CT Primary Parameter (min)
UPDATE public.parameters
SET 
    name = 'Clotting Time',
    unit = 'min',
    value_type = 'Numeric',
    is_active = TRUE,
    is_mandatory = TRUE,
    lifecycle_status = 'Active',
    display_order = 1,
    formula = NULL,
    updated_at = NOW()
WHERE test_id = '1e03e664-18f1-4893-b651-0f25642e83c1' AND (code = 'COA-0008' OR name ILIKE '%Clotting%');

-- ============================================================================
-- 5. LAB-APPROVED REFERENCE RANGES
-- ============================================================================

-- Clean up placeholder or legacy ranges on these parameters
DELETE FROM public.reference_ranges
WHERE parameter_id IN (
    SELECT id FROM public.parameters 
    WHERE test_id IN (
        '2f8b4df3-40e4-4141-b003-9a124fdc75a8',
        '3531fc7b-db20-4f22-85c2-4a2076763113',
        '1e03e664-18f1-4893-b651-0f25642e83c1'
    )
);

-- Insert Lab-Approved Reference Ranges
DO $$
DECLARE
    v_pt_param_id UUID;
    v_inr_param_id UUID;
    v_bt_param_id UUID;
    v_ct_param_id UUID;
BEGIN
    -- 1. PT Reference Range: 11.0 – 13.5 seconds (Manual Tilt Tube Method)
    SELECT id INTO v_pt_param_id FROM public.parameters 
    WHERE test_id = '2f8b4df3-40e4-4141-b003-9a124fdc75a8' AND (code = 'COA-0001' OR name = 'Prothrombin Time')
    LIMIT 1;

    IF v_pt_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id,
            gender,
            age_min_days,
            age_max_days,
            normal_min,
            normal_max,
            critical_low,
            critical_high,
            unit,
            method,
            reference_text,
            is_active,
            is_approved,
            validation_state,
            lifecycle_status
        ) VALUES (
            v_pt_param_id,
            'All',
            0,
            43800,
            11.0,
            13.5,
            NULL,
            NULL,
            'sec',
            'Manual Tilt Tube Method',
            '11.0 - 13.5 sec',
            TRUE,
            TRUE,
            'ClinicallyValidated',
            'Active'
        );
    END IF;

    -- 2. INR Reference Range: 0.8 – 1.2 (Normal)
    SELECT id INTO v_inr_param_id FROM public.parameters 
    WHERE test_id = '2f8b4df3-40e4-4141-b003-9a124fdc75a8' AND (code = 'INR' OR name = 'International Normalized Ratio')
    LIMIT 1;

    IF v_inr_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id,
            gender,
            age_min_days,
            age_max_days,
            normal_min,
            normal_max,
            critical_low,
            critical_high,
            unit,
            method,
            reference_text,
            is_active,
            is_approved,
            validation_state,
            lifecycle_status
        ) VALUES (
            v_inr_param_id,
            'All',
            0,
            43800,
            0.8,
            1.2,
            NULL,
            NULL,
            '',
            'Calculated ((Patient PT / MNPT) ^ ISI)',
            'Normal: 0.8 - 1.2',
            TRUE,
            TRUE,
            'ClinicallyValidated',
            'Active'
        );
    END IF;

    -- 3. BT Reference Range: 2 – 7 minutes (Duke's Method)
    SELECT id INTO v_bt_param_id FROM public.parameters 
    WHERE test_id = '3531fc7b-db20-4f22-85c2-4a2076763113' AND (code = 'COA-0007' OR name = 'Bleeding Time')
    LIMIT 1;

    IF v_bt_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id,
            gender,
            age_min_days,
            age_max_days,
            normal_min,
            normal_max,
            critical_low,
            critical_high,
            unit,
            method,
            reference_text,
            is_active,
            is_approved,
            validation_state,
            lifecycle_status
        ) VALUES (
            v_bt_param_id,
            'All',
            0,
            43800,
            2.0,
            7.0,
            NULL,
            NULL,
            'min',
            'Duke''s Method',
            '2 - 7 min',
            TRUE,
            TRUE,
            'ClinicallyValidated',
            'Active'
        );
    END IF;

    -- 4. CT Reference Range: 3 – 8 minutes (Capillary Tube Method)
    SELECT id INTO v_ct_param_id FROM public.parameters 
    WHERE test_id = '1e03e664-18f1-4893-b651-0f25642e83c1' AND (code = 'COA-0008' OR name = 'Clotting Time')
    LIMIT 1;

    IF v_ct_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id,
            gender,
            age_min_days,
            age_max_days,
            normal_min,
            normal_max,
            critical_low,
            critical_high,
            unit,
            method,
            reference_text,
            is_active,
            is_approved,
            validation_state,
            lifecycle_status
        ) VALUES (
            v_ct_param_id,
            'All',
            0,
            43800,
            3.0,
            8.0,
            NULL,
            NULL,
            'min',
            'Capillary Tube Method',
            '3 - 8 min',
            TRUE,
            TRUE,
            'ClinicallyValidated',
            'Active'
        );
    END IF;
END $$;

-- ============================================================================
-- 6. RATE VERSIONING IN public.catalogue_rate_versions
-- ============================================================================

DO $$
DECLARE
    v_pt_id UUID := '2f8b4df3-40e4-4141-b003-9a124fdc75a8';
    v_panel_id UUID;
    v_next_version INT;
BEGIN
    -- Rate version for PT/INR (NPR 500 = 50,000 paisa)
    UPDATE public.catalogue_rate_versions
    SET status = 'Inactive', effective_to = NOW(), updated_at = NOW()
    WHERE test_id = v_pt_id AND status = 'Active';

    SELECT COALESCE(MAX(version_number), 0) + 1 INTO v_next_version
    FROM public.catalogue_rate_versions
    WHERE test_id = v_pt_id;

    INSERT INTO public.catalogue_rate_versions (
        entity_type,
        test_id,
        version_number,
        price_paisa,
        effective_from,
        status
    ) VALUES (
        'Test',
        v_pt_id,
        v_next_version,
        50000,
        NOW(),
        'Active'
    );

    -- Rate version for BT & CT combo (PRO-0030: NPR 200 = 20,000 paisa)
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0030';
    IF v_panel_id IS NOT NULL THEN
        UPDATE public.catalogue_rate_versions
        SET status = 'Inactive', effective_to = NOW(), updated_at = NOW()
        WHERE test_id = v_panel_id AND status = 'Active';

        SELECT COALESCE(MAX(version_number), 0) + 1 INTO v_next_version
        FROM public.catalogue_rate_versions
        WHERE test_id = v_panel_id;

        INSERT INTO public.catalogue_rate_versions (
            entity_type,
            test_id,
            version_number,
            price_paisa,
            effective_from,
            status
        ) VALUES (
            'Test',
            v_panel_id,
            v_next_version,
            20000,
            NOW(),
            'Active'
        );
    END IF;
END $$;

-- ============================================================================
-- 7. SEARCH ALIASES SEEDING
-- ============================================================================

-- Clean up and re-seed aliases for clean lookup
DELETE FROM public.test_aliases
WHERE test_id IN (
    '2f8b4df3-40e4-4141-b003-9a124fdc75a8',
    '3531fc7b-db20-4f22-85c2-4a2076763113',
    '1e03e664-18f1-4893-b651-0f25642e83c1',
    (SELECT id FROM public.tests WHERE code = 'PRO-0030')
);

-- PT/INR Aliases
INSERT INTO public.test_aliases (test_id, alias_name, alias_type, is_primary)
VALUES
    ('2f8b4df3-40e4-4141-b003-9a124fdc75a8', 'PT/INR', 'Acronym', TRUE),
    ('2f8b4df3-40e4-4141-b003-9a124fdc75a8', 'PT', 'Acronym', FALSE),
    ('2f8b4df3-40e4-4141-b003-9a124fdc75a8', 'PT INR', 'Synonym', FALSE),
    ('2f8b4df3-40e4-4141-b003-9a124fdc75a8', 'Prothrombin Time', 'Synonym', FALSE),
    ('2f8b4df3-40e4-4141-b003-9a124fdc75a8', 'Prothrombin Time / INR', 'Synonym', FALSE),
    ('2f8b4df3-40e4-4141-b003-9a124fdc75a8', 'COA-0001', 'LegacyCode', FALSE),
    ('2f8b4df3-40e4-4141-b003-9a124fdc75a8', 'प्रोध्रोम्बिन टाइम', 'AlternativeName', FALSE);

-- BT Aliases
INSERT INTO public.test_aliases (test_id, alias_name, alias_type, is_primary)
VALUES
    ('3531fc7b-db20-4f22-85c2-4a2076763113', 'BT', 'Acronym', TRUE),
    ('3531fc7b-db20-4f22-85c2-4a2076763113', 'Bleeding Time', 'Synonym', FALSE),
    ('3531fc7b-db20-4f22-85c2-4a2076763113', 'COA-0007', 'LegacyCode', FALSE),
    ('3531fc7b-db20-4f22-85c2-4a2076763113', 'ब्लिडिङ टाइम', 'AlternativeName', FALSE);

-- CT Aliases
INSERT INTO public.test_aliases (test_id, alias_name, alias_type, is_primary)
VALUES
    ('1e03e664-18f1-4893-b651-0f25642e83c1', 'CT', 'Acronym', TRUE),
    ('1e03e664-18f1-4893-b651-0f25642e83c1', 'Clotting Time', 'Synonym', FALSE),
    ('1e03e664-18f1-4893-b651-0f25642e83c1', 'Coagulation Time', 'AlternativeName', FALSE),
    ('1e03e664-18f1-4893-b651-0f25642e83c1', 'COA-0008', 'LegacyCode', FALSE),
    ('1e03e664-18f1-4893-b651-0f25642e83c1', 'क्लटिङ टाइम', 'AlternativeName', FALSE);

-- BT & CT Combo Aliases
DO $$
DECLARE
    v_panel_id UUID;
BEGIN
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0030';
    IF v_panel_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type, is_primary)
        VALUES
            (v_panel_id, 'BT & CT', 'Acronym', TRUE),
            (v_panel_id, 'BT CT', 'Synonym', FALSE),
            (v_panel_id, 'BT/CT', 'Synonym', FALSE),
            (v_panel_id, 'BT and CT', 'Synonym', FALSE),
            (v_panel_id, 'Bleeding Time & Clotting Time', 'Synonym', FALSE),
            (v_panel_id, 'Bleeding Time Clotting Time', 'Synonym', FALSE),
            (v_panel_id, 'PRO-0030', 'LegacyCode', FALSE),
            (v_panel_id, 'ब्लिडिङ एण्ड क्लटिङ टाइम', 'AlternativeName', FALSE);
    END IF;
END $$;

-- Audit Logging
INSERT INTO public.audit_logs (user_id, user_name, action, entity_type, entity_id, new_data)
VALUES (
    auth.uid(),
    'Migration 00119',
    'PT_INR_BT_CT_CLINICAL_AND_RATES_CONFIGURED',
    'Catalogue',
    'COA-0001,COA-0007,COA-0008,PRO-0030',
    jsonb_build_object(
        'pt_inr_rate_paisa', 50000,
        'bt_ct_combo_rate_paisa', 20000,
        'pt_ref_range', '11.0 - 13.5 sec',
        'inr_ref_range', '0.8 - 1.2',
        'bt_ref_range', '2 - 7 min',
        'ct_ref_range', '3 - 8 min',
        'reagent_config_table', 'public.pt_inr_reagent_configs'
    )
);

COMMIT;
