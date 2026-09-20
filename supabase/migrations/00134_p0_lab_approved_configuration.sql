-- ====================================================================
-- Migration 00134: Lab-Approved Configuration for 15 High-Priority (P0) Investigations
-- ====================================================================
-- Purpose:
-- Configure reportable leaf parameters, units, validated specimens,
-- analytical methods, and approved reference ranges / interpretation rules
-- for the 15 P0 tests without creating fake structural parent parameters,
-- without deactivating any test, and without inventing unapproved rates/mappings.
--
-- 15 Configured Tests:
-- 1.  BIO-0141: Cystatin C
-- 2.  IMM-0093: Interleukin-6 (IL-6)
-- 3.  SER-0089: Scrub Typhus (FIA IgM/IgG)
-- 4.  END-0056: Oral Glucose Tolerance Test (75 g)
-- 5.  END-0057: Gestational OGTT 75 g
-- 6.  END-0058: Glucose Challenge Test 50 g
-- 7.  END-0059: Overnight Dexamethasone Suppression
-- 8.  END-0060: Low Dose Dexamethasone Suppression Test
-- 9.  END-0061: High Dose Dexamethasone Suppression Test
-- 10. END-0062: ACTH Stimulation Test
-- 11. END-0063: Growth Hormone Suppression Test
-- 12. END-0064: Growth Hormone Stimulation Test
-- 13. END-0065: Water Deprivation Test
-- 14. POC-0002: Venous Blood Gas (VBG)
-- 15. SPC-0007: Organic Acids, Urine
-- ====================================================================

BEGIN;

-- --------------------------------------------------------------------
-- 1. UPDATE TEST METADATA (Specimens and Methods)
-- --------------------------------------------------------------------
UPDATE public.tests SET sample_type = 'Serum / Li-Heparin Plasma', method = 'Immunoturbidimetry / PETIA', updated_at = NOW() WHERE code = 'BIO-0141';
UPDATE public.tests SET sample_type = 'Serum / EDTA Plasma', method = 'FIA / CLIA / ELISA', updated_at = NOW() WHERE code = 'IMM-0093';
UPDATE public.tests SET sample_type = 'Serum / EDTA Whole Blood', method = 'Fluorescence Immunoassay (FIA)', updated_at = NOW() WHERE code = 'SER-0089';
UPDATE public.tests SET sample_type = 'Na-Fluoride Plasma', method = 'Hexokinase / GOD-POD (Protocol-based)', updated_at = NOW() WHERE code = 'END-0056';
UPDATE public.tests SET sample_type = 'Na-Fluoride Plasma', method = 'Hexokinase / GOD-POD (Protocol-based)', updated_at = NOW() WHERE code = 'END-0057';
UPDATE public.tests SET sample_type = 'Na-Fluoride Plasma', method = 'Hexokinase / GOD-POD (Protocol-based)', updated_at = NOW() WHERE code = 'END-0058';
UPDATE public.tests SET sample_type = 'Serum', method = 'Chemiluminescent Immunoassay (CLIA) / FIA', updated_at = NOW() WHERE code = 'END-0059';
UPDATE public.tests SET sample_type = 'Serum', method = 'Chemiluminescent Immunoassay (CLIA) / FIA', updated_at = NOW() WHERE code = 'END-0060';
UPDATE public.tests SET sample_type = 'Serum', method = 'Chemiluminescent Immunoassay (CLIA) / FIA', updated_at = NOW() WHERE code = 'END-0061';
UPDATE public.tests SET sample_type = 'Serum / Heparin Plasma', method = 'Chemiluminescent Immunoassay (CLIA) / FIA', updated_at = NOW() WHERE code = 'END-0062';
UPDATE public.tests SET sample_type = 'Serum', method = 'Chemiluminescent Immunoassay (CLIA) / FIA', updated_at = NOW() WHERE code = 'END-0063';
UPDATE public.tests SET sample_type = 'Serum', method = 'Chemiluminescent Immunoassay (CLIA) / FIA', updated_at = NOW() WHERE code = 'END-0064';
UPDATE public.tests SET sample_type = 'Serum + Urine (Timed)', method = 'Multi-discipline protocol', updated_at = NOW() WHERE code = 'END-0065';
UPDATE public.tests SET sample_type = 'Heparinized Whole Blood (Venous)', method = 'Blood gas analyzer', updated_at = NOW() WHERE code = 'POC-0002';
UPDATE public.tests SET sample_type = 'Random / First Morning Urine (Frozen)', method = 'GC-MS / LC-MS/MS', updated_at = NOW() WHERE code = 'SPC-0007';

-- --------------------------------------------------------------------
-- 2. INSERT / UPDATE REPORTABLE LEAF PARAMETERS & APPROVED REFERENCE RANGES
-- --------------------------------------------------------------------
DO $$
DECLARE
    v_test_id UUID;
    v_param_id UUID;
BEGIN
    -- ================================================================
    -- 1. BIO-0141: Cystatin C
    -- ================================================================
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0141';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'BIO-0141-01', 'Cystatin C', 'Numeric', 'mg/L', 1, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Cystatin C', value_type = 'Numeric', unit = 'mg/L', display_order = 1, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 6570, 43800, 0.61, 0.95, '0.61 - 0.95', 'mg/L', 'Immunoturbidimetry / PETIA', TRUE, TRUE);
    END IF;

    -- ================================================================
    -- 2. IMM-0093: Interleukin-6 (IL-6)
    -- ================================================================
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'IMM-0093';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'IMM-0093-01', 'Interleukin-6 (IL-6)', 'Numeric', 'pg/mL', 1, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Interleukin-6 (IL-6)', value_type = 'Numeric', unit = 'pg/mL', display_order = 1, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 7.0, '< 7.0', '<7.0 pg/mL = Normal / Non-inflammatory', 'pg/mL', 'FIA / CLIA / ELISA', TRUE, TRUE);
    END IF;

    -- ================================================================
    -- 3. SER-0089: Scrub Typhus (FIA IgM/IgG)
    -- ================================================================
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'SER-0089';
    IF v_test_id IS NOT NULL THEN
        -- Scrub Typhus IgM
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'SER-0089-01', 'Scrub Typhus IgM', 'Numeric', 'Index', 1, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Scrub Typhus IgM', value_type = 'Numeric', unit = 'Index', display_order = 1, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 1.0, '< 1.0 (Negative)', 'Index < 1.0: Negative; Index >= 1.0: Positive', 'Index', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE);

        -- Scrub Typhus IgG
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'SER-0089-02', 'Scrub Typhus IgG', 'Numeric', 'Index', 2, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Scrub Typhus IgG', value_type = 'Numeric', unit = 'Index', display_order = 2, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 1.0, '< 1.0 (Negative)', 'Index < 1.0: Negative; Index >= 1.0: Positive', 'Index', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE);
    END IF;

    -- ================================================================
    -- 4. END-0056: Oral Glucose Tolerance Test (75 g)
    -- ================================================================
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0056';
    IF v_test_id IS NOT NULL THEN
        -- Fasting Glucose
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0056-01', 'Fasting Glucose (0 min)', 'Numeric', 'mg/dL', 1, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Fasting Glucose (0 min)', value_type = 'Numeric', unit = 'mg/dL', display_order = 1, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 70.0, 99.0, '70 - 99', '70-99: Normal; 100-125: Impaired; >=126: DM', 'mg/dL', 'Hexokinase / GOD-POD', TRUE, TRUE);

        -- 1-Hour Glucose
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0056-02', '1-Hour Glucose (60 min)', 'Numeric', 'mg/dL', 2, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = '1-Hour Glucose (60 min)', value_type = 'Numeric', unit = 'mg/dL', display_order = 2, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, '—', 'mg/dL', 'Hexokinase / GOD-POD', TRUE, TRUE);

        -- 2-Hour Glucose
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0056-03', '2-Hour Glucose (120 min)', 'Numeric', 'mg/dL', 3, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = '2-Hour Glucose (120 min)', value_type = 'Numeric', unit = 'mg/dL', display_order = 3, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 140.0, '< 140', '<140: Normal; 140-199: IGT; >=200: DM', 'mg/dL', 'Hexokinase / GOD-POD', TRUE, TRUE);
    END IF;

    -- ================================================================
    -- 5. END-0057: Gestational OGTT 75 g
    -- ================================================================
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0057';
    IF v_test_id IS NOT NULL THEN
        -- Fasting Glucose
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0057-01', 'Fasting Glucose (0 min)', 'Numeric', 'mg/dL', 1, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Fasting Glucose (0 min)', value_type = 'Numeric', unit = 'mg/dL', display_order = 1, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'Female', 4380, 21900, 92.0, '< 92', 'Threshold <92 mg/dL. Any >=92 indicates GDM.', 'mg/dL', 'Hexokinase / GOD-POD', TRUE, TRUE);

        -- 1-Hour Glucose
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0057-02', '1-Hour Glucose (60 min)', 'Numeric', 'mg/dL', 2, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = '1-Hour Glucose (60 min)', value_type = 'Numeric', unit = 'mg/dL', display_order = 2, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'Female', 4380, 21900, 180.0, '< 180', 'Threshold <180 mg/dL. Any >=180 indicates GDM.', 'mg/dL', 'Hexokinase / GOD-POD', TRUE, TRUE);

        -- 2-Hour Glucose
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0057-03', '2-Hour Glucose (120 min)', 'Numeric', 'mg/dL', 3, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = '2-Hour Glucose (120 min)', value_type = 'Numeric', unit = 'mg/dL', display_order = 3, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'Female', 4380, 21900, 153.0, '< 153', 'Threshold <153 mg/dL. Any >=153 indicates GDM.', 'mg/dL', 'Hexokinase / GOD-POD', TRUE, TRUE);
    END IF;

    -- ================================================================
    -- 6. END-0058: Glucose Challenge Test 50 g
    -- ================================================================
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0058';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0058-01', '1-Hour Post-50g Glucose', 'Numeric', 'mg/dL', 1, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = '1-Hour Post-50g Glucose', value_type = 'Numeric', unit = 'mg/dL', display_order = 1, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 140.0, '< 140', '<140: Screening Negative; >=140: Positive Screen (confirmatory testing required)', 'mg/dL', 'Hexokinase / GOD-POD', TRUE, TRUE);
    END IF;

    -- ================================================================
    -- 7. END-0059: Overnight Dexamethasone Suppression
    -- ================================================================
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0059';
    IF v_test_id IS NOT NULL THEN
        -- Baseline Cortisol (optional)
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0059-01', 'Baseline Cortisol (8 AM)', 'Numeric', 'µg/dL', 1, TRUE, 'Active', FALSE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Baseline Cortisol (8 AM)', value_type = 'Numeric', unit = 'µg/dL', display_order = 1, is_active = TRUE, lifecycle_status = 'Active', is_mandatory = FALSE
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Baseline', 'µg/dL', 'Chemiluminescent Immunoassay (CLIA)', TRUE, TRUE);

        -- Post-1mg Dex Cortisol (mandatory reportable)
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0059-02', 'Post-1mg Dex Cortisol (8 AM)', 'Numeric', 'µg/dL', 2, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Post-1mg Dex Cortisol (8 AM)', value_type = 'Numeric', unit = 'µg/dL', display_order = 2, is_active = TRUE, lifecycle_status = 'Active', is_mandatory = TRUE
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 1.8, '< 1.8', '<1.8 µg/dL: Normal Suppression; >=1.8 µg/dL: Non-suppression (Cushing''s suspicion / clinical correlation required)', 'µg/dL', 'Chemiluminescent Immunoassay (CLIA)', TRUE, TRUE);
    END IF;

    -- ================================================================
    -- 8. END-0060: Low Dose Dexamethasone Suppression Test
    -- ================================================================
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0060';
    IF v_test_id IS NOT NULL THEN
        -- Baseline Cortisol
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0060-01', 'Baseline Cortisol (Day 0, 8 AM)', 'Numeric', 'µg/dL', 1, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Baseline Cortisol (Day 0, 8 AM)', value_type = 'Numeric', unit = 'µg/dL', display_order = 1, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Baseline', 'µg/dL', 'Chemiluminescent Immunoassay (CLIA)', TRUE, TRUE);

        -- Post-LDDST Cortisol
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0060-02', 'Post-LDDST Cortisol (Day 2, 8 AM)', 'Numeric', 'µg/dL', 2, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Post-LDDST Cortisol (Day 2, 8 AM)', value_type = 'Numeric', unit = 'µg/dL', display_order = 2, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 1.8, '< 1.8', '<1.8 µg/dL: Normal Response', 'µg/dL', 'Chemiluminescent Immunoassay (CLIA)', TRUE, TRUE);
    END IF;

    -- ================================================================
    -- 9. END-0061: High Dose Dexamethasone Suppression Test
    -- ================================================================
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0061';
    IF v_test_id IS NOT NULL THEN
        -- Baseline Cortisol
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0061-01', 'Baseline Cortisol (0 hr)', 'Numeric', 'µg/dL', 1, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Baseline Cortisol (0 hr)', value_type = 'Numeric', unit = 'µg/dL', display_order = 1, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Baseline', 'µg/dL', 'Chemiluminescent Immunoassay (CLIA)', TRUE, TRUE);

        -- Post-HDDST Cortisol
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0061-02', 'Post-HDDST Cortisol (8 AM)', 'Numeric', 'µg/dL', 2, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Post-HDDST Cortisol (8 AM)', value_type = 'Numeric', unit = 'µg/dL', display_order = 2, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Post-Suppression', 'µg/dL', 'Chemiluminescent Immunoassay (CLIA)', TRUE, TRUE);

        -- Suppression Percentage (Calculated)
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory, formula)
        VALUES (v_test_id, 'END-0061-03', 'Suppression Percentage', 'Calculated', '%', 3, TRUE, 'Active', TRUE, '((Baseline - Post) / Baseline) * 100')
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Suppression Percentage', value_type = 'Calculated', unit = '%', display_order = 3, is_active = TRUE, lifecycle_status = 'Active', formula = '((Baseline - Post) / Baseline) * 100'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, '> 50 %', '>50% suppression: Pituitary pattern / Cushing disease pattern; <50% suppression: No significant suppression / ectopic-adrenal pattern', '%', 'Governed Calculation', TRUE, TRUE);
    END IF;

    -- ================================================================
    -- 10. END-0062: ACTH Stimulation Test
    -- ================================================================
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0062';
    IF v_test_id IS NOT NULL THEN
        -- Cortisol Baseline
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0062-01', 'Cortisol Baseline (0 min)', 'Numeric', 'µg/dL', 1, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Cortisol Baseline (0 min)', value_type = 'Numeric', unit = 'µg/dL', display_order = 1, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Baseline', 'µg/dL', 'Chemiluminescent Immunoassay (CLIA)', TRUE, TRUE);

        -- Cortisol 30 min Post-ACTH
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0062-02', 'Cortisol 30 min Post-ACTH', 'Numeric', 'µg/dL', 2, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Cortisol 30 min Post-ACTH', value_type = 'Numeric', unit = 'µg/dL', display_order = 2, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 18.0, '>= 18.0', 'Peak Cortisol >= 18.0 µg/dL = Normal adrenal reserve', 'µg/dL', 'Chemiluminescent Immunoassay (CLIA)', TRUE, TRUE);

        -- Cortisol 60 min Post-ACTH
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0062-03', 'Cortisol 60 min Post-ACTH', 'Numeric', 'µg/dL', 3, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Cortisol 60 min Post-ACTH', value_type = 'Numeric', unit = 'µg/dL', display_order = 3, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 18.0, '>= 18.0', 'Peak Cortisol >= 18.0 µg/dL = Normal adrenal reserve', 'µg/dL', 'Chemiluminescent Immunoassay (CLIA)', TRUE, TRUE);
    END IF;

    -- ================================================================
    -- 11. END-0063: Growth Hormone Suppression Test
    -- ================================================================
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0063';
    IF v_test_id IS NOT NULL THEN
        -- GH Baseline
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0063-01', 'GH Baseline (0 min)', 'Numeric', 'ng/mL', 1, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'GH Baseline (0 min)', value_type = 'Numeric', unit = 'ng/mL', display_order = 1, is_active = TRUE, lifecycle_status = 'Active';

        -- GH 30 min
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0063-02', 'GH 30 min', 'Numeric', 'ng/mL', 2, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'GH 30 min', value_type = 'Numeric', unit = 'ng/mL', display_order = 2, is_active = TRUE, lifecycle_status = 'Active';

        -- GH 60 min
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0063-03', 'GH 60 min', 'Numeric', 'ng/mL', 3, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'GH 60 min', value_type = 'Numeric', unit = 'ng/mL', display_order = 3, is_active = TRUE, lifecycle_status = 'Active';

        -- GH 90 min
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0063-04', 'GH 90 min', 'Numeric', 'ng/mL', 4, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'GH 90 min', value_type = 'Numeric', unit = 'ng/mL', display_order = 4, is_active = TRUE, lifecycle_status = 'Active';

        -- GH 120 min
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0063-05', 'GH 120 min', 'Numeric', 'ng/mL', 5, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'GH 120 min', value_type = 'Numeric', unit = 'ng/mL', display_order = 5, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id IN (SELECT id FROM public.parameters WHERE test_id = v_test_id);
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        SELECT id, 'All', 0, 43800, 1.0, '< 1.0', 'Standard method: Normal nadir suppression <1.0 ng/mL; Ultra-sensitive method: <0.4 ng/mL', 'ng/mL', 'Chemiluminescent Immunoassay (CLIA)', TRUE, TRUE
        FROM public.parameters WHERE test_id = v_test_id;
    END IF;

    -- ================================================================
    -- 12. END-0064: Growth Hormone Stimulation Test
    -- ================================================================
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0064';
    IF v_test_id IS NOT NULL THEN
        -- Stimulating Agent
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0064-01', 'Stimulating Agent', 'Text', '', 1, TRUE, 'Active', FALSE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Stimulating Agent', value_type = 'Text', unit = '', display_order = 1, is_active = TRUE, lifecycle_status = 'Active';

        -- GH Baseline
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0064-02', 'GH Baseline (0 min)', 'Numeric', 'ng/mL', 2, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'GH Baseline (0 min)', value_type = 'Numeric', unit = 'ng/mL', display_order = 2, is_active = TRUE, lifecycle_status = 'Active';

        -- GH 30 min
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0064-03', 'GH 30 min', 'Numeric', 'ng/mL', 3, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'GH 30 min', value_type = 'Numeric', unit = 'ng/mL', display_order = 3, is_active = TRUE, lifecycle_status = 'Active';

        -- GH 60 min
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0064-04', 'GH 60 min', 'Numeric', 'ng/mL', 4, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'GH 60 min', value_type = 'Numeric', unit = 'ng/mL', display_order = 4, is_active = TRUE, lifecycle_status = 'Active';

        -- GH 90 min
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0064-05', 'GH 90 min', 'Numeric', 'ng/mL', 5, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'GH 90 min', value_type = 'Numeric', unit = 'ng/mL', display_order = 5, is_active = TRUE, lifecycle_status = 'Active';

        -- GH 120 min
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0064-06', 'GH 120 min', 'Numeric', 'ng/mL', 6, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'GH 120 min', value_type = 'Numeric', unit = 'ng/mL', display_order = 6, is_active = TRUE, lifecycle_status = 'Active';

        DELETE FROM public.reference_ranges WHERE parameter_id IN (SELECT id FROM public.parameters WHERE test_id = v_test_id AND value_type = 'Numeric');
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, reference_text, unit, method, is_approved, is_active)
        SELECT id, 'All', 0, 43800, 'Peak > 5 - 10 ng/mL', 'Normal Peak: >5-10 ng/mL; GH Deficiency pattern: Peak <5.0 ng/mL', 'ng/mL', 'Chemiluminescent Immunoassay (CLIA)', TRUE, TRUE
        FROM public.parameters WHERE test_id = v_test_id AND value_type = 'Numeric';
    END IF;

    -- ================================================================
    -- 13. END-0065: Water Deprivation Test
    -- ================================================================
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0065';
    IF v_test_id IS NOT NULL THEN
        -- Hourly Body Weight
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0065-01', 'Hourly Body Weight', 'Numeric', 'kg', 1, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Hourly Body Weight', value_type = 'Numeric', unit = 'kg', display_order = 1, is_active = TRUE, lifecycle_status = 'Active';

        -- Plasma Osmolality
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0065-02', 'Plasma Osmolality', 'Numeric', 'mOsm/kg', 2, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Plasma Osmolality', value_type = 'Numeric', unit = 'mOsm/kg', display_order = 2, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 275.0, 295.0, '275 - 295', 'mOsm/kg', 'Freezing Point Osmometry', TRUE, TRUE);

        -- Urine Osmolality
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0065-03', 'Urine Osmolality', 'Numeric', 'mOsm/kg', 3, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Urine Osmolality', value_type = 'Numeric', unit = 'mOsm/kg', display_order = 3, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, '> 600 - 800', 'Normal: Urine Osmolality >600-800 mOsm/kg after dehydration', 'mOsm/kg', 'Freezing Point Osmometry', TRUE, TRUE);

        -- Serum Sodium
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0065-04', 'Serum Sodium', 'Numeric', 'mmol/L', 4, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Serum Sodium', value_type = 'Numeric', unit = 'mmol/L', display_order = 4, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 135.0, 145.0, '135 - 145', 'mmol/L', 'ISE / Ion Selective Electrode', TRUE, TRUE);

        -- Post-Desmopressin Urine Osmolality
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'END-0065-05', 'Post-Desmopressin Urine Osmolality', 'Numeric', 'mOsm/kg', 5, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Post-Desmopressin Urine Osmolality', value_type = 'Numeric', unit = 'mOsm/kg', display_order = 5, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Post-DDAVP', 'Central DI: >50% increase in urine osmolality; Nephrogenic DI: <9% increase', 'mOsm/kg', 'Freezing Point Osmometry', TRUE, TRUE);
    END IF;

    -- ================================================================
    -- 14. POC-0002: Venous Blood Gas (VBG)
    -- ================================================================
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'POC-0002';
    IF v_test_id IS NOT NULL THEN
        -- 1. pH (Venous)
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'POC-0002-01', 'pH (Venous)', 'Numeric', '', 1, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'pH (Venous)', value_type = 'Numeric', unit = '', display_order = 1, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 7.31, 7.41, '7.31 - 7.41', 'Blood gas analyzer', TRUE, TRUE);

        -- 2. pvCO2
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'POC-0002-02', 'pvCO2', 'Numeric', 'mmHg', 2, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'pvCO2', value_type = 'Numeric', unit = 'mmHg', display_order = 2, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 40.0, 52.0, '40 - 52', 'mmHg', 'Blood gas analyzer', TRUE, TRUE);

        -- 3. pvO2
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'POC-0002-03', 'pvO2', 'Numeric', 'mmHg', 3, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'pvO2', value_type = 'Numeric', unit = 'mmHg', display_order = 3, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 30.0, 50.0, '30 - 50', 'mmHg', 'Blood gas analyzer', TRUE, TRUE);

        -- 4. HCO3- / Bicarbonate
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'POC-0002-04', 'HCO3- / Bicarbonate', 'Numeric', 'mmol/L', 4, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'HCO3- / Bicarbonate', value_type = 'Numeric', unit = 'mmol/L', display_order = 4, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 22.0, 28.0, '22 - 28', 'mmol/L', 'Blood gas analyzer', TRUE, TRUE);

        -- 5. Base Excess
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'POC-0002-05', 'Base Excess', 'Numeric', 'mmol/L', 5, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Base Excess', value_type = 'Numeric', unit = 'mmol/L', display_order = 5, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, -2.0, 2.0, '-2 to +2', 'mmol/L', 'Blood gas analyzer', TRUE, TRUE);

        -- 6. Venous O2 Saturation
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'POC-0002-06', 'Venous O2 Saturation', 'Numeric', '%', 6, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Venous O2 Saturation', value_type = 'Numeric', unit = '%', display_order = 6, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 60.0, 85.0, '60 - 85', '%', 'Blood gas analyzer', TRUE, TRUE);

        -- 7. Lactate
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'POC-0002-07', 'Lactate', 'Numeric', 'mmol/L', 7, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Lactate', value_type = 'Numeric', unit = 'mmol/L', display_order = 7, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.5, 2.2, '0.5 - 2.2', 'mmol/L', 'Blood gas analyzer', TRUE, TRUE);
    END IF;

    -- ================================================================
    -- 15. SPC-0007: Organic Acids, Urine
    -- ================================================================
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'SPC-0007';
    IF v_test_id IS NOT NULL THEN
        -- 1. Metabolic Profile Result
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'SPC-0007-01', 'Metabolic Profile Result', 'Text', '', 1, TRUE, 'Active', TRUE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Metabolic Profile Result', value_type = 'Text', unit = '', display_order = 1, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Normal Organic Acid Excretion', 'GC-MS / LC-MS/MS', TRUE, TRUE);

        -- 2. Key Excreted Acids
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'SPC-0007-02', 'Key Excreted Acids', 'Text', '', 2, TRUE, 'Active', FALSE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Key Excreted Acids', value_type = 'Text', unit = '', display_order = 2, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'No abnormal metabolites detected', 'GC-MS / LC-MS/MS', TRUE, TRUE);

        -- 3. Clinical Interpretation
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status, is_mandatory)
        VALUES (v_test_id, 'SPC-0007-03', 'Clinical Interpretation', 'Text', '', 3, TRUE, 'Active', FALSE)
        ON CONFLICT (test_id, code) DO UPDATE 
        SET name = 'Clinical Interpretation', value_type = 'Text', unit = '', display_order = 3, is_active = TRUE, lifecycle_status = 'Active'
        RETURNING id INTO v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Normal metabolic excretion pattern', 'GC-MS / LC-MS/MS', TRUE, TRUE);
    END IF;

END $$;

COMMIT;
