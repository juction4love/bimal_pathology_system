-- Migration 00107: CORALAB ACE Clinical Biochemistry Analyzer Integration & Routine Chemistry Governance
--
-- Analyzer Specifications:
-- - Analyzer Code: CORALAB_ACE
-- - Analyzer Name: CORALAB ACE
-- - Manufacturer: Coral Clinical Systems / Tulip Diagnostics
-- - Type: Semi-Automated / Automated Clinical Chemistry Analyzer
-- - Department: Clinical Biochemistry
-- - Laboratory Location: Biochemistry Laboratory
-- - Capabilities: 30 routine pre-programmed chemistry assays, up to 300 open programming positions
--
-- Routine Clinical Panels Configured:
-- 1. Liver Function Tests (LFT): ALT, AST, ALP, TBIL, DBIL, Total Protein, Albumin, Globulin (Calc), A/G Ratio (Calc), GGT
-- 2. Renal Function Tests (RFT/KFT): Creatinine, Urea, BUN (Calc), Uric Acid
-- 3. Glucose: FBS, PPBS, RBS
-- 4. Lipid Profile: Total Cholesterol, Triglycerides, HDL Cholesterol, LDL Cholesterol (Calc), VLDL Cholesterol (Calc)
-- 5. Minerals / Electrolytes: Calcium, Phosphorus, Magnesium, Sodium (Photometric/Colorimetric), Potassium (Photometric/Turbidimetric), Chloride (Photometric)
-- 6. Cardiac / Enzymes: CK Total, CK-MB, LDH, Alpha-Amylase

BEGIN;

-- 1. Create or Update CORALAB ACE Analyzer Master Record
INSERT INTO public.analyzers (
    code,
    name,
    manufacturer,
    model,
    laboratory_location,
    lifecycle_status,
    row_version
) VALUES (
    'CORALAB_ACE',
    'CORALAB ACE',
    'Coral Clinical Systems / Tulip Diagnostics',
    'CORALAB ACE',
    'Biochemistry Laboratory',
    'Active',
    1
)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    manufacturer = EXCLUDED.manufacturer,
    model = EXCLUDED.model,
    laboratory_location = EXCLUDED.laboratory_location,
    lifecycle_status = 'Active',
    row_version = public.analyzers.row_version + 1,
    updated_at = NOW();

-- 2. Populate Analyzer Parameter Channels & Configure Routine Clinical Tests
DO $$
DECLARE
    v_analyzer_id UUID;
    v_test_id UUID;
    v_param_id UUID;
    v_panel_id UUID;
    v_comp_id UUID;
BEGIN
    SELECT id INTO v_analyzer_id FROM public.analyzers WHERE code = 'CORALAB_ACE';

    -- =========================================================================
    -- GROUP 1: LIVER FUNCTION TESTS (LFT)
    -- =========================================================================

    -- ALT / SGPT (BIO-0021)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0021';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'UV Kinetic (IFCC)',
            unit = 'U/L',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'U/L' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'ALT', 'Alanine Aminotransferase (ALT/SGPT)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'UV Kinetic (IFCC)', 'U/L', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 0, 45, '0 - 45 U/L', 'U/L', 'UV Kinetic (IFCC)', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 0, 34, '0 - 34 U/L', 'U/L', 'UV Kinetic (IFCC)', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'UV Kinetic (IFCC)', 'CORALAB_ALT',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'SGPT', 'Synonym'), (v_test_id, 'ALT', 'Synonym'), (v_test_id, 'Alanine Aminotransferase', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- AST / SGOT (BIO-0020)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0020';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'UV Kinetic (IFCC)',
            unit = 'U/L',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'U/L' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'AST', 'Aspartate Aminotransferase (AST/SGOT)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'UV Kinetic (IFCC)', 'U/L', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 0, 40, '0 - 40 U/L', 'U/L', 'UV Kinetic (IFCC)', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 0, 32, '0 - 32 U/L', 'U/L', 'UV Kinetic (IFCC)', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'UV Kinetic (IFCC)', 'CORALAB_AST',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'SGOT', 'Synonym'), (v_test_id, 'AST', 'Synonym'), (v_test_id, 'Aspartate Aminotransferase', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- ALP (BIO-0022)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0022';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Kinetic p-NPP / AMP buffer / IFCC',
            unit = 'U/L',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'U/L' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'ALP', 'Alkaline Phosphatase (ALP)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Kinetic p-NPP / AMP buffer / IFCC', 'U/L', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 44, 147, '44 - 147 U/L', 'U/L', 'Kinetic p-NPP / AMP buffer / IFCC', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Kinetic p-NPP / AMP buffer / IFCC', 'CORALAB_ALP',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'ALP', 'Synonym'), (v_test_id, 'Alk Phos', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Total Bilirubin (BIO-0017)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0017';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'DCA / Modified Jendrassik-Grof',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'TBIL', 'Total Bilirubin', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'DCA / Modified Jendrassik-Grof', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.2, 1.2, '0.2 - 1.2 mg/dL', 'mg/dL', 'DCA / Modified Jendrassik-Grof', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'DCA / Modified Jendrassik-Grof', 'CORALAB_TBIL',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'TBIL', 'Synonym'), (v_test_id, 'Total Bilirubin', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Direct Bilirubin (BIO-0018)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0018';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Diazotized Sulfanilic Acid',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'DBIL', 'Direct Bilirubin', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Diazotized Sulfanilic Acid', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.0, 0.3, '0.0 - 0.3 mg/dL', 'mg/dL', 'Diazotized Sulfanilic Acid', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Diazotized Sulfanilic Acid', 'CORALAB_DBIL',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'DBIL', 'Synonym'), (v_test_id, 'Direct Bilirubin', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Total Protein (BIO-0013)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0013';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Biuret End-point',
            unit = 'g/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'g/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'TP', 'Total Protein', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Biuret End-point', 'g/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 6.4, 8.3, '6.4 - 8.3 g/dL', 'g/dL', 'Biuret End-point', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Biuret End-point', 'CORALAB_TP',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'TP', 'Synonym'), (v_test_id, 'Total Protein', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Albumin (BIO-0014)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0014';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Bromocresol Green (BCG)',
            unit = 'g/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'g/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'ALB', 'Albumin', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Bromocresol Green (BCG)', 'g/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 3.5, 5.2, '3.5 - 5.2 g/dL', 'g/dL', 'Bromocresol Green (BCG)', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Bromocresol Green (BCG)', 'CORALAB_ALB',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'ALB', 'Synonym'), (v_test_id, 'Albumin', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Globulin (BIO-0015 - CALCULATED)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0015';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Calculated: Total Protein - Albumin',
            unit = 'g/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Calculated from Total Protein and Albumin'
        WHERE id = v_test_id;

        UPDATE public.parameters
        SET unit = 'g/dL',
            value_type = 'Calculated',
            formula = 'TP - ALB',
            calculation_identifier = 'LFT_GLOBULIN_V1'
        WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'GLOB', 'Globulin', v_test_id, v_param_id,
            'ANALYZER_CALCULATED', 'Calculated: Total Protein - Albumin', 'g/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 2.0, 3.5, '2.0 - 3.5 g/dL', 'g/dL', 'Calculated: Total Protein - Albumin', TRUE, TRUE);

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'GLOB', 'Synonym'), (v_test_id, 'Globulin', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- A/G Ratio (BIO-0016 - CALCULATED)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0016';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Calculated: Albumin / Globulin',
            unit = 'ratio',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Calculated from Albumin and Globulin'
        WHERE id = v_test_id;

        UPDATE public.parameters
        SET unit = 'ratio',
            value_type = 'Calculated',
            formula = 'ALB / GLOB',
            calculation_identifier = 'LFT_AG_RATIO_V1'
        WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'AG_RATIO', 'A/G Ratio', v_test_id, v_param_id,
            'ANALYZER_CALCULATED', 'Calculated: Albumin / Globulin', 'ratio', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 1.1, 2.2, '1.1 - 2.2', 'ratio', 'Calculated: Albumin / Globulin', TRUE, TRUE);

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'AG Ratio', 'Synonym'), (v_test_id, 'A/G Ratio', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- GGT (BIO-0023)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0023';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Carboxy Substrate Kinetic',
            unit = 'U/L',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'U/L' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'GGT', 'Gamma-Glutamyl Transferase (GGT)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Carboxy Substrate Kinetic', 'U/L', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 10, 50, '10 - 50 U/L', 'U/L', 'Carboxy Substrate Kinetic', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 7, 32, '7 - 32 U/L', 'U/L', 'Carboxy Substrate Kinetic', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Carboxy Substrate Kinetic', 'CORALAB_GGT',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'GGT', 'Synonym'), (v_test_id, 'GGTP', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- =========================================================================
    -- GROUP 2: RENAL / KIDNEY FUNCTION TESTS (RFT / KFT)
    -- =========================================================================

    -- Creatinine (BIO-0010)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0010';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Modified Jaffe Kinetic / Enzymatic',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'CREAT', 'Creatinine', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Modified Jaffe Kinetic / Enzymatic', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 0.7, 1.3, '0.7 - 1.3 mg/dL', 'mg/dL', 'Modified Jaffe Kinetic / Enzymatic', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 0.6, 1.1, '0.6 - 1.1 mg/dL', 'mg/dL', 'Modified Jaffe Kinetic / Enzymatic', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Modified Jaffe Kinetic / Enzymatic', 'CORALAB_CREAT',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Creatinine', 'Synonym'), (v_test_id, 'Sr Creatinine', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Urea (BIO-0008)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0008';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Urease-GLDH UV Kinetic / Berthelot',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'UREA', 'Urea', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Urease-GLDH UV Kinetic / Berthelot', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 15, 45, '15 - 45 mg/dL', 'mg/dL', 'Urease-GLDH UV Kinetic / Berthelot', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Urease-GLDH UV Kinetic / Berthelot', 'CORALAB_UREA',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Urea', 'Synonym'), (v_test_id, 'Blood Urea', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- BUN (BIO-0009 - CALCULATED)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0009';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Calculated: Urea / 2.14',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Calculated from Urea (Urea / 2.14)'
        WHERE id = v_test_id;

        UPDATE public.parameters
        SET unit = 'mg/dL',
            value_type = 'Calculated',
            formula = 'UREA / 2.14',
            calculation_identifier = 'RFT_BUN_V1'
        WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'BUN', 'Blood Urea Nitrogen (BUN)', v_test_id, v_param_id,
            'ANALYZER_CALCULATED', 'Calculated: Urea / 2.14', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 7, 20, '7 - 20 mg/dL', 'mg/dL', 'Calculated: Urea / 2.14', TRUE, TRUE);

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'BUN', 'Synonym'), (v_test_id, 'Blood Urea Nitrogen', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Uric Acid (BIO-0012)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0012';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Uricase-PAP',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'URIC', 'Uric Acid', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Uricase-PAP', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 3.5, 7.2, '3.5 - 7.2 mg/dL', 'mg/dL', 'Uricase-PAP', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 2.6, 6.0, '2.6 - 6.0 mg/dL', 'mg/dL', 'Uricase-PAP', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Uricase-PAP', 'CORALAB_URIC',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Uric Acid', 'Synonym'), (v_test_id, 'Serum Uric Acid', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- =========================================================================
    -- GROUP 3: GLUCOSE
    -- =========================================================================

    -- FBS (BIO-0001)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0001';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'GOD-PAP',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'GLU_FASTING', 'Glucose, Fasting (FBS)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'GOD-PAP', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 70, 99, '70 - 99 mg/dL', 'mg/dL', 'GOD-PAP', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'GOD-PAP', 'CORALAB_GLU_F',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'FBS', 'Synonym'), (v_test_id, 'Fasting Blood Sugar', 'Synonym'), (v_test_id, 'Glucose Fasting', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- PPBS (BIO-0003 - One-sided <140)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0003';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'GOD-PAP',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'GLU_PP', 'Glucose, Postprandial 2 hr (PPBS)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'GOD-PAP', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 140, '<140 mg/dL', 'mg/dL', 'GOD-PAP', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'GOD-PAP', 'CORALAB_GLU_PP',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'PPBS', 'Synonym'), (v_test_id, 'Postprandial Blood Sugar', 'Synonym'), (v_test_id, 'Glucose PP', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- RBS (BIO-0002)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0002';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'GOD-PAP',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'GLU_RANDOM', 'Glucose, Random (RBS)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'GOD-PAP', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 70, 140, '70 - 140 mg/dL', 'mg/dL', 'GOD-PAP', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'GOD-PAP', 'CORALAB_GLU_R',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'RBS', 'Synonym'), (v_test_id, 'Random Blood Sugar', 'Synonym'), (v_test_id, 'Glucose Random', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- =========================================================================
    -- GROUP 4: LIPID PROFILE
    -- =========================================================================

    -- Total Cholesterol (BIO-0027 - One-sided <200 Desirable)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0027';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'CHOD-PAP',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'CHOL', 'Total Cholesterol', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'CHOD-PAP', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 200, '<200 mg/dL (Desirable)', 'mg/dL', 'CHOD-PAP', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'CHOD-PAP', 'CORALAB_CHOL',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Cholesterol', 'Synonym'), (v_test_id, 'Total Cholesterol', 'Synonym'), (v_test_id, 'Sr Cholesterol', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Triglycerides (BIO-0028 - One-sided <150 Normal)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0028';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'GPO-PAP',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'TRIG', 'Triglycerides', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'GPO-PAP', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 150, '<150 mg/dL (Normal)', 'mg/dL', 'GPO-PAP', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'GPO-PAP', 'CORALAB_TRIG',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Triglycerides', 'Synonym'), (v_test_id, 'TG', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- HDL Cholesterol (BIO-0029 - One-sided Male >40, Female >50)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0029';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Direct Clearance / PEG Precipitation',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'HDL', 'HDL Cholesterol', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Direct Clearance / PEG Precipitation', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 40, NULL, '>40 mg/dL', 'mg/dL', 'Direct Clearance / PEG Precipitation', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 50, NULL, '>50 mg/dL', 'mg/dL', 'Direct Clearance / PEG Precipitation', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Direct Clearance / PEG Precipitation', 'CORALAB_HDL',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'HDL', 'Synonym'), (v_test_id, 'HDL Cholesterol', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- LDL Cholesterol, Calculated (BIO-0031 - CALCULATED / Friedewald)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0031';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Calculated: Friedewald Equation (Total Chol - HDL - TG/5)',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Calculated via Friedewald equation when TG < 400 mg/dL'
        WHERE id = v_test_id;

        UPDATE public.parameters
        SET unit = 'mg/dL',
            value_type = 'Calculated',
            formula = 'CHOL - HDL - (TRIG / 5)',
            calculation_identifier = 'LIPID_LDL_CALCULATED_V1'
        WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'LDL_CALC', 'LDL Cholesterol, Calculated', v_test_id, v_param_id,
            'ANALYZER_CALCULATED', 'Calculated: Total Cholesterol - HDL - (Triglycerides / 5)', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 100, '<100 mg/dL (Optimal)', 'mg/dL', 'Calculated: Friedewald Equation', TRUE, TRUE);

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'LDL', 'Synonym'), (v_test_id, 'LDL Cholesterol', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Direct LDL Cholesterol (BIO-0030 - DIRECT MEASURED)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0030';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Direct Clearance / Immunoinhibition',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Directly measured LDL cholesterol assay'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'LDL_DIRECT', 'LDL Cholesterol, Direct', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Direct Clearance / Immunoinhibition', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 100, '<100 mg/dL (Optimal)', 'mg/dL', 'Direct Clearance / Immunoinhibition', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Direct Clearance / Immunoinhibition', 'CORALAB_LDL_DIR',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Direct LDL Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;
    END IF;

    -- VLDL Cholesterol (BIO-0032 - CALCULATED)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0032';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Calculated: Triglycerides / 5',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Calculated from Triglycerides (TG / 5)'
        WHERE id = v_test_id;

        UPDATE public.parameters
        SET unit = 'mg/dL',
            value_type = 'Calculated',
            formula = 'TRIG / 5',
            calculation_identifier = 'LIPID_VLDL_V1'
        WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'VLDL', 'VLDL Cholesterol', v_test_id, v_param_id,
            'ANALYZER_CALCULATED', 'Calculated: Triglycerides / 5', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 10, 30, '10 - 30 mg/dL', 'mg/dL', 'Calculated: Triglycerides / 5', TRUE, TRUE);

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'VLDL', 'Synonym'), (v_test_id, 'VLDL Cholesterol', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- =========================================================================
    -- GROUP 5: MINERALS & ELECTROLYTES (Photometric Reagents - NOT ISE)
    -- =========================================================================

    -- Calcium, Total (BIO-0041)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0041';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Arsenazo III / O-CPC',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'CALC', 'Calcium, Total', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Arsenazo III / O-CPC', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 8.5, 10.5, '8.5 - 10.5 mg/dL', 'mg/dL', 'Arsenazo III / O-CPC', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Arsenazo III / O-CPC', 'CORALAB_CALC',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Calcium', 'Synonym'), (v_test_id, 'Total Calcium', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Phosphorus (BIO-0043)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0043';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Phosphomolybdate UV',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'PHOS', 'Phosphorus', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Phosphomolybdate UV', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 2.5, 4.5, '2.5 - 4.5 mg/dL', 'mg/dL', 'Phosphomolybdate UV', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Phosphomolybdate UV', 'CORALAB_PHOS',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Phosphorus', 'Synonym'), (v_test_id, 'Inorganic Phosphorus', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Magnesium (BIO-0044)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0044';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Calmagite / Xylidyl Blue',
            unit = 'mg/dL',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mg/dL' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'MAG', 'Magnesium', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Calmagite / Xylidyl Blue', 'mg/dL', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 1.6, 2.6, '1.6 - 2.6 mg/dL', 'mg/dL', 'Calmagite / Xylidyl Blue', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Calmagite / Xylidyl Blue', 'CORALAB_MAG',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Magnesium', 'Synonym'), (v_test_id, 'Mg', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Sodium (BIO-0037 - Photometric / Colorimetric - NON-ISE)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0037';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Enzymatic / Colorimetric (CORALAB ACE Photometric Reagent - Non-ISE)',
            unit = 'mmol/L',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Photometric enzymatic assay on CORALAB ACE (Non-ISE)'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mmol/L' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'NA_PHOTOMETRIC', 'Sodium (Photometric)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Enzymatic / Colorimetric (Photometric Non-ISE)', 'mmol/L', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 135, 145, '135 - 145 mmol/L', 'mmol/L', 'Enzymatic / Colorimetric (Non-ISE)', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Enzymatic / Colorimetric (Non-ISE)', 'CORALAB_NA',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Photometric Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Sodium', 'Synonym'), (v_test_id, 'Serum Sodium', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Potassium (BIO-0038 - Photometric / Turbidimetric - NON-ISE)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0038';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Enzymatic / Turbidimetric (CORALAB ACE Photometric Reagent - Non-ISE)',
            unit = 'mmol/L',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Photometric turbidimetric assay on CORALAB ACE (Non-ISE)'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mmol/L' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'K_PHOTOMETRIC', 'Potassium (Photometric)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Enzymatic / Turbidimetric (Photometric Non-ISE)', 'mmol/L', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 3.5, 5.1, '3.5 - 5.1 mmol/L', 'mmol/L', 'Enzymatic / Turbidimetric (Non-ISE)', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Enzymatic / Turbidimetric (Non-ISE)', 'CORALAB_K',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Photometric Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Potassium', 'Synonym'), (v_test_id, 'Serum Potassium', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Chloride (BIO-0039 - Mercuric Thiocyanate - NON-ISE)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0039';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Mercuric Thiocyanate (CORALAB ACE Photometric Reagent - Non-ISE)',
            unit = 'mmol/L',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Photometric mercuric thiocyanate assay on CORALAB ACE (Non-ISE)'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'mmol/L' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'CL_PHOTOMETRIC', 'Chloride (Photometric)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Mercuric Thiocyanate (Photometric Non-ISE)', 'mmol/L', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 96, 106, '96 - 106 mmol/L', 'mmol/L', 'Mercuric Thiocyanate (Non-ISE)', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Mercuric Thiocyanate (Non-ISE)', 'CORALAB_CL',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Photometric Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Chloride', 'Synonym'), (v_test_id, 'Serum Chloride', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- =========================================================================
    -- GROUP 6: CARDIAC & SPECIAL ENZYMES
    -- =========================================================================

    -- CK Total (BIO-0060)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0060';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'CK-NAC / Modified IFCC Kinetic',
            unit = 'U/L',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'U/L' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'CK_TOTAL', 'CK Total (Creatine Kinase)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'CK-NAC / Modified IFCC Kinetic', 'U/L', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES 
        (v_param_id, 'Male', 0, 43800, 39, 308, '39 - 308 U/L', 'U/L', 'CK-NAC / Modified IFCC Kinetic', TRUE, TRUE),
        (v_param_id, 'Female', 0, 43800, 26, 192, '26 - 192 U/L', 'U/L', 'CK-NAC / Modified IFCC Kinetic', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'CK-NAC / Modified IFCC Kinetic', 'CORALAB_CK',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'CPK', 'Synonym'), (v_test_id, 'CK', 'Synonym'), (v_test_id, 'Creatine Kinase Total', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- CK-MB Activity (BIO-0062 - One-sided <25)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0062';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'Immunoinhibition Kinetic',
            unit = 'U/L',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'U/L' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'CK_MB', 'CK-MB Activity', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'Immunoinhibition Kinetic', 'U/L', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, NULL, 25, '<25 U/L', 'U/L', 'Immunoinhibition Kinetic', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'Immunoinhibition Kinetic', 'CORALAB_CKMB',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'CK-MB', 'Synonym'), (v_test_id, 'CPK-MB', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- LDH (BIO-0024)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0024';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'DGKC / IFCC UV Kinetic',
            unit = 'U/L',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'U/L' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'LDH', 'Lactate Dehydrogenase (LDH)', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'DGKC / IFCC UV Kinetic', 'U/L', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 140, 280, '140 - 280 U/L', 'U/L', 'DGKC / IFCC UV Kinetic', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'DGKC / IFCC UV Kinetic', 'CORALAB_LDH',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'LDH', 'Synonym'), (v_test_id, 'Lactate Dehydrogenase', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Alpha-Amylase (BIO-0058)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0058';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        
        UPDATE public.tests
        SET method = 'CNP-G3 Direct Substrate',
            unit = 'U/L',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Standard routine chemistry configured for CORALAB ACE'
        WHERE id = v_test_id;

        UPDATE public.parameters SET unit = 'U/L' WHERE id = v_param_id;

        INSERT INTO public.analyzer_parameter_mappings (
            analyzer_id, channel_code, channel_name, test_id, parameter_id,
            measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
        ) VALUES (
            v_analyzer_id, 'AMYLASE', 'Amylase', v_test_id, v_param_id,
            'DIRECT_MEASURED', 'CNP-G3 Direct Substrate', 'U/L', 'Not Applicable', FALSE
        ) ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
            test_id = EXCLUDED.test_id, parameter_id = EXCLUDED.parameter_id,
            measurement_type = EXCLUDED.measurement_type, analytical_method = EXCLUDED.analytical_method, unit = EXCLUDED.unit;

        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 28, 100, '28 - 100 U/L', 'U/L', 'CNP-G3 Direct Substrate', TRUE, TRUE);

        INSERT INTO public.test_analyzer_configurations (
            test_id, parameter_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state, validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_test_id, v_param_id, v_analyzer_id, 'CNP-G3 Direct Substrate', 'CORALAB_AMYLASE',
            'CORALAB_V1', CURRENT_DATE, 'ClinicallyValidated', 'CORALAB ACE Standard Chemistry Protocol', FALSE, 'Active'
        ) ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;

        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_test_id, 'Amylase', 'Synonym'), (v_test_id, 'Serum Amylase', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- =========================================================================
    -- GROUP 7: AUDIT PROFILE PANELS TO REUSE CANONICAL COMPONENT TESTS
    -- =========================================================================

    -- PRO-0001: Liver Function Test (LFT)
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0001';
    IF v_panel_id IS NOT NULL THEN
        UPDATE public.tests
        SET validation_status = 'VALIDATED',
            is_active = TRUE,
            method = 'Automated Clinical Chemistry (CORALAB ACE)'
        WHERE id = v_panel_id;

        -- Ensure LFT components are linked
        -- Total Bilirubin (BIO-0017)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0017';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 1, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- Direct Bilirubin (BIO-0018)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0018';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 2, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- AST / SGOT (BIO-0020)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0020';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 3, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- ALT / SGPT (BIO-0021)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0021';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 4, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- ALP (BIO-0022)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0022';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 5, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 5, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- Total Protein (BIO-0013)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0013';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 6, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 6, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- Albumin (BIO-0014)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0014';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 7, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 7, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- Globulin (BIO-0015 - Calc)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0015';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 8, TRUE, 'Calculated')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 8, is_required = TRUE, component_role = 'Calculated';
        END IF;

        -- A/G Ratio (BIO-0016 - Calc)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0016';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 9, TRUE, 'Calculated')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 9, is_required = TRUE, component_role = 'Calculated';
        END IF;

        -- GGT (BIO-0023 - Optional/Required)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0023';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 10, FALSE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 10, is_required = FALSE, component_role = 'Measured';
        END IF;
    END IF;

    -- PRO-0002: Renal Function Test (RFT/KFT)
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0002';
    IF v_panel_id IS NOT NULL THEN
        UPDATE public.tests
        SET validation_status = 'VALIDATED',
            is_active = TRUE,
            method = 'Automated Clinical Chemistry (CORALAB ACE)'
        WHERE id = v_panel_id;

        -- Urea (BIO-0008)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0008';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 1, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- BUN (BIO-0009 - Calc)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0009';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Calculated')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 2, is_required = TRUE, component_role = 'Calculated';
        END IF;

        -- Creatinine (BIO-0010)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0010';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 3, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- Uric Acid (BIO-0012)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0012';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 4, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- Sodium (BIO-0037 - Optional in basic RFT)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0037';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 5, FALSE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 5, is_required = FALSE, component_role = 'Measured';
        END IF;

        -- Potassium (BIO-0038 - Optional in basic RFT)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0038';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 6, FALSE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 6, is_required = FALSE, component_role = 'Measured';
        END IF;

        -- Chloride (BIO-0039 - Optional in basic RFT)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0039';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 7, FALSE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 7, is_required = FALSE, component_role = 'Measured';
        END IF;
    END IF;

    -- PRO-0003: Lipid Profile
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0003';
    IF v_panel_id IS NOT NULL THEN
        UPDATE public.tests
        SET validation_status = 'VALIDATED',
            is_active = TRUE,
            method = 'Automated Clinical Chemistry (CORALAB ACE)'
        WHERE id = v_panel_id;

        -- Total Cholesterol (BIO-0027)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0027';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 1, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- Triglycerides (BIO-0028)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0028';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 2, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- HDL Cholesterol (BIO-0029)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0029';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 3, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- LDL Cholesterol, Calculated (BIO-0031 - Calc)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0031';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 4, TRUE, 'Calculated')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 4, is_required = TRUE, component_role = 'Calculated';
        END IF;

        -- VLDL Cholesterol (BIO-0032 - Calc)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0032';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 5, TRUE, 'Calculated')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 5, is_required = TRUE, component_role = 'Calculated';
        END IF;
    END IF;

    -- PRO-0008: Electrolyte Panel (Photometric Non-ISE)
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0008';
    IF v_panel_id IS NOT NULL THEN
        UPDATE public.tests
        SET validation_status = 'VALIDATED',
            is_active = TRUE,
            method = 'Photometric Enzymatic / Colorimetric (CORALAB ACE Non-ISE)'
        WHERE id = v_panel_id;

        -- Sodium (BIO-0037)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0037';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 1, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 1, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- Potassium (BIO-0038)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0038';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 2, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 2, is_required = TRUE, component_role = 'Measured';
        END IF;

        -- Chloride (BIO-0039)
        SELECT id INTO v_comp_id FROM public.tests WHERE code = 'BIO-0039';
        IF v_comp_id IS NOT NULL THEN
            INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required, component_role)
            VALUES (v_panel_id, v_panel_id, v_comp_id, 3, TRUE, 'Measured')
            ON CONFLICT (panel_id, component_test_id) DO UPDATE SET display_order = 3, is_required = TRUE, component_role = 'Measured';
        END IF;
    END IF;

END $$;

COMMIT;
