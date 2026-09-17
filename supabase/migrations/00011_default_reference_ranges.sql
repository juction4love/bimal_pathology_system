-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Migration 00011: Default Practical Reference Ranges for Standard Catalogue
-- Adult baseline intervals (age_min_days = 6570 / 18Y, age_max_days = 43800 / 120Y)
-- Marked clearly as uncertified default template intervals requiring analyzer verification
-- Idempotent: Does not duplicate or overwrite existing approved reference ranges
-- ============================================================================

-- 1. Helper function to seed reference ranges idempotently
CREATE OR REPLACE FUNCTION pg_temp.seed_ref_range(
    p_test_code VARCHAR,
    p_param_code VARCHAR,
    p_gender VARCHAR,
    p_age_min_days INT,
    p_age_max_days INT,
    p_normal_min NUMERIC,
    p_normal_max NUMERIC,
    p_normal_text TEXT,
    p_reference_text TEXT
)
RETURNS VOID AS $$
DECLARE
    v_param_id UUID;
BEGIN
    SELECT p.id INTO v_param_id
    FROM public.parameters p
    JOIN public.tests t ON p.test_id = t.id
    WHERE t.code = p_test_code AND p.code = p_param_code;

    IF v_param_id IS NULL THEN
        RETURN;
    END IF;

    -- Only insert when no approved active range already exists for same parameter_id + gender + age window
    IF NOT EXISTS (
        SELECT 1
        FROM public.reference_ranges
        WHERE parameter_id = v_param_id
          AND gender = p_gender
          AND age_min_days = p_age_min_days
          AND is_approved = TRUE
          AND is_active = TRUE
    ) THEN
        INSERT INTO public.reference_ranges (
            parameter_id,
            gender,
            age_min_days,
            age_max_days,
            normal_min,
            normal_max,
            critical_low,
            critical_high,
            normal_text,
            reference_text,
            method,
            effective_from,
            is_active,
            is_approved
        ) VALUES (
            v_param_id,
            p_gender,
            p_age_min_days,
            COALESCE(p_age_max_days, 43800),
            p_normal_min,
            p_normal_max,
            NULL,
            NULL,
            p_normal_text,
            COALESCE(p_reference_text, 'Default reference interval. Verify with laboratory analyzer/reagent.'),
            'Default reference interval - verify with analyzer/reagent',
            CURRENT_DATE,
            TRUE,
            TRUE
        );
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 2. Populate Default Adult Reference Ranges
DO $$
DECLARE
    v_adult_age_min INT := 6570; -- 18 years in days
    v_adult_age_max INT := 43800; -- 120 years in days
BEGIN

    -- ------------------------------------------------------------------------
    -- A. HEMATOLOGY - COMPLETE BLOOD COUNT (CBC Profile & Singles)
    -- ------------------------------------------------------------------------
    -- CBC Profile
    PERFORM pg_temp.seed_ref_range('CBC', 'HB', 'Male', v_adult_age_min, v_adult_age_max, 13.0, 17.0, NULL, '13.0 - 17.0 g/dL');
    PERFORM pg_temp.seed_ref_range('CBC', 'HB', 'Female', v_adult_age_min, v_adult_age_max, 12.0, 15.0, NULL, '12.0 - 15.0 g/dL');
    PERFORM pg_temp.seed_ref_range('CBC', 'TLC', 'All', v_adult_age_min, v_adult_age_max, 4000, 11000, NULL, '4000 - 11000 /cumm');
    PERFORM pg_temp.seed_ref_range('CBC', 'NEUT', 'All', v_adult_age_min, v_adult_age_max, 40, 75, NULL, '40 - 75 %');
    PERFORM pg_temp.seed_ref_range('CBC', 'LYMPH', 'All', v_adult_age_min, v_adult_age_max, 20, 45, NULL, '20 - 45 %');
    PERFORM pg_temp.seed_ref_range('CBC', 'EOSIN', 'All', v_adult_age_min, v_adult_age_max, 1, 6, NULL, '1 - 6 %');
    PERFORM pg_temp.seed_ref_range('CBC', 'MONO', 'All', v_adult_age_min, v_adult_age_max, 2, 10, NULL, '2 - 10 %');
    PERFORM pg_temp.seed_ref_range('CBC', 'BASO', 'All', v_adult_age_min, v_adult_age_max, 0, 1, NULL, '0 - 1 %');
    PERFORM pg_temp.seed_ref_range('CBC', 'RBC', 'Male', v_adult_age_min, v_adult_age_max, 4.5, 5.9, NULL, '4.5 - 5.9 million/cumm');
    PERFORM pg_temp.seed_ref_range('CBC', 'RBC', 'Female', v_adult_age_min, v_adult_age_max, 4.1, 5.1, NULL, '4.1 - 5.1 million/cumm');
    PERFORM pg_temp.seed_ref_range('CBC', 'PCV', 'Male', v_adult_age_min, v_adult_age_max, 40, 52, NULL, '40 - 52 %');
    PERFORM pg_temp.seed_ref_range('CBC', 'PCV', 'Female', v_adult_age_min, v_adult_age_max, 36, 48, NULL, '36 - 48 %');
    PERFORM pg_temp.seed_ref_range('CBC', 'MCV', 'All', v_adult_age_min, v_adult_age_max, 80, 100, NULL, '80 - 100 fL');
    PERFORM pg_temp.seed_ref_range('CBC', 'MCH', 'All', v_adult_age_min, v_adult_age_max, 27, 33, NULL, '27 - 33 pg');
    PERFORM pg_temp.seed_ref_range('CBC', 'MCHC', 'All', v_adult_age_min, v_adult_age_max, 32, 36, NULL, '32 - 36 g/dL');
    PERFORM pg_temp.seed_ref_range('CBC', 'RDW', 'All', v_adult_age_min, v_adult_age_max, 11.5, 14.5, NULL, '11.5 - 14.5 %');
    PERFORM pg_temp.seed_ref_range('CBC', 'PLT', 'All', v_adult_age_min, v_adult_age_max, 150000, 450000, NULL, '150000 - 450000 /cumm');

    -- Hematology Individual Tests
    PERFORM pg_temp.seed_ref_range('HB', 'HB_VAL', 'Male', v_adult_age_min, v_adult_age_max, 13.0, 17.0, NULL, '13.0 - 17.0 g/dL');
    PERFORM pg_temp.seed_ref_range('HB', 'HB_VAL', 'Female', v_adult_age_min, v_adult_age_max, 12.0, 15.0, NULL, '12.0 - 15.0 g/dL');
    PERFORM pg_temp.seed_ref_range('TLC', 'TLC_VAL', 'All', v_adult_age_min, v_adult_age_max, 4000, 11000, NULL, '4000 - 11000 /cumm');
    PERFORM pg_temp.seed_ref_range('DLC', 'NEUT_VAL', 'All', v_adult_age_min, v_adult_age_max, 40, 75, NULL, '40 - 75 %');
    PERFORM pg_temp.seed_ref_range('DLC', 'LYMPH_VAL', 'All', v_adult_age_min, v_adult_age_max, 20, 45, NULL, '20 - 45 %');
    PERFORM pg_temp.seed_ref_range('DLC', 'EOSIN_VAL', 'All', v_adult_age_min, v_adult_age_max, 1, 6, NULL, '1 - 6 %');
    PERFORM pg_temp.seed_ref_range('DLC', 'MONO_VAL', 'All', v_adult_age_min, v_adult_age_max, 2, 10, NULL, '2 - 10 %');
    PERFORM pg_temp.seed_ref_range('DLC', 'BASO_VAL', 'All', v_adult_age_min, v_adult_age_max, 0, 1, NULL, '0 - 1 %');
    PERFORM pg_temp.seed_ref_range('PLT', 'PLT_VAL', 'All', v_adult_age_min, v_adult_age_max, 150000, 450000, NULL, '150000 - 450000 /cumm');
    PERFORM pg_temp.seed_ref_range('ESR', 'ESR_VAL', 'Male', v_adult_age_min, v_adult_age_max, 0, 15, NULL, '0 - 15 mm/hr');
    PERFORM pg_temp.seed_ref_range('ESR', 'ESR_VAL', 'Female', v_adult_age_min, v_adult_age_max, 0, 20, NULL, '0 - 20 mm/hr');
    PERFORM pg_temp.seed_ref_range('PCV', 'PCV_VAL', 'Male', v_adult_age_min, v_adult_age_max, 40, 52, NULL, '40 - 52 %');
    PERFORM pg_temp.seed_ref_range('PCV', 'PCV_VAL', 'Female', v_adult_age_min, v_adult_age_max, 36, 48, NULL, '36 - 48 %');
    PERFORM pg_temp.seed_ref_range('RBC_COUNT', 'RBC_VAL', 'Male', v_adult_age_min, v_adult_age_max, 4.5, 5.9, NULL, '4.5 - 5.9 million/cumm');
    PERFORM pg_temp.seed_ref_range('RBC_COUNT', 'RBC_VAL', 'Female', v_adult_age_min, v_adult_age_max, 4.1, 5.1, NULL, '4.1 - 5.1 million/cumm');

    -- ------------------------------------------------------------------------
    -- B. CLINICAL BIOCHEMISTRY & ROUTINE METABOLIC
    -- ------------------------------------------------------------------------
    PERFORM pg_temp.seed_ref_range('FBS', 'GLU_FASTING', 'All', v_adult_age_min, v_adult_age_max, 70, 99, NULL, '70 - 99 mg/dL');
    PERFORM pg_temp.seed_ref_range('PPBS', 'GLU_PP', 'All', v_adult_age_min, v_adult_age_max, NULL, 140, NULL, '< 140 mg/dL');
    PERFORM pg_temp.seed_ref_range('RBS', 'GLU_RANDOM', 'All', v_adult_age_min, v_adult_age_max, 70, 140, NULL, '70 - 140 mg/dL');
    PERFORM pg_temp.seed_ref_range('HBA1C', 'HBA1C_VAL', 'All', v_adult_age_min, v_adult_age_max, 4.0, 5.6, NULL, '4.0 - 5.6 % (Non-diabetic)');
    PERFORM pg_temp.seed_ref_range('UREA', 'UREA_VAL', 'All', v_adult_age_min, v_adult_age_max, 15, 45, NULL, '15 - 45 mg/dL');
    PERFORM pg_temp.seed_ref_range('CREATININE', 'CREAT_VAL', 'Male', v_adult_age_min, v_adult_age_max, 0.7, 1.3, NULL, '0.7 - 1.3 mg/dL');
    PERFORM pg_temp.seed_ref_range('CREATININE', 'CREAT_VAL', 'Female', v_adult_age_min, v_adult_age_max, 0.6, 1.1, NULL, '0.6 - 1.1 mg/dL');
    PERFORM pg_temp.seed_ref_range('URIC_ACID', 'URIC_VAL', 'Male', v_adult_age_min, v_adult_age_max, 3.4, 7.0, NULL, '3.4 - 7.0 mg/dL');
    PERFORM pg_temp.seed_ref_range('URIC_ACID', 'URIC_VAL', 'Female', v_adult_age_min, v_adult_age_max, 2.4, 6.0, NULL, '2.4 - 6.0 mg/dL');
    PERFORM pg_temp.seed_ref_range('SODIUM', 'NA_VAL', 'All', v_adult_age_min, v_adult_age_max, 135, 145, NULL, '135 - 145 mmol/L');
    PERFORM pg_temp.seed_ref_range('POTASSIUM', 'K_VAL', 'All', v_adult_age_min, v_adult_age_max, 3.5, 5.1, NULL, '3.5 - 5.1 mmol/L');
    PERFORM pg_temp.seed_ref_range('CHLORIDE', 'CL_VAL', 'All', v_adult_age_min, v_adult_age_max, 98, 107, NULL, '98 - 107 mmol/L');
    PERFORM pg_temp.seed_ref_range('CALCIUM', 'CA_VAL', 'All', v_adult_age_min, v_adult_age_max, 8.5, 10.5, NULL, '8.5 - 10.5 mg/dL');
    PERFORM pg_temp.seed_ref_range('PHOSPHORUS', 'PHOS_VAL', 'All', v_adult_age_min, v_adult_age_max, 2.5, 4.5, NULL, '2.5 - 4.5 mg/dL');
    PERFORM pg_temp.seed_ref_range('MAGNESIUM', 'MG_VAL', 'All', v_adult_age_min, v_adult_age_max, 1.7, 2.4, NULL, '1.7 - 2.4 mg/dL');

    -- ------------------------------------------------------------------------
    -- C. LIVER FUNCTION TEST (LFT Profile)
    -- ------------------------------------------------------------------------
    PERFORM pg_temp.seed_ref_range('LFT', 'TBIL', 'All', v_adult_age_min, v_adult_age_max, 0.3, 1.2, NULL, '0.3 - 1.2 mg/dL');
    PERFORM pg_temp.seed_ref_range('LFT', 'DBIL', 'All', v_adult_age_min, v_adult_age_max, 0.0, 0.3, NULL, '0.0 - 0.3 mg/dL');
    PERFORM pg_temp.seed_ref_range('LFT', 'IBIL', 'All', v_adult_age_min, v_adult_age_max, 0.2, 0.9, NULL, '0.2 - 0.9 mg/dL');
    PERFORM pg_temp.seed_ref_range('LFT', 'SGOT', 'All', v_adult_age_min, v_adult_age_max, 10, 40, NULL, '10 - 40 U/L');
    PERFORM pg_temp.seed_ref_range('LFT', 'SGPT', 'All', v_adult_age_min, v_adult_age_max, 7, 56, NULL, '7 - 56 U/L');
    PERFORM pg_temp.seed_ref_range('LFT', 'ALP', 'All', v_adult_age_min, v_adult_age_max, 44, 147, NULL, '44 - 147 U/L');
    PERFORM pg_temp.seed_ref_range('LFT', 'TP', 'All', v_adult_age_min, v_adult_age_max, 6.4, 8.3, NULL, '6.4 - 8.3 g/dL');
    PERFORM pg_temp.seed_ref_range('LFT', 'ALB', 'All', v_adult_age_min, v_adult_age_max, 3.5, 5.0, NULL, '3.5 - 5.0 g/dL');
    PERFORM pg_temp.seed_ref_range('LFT', 'GLOB', 'All', v_adult_age_min, v_adult_age_max, 2.0, 3.5, NULL, '2.0 - 3.5 g/dL');
    PERFORM pg_temp.seed_ref_range('LFT', 'AG_RATIO', 'All', v_adult_age_min, v_adult_age_max, 1.0, 2.5, NULL, '1.0 - 2.5');

    -- ------------------------------------------------------------------------
    -- D. KIDNEY FUNCTION TEST (KFT Profile)
    -- ------------------------------------------------------------------------
    PERFORM pg_temp.seed_ref_range('KFT', 'UREA', 'All', v_adult_age_min, v_adult_age_max, 15, 45, NULL, '15 - 45 mg/dL');
    PERFORM pg_temp.seed_ref_range('KFT', 'CREAT', 'Male', v_adult_age_min, v_adult_age_max, 0.7, 1.3, NULL, '0.7 - 1.3 mg/dL');
    PERFORM pg_temp.seed_ref_range('KFT', 'CREAT', 'Female', v_adult_age_min, v_adult_age_max, 0.6, 1.1, NULL, '0.6 - 1.1 mg/dL');
    PERFORM pg_temp.seed_ref_range('KFT', 'NA', 'All', v_adult_age_min, v_adult_age_max, 135, 145, NULL, '135 - 145 mmol/L');
    PERFORM pg_temp.seed_ref_range('KFT', 'K', 'All', v_adult_age_min, v_adult_age_max, 3.5, 5.1, NULL, '3.5 - 5.1 mmol/L');
    PERFORM pg_temp.seed_ref_range('KFT', 'URIC', 'Male', v_adult_age_min, v_adult_age_max, 3.4, 7.0, NULL, '3.4 - 7.0 mg/dL');
    PERFORM pg_temp.seed_ref_range('KFT', 'URIC', 'Female', v_adult_age_min, v_adult_age_max, 2.4, 6.0, NULL, '2.4 - 6.0 mg/dL');

    -- ------------------------------------------------------------------------
    -- E. LIPID PROFILE
    -- ------------------------------------------------------------------------
    PERFORM pg_temp.seed_ref_range('LIPID_PROFILE', 'CHOL', 'All', v_adult_age_min, v_adult_age_max, NULL, 200, NULL, 'Desirable: < 200 mg/dL');
    PERFORM pg_temp.seed_ref_range('LIPID_PROFILE', 'TRIG', 'All', v_adult_age_min, v_adult_age_max, NULL, 150, NULL, 'Normal: < 150 mg/dL');
    PERFORM pg_temp.seed_ref_range('LIPID_PROFILE', 'HDL', 'Male', v_adult_age_min, v_adult_age_max, 40, NULL, NULL, '> 40 mg/dL');
    PERFORM pg_temp.seed_ref_range('LIPID_PROFILE', 'HDL', 'Female', v_adult_age_min, v_adult_age_max, 50, NULL, NULL, '> 50 mg/dL');
    PERFORM pg_temp.seed_ref_range('LIPID_PROFILE', 'LDL', 'All', v_adult_age_min, v_adult_age_max, NULL, 100, NULL, 'Optimal: < 100 mg/dL');
    PERFORM pg_temp.seed_ref_range('LIPID_PROFILE', 'VLDL', 'All', v_adult_age_min, v_adult_age_max, 5, 40, NULL, '5 - 40 mg/dL');

    -- ------------------------------------------------------------------------
    -- F. THYROID PROFILE & INDIVIDUAL TESTS
    -- ------------------------------------------------------------------------
    PERFORM pg_temp.seed_ref_range('THYROID_PROFILE', 'T3', 'All', v_adult_age_min, v_adult_age_max, 80, 200, NULL, '80 - 200 ng/dL');
    PERFORM pg_temp.seed_ref_range('THYROID_PROFILE', 'T4', 'All', v_adult_age_min, v_adult_age_max, 5.0, 12.0, NULL, '5.0 - 12.0 µg/dL');
    PERFORM pg_temp.seed_ref_range('THYROID_PROFILE', 'TSH', 'All', v_adult_age_min, v_adult_age_max, 0.4, 4.0, NULL, '0.4 - 4.0 µIU/mL');
    PERFORM pg_temp.seed_ref_range('T3', 'T3_VAL', 'All', v_adult_age_min, v_adult_age_max, 80, 200, NULL, '80 - 200 ng/dL');
    PERFORM pg_temp.seed_ref_range('T4', 'T4_VAL', 'All', v_adult_age_min, v_adult_age_max, 5.0, 12.0, NULL, '5.0 - 12.0 µg/dL');
    PERFORM pg_temp.seed_ref_range('TSH', 'TSH_VAL', 'All', v_adult_age_min, v_adult_age_max, 0.4, 4.0, NULL, '0.4 - 4.0 µIU/mL');
    PERFORM pg_temp.seed_ref_range('FT3', 'FT3_VAL', 'All', v_adult_age_min, v_adult_age_max, 2.3, 4.2, NULL, '2.3 - 4.2 pg/mL');
    PERFORM pg_temp.seed_ref_range('FT4', 'FT4_VAL', 'All', v_adult_age_min, v_adult_age_max, 0.8, 1.8, NULL, '0.8 - 1.8 ng/dL');

    -- ------------------------------------------------------------------------
    -- G. SEROLOGY & IMMUNOLOGY
    -- ------------------------------------------------------------------------
    PERFORM pg_temp.seed_ref_range('CRP', 'CRP_VAL', 'All', v_adult_age_min, v_adult_age_max, NULL, 6, NULL, '< 6 mg/L');
    PERFORM pg_temp.seed_ref_range('RA_FACTOR', 'RA_VAL', 'All', v_adult_age_min, v_adult_age_max, NULL, 14, NULL, '< 14 IU/mL');
    PERFORM pg_temp.seed_ref_range('ASO', 'ASO_VAL', 'All', v_adult_age_min, v_adult_age_max, NULL, 200, NULL, '< 200 IU/mL');
    PERFORM pg_temp.seed_ref_range('HBSAG', 'HBSAG_RES', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Non-Reactive', 'Non-Reactive');
    PERFORM pg_temp.seed_ref_range('ANTI_HCV', 'HCV_RES', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Non-Reactive', 'Non-Reactive');
    PERFORM pg_temp.seed_ref_range('HIV', 'HIV_RES', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Non-Reactive', 'Non-Reactive');
    PERFORM pg_temp.seed_ref_range('VDRL', 'VDRL_RES', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Non-Reactive', 'Non-Reactive');
    PERFORM pg_temp.seed_ref_range('DENGUE_NS1', 'DENGUE_NS1_RES', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Negative', 'Negative');
    PERFORM pg_temp.seed_ref_range('DENGUE_IGM', 'DENGUE_IGM_RES', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Negative', 'Negative');
    PERFORM pg_temp.seed_ref_range('DENGUE_IGG', 'DENGUE_IGG_RES', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Negative', 'Negative');

    -- ------------------------------------------------------------------------
    -- H. CLINICAL PATHOLOGY (URINE & STOOL)
    -- ------------------------------------------------------------------------
    -- Urine R/E
    PERFORM pg_temp.seed_ref_range('URINE_RE', 'PROTEIN', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Negative', 'Negative');
    PERFORM pg_temp.seed_ref_range('URINE_RE', 'GLUCOSE', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Negative', 'Negative');
    PERFORM pg_temp.seed_ref_range('URINE_RE', 'KETONE', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Negative', 'Negative');
    PERFORM pg_temp.seed_ref_range('URINE_RE', 'BILE_SALT', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Negative', 'Negative');
    PERFORM pg_temp.seed_ref_range('URINE_RE', 'BILE_PIGMENT', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Negative', 'Negative');
    PERFORM pg_temp.seed_ref_range('URINE_RE', 'PUS_CELLS', 'All', v_adult_age_min, v_adult_age_max, 0, 5, '0 - 5', '0 - 5 /HPF');
    PERFORM pg_temp.seed_ref_range('URINE_RE', 'RBC_URINE', 'All', v_adult_age_min, v_adult_age_max, 0, 2, '0 - 2', '0 - 2 /HPF');
    PERFORM pg_temp.seed_ref_range('URINE_RE', 'EPITHELIAL', 'All', v_adult_age_min, v_adult_age_max, 0, 5, '0 - 5', '0 - 5 /HPF');
    PERFORM pg_temp.seed_ref_range('URINE_RE', 'CASTS', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Nil', 'Nil');
    PERFORM pg_temp.seed_ref_range('URINE_RE', 'CRYSTALS', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Nil', 'Nil');
    PERFORM pg_temp.seed_ref_range('URINE_RE', 'SP_GRAVITY', 'All', v_adult_age_min, v_adult_age_max, 1.005, 1.030, NULL, '1.005 - 1.030');
    PERFORM pg_temp.seed_ref_range('URINE_RE', 'PH', 'All', v_adult_age_min, v_adult_age_max, 4.5, 8.0, NULL, '4.5 - 8.0');

    -- Stool R/E & FOBT
    PERFORM pg_temp.seed_ref_range('STOOL_RE', 'STOOL_PUS', 'All', v_adult_age_min, v_adult_age_max, 0, 2, '0 - 2', '0 - 2 /HPF');
    PERFORM pg_temp.seed_ref_range('STOOL_RE', 'STOOL_RBC', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Nil', 'Nil');
    PERFORM pg_temp.seed_ref_range('STOOL_RE', 'STOOL_OVA', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Not Seen', 'Not Seen');
    PERFORM pg_temp.seed_ref_range('STOOL_RE', 'STOOL_CYST', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Not Seen', 'Not Seen');
    PERFORM pg_temp.seed_ref_range('STOOL_OB', 'FOBT_RES', 'All', v_adult_age_min, v_adult_age_max, NULL, NULL, 'Negative', 'Negative');

END $$;

-- 3. Cleanup temporary seeding function
DROP FUNCTION IF EXISTS pg_temp.seed_ref_range(VARCHAR, VARCHAR, VARCHAR, INT, INT, NUMERIC, NUMERIC, TEXT, TEXT);
