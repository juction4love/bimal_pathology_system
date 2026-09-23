-- ====================================================================
-- Migration 00130: Final Simple 21-Test Approved Routine Pathology Catalogue
-- ====================================================================
-- Reduces the operational LIS billing catalogue to EXACTLY 21 user-facing
-- clinically-ready selectable investigations:
--  1. CBC (HEM-0001)
--  2. Hemoglobin (HEM-0002)
--  3. ESR (HEM-0027)
--  4. Liver Function Test - LFT (PRO-0001)
--  5. Renal Function Test - KFT/RFT (PRO-0002)
--  6. Glucose, Fasting - FBS (BIO-0001)
--  7. Glucose, Postprandial - PPBS (BIO-0003)
--  8. HbA1c (BIO-0006)
--  9. Lipid Profile (PRO-0003)
-- 10. Troponin I, High Sensitivity (BIO-0063)
-- 11. TSH (END-0001)
-- 12. Free T3 - FT3 (END-0003)
-- 13. Free T4 - FT4 (END-0002)
-- 14. Vitamin D, 25-OH (BIO-0053)
-- 15. Vitamin B12 (BIO-0051)
-- 16. Urine Routine Examination - RE/ME (CLP-0001)
-- 17. Dengue NS1 Antigen (SER-0015)
-- 18. Dengue IgM (SER-0016)
-- 19. Widal Test (SER-0024) [4 Antigens: S. Typhi O/H, S. Paratyphi AH/BH]
-- 20. HBsAg (SER-0004)
-- 21. Anti-HCV (SER-0010)
--
-- Safety & Clinical Governance:
-- 1. billing_enabled = TRUE ONLY on the 21 top-level investigations.
-- 2. SER-0024 configured with Tube Agglutination and 4 discrete titer parameters.
-- 3. Internal child tests for LFT/KFT/Lipid/Urine have billing_enabled = FALSE.
-- 4. KFT panel cleaned: contains only Urea, BUN, Creatinine, Uric Acid.
-- 5. Lipid panel cleaned: contains only Total Cholesterol, Triglycerides, HDL, LDL, VLDL.
-- 6. Urine Routine cleaned: contains only 14 approved routine fields.
-- 7. Duplicate serology rapid tests (SER-0087, SER-0088) deactivated.
-- 8. ZERO hard-deletions of tests; all non-approved tests deactivated.
-- ====================================================================

DO $$
DECLARE
    v_widal_test_id UUID;
    v_widal_opt_set_id UUID;
    v_param_to UUID;
    v_param_th UUID;
    v_param_ah UUID;
    v_param_bh UUID;

    -- Exactly 21 user-facing clinically-ready billing investigations
    v_billing_codes TEXT[] := ARRAY[
        'HEM-0001', -- 1. Complete Blood Count (CBC)
        'HEM-0002', -- 2. Hemoglobin (Hb)
        'HEM-0027', -- 3. ESR (Westergren)
        'PRO-0001', -- 4. Liver Function Test (LFT)
        'PRO-0002', -- 5. Renal Function Test (RFT/KFT)
        'BIO-0001', -- 6. Glucose, Fasting (FBS)
        'BIO-0003', -- 7. Glucose, Postprandial 2 hr (PPBS)
        'BIO-0006', -- 8. HbA1c
        'PRO-0003', -- 9. Lipid Profile
        'BIO-0063', -- 10. Troponin I, High Sensitivity
        'END-0001', -- 11. TSH
        'END-0003', -- 12. Free T3 (FT3)
        'END-0002', -- 13. Free T4 (FT4)
        'BIO-0053', -- 14. Vitamin D, 25-OH
        'BIO-0051', -- 15. Vitamin B12
        'CLP-0001', -- 16. Urine Routine Examination (RE/ME)
        'SER-0015', -- 17. Dengue NS1 Antigen
        'SER-0016', -- 18. Dengue IgM
        'SER-0024', -- 19. Widal Test
        'SER-0004', -- 20. HBsAg
        'SER-0010'  -- 21. Anti-HCV
    ];

    -- Internal active child component tests required for panel execution / reporting
    v_internal_workflow_codes TEXT[] := ARRAY[
        -- LFT child tests (10 core + GGT)
        'BIO-0017', -- Total Bilirubin
        'BIO-0018', -- Direct Bilirubin
        'BIO-0019', -- Indirect Bilirubin (Calculated)
        'BIO-0020', -- AST (SGOT)
        'BIO-0021', -- ALT (SGPT)
        'BIO-0022', -- Alkaline Phosphatase (ALP)
        'BIO-0013', -- Total Protein
        'BIO-0014', -- Albumin
        'BIO-0015', -- Globulin (Calculated)
        'BIO-0016', -- A/G Ratio (Calculated)
        'BIO-0023', -- GGT

        -- KFT child tests (Urea, BUN, Creatinine, Uric Acid)
        'BIO-0008', -- Urea
        'BIO-0009', -- Blood Urea Nitrogen (BUN)
        'BIO-0010', -- Creatinine
        'BIO-0012', -- Uric Acid

        -- Lipid child tests (Total Chol, Trig, HDL, LDL, VLDL)
        'BIO-0027', -- Total Cholesterol
        'BIO-0028', -- Triglycerides
        'BIO-0029', -- HDL Cholesterol
        'BIO-0031', -- LDL Cholesterol, Calculated
        'BIO-0032', -- VLDL Cholesterol

        -- Urine child tests (14 approved routine fields)
        'CLP-0002', -- Urine Color
        'CLP-0003', -- Urine Appearance / Transparency
        'CLP-0004', -- Urine Specific Gravity
        'CLP-0005', -- Urine pH
        'CLP-0006', -- Urine Protein, Dipstick
        'CLP-0007', -- Urine Glucose, Dipstick (Sugar)
        'CLP-0008', -- Urine Ketone
        'CLP-0009', -- Urine Blood/Hemoglobin
        'CLP-0010', -- Urine Bilirubin
        'CLP-0014', -- Urine RBC Microscopy
        'CLP-0015', -- Urine WBC/Pus Cells
        'CLP-0016', -- Urine Epithelial Cells
        'CLP-0017', -- Urine Casts
        'CLP-0018'  -- Urine Crystals
    ];
BEGIN
    -- 1. Deactivate all non-approved tests for new operations
    UPDATE public.tests
    SET 
        is_active = FALSE,
        billing_enabled = FALSE,
        clinical_reporting_enabled = FALSE,
        updated_at = now()
    WHERE code != ALL(v_billing_codes || v_internal_workflow_codes);

    -- 2. Deactivate parameters belonging to inactive tests
    UPDATE public.parameters
    SET 
        is_active = FALSE,
        updated_at = now()
    WHERE test_id IN (
        SELECT id FROM public.tests WHERE is_active = FALSE
    );

    -- 3. Set EXACTLY the 21 top-level investigations as billing-enabled
    UPDATE public.tests
    SET 
        is_active = TRUE,
        billing_enabled = TRUE,
        clinical_reporting_enabled = TRUE,
        updated_at = now()
    WHERE code = ANY(v_billing_codes);

    -- 4. Set internal workflow child tests as active for execution but hidden from billing
    UPDATE public.tests
    SET 
        is_active = TRUE,
        billing_enabled = FALSE,
        clinical_reporting_enabled = TRUE,
        updated_at = now()
    WHERE code = ANY(v_internal_workflow_codes);

    -- 5. Ensure parameters of active tests are active
    UPDATE public.parameters
    SET 
        is_active = TRUE,
        updated_at = now()
    WHERE test_id IN (
        SELECT id FROM public.tests WHERE is_active = TRUE
    );

    -- 6. Clean KFT Profile components (Remove Sodium, Potassium, Chloride, eGFR)
    DELETE FROM public.catalogue_panel_components
    WHERE panel_id = (SELECT id FROM public.tests WHERE code = 'PRO-0002')
      AND component_test_id IN (
          SELECT id FROM public.tests WHERE code IN ('BIO-0037', 'BIO-0038', 'BIO-0039', 'BIO-0011')
      );

    -- 7. Clean Lipid Profile components (Remove Non-HDL)
    DELETE FROM public.catalogue_panel_components
    WHERE panel_id = (SELECT id FROM public.tests WHERE code = 'PRO-0003')
      AND component_test_id IN (
          SELECT id FROM public.tests WHERE code IN ('BIO-0033')
      );

    -- 8. Clean Urine Routine components (Remove Urobilinogen, Nitrite, Leukocyte Esterase, Bacteria)
    DELETE FROM public.catalogue_panel_components
    WHERE panel_id = (SELECT id FROM public.tests WHERE code = 'CLP-0001')
      AND component_test_id IN (
          SELECT id FROM public.tests WHERE code IN ('CLP-0011', 'CLP-0012', 'CLP-0013', 'CLP-0019')
      );

    -- 9. Structure and configure SER-0024 Widal Test with 4 distinct antigen parameters
    SELECT id INTO v_widal_test_id FROM public.tests WHERE code = 'SER-0024';
    
    IF v_widal_test_id IS NOT NULL THEN
        -- Update Test Metadata
        UPDATE public.tests
        SET 
            name = 'Widal Test',
            sample_type = 'Serum',
            specimen_type = 'Serum',
            method = 'Tube Agglutination',
            unit = 'Titer',
            reporting_model = 'Qualitative',
            is_active = TRUE,
            billing_enabled = TRUE,
            clinical_reporting_enabled = TRUE,
            updated_at = now()
        WHERE id = v_widal_test_id;

        -- Ensure Option Set for Widal Dilutions exists
        SELECT id INTO v_widal_opt_set_id FROM public.catalogue_option_sets WHERE code = 'WIDAL_TITER_OPTIONS' OR name = 'Widal Titer Options' OR name = 'Widal Slide Titer' LIMIT 1;
        IF v_widal_opt_set_id IS NULL THEN
            INSERT INTO public.catalogue_option_sets (id, code, name, lifecycle_status)
            VALUES (gen_random_uuid(), 'WIDAL_TITER_OPTIONS', 'Widal Titer Options', 'Active')
            RETURNING id INTO v_widal_opt_set_id;
        END IF;

        -- Ensure standard dilution option values exist
        DELETE FROM public.catalogue_option_values WHERE option_set_id = v_widal_opt_set_id;
        INSERT INTO public.catalogue_option_values (option_set_id, value_code, label, display_order, is_active)
        VALUES
            (v_widal_opt_set_id, 'TITER_LT_1_20', '< 1:20', 1, TRUE),
            (v_widal_opt_set_id, 'TITER_1_20', '1:20', 2, TRUE),
            (v_widal_opt_set_id, 'TITER_1_40', '1:40', 3, TRUE),
            (v_widal_opt_set_id, 'TITER_1_80', '1:80', 4, TRUE),
            (v_widal_opt_set_id, 'TITER_1_160', '1:160', 5, TRUE),
            (v_widal_opt_set_id, 'TITER_1_320', '1:320', 6, TRUE);

        -- Deactivate old single generic Widal parameter if exists
        UPDATE public.parameters
        SET is_active = FALSE, updated_at = now()
        WHERE test_id = v_widal_test_id AND code = 'SER-0024';

        -- 9a. Parameter 1: Salmonella Typhi 'O'
        SELECT id INTO v_param_to FROM public.parameters WHERE test_id = v_widal_test_id AND code = 'WIDAL_TO';
        IF v_param_to IS NULL THEN
            INSERT INTO public.parameters (id, test_id, code, name, value_type, unit, option_set_id, display_order, is_active, is_mandatory, clinical_class, calculation_reporting_mode)
            VALUES (gen_random_uuid(), v_widal_test_id, 'WIDAL_TO', 'Salmonella Typhi ''O''', 'Select', 'Titer', v_widal_opt_set_id, 1, TRUE, TRUE, 'Measured', 'Measured')
            RETURNING id INTO v_param_to;
        ELSE
            UPDATE public.parameters
            SET name = 'Salmonella Typhi ''O''', value_type = 'Select', unit = 'Titer', option_set_id = v_widal_opt_set_id, display_order = 1, is_active = TRUE, updated_at = now()
            WHERE id = v_param_to;
        END IF;

        -- 9b. Parameter 2: Salmonella Typhi 'H'
        SELECT id INTO v_param_th FROM public.parameters WHERE test_id = v_widal_test_id AND code = 'WIDAL_TH';
        IF v_param_th IS NULL THEN
            INSERT INTO public.parameters (id, test_id, code, name, value_type, unit, option_set_id, display_order, is_active, is_mandatory, clinical_class, calculation_reporting_mode)
            VALUES (gen_random_uuid(), v_widal_test_id, 'WIDAL_TH', 'Salmonella Typhi ''H''', 'Select', 'Titer', v_widal_opt_set_id, 2, TRUE, TRUE, 'Measured', 'Measured')
            RETURNING id INTO v_param_th;
        ELSE
            UPDATE public.parameters
            SET name = 'Salmonella Typhi ''H''', value_type = 'Select', unit = 'Titer', option_set_id = v_widal_opt_set_id, display_order = 2, is_active = TRUE, updated_at = now()
            WHERE id = v_param_th;
        END IF;

        -- 9c. Parameter 3: Salmonella Paratyphi 'AH'
        SELECT id INTO v_param_ah FROM public.parameters WHERE test_id = v_widal_test_id AND code = 'WIDAL_AH';
        IF v_param_ah IS NULL THEN
            INSERT INTO public.parameters (id, test_id, code, name, value_type, unit, option_set_id, display_order, is_active, is_mandatory, clinical_class, calculation_reporting_mode)
            VALUES (gen_random_uuid(), v_widal_test_id, 'WIDAL_AH', 'Salmonella Paratyphi ''AH''', 'Select', 'Titer', v_widal_opt_set_id, 3, TRUE, TRUE, 'Measured', 'Measured')
            RETURNING id INTO v_param_ah;
        ELSE
            UPDATE public.parameters
            SET name = 'Salmonella Paratyphi ''AH''', value_type = 'Select', unit = 'Titer', option_set_id = v_widal_opt_set_id, display_order = 3, is_active = TRUE, updated_at = now()
            WHERE id = v_param_ah;
        END IF;

        -- 9d. Parameter 4: Salmonella Paratyphi 'BH'
        SELECT id INTO v_param_bh FROM public.parameters WHERE test_id = v_widal_test_id AND code = 'WIDAL_BH';
        IF v_param_bh IS NULL THEN
            INSERT INTO public.parameters (id, test_id, code, name, value_type, unit, option_set_id, display_order, is_active, is_mandatory, clinical_class, calculation_reporting_mode)
            VALUES (gen_random_uuid(), v_widal_test_id, 'WIDAL_BH', 'Salmonella Paratyphi ''BH''', 'Select', 'Titer', v_widal_opt_set_id, 4, TRUE, TRUE, 'Measured', 'Measured')
            RETURNING id INTO v_param_bh;
        ELSE
            UPDATE public.parameters
            SET name = 'Salmonella Paratyphi ''BH''', value_type = 'Select', unit = 'Titer', option_set_id = v_widal_opt_set_id, display_order = 4, is_active = TRUE, updated_at = now()
            WHERE id = v_param_bh;
        END IF;

        -- Reference ranges / Diagnostic cut-offs for the 4 parameters
        DELETE FROM public.reference_ranges WHERE parameter_id IN (v_param_to, v_param_th, v_param_ah, v_param_bh);
        
        -- S. Typhi O Cutoff (>= 1:160)
        INSERT INTO public.reference_ranges (parameter_id, gender, normal_text, reference_text, is_active, is_approved)
        VALUES (v_param_to, 'All', '>= 1:160', 'Diagnostic Cut-off: >= 1:160', TRUE, TRUE);

        -- S. Typhi H Cutoff (>= 1:160)
        INSERT INTO public.reference_ranges (parameter_id, gender, normal_text, reference_text, is_active, is_approved)
        VALUES (v_param_th, 'All', '>= 1:160', 'Diagnostic Cut-off: >= 1:160', TRUE, TRUE);

        -- S. Paratyphi AH Cutoff (>= 1:80)
        INSERT INTO public.reference_ranges (parameter_id, gender, normal_text, reference_text, is_active, is_approved)
        VALUES (v_param_ah, 'All', '>= 1:80', 'Diagnostic Cut-off: >= 1:80', TRUE, TRUE);

        -- S. Paratyphi BH Cutoff (>= 1:80)
        INSERT INTO public.reference_ranges (parameter_id, gender, normal_text, reference_text, is_active, is_approved)
        VALUES (v_param_bh, 'All', '>= 1:80', 'Diagnostic Cut-off: >= 1:80', TRUE, TRUE);
    END IF;

    RAISE NOTICE 'Migration 00130: Final Simple 21-Test Approved Catalogue with 4-Antigen Widal configured successfully.';
END $$;
