-- Migration: 00124_cbc_reporting_parameters.sql
-- Goal: Configure complete approved 24-parameter reporting set for Complete Blood Count (CBC / HEM-0001) from CounCell 23 Excel.
--
-- Authoritative CounCell 23 Excel Specification:
--  1. HEM-0001 remains ONE single billable/orderable test in the catalogue and billing system.
--  2. Result Entry and Diagnostic Reports render the complete 24 CounCell 23 Excel parameter set under HEM-0001 in authoritative clinical order.
--  3. Units:
--     - WBC, Lym#, Mid#, Gran#, PLT, P-LCC: 10^9/L
--     - RBC: 10^12/L
--     - HGB, MCHC: g/dL
--     - HCT, Lym%, Mid%, Gran%, RDW-CV, PDW-CV, PCT, P-LCR: %
--     - MCV, RDW-SD, MPV, PDW-SD: fL
--     - MCH: pg
--     - NLR, PLR: Ratio
--  4. Preserves approved reference ranges (HGB: Female 12-15 g/dL, Male 13-17 g/dL; WBC: 4.0-11.0 10^9/L; PLT: 150-450 10^9/L). Missing ranges remain unconfigured without blocking entry.
--  5. Updates CounCell 23 Excel analyzer parameter mappings to link each channel to the canonical CBC parameter.
--  6. Manual microscopy 5-part differential (HEM-0015..HEM-0022) remains strictly isolated and optional.
--  7. Does NOT derive or fabricate automated ANC in the 3-part CBC parameter set.
--  8. Fully idempotent, safe to re-execute without creating duplicate parameters or altering historical reports.

BEGIN;

DO $$
DECLARE
    v_cbc_id UUID;
    v_analyzer_id UUID;
    v_dummy_param_id UUID;
    v_wbc_param_id UUID;
    v_lym_abs_param_id UUID;
    v_mid_abs_param_id UUID;
    v_gran_abs_param_id UUID;
    v_lym_pct_param_id UUID;
    v_mid_pct_param_id UUID;
    v_gran_pct_param_id UUID;
    v_nlr_param_id UUID;
    v_plr_param_id UUID;
    v_rbc_param_id UUID;
    v_hgb_param_id UUID;
    v_hct_param_id UUID;
    v_mcv_param_id UUID;
    v_mch_param_id UUID;
    v_mchc_param_id UUID;
    v_rdw_cv_param_id UUID;
    v_rdw_sd_param_id UUID;
    v_plt_param_id UUID;
    v_mpv_param_id UUID;
    v_pdw_cv_param_id UUID;
    v_pdw_sd_param_id UUID;
    v_pct_param_id UUID;
    v_p_lcc_param_id UUID;
    v_p_lcr_param_id UUID;
BEGIN
    SELECT id INTO v_cbc_id FROM public.tests WHERE code = 'HEM-0001';
    IF v_cbc_id IS NULL THEN
        RAISE EXCEPTION 'Test HEM-0001 (Complete Blood Count) not found.' USING ERRCODE = 'P0002';
    END IF;

    SELECT id INTO v_analyzer_id FROM public.analyzers WHERE code = 'COUNCELL_23_EXCEL';

    -- 1. Remove or deactivate legacy placeholder dummy parameter ('HEM-0001' / 'Panel') if no test_results reference it
    SELECT id INTO v_dummy_param_id 
    FROM public.parameters 
    WHERE test_id = v_cbc_id AND code = 'HEM-0001' AND (unit = 'Panel' OR name = 'Complete Blood Count (CBC)');

    IF v_dummy_param_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM public.test_results WHERE parameter_id = v_dummy_param_id) THEN
            DELETE FROM public.reference_ranges WHERE parameter_id = v_dummy_param_id;
            DELETE FROM public.parameters WHERE id = v_dummy_param_id;
        ELSE
            UPDATE public.parameters 
            SET is_active = FALSE, lifecycle_status = 'Archived', updated_at = NOW() 
            WHERE id = v_dummy_param_id;
        END IF;
    END IF;

    -- 2. Upsert the 24 Canonical CounCell 23 Excel CBC Parameters in Authoritative Display Order
    -- ------------------------------------------------------------------------
    -- 1. WBC - White Blood Cell Count (TLC)
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'WBC', 'White Blood Cell Count (TLC)', 'Numeric', '10^9/L', 1, TRUE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_mandatory = EXCLUDED.is_mandatory,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_wbc_param_id;

    -- 2. Lym# - Absolute Lymphocyte Count
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'LYM_ABS', 'Absolute Lymphocyte Count', 'Numeric', '10^9/L', 2, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_lym_abs_param_id;

    -- 3. Mid# - Absolute Mid-cell (Monocytes/Eosinophils) Count
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'MID_ABS', 'Absolute Mid-cell (Monocytes/Eosinophils) Count', 'Numeric', '10^9/L', 3, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_mid_abs_param_id;

    -- 4. Gran# - Absolute Granulocyte (Neutrophil) Count
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'GRAN_ABS', 'Absolute Granulocyte (Neutrophil) Count', 'Numeric', '10^9/L', 4, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_gran_abs_param_id;

    -- 5. Lym% - Lymphocyte Percentage
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'LYM_PERCENT', 'Lymphocyte Percentage', 'Numeric', '%', 5, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_lym_pct_param_id;

    -- 6. Mid% - Mid-cell Percentage
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'MID_PERCENT', 'Mid-cell Percentage', 'Numeric', '%', 6, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_mid_pct_param_id;

    -- 7. Gran% - Granulocyte Percentage
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'GRAN_PERCENT', 'Granulocyte Percentage', 'Numeric', '%', 7, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_gran_pct_param_id;

    -- 8. NLR - Neutrophil-to-Lymphocyte Ratio
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'NLR', 'Neutrophil-to-Lymphocyte Ratio', 'Numeric', 'Ratio', 8, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_nlr_param_id;

    -- 9. PLR - Platelet-to-Lymphocyte Ratio
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'PLR', 'Platelet-to-Lymphocyte Ratio', 'Numeric', 'Ratio', 9, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_plr_param_id;

    -- 10. RBC - Red Blood Cell Count
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'RBC', 'Red Blood Cell Count', 'Numeric', '10^12/L', 10, TRUE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_mandatory = EXCLUDED.is_mandatory,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_rbc_param_id;

    -- 11. HGB - Hemoglobin Concentration
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'HGB', 'Hemoglobin Concentration', 'Numeric', 'g/dL', 11, TRUE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_mandatory = EXCLUDED.is_mandatory,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_hgb_param_id;

    -- 12. HCT - Hematocrit (Packed Cell Volume - PCV)
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'HCT', 'Hematocrit (Packed Cell Volume - PCV)', 'Numeric', '%', 12, TRUE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_mandatory = EXCLUDED.is_mandatory,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_hct_param_id;

    -- 13. MCV - Mean Corpuscular Volume
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'MCV', 'Mean Corpuscular Volume', 'Numeric', 'fL', 13, TRUE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_mandatory = EXCLUDED.is_mandatory,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_mcv_param_id;

    -- 14. MCH - Mean Corpuscular Hemoglobin
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'MCH', 'Mean Corpuscular Hemoglobin', 'Numeric', 'pg', 14, TRUE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_mandatory = EXCLUDED.is_mandatory,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_mch_param_id;

    -- 15. MCHC - Mean Corpuscular Hemoglobin Concentration
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'MCHC', 'Mean Corpuscular Hemoglobin Concentration', 'Numeric', 'g/dL', 15, TRUE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_mandatory = EXCLUDED.is_mandatory,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_mchc_param_id;

    -- 16. RDW-CV - Red Cell Distribution Width - Coeff. of Variation
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'RDW_CV', 'Red Cell Distribution Width - Coeff. of Variation', 'Numeric', '%', 16, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_rdw_cv_param_id;

    -- 17. RDW-SD - Red Cell Distribution Width - Standard Deviation
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'RDW_SD', 'Red Cell Distribution Width - Standard Deviation', 'Numeric', 'fL', 17, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_rdw_sd_param_id;

    -- 18. PLT - Platelet Count
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'PLT', 'Platelet Count', 'Numeric', '10^9/L', 18, TRUE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_mandatory = EXCLUDED.is_mandatory,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_plt_param_id;

    -- 19. MPV - Mean Platelet Volume
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'MPV', 'Mean Platelet Volume', 'Numeric', 'fL', 19, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_mpv_param_id;

    -- 20. PDW-CV - Platelet Distribution Width - CV
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'PDW_CV', 'Platelet Distribution Width - CV', 'Numeric', '%', 20, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_pdw_cv_param_id;

    -- 21. PDW-SD - Platelet Distribution Width - SD
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'PDW_SD', 'Platelet Distribution Width - SD', 'Numeric', 'fL', 21, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_pdw_sd_param_id;

    -- 22. PCT - Plateletcrit
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'PCT', 'Plateletcrit', 'Numeric', '%', 22, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_pct_param_id;

    -- 23. P-LCC - Platelet Large Cell Count
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'P_LCC', 'Platelet Large Cell Count', 'Numeric', '10^9/L', 23, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_p_lcc_param_id;

    -- 24. P-LCR - Platelet Large Cell Ratio
    INSERT INTO public.parameters (
        test_id, code, name, value_type, unit, display_order, is_mandatory, is_active, lifecycle_status
    ) VALUES (
        v_cbc_id, 'P_LCR', 'Platelet Large Cell Ratio', 'Numeric', '%', 24, FALSE, TRUE, 'Active'
    )
    ON CONFLICT (test_id, code) DO UPDATE SET
        name = EXCLUDED.name,
        value_type = EXCLUDED.value_type,
        unit = EXCLUDED.unit,
        display_order = EXCLUDED.display_order,
        is_active = TRUE,
        lifecycle_status = 'Active',
        updated_at = NOW()
    RETURNING id INTO v_p_lcr_param_id;

    -- 3. Configure Authoritative Approved Reference Ranges for HEM-0001
    -- HGB Approved Reference Ranges
    IF v_hgb_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_hgb_param_id;
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_hgb_param_id, 'Female', 0, 43800, 12.0, 15.0, '12.0 - 15.0 g/dL', 'g/dL', 'Cyanide-free Colorimetry', TRUE, TRUE),
        (v_hgb_param_id, 'Male', 0, 43800, 13.0, 17.0, '13.0 - 17.0 g/dL', 'g/dL', 'Cyanide-free Colorimetry', TRUE, TRUE);
    END IF;

    -- WBC Approved Reference Range
    IF v_wbc_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_wbc_param_id;
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_wbc_param_id, 'All', 0, 43800, 4.0, 11.0, '4.0 - 11.0 10^9/L', '10^9/L', 'Electrical Impedance', TRUE, TRUE);
    END IF;

    -- PLT Approved Reference Range
    IF v_plt_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_plt_param_id;
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_plt_param_id, 'All', 0, 43800, 150.0, 450.0, '150 - 450 10^9/L', '10^9/L', 'Electrical Impedance', TRUE, TRUE);
    END IF;

    -- 4. Update CounCell 23 Excel Analyzer Parameter Mappings to link directly to CBC parameters
    IF v_analyzer_id IS NOT NULL THEN
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_wbc_param_id, unit = '10^9/L' WHERE analyzer_id = v_analyzer_id AND channel_code = 'WBC';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_lym_abs_param_id, unit = '10^9/L' WHERE analyzer_id = v_analyzer_id AND channel_code = 'LYM_ABS';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_mid_abs_param_id, unit = '10^9/L' WHERE analyzer_id = v_analyzer_id AND channel_code = 'MID_ABS';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_gran_abs_param_id, unit = '10^9/L' WHERE analyzer_id = v_analyzer_id AND channel_code = 'GRAN_ABS';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_lym_pct_param_id, unit = '%' WHERE analyzer_id = v_analyzer_id AND channel_code = 'LYM_PERCENT';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_mid_pct_param_id, unit = '%' WHERE analyzer_id = v_analyzer_id AND channel_code = 'MID_PERCENT';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_gran_pct_param_id, unit = '%' WHERE analyzer_id = v_analyzer_id AND channel_code = 'GRAN_PERCENT';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_nlr_param_id, unit = 'Ratio' WHERE analyzer_id = v_analyzer_id AND channel_code = 'NLR';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_plr_param_id, unit = 'Ratio' WHERE analyzer_id = v_analyzer_id AND channel_code = 'PLR';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_rbc_param_id, unit = '10^12/L' WHERE analyzer_id = v_analyzer_id AND channel_code = 'RBC';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_hgb_param_id, unit = 'g/dL' WHERE analyzer_id = v_analyzer_id AND channel_code = 'HGB';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_hct_param_id, unit = '%' WHERE analyzer_id = v_analyzer_id AND channel_code = 'HCT';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_mcv_param_id, unit = 'fL' WHERE analyzer_id = v_analyzer_id AND channel_code = 'MCV';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_mch_param_id, unit = 'pg' WHERE analyzer_id = v_analyzer_id AND channel_code = 'MCH';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_mchc_param_id, unit = 'g/dL' WHERE analyzer_id = v_analyzer_id AND channel_code = 'MCHC';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_rdw_cv_param_id, unit = '%' WHERE analyzer_id = v_analyzer_id AND channel_code = 'RDW_CV';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_rdw_sd_param_id, unit = 'fL' WHERE analyzer_id = v_analyzer_id AND channel_code = 'RDW_SD';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_plt_param_id, unit = '10^9/L' WHERE analyzer_id = v_analyzer_id AND channel_code = 'PLT';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_mpv_param_id, unit = 'fL' WHERE analyzer_id = v_analyzer_id AND channel_code = 'MPV';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_pdw_cv_param_id, unit = '%' WHERE analyzer_id = v_analyzer_id AND channel_code = 'PDW_CV';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_pdw_sd_param_id, unit = 'fL' WHERE analyzer_id = v_analyzer_id AND channel_code = 'PDW_SD';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_pct_param_id, unit = '%' WHERE analyzer_id = v_analyzer_id AND channel_code = 'PCT';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_p_lcc_param_id, unit = '10^9/L' WHERE analyzer_id = v_analyzer_id AND channel_code = 'P_LCC';
        UPDATE public.analyzer_parameter_mappings SET test_id = v_cbc_id, parameter_id = v_p_lcr_param_id, unit = '%' WHERE analyzer_id = v_analyzer_id AND channel_code = 'P_LCR';
    END IF;

    -- 5. Update HEM-0001 Test Configuration Status
    UPDATE public.tests
    SET 
        validation_status = 'VALIDATED',
        configuration_status = 'CONFIGURED',
        method = 'Electrical Impedance & Cyanide-free Colorimetry (CounCell 23 Excel)',
        updated_at = NOW()
    WHERE id = v_cbc_id;

END $$;

COMMIT;
