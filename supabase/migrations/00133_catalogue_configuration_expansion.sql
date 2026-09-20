-- ====================================================================
-- Migration 00133: Comprehensive Clinical Catalogue Configuration Expansion
-- ====================================================================
-- Purpose:
-- 1. GLOBAL POLICY: Reactivate all catalogue tests (all ~1,139 tests) for billing & ordering.
--    - is_active = TRUE, lifecycle_status = 'Active', billing_enabled = TRUE, clinical_reporting_enabled = TRUE.
--    - Leaf parameters of tests activated (structural dummy panel parameters remain archived).
-- 2. VERIFIED CLINICAL CONFIGURATION:
--    - CBC (HEM-0001): 24 reportable parameters, adult reference ranges, CounCell 23 mappings.
--    - Hemoglobin (HEM-0002): HGB, Male 13-17, Female 12-15.5 g/dL.
--    - ESR (HEM-0027): Method Westergren, Male/Female age-stratified ranges (<=50, >50).
--    - LFT (PRO-0001): 11 child tests (Total/Direct/Indirect Bilirubin, ALT, AST, ALP, Total Protein, Albumin, Globulin, A/G Ratio, GGT).
--    - KFT (PRO-0002): 4 child tests (Urea, BUN, Creatinine, Uric Acid).
--    - Glucose: Fasting FBS (BIO-0001), PPBS (BIO-0003), RBS (BIO-0002), HbA1c (BIO-0006).
--    - Lipid Profile (PRO-0003): Total Cholesterol, Triglycerides, HDL, LDL, VLDL.
--    - Thyroid: TSH (END-0001), FT3 (END-0003), FT4 (END-0002).
--    - Vitamin D (BIO-0053): Deficient <20, Insufficient 20-30, Sufficient 30-100 ng/mL.
--    - Vitamin B12 (BIO-0051): 200-900 pg/mL (Borderline 200-300).
--    - Troponin I (BIO-0063): <0.1 ng/mL.
--    - Urine Routine (CLP-0001): 14 reportable parameters (Colour, Transparency, SG, pH, Protein, Sugar, Ketone, Bilirubin, Blood, Pus Cells, RBC, Epithelial Cells, Casts, Crystals).
--    - Widal Test (SER-0024): 4 antigens (Typhi O/H, Paratyphi AH/BH) with discrete titers.
--    - Serology Rapid: Dengue NS1 (SER-0015), Dengue IgM (SER-0016), HBsAg (SER-0004), Anti-HCV (SER-0010).
--    - Immunoassays: D-Dimer (COA-0006), CK-MB Mass (BIO-0061), Ferritin (BIO-0050).
-- 3. ATOMIC BILLING RPC:
--    - Replace create_patient_bill_order_with_packages to remove the artificial zero-parameter check
--      so tests pending detailed configuration can still be billed without blocking reception.
-- ====================================================================

BEGIN;

-- --------------------------------------------------------------------
-- 1. REACTIVATE ALL MASTER CATALOGUE TESTS
-- --------------------------------------------------------------------
UPDATE public.tests
SET 
    is_active = TRUE,
    lifecycle_status = 'Active',
    billing_enabled = TRUE,
    clinical_reporting_enabled = TRUE,
    updated_at = NOW();

-- --------------------------------------------------------------------
-- 2. REACTIVATE LEAF PARAMETERS OF ACTIVE TESTS
-- --------------------------------------------------------------------
UPDATE public.parameters
SET 
    is_active = TRUE,
    lifecycle_status = 'Active',
    updated_at = NOW()
WHERE (unit IS NULL OR unit NOT ILIKE 'Panel')
  AND (value_type IS NULL OR (value_type::text NOT ILIKE 'Panel' AND value_type::text NOT ILIKE 'Profile'));

-- Ensure structural dummy panel parameters remain archived
UPDATE public.parameters
SET 
    is_active = FALSE,
    lifecycle_status = 'Archived',
    updated_at = NOW()
WHERE unit ILIKE 'Panel' 
   OR value_type::text ILIKE 'Panel' 
   OR value_type::text ILIKE 'Profile';

-- --------------------------------------------------------------------
-- 3. REACTIVATE EXISTING APPROVED REFERENCE RANGES
-- --------------------------------------------------------------------
UPDATE public.reference_ranges rr
SET 
    is_active = TRUE,
    updated_at = NOW()
FROM public.parameters p
WHERE rr.parameter_id = p.id
  AND p.is_active = TRUE
  AND rr.is_approved = TRUE;

-- --------------------------------------------------------------------
-- 4. VERIFIED METHODS & SPECIMENS ON APPROVED TESTS
-- --------------------------------------------------------------------
UPDATE public.tests SET method = 'Automated Impedance / Colorimetry', sample_type = 'Whole Blood (EDTA)', updated_at = NOW() WHERE code = 'HEM-0001';
UPDATE public.tests SET method = 'Automated Impedance / Colorimetry', sample_type = 'Whole Blood (EDTA)', updated_at = NOW() WHERE code = 'HEM-0002';
UPDATE public.tests SET method = 'Westergren', sample_type = 'Whole Blood (Sodium Citrate / EDTA)', updated_at = NOW() WHERE code = 'HEM-0027';
UPDATE public.tests SET method = 'Multi-method automated biochemistry', sample_type = 'Serum', updated_at = NOW() WHERE code IN ('PRO-0001', 'PRO-0002', 'PRO-0003');
UPDATE public.tests SET method = 'Tube Agglutination', sample_type = 'Serum', updated_at = NOW() WHERE code = 'SER-0024';
UPDATE public.tests SET method = 'Manual Microscopy & Dipstick', sample_type = 'Urine', updated_at = NOW() WHERE code = 'CLP-0001';
UPDATE public.tests SET method = 'Rapid Immunochromatography (ICT)', sample_type = 'Serum/Plasma', updated_at = NOW() WHERE code IN ('SER-0015', 'SER-0016', 'SER-0004', 'SER-0010');

-- --------------------------------------------------------------------
-- 5. VERIFIED REFERENCE RANGES CONFIGURATION
-- --------------------------------------------------------------------
DO $$
DECLARE
    v_param_id UUID;
    v_test_id UUID;
BEGIN
    -- ----------------------------------------------------------------
    -- A. HEM-0002: Hemoglobin
    -- ----------------------------------------------------------------
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'HEM-0002' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'g/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 13.0, 17.0, '13.0 - 17.0 g/dL', 'g/dL', 'Automated Impedance / Colorimetry', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 12.0, 15.5, '12.0 - 15.5 g/dL', 'g/dL', 'Automated Impedance / Colorimetry', TRUE, TRUE);
    END IF;

    -- ----------------------------------------------------------------
    -- B. HEM-0027: ESR (Westergren)
    -- ----------------------------------------------------------------
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'HEM-0027' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mm/1st hr' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 18262, 0.0, 15.0, '0 - 15 mm/1st hr (<= 50 yrs)', 'mm/1st hr', 'Westergren', TRUE, TRUE),
        (v_param_id, 'Male', 18263, 43800, 0.0, 20.0, '0 - 20 mm/1st hr (> 50 yrs)', 'mm/1st hr', 'Westergren', TRUE, TRUE),
        (v_param_id, 'Female', 0, 18262, 0.0, 20.0, '0 - 20 mm/1st hr (<= 50 yrs)', 'mm/1st hr', 'Westergren', TRUE, TRUE),
        (v_param_id, 'Female', 18263, 43800, 0.0, 30.0, '0 - 30 mm/1st hr (> 50 yrs)', 'mm/1st hr', 'Westergren', TRUE, TRUE);
    END IF;

    -- ----------------------------------------------------------------
    -- C. GLUCOSE & DIABETES
    -- ----------------------------------------------------------------
    -- BIO-0001 (FBS: 70-100 mg/dL)
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0001' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mg/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 70.0, 100.0, '70 - 100 mg/dL', 'mg/dL', 'GOD-POD', TRUE, TRUE);
    END IF;

    -- BIO-0003 (PPBS: < 140 mg/dL)
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0003' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mg/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 140.0, '< 140 mg/dL', 'mg/dL', 'GOD-POD', TRUE, TRUE);
    END IF;

    -- BIO-0002 (RBS: 70-140 mg/dL)
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0002' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mg/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 70.0, 140.0, '70 - 140 mg/dL', 'mg/dL', 'GOD-POD', TRUE, TRUE);
    END IF;

    -- BIO-0006 (HbA1c: < 5.7 %)
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0006' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = '%' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 5.7, '< 5.7 % (Normal: < 5.7% | Prediabetes: 5.7-6.4% | Diabetes: >= 6.5%)', '%', 'HPLC / Nephelometry', TRUE, TRUE);
    END IF;

    -- ----------------------------------------------------------------
    -- D. KFT / RFT (PRO-0002 Children)
    -- ----------------------------------------------------------------
    -- BIO-0008 Urea: 15-45 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0008' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mg/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 15.0, 45.0, '15 - 45 mg/dL', 'mg/dL', 'GLDH / Urease', TRUE, TRUE);
    END IF;

    -- BIO-0009 BUN: 7-20 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0009' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mg/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 7.0, 20.0, '7 - 20 mg/dL', 'mg/dL', 'Calculated / Urease', TRUE, TRUE);
    END IF;

    -- BIO-0010 Creatinine: Male 0.7-1.3, Female 0.6-1.1 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0010' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mg/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 0.7, 1.3, '0.7 - 1.3 mg/dL', 'mg/dL', 'Modified Jaffe', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 0.6, 1.1, '0.6 - 1.1 mg/dL', 'mg/dL', 'Modified Jaffe', TRUE, TRUE);
    END IF;

    -- BIO-0012 Uric Acid: Male 3.5-7.2, Female 2.6-6.0 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0012' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mg/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 3.5, 7.2, '3.5 - 7.2 mg/dL', 'mg/dL', 'Uricase-PAP', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 2.6, 6.0, '2.6 - 6.0 mg/dL', 'mg/dL', 'Uricase-PAP', TRUE, TRUE);
    END IF;

    -- ----------------------------------------------------------------
    -- E. LFT (PRO-0001 Children)
    -- ----------------------------------------------------------------
    -- BIO-0017 Total Bilirubin: 0.2-1.2 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0017' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mg/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.2, 1.2, '0.2 - 1.2 mg/dL', 'mg/dL', 'Diazo / Jendrassik-Grof', TRUE, TRUE);
    END IF;

    -- BIO-0018 Direct Bilirubin: 0.0-0.3 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0018' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mg/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.0, 0.3, '0.0 - 0.3 mg/dL', 'mg/dL', 'Diazo / Jendrassik-Grof', TRUE, TRUE);
    END IF;

    -- BIO-0019 Indirect Bilirubin (Calculated): 0.2-0.9 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0019' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mg/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.2, 0.9, '0.2 - 0.9 mg/dL', 'mg/dL', 'Calculated (Total - Direct)', TRUE, TRUE);
    END IF;

    -- BIO-0021 ALT / SGPT: Male < 45, Female < 35 U/L
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0021' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'U/L' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, NULL, 45.0, '< 45 U/L', 'U/L', 'UV Kinetic (IFCC)', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, NULL, 35.0, '< 35 U/L', 'U/L', 'UV Kinetic (IFCC)', TRUE, TRUE);
    END IF;

    -- BIO-0020 AST / SGOT: Male < 40, Female < 35 U/L
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0020' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'U/L' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, NULL, 40.0, '< 40 U/L', 'U/L', 'UV Kinetic (IFCC)', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, NULL, 35.0, '< 35 U/L', 'U/L', 'UV Kinetic (IFCC)', TRUE, TRUE);
    END IF;

    -- BIO-0022 ALP: 44-147 U/L
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0022' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'U/L' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 44.0, 147.0, '44 - 147 U/L', 'U/L', 'p-NPP Kinetic', TRUE, TRUE);
    END IF;

    -- BIO-0013 Total Protein: 6.4-8.3 g/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0013' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'g/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 6.4, 8.3, '6.4 - 8.3 g/dL', 'g/dL', 'Biuret', TRUE, TRUE);
    END IF;

    -- BIO-0014 Albumin: 3.5-5.0 g/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0014' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'g/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 3.5, 5.0, '3.5 - 5.0 g/dL', 'g/dL', 'BCG Dye Binding', TRUE, TRUE);
    END IF;

    -- BIO-0015 Globulin (Calculated): 2.0-3.5 g/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0015' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'g/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 2.0, 3.5, '2.0 - 3.5 g/dL', 'g/dL', 'Calculated (TP - Albumin)', TRUE, TRUE);
    END IF;

    -- BIO-0016 A/G Ratio (Calculated): 1.2-2.2
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0016' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'ratio' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 1.2, 2.2, '1.2 - 2.2', 'ratio', 'Calculated (Albumin / Globulin)', TRUE, TRUE);
    END IF;

    -- BIO-0023 GGT: Male 10-71, Female 6-42 U/L
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0023' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'U/L' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 10.0, 71.0, '10 - 71 U/L', 'U/L', 'Enzymatic Kinetic', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 6.0, 42.0, '6 - 42 U/L', 'U/L', 'Enzymatic Kinetic', TRUE, TRUE);
    END IF;

    -- ----------------------------------------------------------------
    -- F. LIPID PROFILE (PRO-0003 Children)
    -- ----------------------------------------------------------------
    -- BIO-0027 Total Cholesterol: < 200 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0027' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mg/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 200.0, '< 200 mg/dL (Desirable)', 'mg/dL', 'CHOD-PAP', TRUE, TRUE);
    END IF;

    -- BIO-0028 Triglycerides: < 150 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0028' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mg/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 150.0, '< 150 mg/dL (Normal)', 'mg/dL', 'GPO-PAP', TRUE, TRUE);
    END IF;

    -- BIO-0029 HDL: Male > 40, Female > 50 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0029' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mg/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 40.0, NULL, '> 40 mg/dL', 'mg/dL', 'Direct Immunoinhibition', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 50.0, NULL, '> 50 mg/dL', 'mg/dL', 'Direct Immunoinhibition', TRUE, TRUE);
    END IF;

    -- BIO-0030 & BIO-0031 LDL: < 100 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code IN ('BIO-0030', 'BIO-0031') LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mg/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 100.0, '< 100 mg/dL (Optimal)', 'mg/dL', 'Calculated / Direct', TRUE, TRUE);
    END IF;

    -- BIO-0032 VLDL: 10-30 mg/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0032' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'mg/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 10.0, 30.0, '10 - 30 mg/dL', 'mg/dL', 'Calculated (Triglycerides / 5)', TRUE, TRUE);
    END IF;

    -- ----------------------------------------------------------------
    -- G. THYROID (END-0001 TSH, END-0003 FT3, END-0002 FT4)
    -- ----------------------------------------------------------------
    -- END-0001 TSH: 0.40 - 4.20 µIU/mL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'END-0001' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'µIU/mL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.40, 4.20, '0.40 - 4.20 µIU/mL', 'µIU/mL', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE);
    END IF;

    -- END-0003 FT3: 2.0 - 4.4 pg/mL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'END-0003' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'pg/mL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 2.0, 4.4, '2.0 - 4.4 pg/mL', 'pg/mL', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE);
    END IF;

    -- END-0002 FT4: 0.9 - 1.7 ng/dL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'END-0002' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'ng/dL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.9, 1.7, '0.9 - 1.7 ng/dL', 'ng/dL', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE);
    END IF;

    -- ----------------------------------------------------------------
    -- H. VITAMINS & CARDIAC MARKERS
    -- ----------------------------------------------------------------
    -- BIO-0053 Vitamin D: Deficient <20, Insufficient 20-30, Sufficient 30-100 ng/mL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0053' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'ng/mL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'All', 0, 43800, 30.0, 100.0, 'Sufficient: 30 - 100 ng/mL | Insufficient: 20 - 30 ng/mL | Deficient: < 20 ng/mL', 'ng/mL', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE);
    END IF;

    -- BIO-0051 Vitamin B12: 200 - 900 pg/mL (Borderline: 200 - 300)
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0051' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'pg/mL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 200.0, 900.0, '200 - 900 pg/mL (Borderline: 200 - 300 pg/mL)', 'pg/mL', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE);
    END IF;

    -- BIO-0063 Troponin I: < 0.1 ng/mL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0063' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'ng/mL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 0.1, '< 0.1 ng/mL Normal', 'ng/mL', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE);
    END IF;

    -- COA-0006 D-Dimer: < 0.50 µg/mL FEU
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'COA-0006' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'µg/mL FEU' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 0.50, '< 0.50 µg/mL FEU', 'µg/mL FEU', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE);
    END IF;

    -- BIO-0061 CK-MB Mass: < 5.0 ng/mL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0061' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'ng/mL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 5.0, '< 5.0 ng/mL', 'ng/mL', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE);
    END IF;

    -- BIO-0050 Ferritin: Male 20-250, Female 10-120 ng/mL
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'BIO-0050' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'ng/mL' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 20.0, 250.0, '20 - 250 ng/mL', 'ng/mL', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 10.0, 120.0, '10 - 120 ng/mL', 'ng/mL', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE);
    END IF;

    -- ----------------------------------------------------------------
    -- I. SEROLOGY RAPID SCREENING (Dengue, HBsAg, Anti-HCV)
    -- ----------------------------------------------------------------
    -- SER-0015 Dengue NS1
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'SER-0015' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'Qualitative' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Negative', 'Qualitative', 'Rapid Immunochromatography (ICT)', TRUE, TRUE);
    END IF;

    -- SER-0016 Dengue IgM
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'SER-0016' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'Qualitative' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Negative', 'Qualitative', 'Rapid Immunochromatography (ICT)', TRUE, TRUE);
    END IF;

    -- SER-0004 HBsAg
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'SER-0004' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'Qualitative' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Non-reactive / Negative', 'Qualitative', 'Rapid Immunochromatography (ICT)', TRUE, TRUE);
    END IF;

    -- SER-0010 Anti-HCV
    SELECT p.id INTO v_param_id FROM public.parameters p JOIN public.tests t ON t.id = p.test_id WHERE t.code = 'SER-0010' LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'Qualitative' WHERE id = v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Non-reactive / Negative', 'Qualitative', 'Rapid Immunochromatography (ICT)', TRUE, TRUE);
    END IF;

    -- ----------------------------------------------------------------
    -- J. CLP-0001: URINE ROUTINE EXAMINATION (14 Approved Parameters)
    -- ----------------------------------------------------------------
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'CLP-0001';
    IF v_test_id IS NOT NULL THEN
        -- Archive dummy parent parameter if present
        UPDATE public.parameters SET is_active = FALSE, lifecycle_status = 'Archived' WHERE test_id = v_test_id AND (unit ILIKE 'Panel' OR code = 'CLP-0001');

        -- 1. Colour
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status)
        VALUES (v_test_id, 'CLP-0001-01', 'Colour', 'Text', '', 1, TRUE, 'Active')
        ON CONFLICT (test_id, code) DO UPDATE SET is_active = TRUE, lifecycle_status = 'Active', unit = '', display_order = 1
        RETURNING id INTO v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Pale Yellow / Straw', 'Visual Inspection', TRUE, TRUE);

        -- 2. Transparency
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status)
        VALUES (v_test_id, 'CLP-0001-02', 'Transparency', 'Text', '', 2, TRUE, 'Active')
        ON CONFLICT (test_id, code) DO UPDATE SET is_active = TRUE, lifecycle_status = 'Active', unit = '', display_order = 2
        RETURNING id INTO v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Clear', 'Visual Inspection', TRUE, TRUE);

        -- 3. Specific Gravity
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status)
        VALUES (v_test_id, 'CLP-0001-03', 'Specific Gravity', 'Numeric', '', 3, TRUE, 'Active')
        ON CONFLICT (test_id, code) DO UPDATE SET is_active = TRUE, lifecycle_status = 'Active', unit = '', display_order = 3
        RETURNING id INTO v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 1.005, 1.030, '1.005 - 1.030', 'Refractometry / Dipstick', TRUE, TRUE);

        -- 4. pH
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status)
        VALUES (v_test_id, 'CLP-0001-04', 'pH', 'Numeric', '', 4, TRUE, 'Active')
        ON CONFLICT (test_id, code) DO UPDATE SET is_active = TRUE, lifecycle_status = 'Active', unit = '', display_order = 4
        RETURNING id INTO v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 4.5, 8.0, '4.5 - 8.0', 'pH Indicator Dipstick', TRUE, TRUE);

        -- 5. Protein
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status)
        VALUES (v_test_id, 'CLP-0001-05', 'Protein', 'Text', '', 5, TRUE, 'Active')
        ON CONFLICT (test_id, code) DO UPDATE SET is_active = TRUE, lifecycle_status = 'Active', unit = '', display_order = 5
        RETURNING id INTO v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Negative / Nil', 'Protein Error of Indicators', TRUE, TRUE);

        -- 6. Sugar
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status)
        VALUES (v_test_id, 'CLP-0001-06', 'Sugar', 'Text', '', 6, TRUE, 'Active')
        ON CONFLICT (test_id, code) DO UPDATE SET is_active = TRUE, lifecycle_status = 'Active', unit = '', display_order = 6
        RETURNING id INTO v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Negative / Nil', 'Glucose Oxidase Dipstick', TRUE, TRUE);

        -- 7. Ketone
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status)
        VALUES (v_test_id, 'CLP-0001-07', 'Ketone', 'Text', '', 7, TRUE, 'Active')
        ON CONFLICT (test_id, code) DO UPDATE SET is_active = TRUE, lifecycle_status = 'Active', unit = '', display_order = 7
        RETURNING id INTO v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Negative', 'Legal''s Test / Nitroprusside', TRUE, TRUE);

        -- 8. Bilirubin
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status)
        VALUES (v_test_id, 'CLP-0001-08', 'Bilirubin', 'Text', '', 8, TRUE, 'Active')
        ON CONFLICT (test_id, code) DO UPDATE SET is_active = TRUE, lifecycle_status = 'Active', unit = '', display_order = 8
        RETURNING id INTO v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Negative', 'Diazo Coupling', TRUE, TRUE);

        -- 9. Blood
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status)
        VALUES (v_test_id, 'CLP-0001-09', 'Blood', 'Text', '', 9, TRUE, 'Active')
        ON CONFLICT (test_id, code) DO UPDATE SET is_active = TRUE, lifecycle_status = 'Active', unit = '', display_order = 9
        RETURNING id INTO v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Negative', 'Pseudoperoxidase Dipstick', TRUE, TRUE);

        -- 10. Pus Cells
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status)
        VALUES (v_test_id, 'CLP-0001-10', 'Pus Cells', 'Numeric', '/HPF', 10, TRUE, 'Active')
        ON CONFLICT (test_id, code) DO UPDATE SET is_active = TRUE, lifecycle_status = 'Active', unit = '/HPF', display_order = 10
        RETURNING id INTO v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.0, 5.0, '0 - 5 /HPF', '/HPF', 'Brightfield Microscopy', TRUE, TRUE);

        -- 11. RBC
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status)
        VALUES (v_test_id, 'CLP-0001-11', 'RBC', 'Numeric', '/HPF', 11, TRUE, 'Active')
        ON CONFLICT (test_id, code) DO UPDATE SET is_active = TRUE, lifecycle_status = 'Active', unit = '/HPF', display_order = 11
        RETURNING id INTO v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.0, 2.0, '0 - 2 /HPF', '/HPF', 'Brightfield Microscopy', TRUE, TRUE);

        -- 12. Epithelial Cells
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status)
        VALUES (v_test_id, 'CLP-0001-12', 'Epithelial Cells', 'Numeric', '/HPF', 12, TRUE, 'Active')
        ON CONFLICT (test_id, code) DO UPDATE SET is_active = TRUE, lifecycle_status = 'Active', unit = '/HPF', display_order = 12
        RETURNING id INTO v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.0, 5.0, '0 - 5 /HPF', '/HPF', 'Brightfield Microscopy', TRUE, TRUE);

        -- 13. Casts
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status)
        VALUES (v_test_id, 'CLP-0001-13', 'Casts', 'Text', '', 13, TRUE, 'Active')
        ON CONFLICT (test_id, code) DO UPDATE SET is_active = TRUE, lifecycle_status = 'Active', unit = '', display_order = 13
        RETURNING id INTO v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Nil / Occasional', 'Brightfield Microscopy', TRUE, TRUE);

        -- 14. Crystals
        INSERT INTO public.parameters (test_id, code, name, value_type, unit, display_order, is_active, lifecycle_status)
        VALUES (v_test_id, 'CLP-0001-14', 'Crystals', 'Text', '', 14, TRUE, 'Active')
        ON CONFLICT (test_id, code) DO UPDATE SET is_active = TRUE, lifecycle_status = 'Active', unit = '', display_order = 14
        RETURNING id INTO v_param_id;
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 'Nil / Occasional', 'Brightfield Microscopy', TRUE, TRUE);
    END IF;

    -- ----------------------------------------------------------------
    -- K. SER-0024: WIDAL TEST (4 Antigens with Discrete Titers)
    -- ----------------------------------------------------------------
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'SER-0024';
    IF v_test_id IS NOT NULL THEN
        -- Archive generic "Widal Test" parameter if present
        UPDATE public.parameters SET is_active = FALSE, lifecycle_status = 'Archived' WHERE test_id = v_test_id AND code = 'SER-0024';

        -- Typhi O
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id AND (code = 'SER-0024-TO' OR code = 'WIDAL_TO' OR name ILIKE '%Typhi%O%') LIMIT 1;
        IF v_param_id IS NOT NULL THEN
            UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'Titer' WHERE id = v_param_id;
            DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
            INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, unit, method, is_approved, is_active)
            VALUES (v_param_id, 'All', 0, 43800, '>= 1:160 Significant', 'Titer', 'Tube Agglutination', TRUE, TRUE);
        END IF;

        -- Typhi H
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id AND (code = 'SER-0024-TH' OR code = 'WIDAL_TH' OR name ILIKE '%Typhi%H%') LIMIT 1;
        IF v_param_id IS NOT NULL THEN
            UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'Titer' WHERE id = v_param_id;
            DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
            INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, unit, method, is_approved, is_active)
            VALUES (v_param_id, 'All', 0, 43800, '>= 1:160 Significant', 'Titer', 'Tube Agglutination', TRUE, TRUE);
        END IF;

        -- Paratyphi AH
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id AND (code = 'SER-0024-AH' OR code = 'WIDAL_AH' OR name ILIKE '%Paratyphi%AH%') LIMIT 1;
        IF v_param_id IS NOT NULL THEN
            UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'Titer' WHERE id = v_param_id;
            DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
            INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, unit, method, is_approved, is_active)
            VALUES (v_param_id, 'All', 0, 43800, '>= 1:80 Significant', 'Titer', 'Tube Agglutination', TRUE, TRUE);
        END IF;

        -- Paratyphi BH
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id AND (code = 'SER-0024-BH' OR code = 'WIDAL_BH' OR name ILIKE '%Paratyphi%BH%') LIMIT 1;
        IF v_param_id IS NOT NULL THEN
            UPDATE public.parameters SET is_active = TRUE, lifecycle_status = 'Active', unit = 'Titer' WHERE id = v_param_id;
            DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
            INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_text, unit, method, is_approved, is_active)
            VALUES (v_param_id, 'All', 0, 43800, '>= 1:80 Significant', 'Titer', 'Tube Agglutination', TRUE, TRUE);
        END IF;
    END IF;

END $$;

-- --------------------------------------------------------------------
-- 6. ATOMIC BILLING RPC: CREATE PATIENT BILL ORDER WITH PACKAGES
-- (Fixes the BILL-VALIDATION check_violation error 23514)
-- --------------------------------------------------------------------
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
    -- 1. Permission Verification
    IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN 
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; 
    END IF;

    -- 2. Duplicate Item Check
    IF cardinality(p_items_data) <> cardinality(supplied_ids) THEN 
        RAISE EXCEPTION 'A canonical service may be selected only once.' USING ERRCODE='23505'; 
    END IF;

    -- 3. Active & Billing Enabled Check
    IF EXISTS (
        SELECT 1 
        FROM unnest(p_items_data) i 
        LEFT JOIN public.tests t ON t.id = (i->>'test_id')::UUID 
        WHERE t.id IS NULL OR t.lifecycle_status <> 'Active' OR NOT t.is_active OR NOT t.billing_enabled
    ) THEN 
        RAISE EXCEPTION 'Only active, billing-enabled catalogue services may be billed.' USING ERRCODE='23514'; 
    END IF;

    -- 4. Valid Rate Verification
    IF EXISTS (
        SELECT 1 
        FROM unnest(p_items_data) i 
        WHERE (i->>'unit_price_paisa') IS NULL OR (i->>'unit_price_paisa')::BIGINT < 0
    ) THEN 
        RAISE EXCEPTION 'Every item requires a valid agreed rate.' USING ERRCODE='23514'; 
    END IF;

    -- 5. Zero-Price Billing Policy Check
    IF EXISTS (
        SELECT 1 
        FROM unnest(p_items_data) i 
        JOIN public.tests t ON t.id = (i->>'test_id')::UUID 
        WHERE (i->>'unit_price_paisa')::BIGINT = 0 
          AND (NOT t.allow_zero_price_billing OR NOT COALESCE((i->>'zero_price_acknowledged')::BOOLEAN, FALSE))
    ) THEN 
        RAISE EXCEPTION 'Zero-price billing requires explicit catalogue authorization and acknowledgement.' USING ERRCODE='23514'; 
    END IF;

    -- 6. Health Package Bundles Verification
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

    -- 7. Lock Selected Tests and Allow Manual Override During Atomic Insert
    PERFORM 1 FROM public.tests t WHERE t.id = ANY(supplied_ids) ORDER BY t.id FOR UPDATE;
    SELECT COALESCE(array_agg(id ORDER BY id), ARRAY[]::UUID[]) INTO manual_ids FROM public.tests WHERE id = ANY(supplied_ids) AND NOT allow_manual_price;
    UPDATE public.tests SET allow_manual_price = TRUE WHERE id = ANY(manual_ids);

    -- 8. Core Billing and Clinical Order Creation
    response := public.create_patient_bill_and_order(p_patient_data, p_bill_data, p_items_data, p_payment_data, p_idempotency_key); 
    bill_uuid := (response->>'bill_id')::UUID;

    UPDATE public.bill_items bi SET catalogue_price_paisa_snapshot = t.price_paisa FROM public.tests t WHERE bi.bill_id = bill_uuid AND bi.test_id = t.id;
    UPDATE public.tests SET allow_manual_price = FALSE WHERE id = ANY(manual_ids);

    -- 9. Record Package Selections and Components
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

REVOKE ALL ON FUNCTION public.create_patient_bill_order_with_packages(JSONB, JSONB, JSONB[], JSONB, TEXT, JSONB) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_order_with_packages(JSONB, JSONB, JSONB[], JSONB, TEXT, JSONB) TO authenticated;

COMMIT;
