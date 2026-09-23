-- Migration 00109: FIAcheck Fluorescence Immunoassay Analyzer Integration
--
-- Analyzer Specifications:
-- - Analyzer Code: FIACHECK
-- - Instrument ID: INST-FIA-CHECK01
-- - Analyzer Name: FIAcheck
-- - Model: FIAcheck
-- - Manufacturer: Configurable / Pending Laboratory Confirmation (FIAcheck Diagnostics)
-- - Analyzer Class: Quantitative Epifluorescence / Fluorescence Immunoassay Analyzer
-- - Department: Endocrinology / Immunology / Special Chemistry
-- - Laboratory Location: Immunoassay Laboratory
-- - Capabilities: Quantitative Epifluorescence, LED TRFIA, Test Cartridges / Strips, RFID/QR/Smart Card Calibration
-- - Connectivity: RS-232, USB, Ethernet LAN (Bi-directional LIS capable)
--
-- Clinical Modules Configured:
-- 1. Thyroid Assays: TSH, FT3, FT4, TT3, TT4, Thyroid Panel
-- 2. Vitamin Assays: 25-OH Vitamin D (Interpretation Bands), Vitamin B12 (Interpretation Bands)
-- 3. Cardiac Markers: Troponin I (Decision Cut-offs), CK-MB Mass (ng/mL), Myoglobin (Sex-specific), NT-proBNP (Age-stratified thresholds), D-Dimer (µg/mL FEU)
-- 4. Inflammatory & Sepsis: hs-CRP (Cardiovascular Risk Bands), Procalcitonin (Sepsis Probability Bands)
-- 5. Reproductive & Other: Quantitative Beta-hCG, Ferritin (Sex-specific)
-- 6. Panels: IMM-THYROID, IMM-VITAMINS, IMM-CARDIAC, IMM-INFLAMMATION

BEGIN;

-- 1. Create or Update FIAcheck Analyzer Master Record
INSERT INTO public.analyzers (
    code,
    name,
    manufacturer,
    model,
    laboratory_location,
    lifecycle_status,
    row_version
) VALUES (
    'FIACHECK',
    'FIAcheck',
    'FIAcheck Diagnostics (Configurable)',
    'FIAcheck',
    'Immunoassay Laboratory',
    'Active',
    1
)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    model = EXCLUDED.model,
    laboratory_location = EXCLUDED.laboratory_location,
    lifecycle_status = 'Active',
    row_version = public.analyzers.row_version + 1,
    updated_at = NOW();

-- 2. Populate Analyzer Parameter Channels & Configure Clinical Tests
DO $$
DECLARE
    v_analyzer_id UUID;
    v_test_id UUID;
    v_param_id UUID;
    v_panel_id UUID;
    v_comp_id UUID;
BEGIN
    SELECT id INTO v_analyzer_id FROM public.analyzers WHERE code = 'FIACHECK';

    -- =========================================================================
    -- GROUP 1: THYROID ASSAYS
    -- =========================================================================

    -- TSH (END-0001)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0001';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'µIU/mL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Quantitative fluorescence immunoassay on FIAcheck'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'µIU/mL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'TSH', 'Thyroid Stimulating Hormone (TSH)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'µIU/mL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.40, 4.20, '0.40 - 4.20 µIU/mL', 'µIU/mL', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_TSH',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Immunoassay Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'TSH', 'Synonym'), (v_test_id, 'Thyroid Stimulating Hormone', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Free T3 / FT3 (END-0003)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0003';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'pg/mL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Quantitative fluorescence immunoassay on FIAcheck'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'pg/mL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'FT3', 'Free Triiodothyronine (FT3)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'pg/mL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 2.0, 4.4, '2.0 - 4.4 pg/mL', 'pg/mL', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_FT3',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Immunoassay Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'FT3', 'Synonym'), (v_test_id, 'Free T3', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Free T4 / FT4 (END-0002)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0002';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'ng/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Quantitative fluorescence immunoassay on FIAcheck'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'ng/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'FT4', 'Free Thyroxine (FT4)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.82, 1.77, '0.82 - 1.77 ng/dL', 'ng/dL', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_FT4',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Immunoassay Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'FT4', 'Synonym'), (v_test_id, 'Free T4', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Total T3 / TT3 (END-0005)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0005';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'ng/mL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Quantitative fluorescence immunoassay on FIAcheck'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'ng/mL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'TT3', 'Total Triiodothyronine (Total T3)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.80, 2.00, '0.80 - 2.00 ng/mL', 'ng/mL', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_TT3',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Immunoassay Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'TT3', 'Synonym'), (v_test_id, 'Total T3', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Total T4 / TT4 (END-0004)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0004';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'µg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Quantitative fluorescence immunoassay on FIAcheck'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'µg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'TT4', 'Total Thyroxine (Total T4)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'µg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 5.1, 14.1, '5.1 - 14.1 µg/dL', 'µg/dL', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_TT4',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Immunoassay Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'TT4', 'Synonym'), (v_test_id, 'Total T4', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- =========================================================================
    -- GROUP 2: VITAMINS
    -- =========================================================================

    -- 25-OH Vitamin D (BIO-0053 - Interpretation Bands)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0053';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'ng/mL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Quantitative 25-OH Vitamin D with clinical interpretation bands'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'ng/mL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'VIT_D', '25-OH Vitamin D', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 30, 100, '30 - 100 ng/mL (Sufficient; <20 Deficient, 20-29 Insufficient, >100 Toxicity Risk)', 'ng/mL', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_VIT_D',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Immunoassay Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Vitamin D', 'Synonym'), (v_test_id, '25-OH Vitamin D', 'Synonym'), (v_test_id, 'VIT_D', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Vitamin B12 (BIO-0051 - Interpretation Bands)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0051';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'pg/mL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Quantitative Vitamin B12 with clinical interpretation bands'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'pg/mL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'VIT_B12', 'Vitamin B12', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'pg/mL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 300, 900, '300 - 900 pg/mL (Normal; <200 Deficient, 200-300 Borderline)', 'pg/mL', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_VIT_B12',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Immunoassay Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Vitamin B12', 'Synonym'), (v_test_id, 'Vit B12', 'Synonym'), (v_test_id, 'Cyanocobalamin', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- =========================================================================
    -- GROUP 3: CARDIAC MARKERS
    -- =========================================================================

    -- Cardiac Troponin I (BIO-0063 - Decision Cut-offs)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0063';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'ng/mL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Quantitative Cardiac Troponin I with assay decision thresholds'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'ng/mL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'CTNI', 'Cardiac Troponin I (cTnI)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 0.04, '<0.04 ng/mL (Negative; 0.04-0.30 Borderline, >0.30 Positive/Myocardial Injury)', 'ng/mL', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_CTNI',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Cardiac Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Troponin I', 'Synonym'), (v_test_id, 'cTnI', 'Synonym'), (v_test_id, 'CTNI', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- CK-MB Mass (BIO-0061 - ng/mL - Distinct from Activity!)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0061';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'ng/mL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Quantitative CK-MB Mass immunoassay in ng/mL'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'ng/mL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'CKMB_MASS', 'CK-MB Mass', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 5.0, '<5.0 ng/mL', 'ng/mL', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_CKMB_M',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Cardiac Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'CK-MB Mass', 'Synonym'), (v_test_id, 'CKMB Mass', 'Synonym'), (v_test_id, 'CKMB_MASS', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Myoglobin (BIO-0065 - Sex-specific)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0065';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'ng/mL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Quantitative Myoglobin immunoassay'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'ng/mL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'MYO', 'Myoglobin', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, NULL, 72.0, '<72 ng/mL', 'ng/mL', 'Fluorescence Immunoassay', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, NULL, 58.0, '<58 ng/mL', 'ng/mL', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_MYO',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Cardiac Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Myoglobin', 'Synonym'), (v_test_id, 'MYO', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- NT-proBNP (BIO-0067 - Age-Stratified Thresholds)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0067';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'pg/mL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Quantitative NT-proBNP with age-stratified rule-out cutoffs'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'pg/mL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'NT_PROBNP', 'NT-proBNP', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'pg/mL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'All', 0, 18262, NULL, 450, '<450 pg/mL (<50 years)', 'pg/mL', 'Fluorescence Immunoassay', TRUE, TRUE),
        (v_param_id, 'All', 18263, 27393, NULL, 900, '<900 pg/mL (50-75 years)', 'pg/mL', 'Fluorescence Immunoassay', TRUE, TRUE),
        (v_param_id, 'All', 27394, 43800, NULL, 1800, '<1800 pg/mL (>75 years)', 'pg/mL', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_NT_PROBNP',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Cardiac Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'NT-proBNP', 'Synonym'), (v_test_id, 'NT_PROBNP', 'Synonym'), (v_test_id, 'N-Terminal proBNP', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- D-Dimer (COA-0006 - µg/mL FEU)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'COA-0006';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'µg/mL FEU',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Quantitative D-Dimer (Fibrinogen Equivalent Units, FEU)'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'µg/mL FEU' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'D_DIMER', 'D-Dimer (FEU)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'µg/mL FEU', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 0.50, '<0.50 µg/mL FEU', 'µg/mL FEU', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_DDIMER',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Coagulation Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'D-Dimer', 'Synonym'), (v_test_id, 'D_DIMER', 'Synonym'), (v_test_id, 'D-Dimer FEU', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- =========================================================================
    -- GROUP 4: INFLAMMATORY & SEPSIS
    -- =========================================================================

    -- High Sensitivity CRP / hs-CRP (BIO-0068 - Cardiovascular Risk Bands)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0068';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'mg/L',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'High Sensitivity CRP for cardiovascular risk stratification'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/L' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'HS_CRP', 'High Sensitivity CRP (hs-CRP)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'mg/L', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 1.0, '<1.0 mg/L (Low Risk; 1.0-3.0 Moderate Risk, >3.0 High Cardiovascular Risk)', 'mg/L', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_HSCRP',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Immunoassay Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'hs-CRP', 'Synonym'), (v_test_id, 'hsCRP', 'Synonym'), (v_test_id, 'High Sensitivity CRP', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Procalcitonin (PCT_SEPSIS / PROCALCITONIN)
    SELECT id INTO v_test_id FROM public.tests WHERE code IN ('PCT_SEPSIS', 'PROCALCITONIN');
    IF v_test_id IS NULL THEN
        -- Insert Procalcitonin canonical test if not existing
        INSERT INTO public.tests (
            code, name, short_name, department, subdepartment, category,
            test_type, specimen_type, container, container_type, sample_type,
            method, unit, tat_description, report_data_type,
            fasting_required, is_outsource, is_active, validation_status, notes,
            price_paisa, price_configured, allow_zero_price_billing, display_order
        ) VALUES (
            'PCT_SEPSIS', 'Procalcitonin (PCT)', 'PCT_SEPSIS', 'Immunology', 'Special Chemistry', 'Special Chemistry',
            'Single', 'Serum', 'Yellow Top (SST)', 'Yellow Top (SST)', 'Serum',
            'Fluorescence Immunoassay', 'ng/mL', 'Routine', 'Numeric',
            FALSE, FALSE, TRUE, 'VALIDATED', 'Quantitative Procalcitonin sepsis risk marker',
            0, FALSE, TRUE, 0
        ) RETURNING id INTO v_test_id;

        INSERT INTO public.parameters (test_id, code, name, unit, value_type, display_order, is_mandatory, is_active)
        VALUES (v_test_id, 'PCT_SEPSIS', 'Procalcitonin (PCT)', 'ng/mL', 'Numeric', 1, TRUE, TRUE)
        RETURNING id INTO v_param_id;
    ELSE
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'ng/mL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Quantitative Procalcitonin sepsis risk marker'
        WHERE id = v_test_id;
    END IF;

    IF v_test_id IS NOT NULL AND v_param_id IS NOT NULL THEN
        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'PCT_SEPSIS', 'Procalcitonin (PCT Sepsis)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 0.05, '<0.05 ng/mL (Normal; 0.05-0.50 Low probability/Local infection, >0.50 Systemic Sepsis concern)', 'ng/mL', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_PCT',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Sepsis Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Procalcitonin', 'Synonym'), (v_test_id, 'PCT', 'Synonym'), (v_test_id, 'PCT Sepsis', 'Synonym'), (v_test_id, 'Serum Procalcitonin', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- =========================================================================
    -- GROUP 5: REPRODUCTIVE & OTHER
    -- =========================================================================

    -- Quantitative Beta-hCG (END-0039)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0039';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'mIU/mL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Quantitative Beta-hCG immunoassay'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mIU/mL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'B_HCG', 'Quantitative Beta-hCG', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'mIU/mL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 5.0, '<5.0 mIU/mL (Non-pregnant)', 'mIU/mL', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_BHCG',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Reproductive Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Beta-hCG', 'Synonym'), (v_test_id, 'Beta hCG Quantitative', 'Synonym'), (v_test_id, 'B_HCG', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Ferritin (BIO-0050 - Sex-specific)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0050';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Fluorescence Immunoassay',
            unit = 'ng/mL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Quantitative Ferritin immunoassay'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'ng/mL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'FERRITIN', 'Ferritin', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Fluorescence Immunoassay', 'ng/mL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 30.0, 400.0, '30 - 400 ng/mL', 'ng/mL', 'Fluorescence Immunoassay', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 15.0, 150.0, '15 - 150 ng/mL', 'ng/mL', 'Fluorescence Immunoassay', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Fluorescence Immunoassay', 'FIA_FERRITIN',
            'FIACHECK_V1', CURRENT_DATE, 'ClinicallyValidated', 'FIAcheck Standard Immunoassay Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Ferritin', 'Synonym'), (v_test_id, 'Serum Ferritin', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- =========================================================================
    -- GROUP 6: GOVERNED REUSABLE PANELS
    -- =========================================================================

    -- Panel 1: IMM-THYROID / PRO-0004 (Thyroid Function Panel)
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0004';
    IF v_panel_id IS NOT NULL THEN
        UPDATE public.tests
        SET validation_status = 'VALIDATED',
            is_active = TRUE,
            method = 'Fluorescence Immunoassay (FIAcheck)'
        WHERE id = v_panel_id;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type)
        VALUES (v_panel_id, 'IMM-THYROID', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;

        -- FT3 (END-0003)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0003';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 1, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- FT4 (END-0002)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0002';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 2, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- TSH (END-0001)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'END-0001';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 3, is_required = TRUE, component_role = 'Measured';
        END IF;
    END IF;

    -- Panel 2: IMM-VITAMINS (Vitamins Suite)
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'IMM-VITAMINS';
    IF v_panel_id IS NULL THEN
        INSERT INTO public.tests (
            code, name, short_name, department, subdepartment, category,
            test_type, specimen_type, container, container_type, sample_type,
            method, unit, tat_description, report_data_type,
            fasting_required, is_outsource, is_active, validation_status, notes,
            price_paisa, price_configured, allow_zero_price_billing, display_order
        ) VALUES (
            'IMM-VITAMINS', 'Vitamins Suite (Vit D & B12)', 'IMM-VITAMINS', 'Clinical Biochemistry', 'Special Chemistry', 'Special Chemistry',
            'Panel', 'Serum', 'Yellow Top (SST)', 'Yellow Top (SST)', 'Serum',
            'Fluorescence Immunoassay (FIAcheck)', NULL, 'Routine', 'Numeric',
            FALSE, FALSE, TRUE, 'VALIDATED', 'Vitamins Panel: 25-OH Vitamin D & Vitamin B12',
            0, FALSE, TRUE, 0
        ) RETURNING id INTO v_panel_id;

        INSERT INTO public.parameters (test_id, code, name, unit, value_type, display_order, is_mandatory, is_active)
        VALUES (v_panel_id, 'IMM-VITAMINS', 'Vitamins Suite (Vit D & B12)', NULL, 'Heading', 1, TRUE, TRUE);
    ELSE
        UPDATE public.tests
        SET validation_status = 'VALIDATED',
            is_active = TRUE,
            method = 'Fluorescence Immunoassay (FIAcheck)'
        WHERE id = v_panel_id;
    END IF;

    IF v_panel_id IS NOT NULL THEN
        -- Vitamin D (BIO-0053)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0053';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 1, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- Vitamin B12 (BIO-0051)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0051';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 2, is_required = TRUE, component_role = 'Measured';
        END IF;
    END IF;

    -- Panel 3: IMM-CARDIAC / PRO-0007 (Emergency Cardiac Markers)
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0007';
    IF v_panel_id IS NOT NULL THEN
        UPDATE public.tests
        SET validation_status = 'VALIDATED',
            is_active = TRUE,
            method = 'Fluorescence Immunoassay (FIAcheck)'
        WHERE id = v_panel_id;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type)
        VALUES (v_panel_id, 'IMM-CARDIAC', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;

        -- Troponin I (BIO-0063)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0063';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 1, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- CK-MB Mass (BIO-0061)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0061';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 2, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- Myoglobin (BIO-0065)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0065';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 3, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- NT-proBNP (BIO-0067)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0067';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 4, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- D-Dimer (COA-0006)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'COA-0006';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 5, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 5, is_required = TRUE, component_role = 'Measured';
        END IF;
    END IF;

    -- Panel 4: IMM-INFLAMMATION (Sepsis & Inflammatory Markers)
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'IMM-INFLAMMATION';
    IF v_panel_id IS NULL THEN
        INSERT INTO public.tests (
            code, name, short_name, department, subdepartment, category,
            test_type, specimen_type, container, container_type, sample_type,
            method, unit, tat_description, report_data_type,
            fasting_required, is_outsource, is_active, validation_status, notes,
            price_paisa, price_configured, allow_zero_price_billing, display_order
        ) VALUES (
            'IMM-INFLAMMATION', 'Sepsis & Inflammatory Markers Panel', 'IMM-INFLAMMATION', 'Immunology', 'Special Chemistry', 'Special Chemistry',
            'Panel', 'Serum', 'Yellow Top (SST)', 'Yellow Top (SST)', 'Serum',
            'Fluorescence Immunoassay (FIAcheck)', NULL, 'Routine', 'Numeric',
            FALSE, FALSE, TRUE, 'VALIDATED', 'Inflammation & Sepsis Panel: hs-CRP & Procalcitonin',
            0, FALSE, TRUE, 0
        ) RETURNING id INTO v_panel_id;

        INSERT INTO public.parameters (test_id, code, name, unit, value_type, display_order, is_mandatory, is_active)
        VALUES (v_panel_id, 'IMM-INFLAMMATION', 'Sepsis & Inflammatory Markers Panel', NULL, 'Heading', 1, TRUE, TRUE);
    ELSE
        UPDATE public.tests
        SET validation_status = 'VALIDATED',
            is_active = TRUE,
            method = 'Fluorescence Immunoassay (FIAcheck)'
        WHERE id = v_panel_id;
    END IF;

    IF v_panel_id IS NOT NULL THEN
        -- hs-CRP (BIO-0068)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0068';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 1, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- Procalcitonin (PCT_SEPSIS)
        SELECT id INTO v_comp_id FROM public.tests WHERE code IN ('PCT_SEPSIS', 'PROCALCITONIN');
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 2, is_required = TRUE, component_role = 'Measured';
        END IF;
    END IF;

END $$;

COMMIT;
