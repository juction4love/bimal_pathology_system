-- Migration: 00126_councell_cbc_adult_reference_ranges.sql
-- Goal: Apply lab-approved adult reference ranges to all 24 Complete Blood Count (CBC / HEM-0001) reporting parameters.
--
-- Approved Adult Reference Ranges:
-- Sex-Specific Parameters (3):
--   1. RBC (10^12/L): Male 4.5 - 5.9 | Female 4.0 - 5.2
--   2. HGB (g/dL): Male 13.0 - 17.0 | Female 12.0 - 15.5
--   3. HCT (%): Male 40.0 - 50.0 | Female 36.0 - 46.0
--
-- Adult Generic Parameters (21):
--   4. WBC (10^9/L): 4.0 - 11.0
--   5. LYM_ABS (10^9/L): 1.0 - 3.0
--   6. MID_ABS (10^9/L): 0.2 - 0.8
--   7. GRAN_ABS (10^9/L): 2.0 - 7.0
--   8. LYM_PERCENT (%): 20.0 - 40.0
--   9. MID_PERCENT (%): 2.0 - 10.0
--  10. GRAN_PERCENT (%): 40.0 - 70.0
--  11. NLR (Ratio): 1.0 - 3.0
--  12. PLR (Ratio): 100.0 - 200.0
--  13. MCV (fL): 80.0 - 100.0
--  14. MCH (pg): 27.0 - 32.0
--  15. MCHC (g/dL): 31.5 - 35.0
--  16. RDW_CV (%): 11.5 - 14.5
--  17. RDW_SD (fL): 39.0 - 46.0
--  18. PLT (10^9/L): 150 - 450
--  19. MPV (fL): 6.5 - 12.0
--  20. PDW_CV (%): 9.0 - 17.0
--  21. PDW_SD (fL): 9.0 - 17.0
--  22. PCT (%): 0.100 - 0.500 (Plateletcrit)
--  23. P_LCC (10^9/L): 30 - 90
--  24. P_LCR (%): 19.7 - 42.4
--
-- Clinical Invariants:
-- - Idempotent, duplicate-safe.
-- - Parameter identities, test identities, units, and billing prices remain 100% unchanged.
-- - No manual microscopy parameter pollution.
-- - CBC Plateletcrit PCT strictly isolated from FIAcheck Procalcitonin PCT_SEPSIS.
-- - Historical test results, signed clinical snapshots, and invoices remain 100% immutable.

BEGIN;

DO $$
DECLARE
    v_cbc_id UUID;
    v_param_id UUID;
BEGIN
    SELECT id INTO v_cbc_id FROM public.tests WHERE code = 'HEM-0001';
    IF v_cbc_id IS NULL THEN
        RAISE EXCEPTION 'Test HEM-0001 (Complete Blood Count) not found.' USING ERRCODE = 'P0002';
    END IF;

    -- =========================================================================
    -- 1. Clean up / replace existing active reference ranges for HEM-0001 parameters
    -- =========================================================================
    DELETE FROM public.reference_ranges
    WHERE parameter_id IN (
        SELECT id FROM public.parameters WHERE test_id = v_cbc_id
    );

    -- =========================================================================
    -- 2. Insert Approved Sex-Specific Reference Ranges (3 parameters -> 6 rows)
    -- =========================================================================

    -- 1. RBC (Red Blood Cell Count) - 10^12/L
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'RBC';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'Male', 0, 43800, 4.5, 5.9, '4.5 - 5.9 10^12/L', '10^12/L', 'Electrical Impedance', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 4.0, 5.2, '4.0 - 5.2 10^12/L', '10^12/L', 'Electrical Impedance', TRUE, TRUE);
    END IF;

    -- 2. HGB (Hemoglobin Concentration) - g/dL
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'HGB';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'Male', 0, 43800, 13.0, 17.0, '13.0 - 17.0 g/dL', 'g/dL', 'Cyanide-free Colorimetry', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 12.0, 15.5, '12.0 - 15.5 g/dL', 'g/dL', 'Cyanide-free Colorimetry', TRUE, TRUE);
    END IF;

    -- 3. HCT (Hematocrit / PCV) - %
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'HCT';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'Male', 0, 43800, 40.0, 50.0, '40.0 - 50.0 %', '%', 'Calculated (CounCell 23 Excel)', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 36.0, 46.0, '36.0 - 46.0 %', '%', 'Calculated (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- =========================================================================
    -- 3. Insert Approved Adult Generic Reference Ranges (21 parameters -> 21 rows)
    -- =========================================================================

    -- 4. WBC (White Blood Cell Count / TLC) - 10^9/L
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'WBC';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 4.0, 11.0, '4.0 - 11.0 10^9/L', '10^9/L', 'Electrical Impedance', TRUE, TRUE);
    END IF;

    -- 5. LYM_ABS (Absolute Lymphocyte Count) - 10^9/L
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'LYM_ABS';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 1.0, 3.0, '1.0 - 3.0 10^9/L', '10^9/L', 'Analyzer Differential (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 6. MID_ABS (Absolute Mid-cell Count) - 10^9/L
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'MID_ABS';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 0.2, 0.8, '0.2 - 0.8 10^9/L', '10^9/L', 'Analyzer Differential (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 7. GRAN_ABS (Absolute Granulocyte Count) - 10^9/L
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'GRAN_ABS';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 2.0, 7.0, '2.0 - 7.0 10^9/L', '10^9/L', 'Analyzer Differential (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 8. LYM_PERCENT (Lymphocyte Percentage) - %
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'LYM_PERCENT';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 20.0, 40.0, '20.0 - 40.0 %', '%', 'Electrical Impedance (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 9. MID_PERCENT (Mid-cell Percentage) - %
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'MID_PERCENT';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 2.0, 10.0, '2.0 - 10.0 %', '%', 'Electrical Impedance (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 10. GRAN_PERCENT (Granulocyte Percentage) - %
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'GRAN_PERCENT';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 40.0, 70.0, '40.0 - 70.0 %', '%', 'Electrical Impedance (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 11. NLR (Neutrophil-to-Lymphocyte Ratio) - Ratio
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'NLR';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 1.0, 3.0, '1.0 - 3.0 Ratio', 'Ratio', 'Analyzer Calculated (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 12. PLR (Platelet-to-Lymphocyte Ratio) - Ratio
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'PLR';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 100.0, 200.0, '100.0 - 200.0 Ratio', 'Ratio', 'Analyzer Calculated (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 13. MCV (Mean Corpuscular Volume) - fL
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'MCV';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 80.0, 100.0, '80.0 - 100.0 fL', 'fL', 'RBC Histogram Peak (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 14. MCH (Mean Corpuscular Hemoglobin) - pg
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'MCH';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 27.0, 32.0, '27.0 - 32.0 pg', 'pg', 'Analyzer Calculated (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 15. MCHC (Mean Corpuscular Hemoglobin Concentration) - g/dL
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'MCHC';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 31.5, 35.0, '31.5 - 35.0 g/dL', 'g/dL', 'Analyzer Calculated (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 16. RDW_CV (Red Cell Distribution Width - CV) - %
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'RDW_CV';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 11.5, 14.5, '11.5 - 14.5 %', '%', 'RBC Size Histogram (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 17. RDW_SD (Red Cell Distribution Width - SD) - fL
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'RDW_SD';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 39.0, 46.0, '39.0 - 46.0 fL', 'fL', 'RBC Size Histogram (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 18. PLT (Platelet Count) - 10^9/L
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'PLT';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 150.0, 450.0, '150 - 450 10^9/L', '10^9/L', 'Electrical Impedance', TRUE, TRUE);
    END IF;

    -- 19. MPV (Mean Platelet Volume) - fL
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'MPV';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 6.5, 12.0, '6.5 - 12.0 fL', 'fL', 'PLT Size Histogram (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 20. PDW_CV (Platelet Distribution Width - CV) - %
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'PDW_CV';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 9.0, 17.0, '9.0 - 17.0 %', '%', 'PLT Size Histogram (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 21. PDW_SD (Platelet Distribution Width - SD) - fL
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'PDW_SD';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 9.0, 17.0, '9.0 - 17.0 fL', 'fL', 'PLT Size Histogram (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 22. PCT (Plateletcrit) - %
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'PCT';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 0.100, 0.500, '0.100 - 0.500 %', '%', 'Analyzer Calculated (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 23. P_LCC (Platelet Large Cell Count) - 10^9/L
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'P_LCC';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 30.0, 90.0, '30 - 90 10^9/L', '10^9/L', 'Analyzer Calculated (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

    -- 24. P_LCR (Platelet Large Cell Ratio) - %
    SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_cbc_id AND code = 'P_LCR';
    IF v_param_id IS NOT NULL THEN
        INSERT INTO public.reference_ranges (
            parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active
        ) VALUES 
        (v_param_id, 'All', 0, 43800, 19.7, 42.4, '19.7 - 42.4 %', '%', 'PLT Histogram Analysis (CounCell 23 Excel)', TRUE, TRUE);
    END IF;

END $$;

COMMIT;
