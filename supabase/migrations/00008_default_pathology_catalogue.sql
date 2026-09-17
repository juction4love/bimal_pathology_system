-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Migration 00008: Default Ready-Made Pathology Test Catalogue & Profiles
-- All prices seeded as 0 Paisa (Admin configures actual rates before clinical use)
-- Idempotent: Safe to rerun without overwriting customized values or creating duplicates
-- ============================================================================

-- 0. Safe cleanup of CRUD verification test record (TEST_CBC) using verified foreign keys
DO $$
DECLARE
    v_test_id UUID;
BEGIN
    SELECT id INTO v_test_id
    FROM public.tests
    WHERE code = 'TEST_CBC';

    IF v_test_id IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM public.bill_items
           WHERE test_id = v_test_id
       )
       AND NOT EXISTS (
           SELECT 1
           FROM public.clinical_order_items
           WHERE test_id = v_test_id
       )
    THEN
        DELETE FROM public.tests
        WHERE id = v_test_id;
    END IF;
END $$;

-- 1. Helper function to seed tests idempotently
CREATE OR REPLACE FUNCTION pg_temp.seed_test(
    p_code VARCHAR,
    p_name VARCHAR,
    p_short_name VARCHAR,
    p_department VARCHAR,
    p_category VARCHAR,
    p_reporting_type reporting_type_enum,
    p_price_paisa BIGINT,
    p_sample_type VARCHAR,
    p_container VARCHAR,
    p_tat_hours INT,
    p_display_order INT
)
RETURNS UUID AS $$
DECLARE
    v_test_id UUID;
BEGIN
    INSERT INTO public.tests (
        code,
        name,
        short_name,
        department,
        category,
        reporting_type,
        price_paisa,
        sample_type,
        container,
        tat_hours,
        display_order,
        is_active
    ) VALUES (
        p_code,
        p_name,
        p_short_name,
        p_department,
        p_category,
        p_reporting_type,
        p_price_paisa,
        p_sample_type,
        p_container,
        p_tat_hours,
        p_display_order,
        TRUE
    )
    ON CONFLICT (code) DO NOTHING;

    SELECT id INTO v_test_id FROM public.tests WHERE code = p_code;
    RETURN v_test_id;
END;
$$ LANGUAGE plpgsql;

-- 2. Helper function to seed parameters idempotently
CREATE OR REPLACE FUNCTION pg_temp.seed_param(
    p_test_id UUID,
    p_code VARCHAR,
    p_name VARCHAR,
    p_value_type parameter_value_type_enum,
    p_unit VARCHAR,
    p_formula TEXT,
    p_dependencies TEXT[],
    p_display_order INT
)
RETURNS VOID AS $$
BEGIN
    IF p_test_id IS NULL THEN
        RETURN;
    END IF;

    INSERT INTO public.parameters (
        test_id,
        code,
        name,
        value_type,
        unit,
        formula,
        formula_dependencies,
        display_order,
        is_mandatory,
        is_active
    ) VALUES (
        p_test_id,
        p_code,
        p_name,
        p_value_type,
        p_unit,
        p_formula,
        p_dependencies,
        p_display_order,
        TRUE,
        TRUE
    )
    ON CONFLICT (test_id, code) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 3. SEED TESTS & PROFILES
-- ============================================================================

DO $$
DECLARE
    v_id UUID;
BEGIN

    -- ------------------------------------------------------------------------
    -- A. HEMATOLOGY
    -- ------------------------------------------------------------------------
    -- 1. Complete Blood Count (CBC Profile)
    v_id := pg_temp.seed_test('CBC', 'Complete Blood Count (CBC)', 'CBC', 'Hematology', 'Complete Blood Count', 'InHouse', 0, 'Whole Blood', 'EDTA / Lavender Top', 4, 10);
    PERFORM pg_temp.seed_param(v_id, 'HB', 'Hemoglobin', 'Numeric', 'g/dL', NULL, NULL, 1);
    PERFORM pg_temp.seed_param(v_id, 'TLC', 'Total Leukocyte Count (TLC / WBC)', 'Numeric', '/cumm', NULL, NULL, 2);
    PERFORM pg_temp.seed_param(v_id, 'NEUT', 'Neutrophils', 'Numeric', '%', NULL, NULL, 3);
    PERFORM pg_temp.seed_param(v_id, 'LYMPH', 'Lymphocytes', 'Numeric', '%', NULL, NULL, 4);
    PERFORM pg_temp.seed_param(v_id, 'EOSIN', 'Eosinophils', 'Numeric', '%', NULL, NULL, 5);
    PERFORM pg_temp.seed_param(v_id, 'MONO', 'Monocytes', 'Numeric', '%', NULL, NULL, 6);
    PERFORM pg_temp.seed_param(v_id, 'BASO', 'Basophils', 'Numeric', '%', NULL, NULL, 7);
    PERFORM pg_temp.seed_param(v_id, 'RBC', 'RBC Count', 'Numeric', 'million/cumm', NULL, NULL, 8);
    PERFORM pg_temp.seed_param(v_id, 'PCV', 'Packed Cell Volume (PCV / Hematocrit)', 'Numeric', '%', NULL, NULL, 9);
    PERFORM pg_temp.seed_param(v_id, 'MCV', 'Mean Corpuscular Volume (MCV)', 'Numeric', 'fL', NULL, NULL, 10);
    PERFORM pg_temp.seed_param(v_id, 'MCH', 'Mean Corpuscular Hemoglobin (MCH)', 'Numeric', 'pg', NULL, NULL, 11);
    PERFORM pg_temp.seed_param(v_id, 'MCHC', 'Mean Corpuscular Hb Conc (MCHC)', 'Numeric', 'g/dL', NULL, NULL, 12);
    PERFORM pg_temp.seed_param(v_id, 'RDW', 'Red Cell Distribution Width (RDW)', 'Numeric', '%', NULL, NULL, 13);
    PERFORM pg_temp.seed_param(v_id, 'PLT', 'Platelet Count', 'Numeric', '/cumm', NULL, NULL, 14);

    -- 2. Hemoglobin (Single)
    v_id := pg_temp.seed_test('HB', 'Hemoglobin (Hb)', 'Hb', 'Hematology', 'Routine Hematology', 'InHouse', 0, 'Whole Blood', 'EDTA / Lavender Top', 2, 20);
    PERFORM pg_temp.seed_param(v_id, 'HB_VAL', 'Hemoglobin', 'Numeric', 'g/dL', NULL, NULL, 1);

    -- 3. Total Leukocyte Count (TLC Single)
    v_id := pg_temp.seed_test('TLC', 'Total Leukocyte Count (TLC / WBC)', 'TLC', 'Hematology', 'Routine Hematology', 'InHouse', 0, 'Whole Blood', 'EDTA / Lavender Top', 2, 30);
    PERFORM pg_temp.seed_param(v_id, 'TLC_VAL', 'Total Leukocyte Count', 'Numeric', '/cumm', NULL, NULL, 1);

    -- 4. Differential Leukocyte Count (DLC Single)
    v_id := pg_temp.seed_test('DLC', 'Differential Leukocyte Count (DLC)', 'DLC', 'Hematology', 'Routine Hematology', 'InHouse', 0, 'Whole Blood', 'EDTA / Lavender Top', 4, 40);
    PERFORM pg_temp.seed_param(v_id, 'NEUT_VAL', 'Neutrophils', 'Numeric', '%', NULL, NULL, 1);
    PERFORM pg_temp.seed_param(v_id, 'LYMPH_VAL', 'Lymphocytes', 'Numeric', '%', NULL, NULL, 2);
    PERFORM pg_temp.seed_param(v_id, 'EOSIN_VAL', 'Eosinophils', 'Numeric', '%', NULL, NULL, 3);
    PERFORM pg_temp.seed_param(v_id, 'MONO_VAL', 'Monocytes', 'Numeric', '%', NULL, NULL, 4);
    PERFORM pg_temp.seed_param(v_id, 'BASO_VAL', 'Basophils', 'Numeric', '%', NULL, NULL, 5);

    -- 5. Platelet Count (Single)
    v_id := pg_temp.seed_test('PLT', 'Platelet Count', 'Platelets', 'Hematology', 'Routine Hematology', 'InHouse', 0, 'Whole Blood', 'EDTA / Lavender Top', 2, 50);
    PERFORM pg_temp.seed_param(v_id, 'PLT_VAL', 'Platelet Count', 'Numeric', '/cumm', NULL, NULL, 1);

    -- 6. ESR
    v_id := pg_temp.seed_test('ESR', 'Erythrocyte Sedimentation Rate (ESR)', 'ESR', 'Hematology', 'Routine Hematology', 'InHouse', 0, 'Whole Blood', 'Sodium Citrate / Black Top', 2, 60);
    PERFORM pg_temp.seed_param(v_id, 'ESR_VAL', 'ESR (Westergren 1st Hour)', 'Numeric', 'mm/1st hr', NULL, NULL, 1);

    -- 7. PCV / Hematocrit
    v_id := pg_temp.seed_test('PCV', 'Packed Cell Volume (PCV / Hematocrit)', 'PCV', 'Hematology', 'Routine Hematology', 'InHouse', 0, 'Whole Blood', 'EDTA / Lavender Top', 2, 70);
    PERFORM pg_temp.seed_param(v_id, 'PCV_VAL', 'Packed Cell Volume', 'Numeric', '%', NULL, NULL, 1);

    -- 8. RBC Count
    v_id := pg_temp.seed_test('RBC_COUNT', 'Red Blood Cell Count (RBC Count)', 'RBC', 'Hematology', 'Routine Hematology', 'InHouse', 0, 'Whole Blood', 'EDTA / Lavender Top', 2, 80);
    PERFORM pg_temp.seed_param(v_id, 'RBC_VAL', 'RBC Count', 'Numeric', 'million/cumm', NULL, NULL, 1);

    -- 9. Peripheral Blood Smear
    v_id := pg_temp.seed_test('PBS', 'Peripheral Blood Smear Examination (PBS)', 'PBS', 'Hematology', 'Morphology', 'InHouse', 0, 'Whole Blood', 'EDTA / Lavender Top', 6, 90);
    PERFORM pg_temp.seed_param(v_id, 'RBC_MORPH', 'RBC Morphology', 'Text', NULL, NULL, NULL, 1);
    PERFORM pg_temp.seed_param(v_id, 'WBC_MORPH', 'WBC Morphology', 'Text', NULL, NULL, NULL, 2);
    PERFORM pg_temp.seed_param(v_id, 'PLT_MORPH', 'Platelet Morphology', 'Text', NULL, NULL, NULL, 3);
    PERFORM pg_temp.seed_param(v_id, 'PBS_IMPRESSION', 'Impression / Remarks', 'Text', NULL, NULL, NULL, 4);

    -- ------------------------------------------------------------------------
    -- B. BIOCHEMISTRY & ROUTINE METABOLIC
    -- ------------------------------------------------------------------------
    -- 10. FBS
    v_id := pg_temp.seed_test('FBS', 'Fasting Blood Sugar (FBS)', 'FBS', 'Clinical Biochemistry', 'Glucose & Diabetes', 'InHouse', 0, 'Fluoride Plasma / Serum', 'Grey Top / Yellow Top', 2, 100);
    PERFORM pg_temp.seed_param(v_id, 'GLU_FASTING', 'Fasting Glucose', 'Numeric', 'mg/dL', NULL, NULL, 1);

    -- 11. PPBS
    v_id := pg_temp.seed_test('PPBS', 'Post Prandial Blood Sugar (PPBS)', 'PPBS', 'Clinical Biochemistry', 'Glucose & Diabetes', 'InHouse', 0, 'Fluoride Plasma / Serum', 'Grey Top / Yellow Top', 2, 110);
    PERFORM pg_temp.seed_param(v_id, 'GLU_PP', 'Post Prandial Glucose', 'Numeric', 'mg/dL', NULL, NULL, 1);

    -- 12. RBS
    v_id := pg_temp.seed_test('RBS', 'Random Blood Sugar (RBS)', 'RBS', 'Clinical Biochemistry', 'Glucose & Diabetes', 'InHouse', 0, 'Fluoride Plasma / Serum', 'Grey Top / Yellow Top', 1, 120);
    PERFORM pg_temp.seed_param(v_id, 'GLU_RANDOM', 'Random Glucose', 'Numeric', 'mg/dL', NULL, NULL, 1);

    -- 13. HbA1c
    v_id := pg_temp.seed_test('HBA1C', 'Glycated Hemoglobin (HbA1c)', 'HbA1c', 'Clinical Biochemistry', 'Glucose & Diabetes', 'InHouse', 0, 'Whole Blood', 'EDTA / Lavender Top', 4, 130);
    PERFORM pg_temp.seed_param(v_id, 'HBA1C_VAL', 'HbA1c (Glycated Hb)', 'Numeric', '%', NULL, NULL, 1);
    PERFORM pg_temp.seed_param(v_id, 'EAG_VAL', 'Estimated Average Glucose (eAG)', 'Numeric', 'mg/dL', NULL, NULL, 2);

    -- 14. Urea
    v_id := pg_temp.seed_test('UREA', 'Blood Urea', 'Urea', 'Clinical Biochemistry', 'Renal Function', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 140);
    PERFORM pg_temp.seed_param(v_id, 'UREA_VAL', 'Blood Urea', 'Numeric', 'mg/dL', NULL, NULL, 1);

    -- 15. Creatinine
    v_id := pg_temp.seed_test('CREATININE', 'Serum Creatinine', 'Creatinine', 'Clinical Biochemistry', 'Renal Function', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 150);
    PERFORM pg_temp.seed_param(v_id, 'CREAT_VAL', 'Serum Creatinine', 'Numeric', 'mg/dL', NULL, NULL, 1);

    -- 16. Uric Acid
    v_id := pg_temp.seed_test('URIC_ACID', 'Serum Uric Acid', 'Uric Acid', 'Clinical Biochemistry', 'Renal Function', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 160);
    PERFORM pg_temp.seed_param(v_id, 'URIC_VAL', 'Serum Uric Acid', 'Numeric', 'mg/dL', NULL, NULL, 1);

    -- 17. Sodium
    v_id := pg_temp.seed_test('SODIUM', 'Serum Sodium (Na+)', 'Sodium', 'Clinical Biochemistry', 'Electrolytes', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 170);
    PERFORM pg_temp.seed_param(v_id, 'NA_VAL', 'Serum Sodium', 'Numeric', 'mEq/L', NULL, NULL, 1);

    -- 18. Potassium
    v_id := pg_temp.seed_test('POTASSIUM', 'Serum Potassium (K+)', 'Potassium', 'Clinical Biochemistry', 'Electrolytes', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 180);
    PERFORM pg_temp.seed_param(v_id, 'K_VAL', 'Serum Potassium', 'Numeric', 'mEq/L', NULL, NULL, 1);

    -- 19. Chloride
    v_id := pg_temp.seed_test('CHLORIDE', 'Serum Chloride (Cl-)', 'Chloride', 'Clinical Biochemistry', 'Electrolytes', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 190);
    PERFORM pg_temp.seed_param(v_id, 'CL_VAL', 'Serum Chloride', 'Numeric', 'mEq/L', NULL, NULL, 1);

    -- 20. Calcium
    v_id := pg_temp.seed_test('CALCIUM', 'Serum Calcium (Total)', 'Calcium', 'Clinical Biochemistry', 'Minerals & Electrolytes', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 200);
    PERFORM pg_temp.seed_param(v_id, 'CA_VAL', 'Total Calcium', 'Numeric', 'mg/dL', NULL, NULL, 1);

    -- 21. Phosphorus
    v_id := pg_temp.seed_test('PHOSPHORUS', 'Serum Phosphorus (Inorganic)', 'Phosphorus', 'Clinical Biochemistry', 'Minerals & Electrolytes', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 210);
    PERFORM pg_temp.seed_param(v_id, 'PHOS_VAL', 'Inorganic Phosphorus', 'Numeric', 'mg/dL', NULL, NULL, 1);

    -- 22. Magnesium
    v_id := pg_temp.seed_test('MAGNESIUM', 'Serum Magnesium', 'Magnesium', 'Clinical Biochemistry', 'Minerals & Electrolytes', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 4, 220);
    PERFORM pg_temp.seed_param(v_id, 'MG_VAL', 'Serum Magnesium', 'Numeric', 'mg/dL', NULL, NULL, 1);

    -- ------------------------------------------------------------------------
    -- C. LIVER FUNCTION TEST (LFT Profile)
    -- ------------------------------------------------------------------------
    v_id := pg_temp.seed_test('LFT', 'Liver Function Test (LFT Profile)', 'LFT', 'Clinical Biochemistry', 'Hepatic Function', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 4, 230);
    PERFORM pg_temp.seed_param(v_id, 'TBIL', 'Bilirubin Total', 'Numeric', 'mg/dL', NULL, NULL, 1);
    PERFORM pg_temp.seed_param(v_id, 'DBIL', 'Bilirubin Direct', 'Numeric', 'mg/dL', NULL, NULL, 2);
    PERFORM pg_temp.seed_param(v_id, 'IBIL', 'Bilirubin Indirect', 'Calculated', 'mg/dL', 'TBIL - DBIL', ARRAY['TBIL', 'DBIL'], 3);
    PERFORM pg_temp.seed_param(v_id, 'SGOT', 'AST / SGOT', 'Numeric', 'U/L', NULL, NULL, 4);
    PERFORM pg_temp.seed_param(v_id, 'SGPT', 'ALT / SGPT', 'Numeric', 'U/L', NULL, NULL, 5);
    PERFORM pg_temp.seed_param(v_id, 'ALP', 'Alkaline Phosphatase (ALP)', 'Numeric', 'U/L', NULL, NULL, 6);
    PERFORM pg_temp.seed_param(v_id, 'TP', 'Total Protein', 'Numeric', 'g/dL', NULL, NULL, 7);
    PERFORM pg_temp.seed_param(v_id, 'ALB', 'Albumin', 'Numeric', 'g/dL', NULL, NULL, 8);
    PERFORM pg_temp.seed_param(v_id, 'GLOB', 'Globulin', 'Calculated', 'g/dL', 'TP - ALB', ARRAY['TP', 'ALB'], 9);
    PERFORM pg_temp.seed_param(v_id, 'AG_RATIO', 'A:G Ratio', 'Calculated', 'ratio', 'ALB / GLOB', ARRAY['ALB', 'GLOB'], 10);

    -- ------------------------------------------------------------------------
    -- D. KIDNEY FUNCTION TEST (KFT / RFT Profile)
    -- ------------------------------------------------------------------------
    v_id := pg_temp.seed_test('KFT', 'Kidney Function Test (KFT / RFT Profile)', 'KFT', 'Clinical Biochemistry', 'Renal Function', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 3, 240);
    PERFORM pg_temp.seed_param(v_id, 'UREA', 'Blood Urea', 'Numeric', 'mg/dL', NULL, NULL, 1);
    PERFORM pg_temp.seed_param(v_id, 'CREAT', 'Serum Creatinine', 'Numeric', 'mg/dL', NULL, NULL, 2);
    PERFORM pg_temp.seed_param(v_id, 'NA', 'Serum Sodium (Na+)', 'Numeric', 'mEq/L', NULL, NULL, 3);
    PERFORM pg_temp.seed_param(v_id, 'K', 'Serum Potassium (K+)', 'Numeric', 'mEq/L', NULL, NULL, 4);
    PERFORM pg_temp.seed_param(v_id, 'URIC', 'Serum Uric Acid', 'Numeric', 'mg/dL', NULL, NULL, 5);

    -- ------------------------------------------------------------------------
    -- E. LIPID PROFILE
    -- ------------------------------------------------------------------------
    v_id := pg_temp.seed_test('LIPID_PROFILE', 'Lipid Profile', 'Lipid', 'Clinical Biochemistry', 'Lipid Metabolism', 'InHouse', 0, 'Serum (Fasting)', 'Yellow Top (SST)', 4, 250);
    PERFORM pg_temp.seed_param(v_id, 'CHOL', 'Total Cholesterol', 'Numeric', 'mg/dL', NULL, NULL, 1);
    PERFORM pg_temp.seed_param(v_id, 'TRIG', 'Triglycerides', 'Numeric', 'mg/dL', NULL, NULL, 2);
    PERFORM pg_temp.seed_param(v_id, 'HDL', 'HDL Cholesterol', 'Numeric', 'mg/dL', NULL, NULL, 3);
    PERFORM pg_temp.seed_param(v_id, 'LDL', 'LDL Cholesterol', 'Numeric', 'mg/dL', NULL, NULL, 4);
    PERFORM pg_temp.seed_param(v_id, 'VLDL', 'VLDL Cholesterol', 'Calculated', 'mg/dL', 'TRIG / 5', ARRAY['TRIG'], 5);

    -- ------------------------------------------------------------------------
    -- F. THYROID PROFILE & INDIVIDUAL TESTS
    -- ------------------------------------------------------------------------
    -- 26. Thyroid Profile (T3, T4, TSH)
    v_id := pg_temp.seed_test('THYROID_PROFILE', 'Thyroid Profile (T3, T4, TSH)', 'TFT', 'Immunology & Endocrinology', 'Endocrinology', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 6, 260);
    PERFORM pg_temp.seed_param(v_id, 'T3', 'Total Triiodothyronine (T3)', 'Numeric', 'ng/mL', NULL, NULL, 1);
    PERFORM pg_temp.seed_param(v_id, 'T4', 'Total Thyroxine (T4)', 'Numeric', 'µg/dL', NULL, NULL, 2);
    PERFORM pg_temp.seed_param(v_id, 'TSH', 'Thyroid Stimulating Hormone (TSH)', 'Numeric', 'µIU/mL', NULL, NULL, 3);

    -- 27. T3 Single
    v_id := pg_temp.seed_test('T3', 'Triiodothyronine Total (T3)', 'T3', 'Immunology & Endocrinology', 'Endocrinology', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 6, 270);
    PERFORM pg_temp.seed_param(v_id, 'T3_VAL', 'Total T3', 'Numeric', 'ng/mL', NULL, NULL, 1);

    -- 28. T4 Single
    v_id := pg_temp.seed_test('T4', 'Thyroxine Total (T4)', 'T4', 'Immunology & Endocrinology', 'Endocrinology', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 6, 280);
    PERFORM pg_temp.seed_param(v_id, 'T4_VAL', 'Total T4', 'Numeric', 'µg/dL', NULL, NULL, 1);

    -- 29. TSH Single
    v_id := pg_temp.seed_test('TSH', 'Thyroid Stimulating Hormone (TSH, Ultrasensitive)', 'TSH', 'Immunology & Endocrinology', 'Endocrinology', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 4, 290);
    PERFORM pg_temp.seed_param(v_id, 'TSH_VAL', 'TSH Ultrasensitive', 'Numeric', 'µIU/mL', NULL, NULL, 1);

    -- 30. FT3
    v_id := pg_temp.seed_test('FT3', 'Free Triiodothyronine (FT3)', 'FT3', 'Immunology & Endocrinology', 'Endocrinology', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 6, 300);
    PERFORM pg_temp.seed_param(v_id, 'FT3_VAL', 'Free T3', 'Numeric', 'pg/mL', NULL, NULL, 1);

    -- 31. FT4
    v_id := pg_temp.seed_test('FT4', 'Free Thyroxine (FT4)', 'FT4', 'Immunology & Endocrinology', 'Endocrinology', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 6, 310);
    PERFORM pg_temp.seed_param(v_id, 'FT4_VAL', 'Free T4', 'Numeric', 'ng/dL', NULL, NULL, 1);

    -- ------------------------------------------------------------------------
    -- G. SEROLOGY & IMMUNOLOGY
    -- ------------------------------------------------------------------------
    -- 32. CRP
    v_id := pg_temp.seed_test('CRP', 'C-Reactive Protein (CRP, Quantitative)', 'CRP', 'Serology & Immunology', 'Inflammatory Markers', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 320);
    PERFORM pg_temp.seed_param(v_id, 'CRP_VAL', 'C-Reactive Protein', 'Numeric', 'mg/L', NULL, NULL, 1);

    -- 33. RA Factor
    v_id := pg_temp.seed_test('RA_FACTOR', 'Rheumatoid Factor (RA Factor, Quantitative)', 'RA Factor', 'Serology & Immunology', 'Autoimmune', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 330);
    PERFORM pg_temp.seed_param(v_id, 'RA_VAL', 'Rheumatoid Factor', 'Numeric', 'IU/mL', NULL, NULL, 1);

    -- 34. ASO Titer
    v_id := pg_temp.seed_test('ASO', 'Anti-Streptolysin O (ASO Titer)', 'ASO', 'Serology & Immunology', 'Infectious Serology', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 340);
    PERFORM pg_temp.seed_param(v_id, 'ASO_VAL', 'ASO Titer', 'Numeric', 'IU/mL', NULL, NULL, 1);

    -- 35. HBsAg
    v_id := pg_temp.seed_test('HBSAG', 'Hepatitis B Surface Antigen (HBsAg)', 'HBsAg', 'Serology & Immunology', 'Viral Serology', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 350);
    PERFORM pg_temp.seed_param(v_id, 'HBSAG_RES', 'HBsAg Result', 'Text', NULL, NULL, NULL, 1);

    -- 36. Anti-HCV
    v_id := pg_temp.seed_test('ANTI_HCV', 'Anti-Hepatitis C Virus (Anti-HCV)', 'Anti-HCV', 'Serology & Immunology', 'Viral Serology', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 360);
    PERFORM pg_temp.seed_param(v_id, 'HCV_RES', 'Anti-HCV Result', 'Text', NULL, NULL, NULL, 1);

    -- 37. HIV 1 & 2
    v_id := pg_temp.seed_test('HIV', 'HIV 1 & 2 Antibody / Antigen', 'HIV', 'Serology & Immunology', 'Viral Serology', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 370);
    PERFORM pg_temp.seed_param(v_id, 'HIV_RES', 'HIV 1 & 2 Result', 'Text', NULL, NULL, NULL, 1);

    -- 38. VDRL / RPR
    v_id := pg_temp.seed_test('VDRL', 'VDRL / RPR (Syphilis Serology)', 'VDRL', 'Serology & Immunology', 'Infectious Serology', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 380);
    PERFORM pg_temp.seed_param(v_id, 'VDRL_RES', 'VDRL Result', 'Text', NULL, NULL, NULL, 1);

    -- 39. Dengue NS1
    v_id := pg_temp.seed_test('DENGUE_NS1', 'Dengue NS1 Antigen (Rapid)', 'Dengue NS1', 'Serology & Immunology', 'Vector-Borne', 'InHouse', 0, 'Serum / Whole Blood', 'Yellow Top (SST) / EDTA', 1, 390);
    PERFORM pg_temp.seed_param(v_id, 'DENGUE_NS1_RES', 'Dengue NS1 Antigen', 'Text', NULL, NULL, NULL, 1);

    -- 40. Dengue IgM
    v_id := pg_temp.seed_test('DENGUE_IGM', 'Dengue IgM Antibody (Rapid)', 'Dengue IgM', 'Serology & Immunology', 'Vector-Borne', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 1, 400);
    PERFORM pg_temp.seed_param(v_id, 'DENGUE_IGM_RES', 'Dengue IgM Antibody', 'Text', NULL, NULL, NULL, 1);

    -- 41. Dengue IgG
    v_id := pg_temp.seed_test('DENGUE_IGG', 'Dengue IgG Antibody (Rapid)', 'Dengue IgG', 'Serology & Immunology', 'Vector-Borne', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 1, 410);
    PERFORM pg_temp.seed_param(v_id, 'DENGUE_IGG_RES', 'Dengue IgG Antibody', 'Text', NULL, NULL, NULL, 1);

    -- 42. Widal Test
    v_id := pg_temp.seed_test('WIDAL', 'Widal Agglutination Test (Typhoid)', 'Widal', 'Serology & Immunology', 'Infectious Serology', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 2, 420);
    PERFORM pg_temp.seed_param(v_id, 'SALM_TO', 'S. Typhi "O" Titer', 'Text', NULL, NULL, NULL, 1);
    PERFORM pg_temp.seed_param(v_id, 'SALM_TH', 'S. Typhi "H" Titer', 'Text', NULL, NULL, NULL, 2);
    PERFORM pg_temp.seed_param(v_id, 'SALM_AH', 'S. Paratyphi "AH" Titer', 'Text', NULL, NULL, NULL, 3);
    PERFORM pg_temp.seed_param(v_id, 'SALM_BH', 'S. Paratyphi "BH" Titer', 'Text', NULL, NULL, NULL, 4);
    PERFORM pg_temp.seed_param(v_id, 'WIDAL_INTERP', 'Impression', 'Text', NULL, NULL, NULL, 5);

    -- ------------------------------------------------------------------------
    -- H. CLINICAL PATHOLOGY (URINE & STOOL)
    -- ------------------------------------------------------------------------
    -- 43. Urine Routine & Microscopy
    v_id := pg_temp.seed_test('URINE_RE', 'Urine Routine & Microscopic Examination (Urine R/E)', 'Urine R/E', 'Clinical Pathology', 'Urine Analysis', 'InHouse', 0, 'Clean Catch Midstream Urine', 'Sterile Urine Container', 2, 430);
    PERFORM pg_temp.seed_param(v_id, 'COLOUR', 'Colour', 'Text', NULL, NULL, NULL, 1);
    PERFORM pg_temp.seed_param(v_id, 'APPEARANCE', 'Appearance', 'Text', NULL, NULL, NULL, 2);
    PERFORM pg_temp.seed_param(v_id, 'SP_GRAVITY', 'Specific Gravity', 'Numeric', NULL, NULL, NULL, 3);
    PERFORM pg_temp.seed_param(v_id, 'PH', 'pH', 'Numeric', NULL, NULL, NULL, 4);
    PERFORM pg_temp.seed_param(v_id, 'PROTEIN', 'Protein / Albumin', 'Text', NULL, NULL, NULL, 5);
    PERFORM pg_temp.seed_param(v_id, 'GLUCOSE', 'Glucose / Sugar', 'Text', NULL, NULL, NULL, 6);
    PERFORM pg_temp.seed_param(v_id, 'KETONE', 'Ketone Bodies', 'Text', NULL, NULL, NULL, 7);
    PERFORM pg_temp.seed_param(v_id, 'BILE_SALT', 'Bile Salts', 'Text', NULL, NULL, NULL, 8);
    PERFORM pg_temp.seed_param(v_id, 'BILE_PIGMENT', 'Bile Pigments', 'Text', NULL, NULL, NULL, 9);
    PERFORM pg_temp.seed_param(v_id, 'PUS_CELLS', 'Pus Cells (WBCs)', 'Text', '/HPF', NULL, NULL, 10);
    PERFORM pg_temp.seed_param(v_id, 'RBC_URINE', 'Red Blood Cells (RBCs)', 'Text', '/HPF', NULL, NULL, 11);
    PERFORM pg_temp.seed_param(v_id, 'EPITHELIAL', 'Epithelial Cells', 'Text', '/HPF', NULL, NULL, 12);
    PERFORM pg_temp.seed_param(v_id, 'CASTS', 'Casts', 'Text', NULL, NULL, NULL, 13);
    PERFORM pg_temp.seed_param(v_id, 'CRYSTALS', 'Crystals', 'Text', NULL, NULL, NULL, 14);

    -- 44. Stool Routine & Microscopy
    v_id := pg_temp.seed_test('STOOL_RE', 'Stool Routine & Microscopic Examination (Stool R/E)', 'Stool R/E', 'Clinical Pathology', 'Stool Analysis', 'InHouse', 0, 'Fresh Stool Specimen', 'Stool Container with Spoon', 2, 440);
    PERFORM pg_temp.seed_param(v_id, 'STOOL_COLOUR', 'Colour', 'Text', NULL, NULL, NULL, 1);
    PERFORM pg_temp.seed_param(v_id, 'STOOL_CONSISTENCY', 'Consistency', 'Text', NULL, NULL, NULL, 2);
    PERFORM pg_temp.seed_param(v_id, 'STOOL_MUCUS', 'Mucus', 'Text', NULL, NULL, NULL, 3);
    PERFORM pg_temp.seed_param(v_id, 'STOOL_BLOOD', 'Gross Blood', 'Text', NULL, NULL, NULL, 4);
    PERFORM pg_temp.seed_param(v_id, 'STOOL_PUS', 'Pus Cells', 'Text', '/HPF', NULL, NULL, 5);
    PERFORM pg_temp.seed_param(v_id, 'STOOL_RBC', 'Red Blood Cells', 'Text', '/HPF', NULL, NULL, 6);
    PERFORM pg_temp.seed_param(v_id, 'STOOL_OVA', 'Ova / Helminths', 'Text', NULL, NULL, NULL, 7);
    PERFORM pg_temp.seed_param(v_id, 'STOOL_CYST', 'Protozoal Cysts', 'Text', NULL, NULL, NULL, 8);

    -- 45. Stool Occult Blood
    v_id := pg_temp.seed_test('STOOL_OB', 'Stool for Occult Blood (FOBT)', 'FOBT', 'Clinical Pathology', 'Stool Analysis', 'InHouse', 0, 'Fresh Stool Specimen', 'Stool Container', 2, 450);
    PERFORM pg_temp.seed_param(v_id, 'FOBT_RES', 'Occult Blood Result', 'Text', NULL, NULL, NULL, 1);

    -- ------------------------------------------------------------------------
    -- I. OTHER SPECIALIZED & HORMONE TESTS
    -- ------------------------------------------------------------------------
    -- 46. Vitamin D
    v_id := pg_temp.seed_test('VITAMIN_D', '25-Hydroxy Vitamin D (Total)', 'Vit D', 'Clinical Biochemistry', 'Vitamins', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 6, 460);
    PERFORM pg_temp.seed_param(v_id, 'VIT_D_VAL', '25-OH Vitamin D', 'Numeric', 'ng/mL', NULL, NULL, 1);

    -- 47. Vitamin B12
    v_id := pg_temp.seed_test('VITAMIN_B12', 'Vitamin B12 (Cyanocobalamin)', 'Vit B12', 'Clinical Biochemistry', 'Vitamins', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 6, 470);
    PERFORM pg_temp.seed_param(v_id, 'VIT_B12_VAL', 'Vitamin B12', 'Numeric', 'pg/mL', NULL, NULL, 1);

    -- 48. Ferritin
    v_id := pg_temp.seed_test('FERRITIN', 'Serum Ferritin', 'Ferritin', 'Clinical Biochemistry', 'Iron Studies', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 4, 480);
    PERFORM pg_temp.seed_param(v_id, 'FERRITIN_VAL', 'Serum Ferritin', 'Numeric', 'ng/mL', NULL, NULL, 1);

    -- 49. Iron
    v_id := pg_temp.seed_test('IRON', 'Serum Iron', 'Iron', 'Clinical Biochemistry', 'Iron Studies', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 4, 490);
    PERFORM pg_temp.seed_param(v_id, 'IRON_VAL', 'Serum Iron', 'Numeric', 'µg/dL', NULL, NULL, 1);

    -- 50. TIBC
    v_id := pg_temp.seed_test('TIBC', 'Total Iron Binding Capacity (TIBC)', 'TIBC', 'Clinical Biochemistry', 'Iron Studies', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 4, 500);
    PERFORM pg_temp.seed_param(v_id, 'TIBC_VAL', 'TIBC', 'Numeric', 'µg/dL', NULL, NULL, 1);

    -- 51. PSA
    v_id := pg_temp.seed_test('PSA', 'Prostate Specific Antigen (PSA, Total)', 'PSA', 'Serology & Immunology', 'Tumor Markers', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 6, 510);
    PERFORM pg_temp.seed_param(v_id, 'PSA_VAL', 'Total PSA', 'Numeric', 'ng/mL', NULL, NULL, 1);

    -- 52. Beta-hCG
    v_id := pg_temp.seed_test('BETA_HCG', 'Beta-Human Chorionic Gonadotropin (Beta-hCG)', 'Beta-hCG', 'Serology & Immunology', 'Hormones & Fertility', 'InHouse', 0, 'Serum', 'Yellow Top (SST)', 4, 520);
    PERFORM pg_temp.seed_param(v_id, 'HCG_VAL', 'Beta-hCG', 'Numeric', 'mIU/mL', NULL, NULL, 1);

END $$;

-- 4. Cleanup temporary seeding functions
DROP FUNCTION IF EXISTS pg_temp.seed_param(UUID, VARCHAR, VARCHAR, parameter_value_type_enum, VARCHAR, TEXT, TEXT[], INT);
DROP FUNCTION IF EXISTS pg_temp.seed_test(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, reporting_type_enum, BIGINT, VARCHAR, VARCHAR, INT, INT);
