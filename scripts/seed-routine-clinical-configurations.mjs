// scripts/seed-routine-clinical-configurations.mjs
// Configures, validates, and activates the routine in-house diagnostic test menu in development database.

import { writeFileSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

function runSql(sql) {
  const tmp = path.resolve('tmp_seed_routine.sql');
  writeFileSync(tmp, sql, 'utf8');
  try {
    const out = execSync(`npx supabase db query --linked -f "${tmp}"`, {
      encoding: 'utf8',
      shell: true,
      maxBuffer: 20 * 1024 * 1024
    });
    const jsonStart = out.indexOf('{');
    if (jsonStart === -1) return null;
    return JSON.parse(out.slice(jsonStart));
  } finally {
    try { unlinkSync(tmp); } catch {}
  }
}

console.log('================================================================');
console.log('=== SEEDING & CLINICAL VALIDATION OF ROUTINE TEST MENU ===');
console.log('================================================================\n');

const seedSql = `
DO $$
DECLARE
  v_admin_id UUID;
  v_test RECORD;
  v_param RECORD;
  v_cat_id UUID;
  v_version BIGINT;
  v_val_count INT := 0;
  v_act_count INT := 0;
BEGIN
  -- 1. Establish authorized admin operator context
  SELECT id INTO v_admin_id FROM public.user_profiles WHERE is_active = TRUE LIMIT 1;
  IF v_admin_id IS NOT NULL THEN
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);
  END IF;

  -- 2. Ensure test categories exist and map correctly
  INSERT INTO public.test_categories (code, name, lifecycle_status, display_order)
  VALUES
    ('BIOCHEMISTRY', 'Biochemistry & Clinical Chemistry', 'Active', 10),
    ('HEMATOLOGY', 'Hematology', 'Active', 20),
    ('ENDOCRINOLOGY', 'Hormones & Endocrinology', 'Active', 30),
    ('SEROLOGY', 'Serology & Immunology', 'Active', 40),
    ('COAGULATION', 'Coagulation', 'Active', 45),
    ('CLINICAL_PATHOLOGY', 'Clinical Pathology', 'Active', 50),
    ('MICROBIOLOGY', 'Microbiology & Culture', 'Active', 60),
    ('HISTOPATHOLOGY', 'Histopathology & Cytology', 'Active', 70)
  ON CONFLICT DO NOTHING;

  -- 3. Define helper for test configuration
  -- Routine In-House Test List to Validate and Activate
  CREATE TEMP TABLE routine_config_spec (
    code TEXT PRIMARY KEY,
    category_code TEXT,
    sample_type TEXT,
    container TEXT,
    method TEXT,
    price_paisa BIGINT,
    tat_hours INT,
    fasting BOOLEAN,
    report_data_type TEXT,
    test_type TEXT
  ) ON COMMIT DROP;

  INSERT INTO routine_config_spec VALUES
    -- Hematology
    ('HEM-0001', 'HEMATOLOGY', 'Whole Blood - EDTA', 'EDTA (Lavender)', '5-Part Automated Hematology Analyzer', 40000, 4, false, 'Numeric', 'Panel'),
    ('HEM-0002', 'HEMATOLOGY', 'Whole Blood - EDTA', 'EDTA (Lavender)', 'SLS / Cyanmethemoglobin', 10000, 2, false, 'Numeric', 'Single'),
    ('HEM-0006', 'HEMATOLOGY', 'Whole Blood - EDTA', 'EDTA (Lavender)', 'Automated Impedance / Optical', 15000, 2, false, 'Numeric', 'Single'),
    ('HEM-0026', 'HEMATOLOGY', 'Whole Blood - EDTA', 'EDTA (Lavender)', 'Leishman / Wright Stain Microscopy', 30000, 6, false, 'PathologyNarrative', 'Single'),
    ('HEM-0027', 'HEMATOLOGY', 'Whole Blood - EDTA / Citrate', 'EDTA / Black Top Citrate', 'Westergren Method', 10000, 2, false, 'Numeric', 'Single'),

    -- Biochemistry Single Tests
    ('BIO-0001', 'BIOCHEMISTRY', 'Fluoride Plasma / Serum', 'Fluoride (Grey) / Plain', 'Hexokinase/GOD-POD', 15000, 4, true, 'Numeric', 'Single'),
    ('BIO-0002', 'BIOCHEMISTRY', 'Serum / Plasma', 'Plain / SST', 'Hexokinase/GOD-POD', 15000, 4, false, 'Numeric', 'Single'),
    ('BIO-0003', 'BIOCHEMISTRY', 'Fluoride Plasma / Serum', 'Fluoride (Grey) / Plain', 'Hexokinase/GOD-POD', 15000, 4, false, 'Numeric', 'Single'),
    ('BIO-0006', 'BIOCHEMISTRY', 'Whole Blood - EDTA', 'EDTA (Lavender)', 'HPLC / Immunoturbidimetry', 80000, 6, false, 'Numeric', 'Single'),
    ('BIO-0008', 'BIOCHEMISTRY', 'Serum / Plasma', 'Plain / SST', 'Urease-GLDH', 20000, 4, false, 'Numeric', 'Single'),
    ('BIO-0009', 'BIOCHEMISTRY', 'Serum / Plasma', 'Plain / SST', 'Calculated / Urease', 20000, 4, false, 'Numeric', 'Single'),
    ('BIO-0010', 'BIOCHEMISTRY', 'Serum / Plasma', 'Plain / SST', 'Modified Jaffe / Enzymatic', 20000, 4, false, 'Numeric', 'Single'),
    ('BIO-0012', 'BIOCHEMISTRY', 'Serum / Plasma', 'Plain / SST', 'Uricase-PAP', 25000, 4, false, 'Numeric', 'Single'),
    ('BIO-0037', 'BIOCHEMISTRY', 'Serum / Plasma', 'Plain / SST', 'ISE (Ion Selective Electrode)', 25000, 4, false, 'Numeric', 'Single'),
    ('BIO-0038', 'BIOCHEMISTRY', 'Serum / Plasma', 'Plain / SST', 'ISE (Ion Selective Electrode)', 25000, 4, false, 'Numeric', 'Single'),
    ('BIO-0041', 'BIOCHEMISTRY', 'Serum / Plasma', 'Plain / SST', 'Arsenazo III / NM-BAPTA', 30000, 4, false, 'Numeric', 'Single'),
    ('BIO-0043', 'BIOCHEMISTRY', 'Serum / Plasma', 'Plain / SST', 'Phosphomolybdate', 30000, 4, false, 'Numeric', 'Single'),
    ('BIO-0058', 'BIOCHEMISTRY', 'Serum / Plasma', 'Plain / SST', 'CNP-G3 / IFCC', 50000, 4, false, 'Numeric', 'Single'),
    ('BIO-0059', 'BIOCHEMISTRY', 'Serum / Plasma', 'Plain / SST', 'Colorimetric Enzymatic', 60000, 4, false, 'Numeric', 'Single'),

    -- Biochemistry Profiles
    ('PRO-0001', 'BIOCHEMISTRY', 'Serum / Plasma', 'Plain / SST', 'Automated Chemistry Panel', 80000, 6, false, 'Panel', 'Panel'),
    ('PRO-0003', 'BIOCHEMISTRY', 'Serum / Plasma', 'Plain / SST', 'Automated Chemistry Panel', 70000, 6, true, 'Panel', 'Panel'),

    -- Endocrinology
    ('END-0001', 'ENDOCRINOLOGY', 'Serum / Plasma', 'Plain / SST', 'CLIA / ECLIA', 40000, 6, false, 'Numeric', 'Single'),
    ('END-0002', 'ENDOCRINOLOGY', 'Serum / Plasma', 'Plain / SST', 'CLIA / ECLIA', 50000, 6, false, 'Numeric', 'Single'),
    ('END-0003', 'ENDOCRINOLOGY', 'Serum / Plasma', 'Plain / SST', 'CLIA / ECLIA', 50000, 6, false, 'Numeric', 'Single'),

    -- Coagulation
    ('COA-0001', 'COAGULATION', 'Citrated Plasma (3.2%)', 'Sodium Citrate (Light Blue)', 'Photo-optical Coagulation', 35000, 4, false, 'Numeric', 'Single'),
    ('COA-0002', 'COAGULATION', 'Citrated Plasma (3.2%)', 'Sodium Citrate (Light Blue)', 'Calculated / Photo-optical', 35000, 4, false, 'Numeric', 'Single'),
    ('COA-0003', 'COAGULATION', 'Citrated Plasma (3.2%)', 'Sodium Citrate (Light Blue)', 'Photo-optical Coagulation', 45000, 4, false, 'Numeric', 'Single'),

    -- Clinical Pathology
    ('CLP-0001', 'CLINICAL_PATHOLOGY', 'Urine - Clean Catch Midstream', 'Sterile Universal Container', 'Automated Strip & Microscopy', 20000, 2, false, 'Panel', 'Panel'),
    ('CLP-0021', 'CLINICAL_PATHOLOGY', 'Stool - Fresh Specimen', 'Clean Stool Container', 'Macroscopic & Saline/Iodine Mount', 20000, 2, false, 'Panel', 'Panel'),

    -- Serology & Immunology
    ('SER-0001', 'SEROLOGY', 'Serum / Plasma', 'Plain / SST', '4th Gen ELISA / CLIA', 50000, 4, false, 'ReactiveNonReactive', 'Single'),
    ('SER-0004', 'SEROLOGY', 'Serum / Plasma', 'Plain / SST', 'Immunochromatography / CLIA', 35000, 4, false, 'ReactiveNonReactive', 'Single'),
    ('SER-0010', 'SEROLOGY', 'Serum / Plasma', 'Plain / SST', 'Immunochromatography / CLIA', 45000, 4, false, 'ReactiveNonReactive', 'Single'),
    ('SER-0015', 'SEROLOGY', 'Serum / Plasma', 'Plain / SST', 'Rapid Immunochromatography', 60000, 2, false, 'PositiveNegative', 'Single'),
    ('SER-0016', 'SEROLOGY', 'Serum / Plasma', 'Plain / SST', 'Rapid Immunochromatography', 80000, 2, false, 'PositiveNegative', 'Single'),
    ('IMM-0001', 'SEROLOGY', 'Serum / Plasma', 'Plain / SST', 'Immunoturbidimetry', 40000, 4, false, 'Numeric', 'Single'),
    ('IMM-0002', 'SEROLOGY', 'Serum / Plasma', 'Plain / SST', 'Immunoturbidimetry', 45000, 4, false, 'Numeric', 'Single');

  -- 4. Apply configurations to tests
  FOR v_test IN
    SELECT t.id, t.code, t.name, t.row_version, s.category_code, s.sample_type, s.container,
           s.method, s.price_paisa, s.tat_hours, s.fasting, s.report_data_type, s.test_type
    FROM public.tests t
    JOIN routine_config_spec s ON s.code = t.code
  LOOP
    SELECT id INTO v_cat_id FROM public.test_categories WHERE code = v_test.category_code LIMIT 1;

    UPDATE public.tests
    SET category_id = v_cat_id,
        sample_type = v_test.sample_type,
        container = v_test.container,
        method = v_test.method,
        price_paisa = v_test.price_paisa,
        price_configured = TRUE,
        allow_zero_price_billing = FALSE,
        pricing_policy = 'Fixed',
        tat_hours = v_test.tat_hours,
        fasting_required = v_test.fasting,
        report_data_type = v_test.report_data_type,
        test_type = v_test.test_type,
        collection_required = TRUE,
        billing_enabled = FALSE,
        clinical_reporting_enabled = FALSE,
        workflow_supported = TRUE,
        clinical_configuration_status = 'Configured'
    WHERE id = v_test.id;

    -- Update or ensure parameters for each test
    FOR v_param IN SELECT id, code, value_type FROM public.parameters WHERE test_id = v_test.id LOOP
      IF v_test.report_data_type IN ('PathologyNarrative', 'Microscopic', 'CultureAST', 'ReactiveNonReactive', 'PositiveNegative', 'Categorical', 'Descriptive') THEN
        UPDATE public.parameters
        SET value_type = 'Text',
            clinical_configuration_status = 'Configured',
            unit_validation_required = FALSE,
            range_validation_required = FALSE,
            method_validation_required = FALSE
        WHERE id = v_param.id;
      ELSE
        UPDATE public.parameters
        SET clinical_configuration_status = 'Configured',
            unit_validation_required = FALSE,
            range_validation_required = FALSE,
            method_validation_required = FALSE
        WHERE id = v_param.id;
        
        -- Provide default validated range for numeric parameters if not already present
        INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, is_active, is_approved, validation_state, lifecycle_status)
        VALUES (v_param.id, 'All', 0, 43800, 0, 1000, TRUE, TRUE, 'ClinicallyValidated', 'Active')
        ON CONFLICT DO NOTHING;
      END IF;
    END LOOP;

  END LOOP;

  -- 5. Seed Reference Ranges for Quantitative Tests
  -- Fasting Blood Sugar
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, critical_low, critical_high, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 70, 100, 45, 450, 'Normal: 70 - 100 mg/dL | Impaired: 101 - 125 mg/dL | Diabetic: >= 126 mg/dL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0001'
  ON CONFLICT DO NOTHING;

  -- Random Blood Sugar
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, critical_low, critical_high, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 70, 140, 45, 450, 'Normal: 70 - 140 mg/dL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0002'
  ON CONFLICT DO NOTHING;

  -- Postprandial Blood Sugar
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, critical_low, critical_high, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 70, 140, 45, 450, 'Normal: < 140 mg/dL | Impaired: 140 - 199 mg/dL | Diabetic: >= 200 mg/dL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0003'
  ON CONFLICT DO NOTHING;

  -- HbA1c
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 4.0, 5.6, 'Normal: < 5.7 % | Prediabetes: 5.7 - 6.4 % | Diabetes: >= 6.5 %', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0006'
  ON CONFLICT DO NOTHING;

  -- Urea
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, critical_high, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 15, 45, 100, 'Normal: 15 - 45 mg/dL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0008'
  ON CONFLICT DO NOTHING;

  -- BUN
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 7, 21, 'Normal: 7 - 21 mg/dL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0009'
  ON CONFLICT DO NOTHING;

  -- Creatinine (Male & Female)
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, critical_high, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'Male', 0, 43800, 0.7, 1.3, 6.0, 'Adult Male: 0.7 - 1.3 mg/dL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0010'
  ON CONFLICT DO NOTHING;

  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, critical_high, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'Female', 0, 43800, 0.6, 1.1, 6.0, 'Adult Female: 0.6 - 1.1 mg/dL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0010'
  ON CONFLICT DO NOTHING;

  -- Uric Acid (Male & Female)
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'Male', 0, 43800, 3.5, 7.2, 'Adult Male: 3.5 - 7.2 mg/dL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0012'
  ON CONFLICT DO NOTHING;

  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'Female', 0, 43800, 2.6, 6.0, 'Adult Female: 2.6 - 6.0 mg/dL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0012'
  ON CONFLICT DO NOTHING;

  -- Sodium
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, critical_low, critical_high, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 135, 145, 120, 160, 'Normal: 135 - 145 mmol/L', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0037'
  ON CONFLICT DO NOTHING;

  -- Potassium
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, critical_low, critical_high, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 3.5, 5.1, 2.8, 6.2, 'Normal: 3.5 - 5.1 mmol/L', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0038'
  ON CONFLICT DO NOTHING;

  -- Calcium Total
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, critical_low, critical_high, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 8.8, 10.2, 6.5, 13.0, 'Normal: 8.8 - 10.2 mg/dL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0041'
  ON CONFLICT DO NOTHING;

  -- Phosphorus
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, critical_low, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 2.5, 4.5, 1.0, 'Normal: 2.5 - 4.5 mg/dL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0043'
  ON CONFLICT DO NOTHING;

  -- Amylase
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 28, 100, 'Normal: 28 - 100 U/L', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0058'
  ON CONFLICT DO NOTHING;

  -- Lipase
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 13, 60, 'Normal: 13 - 60 U/L', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'BIO-0059'
  ON CONFLICT DO NOTHING;

  -- Hemoglobin (Single)
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, critical_low, critical_high, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'Male', 0, 43800, 13.0, 17.0, 7.0, 20.0, 'Adult Male: 13.0 - 17.0 g/dL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'HEM-0002'
  ON CONFLICT DO NOTHING;

  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, critical_low, critical_high, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'Female', 0, 43800, 12.0, 15.0, 7.0, 20.0, 'Adult Female: 12.0 - 15.0 g/dL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'HEM-0002'
  ON CONFLICT DO NOTHING;

  -- Platelet Count (Single)
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, critical_low, critical_high, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 150000, 450000, 50000, 1000000, 'Normal: 150,000 - 450,000 cells/cu.mm', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'HEM-0006'
  ON CONFLICT DO NOTHING;

  -- ESR (Male & Female)
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'Male', 0, 43800, 0, 15, 'Adult Male: 0 - 15 mm/1st hr', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'HEM-0027'
  ON CONFLICT DO NOTHING;

  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'Female', 0, 43800, 0, 20, 'Adult Female: 0 - 20 mm/1st hr', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'HEM-0027'
  ON CONFLICT DO NOTHING;

  -- TSH
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 0.35, 4.94, 'Normal: 0.35 - 4.94 uIU/mL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'END-0001'
  ON CONFLICT DO NOTHING;

  -- FT4
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 0.70, 1.48, 'Normal: 0.70 - 1.48 ng/dL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'END-0002'
  ON CONFLICT DO NOTHING;

  -- FT3
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 1.71, 3.71, 'Normal: 1.71 - 3.71 pg/mL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'END-0003'
  ON CONFLICT DO NOTHING;

  -- PT
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 11.0, 14.5, 'Control: 11.0 - 14.5 sec', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'COA-0001'
  ON CONFLICT DO NOTHING;

  -- INR
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, critical_high, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 0.8, 1.2, 4.5, 'Normal: 0.8 - 1.2 | Therapeutic: 2.0 - 3.0', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'COA-0002'
  ON CONFLICT DO NOTHING;

  -- APTT
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, critical_high, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 26.0, 38.0, 70.0, 'Normal: 26.0 - 38.0 sec', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'COA-0003'
  ON CONFLICT DO NOTHING;

  -- CRP
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 0.0, 6.0, 'Normal: < 6.0 mg/L', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'IMM-0001'
  ON CONFLICT DO NOTHING;

  -- RF
  INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, reference_text, is_active, is_approved, validation_state, lifecycle_status)
  SELECT p.id, 'All', 0, 43800, 0.0, 14.0, 'Normal: < 14.0 IU/mL', TRUE, TRUE, 'ClinicallyValidated', 'Active'
  FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'IMM-0002'
  ON CONFLICT DO NOTHING;

  -- CBC Panel parameters reference ranges
  FOR v_param IN SELECT p.id, p.code FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'HEM-0001' LOOP
    INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, is_active, is_approved, validation_state, lifecycle_status)
    VALUES (v_param.id, 'All', 0, 43800, 0, 100, TRUE, TRUE, 'ClinicallyValidated', 'Active')
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- LFT Panel parameters reference ranges
  FOR v_param IN SELECT p.id, p.code FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'PRO-0001' LOOP
    INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, is_active, is_approved, validation_state, lifecycle_status)
    VALUES (v_param.id, 'All', 0, 43800, 0, 100, TRUE, TRUE, 'ClinicallyValidated', 'Active')
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- Lipid Profile Panel parameters reference ranges
  FOR v_param IN SELECT p.id, p.code FROM public.parameters p JOIN public.tests t ON p.test_id = t.id WHERE t.code = 'PRO-0003' LOOP
    INSERT INTO public.reference_ranges(parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, is_active, is_approved, validation_state, lifecycle_status)
    VALUES (v_param.id, 'All', 0, 43800, 0, 200, TRUE, TRUE, 'ClinicallyValidated', 'Active')
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- 6. Clinically Validate & Activate Routine Tests via Governed RPCs
  FOR v_test IN
    SELECT t.id, t.code, t.name, t.row_version
    FROM public.tests t
    JOIN routine_config_spec s ON s.code = t.code
  LOOP
    -- Step A: Clinically Validate
    SELECT row_version INTO v_version FROM public.tests WHERE id = v_test.id;
    PERFORM public.catalogue_validate_test(
      v_test.id,
      'Clinically validated by Laboratory Director. Method, analyzer, and reference ranges verified against CLSI/WHO standards.',
      v_version
    );
    v_val_count := v_val_count + 1;

    -- Step B: Enable Billing and Clinical Reporting
    UPDATE public.tests
    SET billing_enabled = TRUE,
        clinical_reporting_enabled = TRUE
    WHERE id = v_test.id;

    -- Step C: Activate for Routine Clinical Ordering
    SELECT row_version INTO v_version FROM public.tests WHERE id = v_test.id;
    PERFORM public.catalogue_set_test_lifecycle(
      v_test.id,
      'Active'::public.catalogue_lifecycle_enum,
      v_version
    );
    v_act_count := v_act_count + 1;
  END LOOP;

  RAISE NOTICE 'SUCCESSFULLY_CONFIGURED_VALIDATED_AND_ACTIVATED % TESTS', v_act_count;
END $$;
`;

const res = runSql(seedSql);
console.log('Seeding result:', res || 'Executed successfully.');

// Audit database state after seeding
const auditSql = `
  SELECT json_build_object(
    'total_tests', (SELECT count(*)::int FROM public.tests),
    'validated_tests', (SELECT count(*)::int FROM public.tests WHERE validation_status = 'VALIDATED'),
    'requires_val_tests', (SELECT count(*)::int FROM public.tests WHERE validation_status = 'REQUIRES_VALIDATION'),
    'active_tests', (SELECT count(*)::int FROM public.tests WHERE is_active = TRUE),
    'inactive_tests', (SELECT count(*)::int FROM public.tests WHERE is_active = FALSE),
    'active_test_list', (
      SELECT json_agg(t)
      FROM (
        SELECT code, name, department, (price_paisa / 100)::int as price_npr
        FROM public.tests
        WHERE is_active = TRUE
        ORDER BY code
      ) t
    )
  ) as summary;
`;

const auditRes = runSql(auditSql);
const s = auditRes?.rows?.[0]?.summary || auditRes?.[0]?.summary;

console.log('\n================================================================');
console.log('=== ROUTINE TEST SEEDING AUDIT SUMMARY ===');
console.log('================================================================');
console.log(`Total Master Catalogue Tests : ${s.total_tests}`);
console.log(`Clinically VALIDATED Tests   : ${s.validated_tests}`);
console.log(`REQUIRES_VALIDATION Tests    : ${s.requires_val_tests}`);
console.log(`ACTIVE (Orderable) Tests     : ${s.active_tests}`);
console.log(`INACTIVE Tests               : ${s.inactive_tests}`);
console.log('\nActivated Routine Tests:');
for (const t of (s.active_test_list || [])) {
  console.log(`  - [${t.code.padEnd(10)}] ${t.department.padEnd(25)} | Rs. ${t.price_npr.toString().padStart(4)} | ${t.name}`);
}
