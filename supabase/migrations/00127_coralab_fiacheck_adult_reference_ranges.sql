-- Migration: 00127_coralab_fiacheck_adult_reference_ranges.sql
-- Goal: Apply lab-approved adult clinical reference ranges for CORALAB ACE and FIAcheck analyzers.
--
-- Clinical Invariants Enforced:
-- 1. CORALAB ACE:
--    - Glucose Fasting (BIO-0001, mg/dL): 70 - 100
--    - Glucose PP (BIO-0003, mg/dL): < 140
--    - Glucose Random (BIO-0002, mg/dL): 70 - 140
--    - Urea (BIO-0008, mg/dL): 15 - 45
--    - BUN (BIO-0009, mg/dL): 7 - 20
--    - Creatinine (BIO-0010, mg/dL): Male 0.7 - 1.3 | Female 0.6 - 1.1
--    - Uric Acid (BIO-0012, mg/dL): Male 3.5 - 7.2 | Female 2.6 - 6.0
--    - Total Bilirubin (BIO-0017, mg/dL): 0.2 - 1.2
--    - Direct Bilirubin (BIO-0018, mg/dL): 0.0 - 0.3
--    - ALT / SGPT (BIO-0021, U/L): Male < 45 | Female < 35
--    - AST / SGOT (BIO-0020, U/L): Male < 40 | Female < 35
--    - ALP (BIO-0022, U/L): 44 - 147
--    - Total Protein (BIO-0013, g/dL): 6.4 - 8.3
--    - Albumin (BIO-0014, g/dL): 3.5 - 5.0
--    - Globulin (BIO-0015, g/dL): 2.0 - 3.5
--    - A/G Ratio (BIO-0016, ratio): 1.2 - 2.2
--    - Total Cholesterol (BIO-0027, mg/dL): < 200 (Desirable)
--    - Triglycerides (BIO-0028, mg/dL): < 150 (Normal)
--    - HDL Cholesterol (BIO-0029, mg/dL): Male > 40 | Female > 50
--    - LDL Cholesterol (BIO-0030 & BIO-0031, mg/dL): < 100 (Optimal)
--    - VLDL Cholesterol (BIO-0032, mg/dL): 10 - 30
--    - HbA1c (BIO-0006, %): < 5.7 (Normal: < 5.7% | Prediabetes: 5.7-6.4% | Diabetes: >= 6.5%)
--
-- 2. FIACHECK & RELATED IMMUNOASSAYS:
--    - Troponin I (BIO-0063, ng/mL): < 0.1 (< 0.1 ng/mL Normal | > 0.5 ng/mL MI Suspected)
--    - D-Dimer FEU (COA-0006, µg/mL FEU): < 0.50 (< 0.50 µg/mL FEU Normal | > 0.50 µg/mL FEU Thrombosis/PE Suspected)
--    - CK-MB Mass (BIO-0061, ng/mL): < 5.0 (< 5.0 ng/mL Normal | > 5.0 ng/mL Cardiac Injury Indicator)
--    - Standard CRP (IMM-0001, mg/L): < 6.0
--    - hs-CRP (BIO-0068, mg/L): < 1.0 (Low Risk: < 1.0 | Avg Risk: 1.0 - 3.0 | High Risk: > 3.0 mg/L)
--    - Procalcitonin (PCT_SEPSIS, ng/mL): < 0.05 (< 0.05 ng/mL Normal | > 0.5 ng/mL Systemic Infection)
--    - TSH (END-0001, µIU/mL): 0.40 - 4.20
--    - Total T3 (END-0005, ng/mL): 0.80 - 2.00 (equivalent to 80 - 200 ng/dL)
--    - Total T4 (END-0004, µg/dL): 5.0 - 12.0
--    - Free T3 (END-0003, pg/mL): 2.0 - 4.4
--    - Free T4 (END-0002, ng/dL): 0.9 - 1.7
--    - Ferritin (BIO-0050, ng/mL): Male 20 - 250 | Female 10 - 120
--
-- 3. Safety Invariants:
--    - Zero price changes.
--    - Zero analyzer reassignment (HbA1c on CORALAB, Standard CRP on manual/routine, CK-MB Mass on FIAcheck).
--    - Zero collision between CK-MB Mass (ng/mL) and CK-MB Activity (U/L).
--    - Zero collision between CBC Plateletcrit (PCT, %) and Procalcitonin (PCT_SEPSIS, ng/mL).
--    - Historical test results and signed report snapshots remain 100% immutable.

BEGIN;

DO $$
DECLARE
    v_param_id UUID;
BEGIN

    -- Helper procedure: upsert single range
    -- =========================================================================
    -- 1. CORALAB ACE: GLUCOSE & RENAL FUNCTION
    -- =========================================================================

    -- Glucose Fasting (BIO-0001) - 70 - 100 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0001' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 70.0, 100.0, '70 - 100 mg/dL', 'mg/dL', 'GOD-POD', TRUE, TRUE);
    END IF;

    -- Glucose PP (BIO-0003) - < 140 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0003' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 140.0, '< 140 mg/dL', 'mg/dL', 'GOD-POD', TRUE, TRUE);
    END IF;

    -- Glucose Random (BIO-0002) - 70 - 140 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0002' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 70.0, 140.0, '70 - 140 mg/dL', 'mg/dL', 'GOD-POD', TRUE, TRUE);
    END IF;

    -- Urea (BIO-0008) - 15 - 45 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0008' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 15.0, 45.0, '15 - 45 mg/dL', 'mg/dL', 'GLDH / Urease', TRUE, TRUE);
    END IF;

    -- BUN (BIO-0009) - 7 - 20 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0009' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 7.0, 20.0, '7 - 20 mg/dL', 'mg/dL', 'Calculated / Urease', TRUE, TRUE);
    END IF;

    -- Creatinine (BIO-0010) - Male 0.7 - 1.3 | Female 0.6 - 1.1 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0010' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 0.7, 1.3, '0.7 - 1.3 mg/dL', 'mg/dL', 'Modified Jaffe', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 0.6, 1.1, '0.6 - 1.1 mg/dL', 'mg/dL', 'Modified Jaffe', TRUE, TRUE);
    END IF;

    -- Uric Acid (BIO-0012) - Male 3.5 - 7.2 | Female 2.6 - 6.0 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0012' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 3.5, 7.2, '3.5 - 7.2 mg/dL', 'mg/dL', 'Uricase-PAP', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 2.6, 6.0, '2.6 - 6.0 mg/dL', 'mg/dL', 'Uricase-PAP', TRUE, TRUE);
    END IF;


    -- =========================================================================
    -- 2. CORALAB ACE: LIVER FUNCTION TESTS (LFT)
    -- =========================================================================

    -- Total Bilirubin (BIO-0017) - 0.2 - 1.2 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0017' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.2, 1.2, '0.2 - 1.2 mg/dL', 'mg/dL', 'Diazo / Jendrassik-Grof', TRUE, TRUE);
    END IF;

    -- Direct Bilirubin (BIO-0018) - 0.0 - 0.3 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0018' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.0, 0.3, '0.0 - 0.3 mg/dL', 'mg/dL', 'Diazo / Jendrassik-Grof', TRUE, TRUE);
    END IF;

    -- ALT / SGPT (BIO-0021) - Male < 45 | Female < 35 U/L
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0021' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, NULL, 45.0, '< 45 U/L', 'U/L', 'UV Kinetic (IFCC)', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, NULL, 35.0, '< 35 U/L', 'U/L', 'UV Kinetic (IFCC)', TRUE, TRUE);
    END IF;

    -- AST / SGOT (BIO-0020) - Male < 40 | Female < 35 U/L
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0020' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, NULL, 40.0, '< 40 U/L', 'U/L', 'UV Kinetic (IFCC)', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, NULL, 35.0, '< 35 U/L', 'U/L', 'UV Kinetic (IFCC)', TRUE, TRUE);
    END IF;

    -- ALP (BIO-0022) - 44 - 147 U/L
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0022' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 44.0, 147.0, '44 - 147 U/L', 'U/L', 'pNPP-AMP Kinetic', TRUE, TRUE);
    END IF;

    -- Total Protein (BIO-0013) - 6.4 - 8.3 g/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0013' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 6.4, 8.3, '6.4 - 8.3 g/dL', 'g/dL', 'Biuret', TRUE, TRUE);
    END IF;

    -- Albumin (BIO-0014) - 3.5 - 5.0 g/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0014' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 3.5, 5.0, '3.5 - 5.0 g/dL', 'g/dL', 'Bromocresol Green (BCG)', TRUE, TRUE);
    END IF;

    -- Globulin (BIO-0015) - 2.0 - 3.5 g/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0015' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 2.0, 3.5, '2.0 - 3.5 g/dL', 'g/dL', 'Calculated (TP - Albumin)', TRUE, TRUE);
    END IF;

    -- A/G Ratio (BIO-0016) - 1.2 - 2.2
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0016' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 1.2, 2.2, '1.2 - 2.2', 'ratio', 'Calculated', TRUE, TRUE);
    END IF;


    -- =========================================================================
    -- 3. CORALAB ACE: LIPID PROFILE & HBA1C
    -- =========================================================================

    -- Total Cholesterol (BIO-0027) - < 200 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0027' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 200.0, '< 200 mg/dL', 'Desirable: < 200 mg/dL | Borderline: 200-239 mg/dL | High: >= 240 mg/dL', 'mg/dL', 'CHOD-PAP', TRUE, TRUE);
    END IF;

    -- Triglycerides (BIO-0028) - < 150 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0028' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 150.0, '< 150 mg/dL', 'Normal: < 150 mg/dL | Borderline: 150-199 mg/dL | High: >= 200 mg/dL', 'mg/dL', 'GPO-PAP', TRUE, TRUE);
    END IF;

    -- HDL Cholesterol (BIO-0029) - Male > 40 | Female > 50 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0029' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 40.0, NULL, '> 40 mg/dL', 'mg/dL', 'Direct Enzymatic (Clearance)', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 50.0, NULL, '> 50 mg/dL', 'mg/dL', 'Direct Enzymatic (Clearance)', TRUE, TRUE);
    END IF;

    -- LDL Cholesterol Direct (BIO-0030) - < 100 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0030' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 100.0, '< 100 mg/dL', 'Optimal: < 100 mg/dL | Near Optimal: 100-129 mg/dL | Borderline: 130-159 mg/dL', 'mg/dL', 'Direct Enzymatic (Clearance)', TRUE, TRUE);
    END IF;

    -- LDL Cholesterol Calculated (BIO-0031) - < 100 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0031' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 100.0, '< 100 mg/dL', 'Optimal: < 100 mg/dL | Near Optimal: 100-129 mg/dL | Borderline: 130-159 mg/dL', 'mg/dL', 'Friedewald Calculation', TRUE, TRUE);
    END IF;

    -- VLDL Cholesterol (BIO-0032) - 10 - 30 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0032' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 10.0, 30.0, '10 - 30 mg/dL', 'mg/dL', 'Calculated (Triglycerides / 5)', TRUE, TRUE);
    END IF;

    -- HbA1c (BIO-0006) - < 5.7 %
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0006' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 5.7, '< 5.7 %', 'Normal: < 5.7% | Prediabetes: 5.7 - 6.4% | Diabetes: >= 6.5%', '%', 'Turbidimetric Immunoassay (CORALAB ACE)', TRUE, TRUE);
    END IF;


    -- =========================================================================
    -- 4. FIACHECK & IMMUNOASSAYS: CARDIAC, INFLAMMATORY & COAGULATION
    -- =========================================================================

    -- Troponin I (BIO-0063) - < 0.1 ng/mL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0063' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 0.1, '< 0.1 ng/mL', '< 0.1 ng/mL (Normal) | > 0.5 ng/mL (MI Suspected)', 'ng/mL', 'Fluorescence Immunoassay (FIAcheck)', TRUE, TRUE);
    END IF;

    -- D-Dimer FEU (COA-0006) - < 0.50 µg/mL FEU
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'COA-0006' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 0.5, '< 0.50 µg/mL FEU', '< 0.50 µg/mL FEU (Normal) | > 0.50 µg/mL FEU (Thrombosis/PE Suspected)', 'µg/mL FEU', 'Fluorescence Immunoassay (FIAcheck)', TRUE, TRUE);
    END IF;

    -- CK-MB Mass (BIO-0061) - < 5.0 ng/mL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0061' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 5.0, '< 5.0 ng/mL', '< 5.0 ng/mL (Normal) | > 5.0 ng/mL (Cardiac Injury Indicator)', 'ng/mL', 'Fluorescence Immunoassay (FIAcheck)', TRUE, TRUE);
    END IF;

    -- Standard CRP (IMM-0001) - < 6.0 mg/L
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'IMM-0001' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 6.0, '< 6.0 mg/L', 'mg/L', 'Turbidimetry / Immunoturbidimetry', TRUE, TRUE);
    END IF;

    -- hs-CRP (BIO-0068) - < 1.0 mg/L (Low Risk: < 1.0 | Avg Risk: 1.0 - 3.0 | High Risk: > 3.0 mg/L)
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0068' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 1.0, '< 1.0 mg/L', 'Low Risk: < 1.0 | Avg Risk: 1.0 - 3.0 | High Risk: > 3.0 mg/L', 'mg/L', 'Fluorescence Immunoassay (FIAcheck)', TRUE, TRUE);
    END IF;

    -- Procalcitonin (PCT_SEPSIS) - < 0.05 ng/mL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'PCT_SEPSIS' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 0.05, '< 0.05 ng/mL', '< 0.05 ng/mL (Normal) | > 0.5 ng/mL (Systemic Infection)', 'ng/mL', 'Fluorescence Immunoassay (FIAcheck)', TRUE, TRUE);
    END IF;


    -- =========================================================================
    -- 5. FIACHECK: THYROID HORMONES & FERRITIN
    -- =========================================================================

    -- TSH (END-0001) - 0.40 - 4.20 µIU/mL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'END-0001' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.40, 4.20, '0.40 - 4.20 µIU/mL', 'µIU/mL', 'Fluorescence Immunoassay (FIAcheck)', TRUE, TRUE);
    END IF;

    -- Total T3 / TT3 (END-0005) - 0.80 - 2.00 ng/mL (equivalent to 80 - 200 ng/dL)
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'END-0005' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.80, 2.00, '0.80 - 2.00 ng/mL', 'ng/mL', 'Fluorescence Immunoassay (FIAcheck)', TRUE, TRUE);
    END IF;

    -- Total T4 / TT4 (END-0004) - 5.0 - 12.0 µg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'END-0004' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 5.0, 12.0, '5.0 - 12.0 µg/dL', 'µg/dL', 'Fluorescence Immunoassay (FIAcheck)', TRUE, TRUE);
    END IF;

    -- Free T3 / FT3 (END-0003) - 2.0 - 4.4 pg/mL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'END-0003' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 2.0, 4.4, '2.0 - 4.4 pg/mL', 'pg/mL', 'Fluorescence Immunoassay (FIAcheck)', TRUE, TRUE);
    END IF;

    -- Free T4 / FT4 (END-0002) - 0.9 - 1.7 ng/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'END-0002' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.9, 1.7, '0.9 - 1.7 ng/dL', 'ng/dL', 'Fluorescence Immunoassay (FIAcheck)', TRUE, TRUE);
    END IF;

    -- Ferritin (BIO-0050) - Male 20 - 250 | Female 10 - 120 ng/mL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0050' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 20.0, 250.0, '20 - 250 ng/mL', 'ng/mL', 'Fluorescence Immunoassay (FIAcheck)', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 10.0, 120.0, '10 - 120 ng/mL', 'ng/mL', 'Fluorescence Immunoassay (FIAcheck)', TRUE, TRUE);
    END IF;

    -- =========================================================================
    -- 6. MANUAL TESTS: ESR WESTERGREN & STOOL OCCULT BLOOD
    -- =========================================================================

    -- ESR Westergren (HEM-0027) - mm/1st hr
    -- Male <= 50: 0 - 15 | Male > 50: 0 - 20
    -- Female <= 50: 0 - 20 | Female > 50: 0 - 30
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'HEM-0027' AND p.is_active = TRUE LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET unit = 'mm/1st hr' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 18262, 0.0, 15.0, '0 - 15 mm/1st hr', 'Adult Male (<= 50 yrs): 0 - 15 mm/1st hr', 'mm/1st hr', 'Westergren', TRUE, TRUE),
        (v_param_id, 'Male', 18263, 43800, 0.0, 20.0, '0 - 20 mm/1st hr', 'Adult Male (> 50 yrs): 0 - 20 mm/1st hr', 'mm/1st hr', 'Westergren', TRUE, TRUE),
        (v_param_id, 'Female', 0, 18262, 0.0, 20.0, '0 - 20 mm/1st hr', 'Adult Female (<= 50 yrs): 0 - 20 mm/1st hr', 'mm/1st hr', 'Westergren', TRUE, TRUE),
        (v_param_id, 'Female', 18263, 43800, 0.0, 30.0, '0 - 30 mm/1st hr', 'Adult Female (> 50 yrs): 0 - 30 mm/1st hr', 'mm/1st hr', 'Westergren', TRUE, TRUE);
    END IF;

    -- Stool Occult Blood (CLP-0025) & Fecal Occult Blood Test FOBT (CLP-0026) - Qualitative (Expected: Negative)
    FOR v_param_id IN 
        SELECT p.id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code IN ('CLP-0025', 'CLP-0026') AND p.is_active = TRUE
    LOOP
        UPDATE public.parameters 
        SET value_type = 'Select', 
            options = '["Negative", "Positive"]'::jsonb,
            unit = NULL
        WHERE id = v_param_id;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, reference_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, NULL, 'Negative', 'Expected: Negative', NULL, 'Manual / Rapid (Hemospot / Immunochromatographic)', TRUE, TRUE);
    END LOOP;

    -- Hemoglobin standalone (HEM-0002) - clean up legacy unapproved generic row so sex-specific ranges remain clean
    DELETE FROM public.reference_ranges 
    WHERE parameter_id IN (SELECT p.id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'HEM-0002') 
      AND gender = 'All';

END $$;

COMMIT;

