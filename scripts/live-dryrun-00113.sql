-- Dry-run verification script for migration 00113 on linked production Supabase
-- Executes migration inside a rolled-back transaction to report exact impact without mutating live data.

BEGIN;

-- 1. Baseline Invariant Counts Before
SELECT
    (SELECT COUNT(*) FROM public.tests) AS tests_before,
    (SELECT COUNT(*) FROM public.tests WHERE test_type = 'Panel') AS panels_before,
    (SELECT COUNT(*) FROM public.catalogue_panel_components) AS panel_components_before,
    (SELECT COUNT(*) FROM public.parameters) AS parameters_before,
    (SELECT COUNT(*) FROM public.test_aliases) AS aliases_before,
    (SELECT COUNT(*) FROM public.reference_ranges) AS ref_ranges_before,
    (SELECT COUNT(*) FROM public.assay_specimen_governance_rules) AS specimen_rules_before,
    (SELECT COUNT(*) FROM (SELECT code FROM public.tests GROUP BY code HAVING COUNT(*) > 1) d) AS duplicate_test_codes_before;

-- 2. Verify baseline preserved tests exist untouched before
SELECT code, name, short_name, method, sample_type, is_active, billing_enabled, clinical_reporting_enabled
FROM public.tests
WHERE code IN ('SER-0001', 'SER-0004', 'SER-0010')
ORDER BY code;

-- 3. Execute Migration Statements

-- A. HIV Rapid Screening -> SER-0086
INSERT INTO public.tests (
    code,
    name,
    short_name,
    department,
    subdepartment,
    category,
    category_id,
    test_type,
    specimen_type,
    sample_type,
    container,
    container_type,
    method,
    unit,
    tat_description,
    report_data_type,
    fasting_required,
    is_outsource,
    is_active,
    billing_enabled,
    clinical_reporting_enabled,
    validation_status,
    configuration_status,
    clinical_configuration_status,
    lifecycle_status,
    notes,
    search_aliases,
    price_paisa,
    price_configured,
    allow_zero_price_billing,
    display_order
) VALUES (
    'SER-0086',
    'HUMAN IMMUNODEFICIENCY VIRUS (HIV), RAPID SCREENING TEST',
    'HIV Rapid',
    'Serology / Infectious Disease',
    'Serology / Rapid Screening',
    'Serology / Rapid Screening',
    (SELECT id FROM public.test_categories WHERE name = 'Serology & Immunology' LIMIT 1),
    'Single',
    'Serum',
    'Serum',
    'Container per approved laboratory SOP',
    'Container per approved laboratory SOP',
    'Rapid Immunochromatography (Rapid Screening Test)',
    NULL,
    'Routine',
    'ReactiveNonReactive',
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    FALSE, -- Enforced by chk_tests_reporting_requires_validated pending validation
    'REQUIRES_VALIDATION',
    'PENDING_APPROVAL',
    'Configured',
    'Active',
    'Reactive results suggest Acute / Chronic infection / Carrier state.' || E'\n' || 'Result may be Non reactive if an individual has not seroconverted at the time of testing.',
    ARRAY['hiv rapid', 'hiv rapid screening', 'hiv screening', 'hiv rapid test', 'एचआईभी र्‍यापिड', 'एचआईभी स्क्रिनिङ'],
    50000,
    TRUE,
    FALSE,
    86
) ON CONFLICT (code) DO NOTHING;

INSERT INTO public.parameters (
    test_id,
    code,
    name,
    value_type,
    unit,
    options,
    option_set_id,
    interpretation_config,
    is_active,
    is_mandatory,
    display_order
)
SELECT
    id,
    'SER-0086',
    'HUMAN IMMUNODEFICIENCY VIRUS (HIV), RAPID SCREENING TEST',
    'Select',
    NULL,
    '["Negative", "Reactive"]'::jsonb,
    (SELECT id FROM public.catalogue_option_sets WHERE code = 'REACTIVE_NON_REACTIVE' LIMIT 1),
    '{"control": "Select"}'::jsonb,
    TRUE,
    TRUE,
    1
FROM public.tests
WHERE code = 'SER-0086'
ON CONFLICT (test_id, code) DO NOTHING;

-- B. HBsAg Rapid Screening -> SER-0087
INSERT INTO public.tests (
    code,
    name,
    short_name,
    department,
    subdepartment,
    category,
    category_id,
    test_type,
    specimen_type,
    sample_type,
    container,
    container_type,
    method,
    unit,
    tat_description,
    report_data_type,
    fasting_required,
    is_outsource,
    is_active,
    billing_enabled,
    clinical_reporting_enabled,
    validation_status,
    configuration_status,
    clinical_configuration_status,
    lifecycle_status,
    notes,
    search_aliases,
    price_paisa,
    price_configured,
    allow_zero_price_billing,
    display_order
) VALUES (
    'SER-0087',
    'HEPATITIS B SURFACE ANTIGEN (HBsAg), RAPID SCREENING TEST',
    'HBsAg Rapid',
    'Serology / Infectious Disease',
    'Serology / Rapid Screening',
    'Serology / Rapid Screening',
    (SELECT id FROM public.test_categories WHERE name = 'Serology & Immunology' LIMIT 1),
    'Single',
    'Serum',
    'Serum',
    'Container per approved laboratory SOP',
    'Container per approved laboratory SOP',
    'Rapid Immunochromatography (Rapid Screening Test)',
    NULL,
    'Routine',
    'ReactiveNonReactive',
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    FALSE, -- Enforced by chk_tests_reporting_requires_validated pending validation
    'REQUIRES_VALIDATION',
    'PENDING_APPROVAL',
    'Configured',
    'Active',
    'Reactive results suggest Acute / Chronic infection / Carrier state. All Reactive results should be confirmed Neutralization test ( HBsAg Confirmatory test)' || E'\n' || 'Result may be Non reactive if an individual has not seroconverted at the time of testing.',
    ARRAY['hbsag rapid', 'hbs ag rapid', 'hbsag rapid screening', 'hepatitis b rapid', 'हेपाटाइटिस बी र्‍यापिड'],
    35000,
    TRUE,
    FALSE,
    87
) ON CONFLICT (code) DO NOTHING;

INSERT INTO public.parameters (
    test_id,
    code,
    name,
    value_type,
    unit,
    options,
    option_set_id,
    interpretation_config,
    is_active,
    is_mandatory,
    display_order
)
SELECT
    id,
    'SER-0087',
    'HEPATITIS B SURFACE ANTIGEN (HBsAg), RAPID SCREENING TEST',
    'Select',
    NULL,
    '["Negative", "Reactive"]'::jsonb,
    (SELECT id FROM public.catalogue_option_sets WHERE code = 'REACTIVE_NON_REACTIVE' LIMIT 1),
    '{"control": "Select"}'::jsonb,
    TRUE,
    TRUE,
    1
FROM public.tests
WHERE code = 'SER-0087'
ON CONFLICT (test_id, code) DO NOTHING;

-- C. HCV Rapid Screening -> SER-0088
INSERT INTO public.tests (
    code,
    name,
    short_name,
    department,
    subdepartment,
    category,
    category_id,
    test_type,
    specimen_type,
    sample_type,
    container,
    container_type,
    method,
    unit,
    tat_description,
    report_data_type,
    fasting_required,
    is_outsource,
    is_active,
    billing_enabled,
    clinical_reporting_enabled,
    validation_status,
    configuration_status,
    clinical_configuration_status,
    lifecycle_status,
    notes,
    search_aliases,
    price_paisa,
    price_configured,
    allow_zero_price_billing,
    display_order
) VALUES (
    'SER-0088',
    'HCV RAPID SCREENING TEST',
    'HCV Rapid',
    'Serology / Infectious Disease',
    'Serology / Rapid Screening',
    'Serology / Rapid Screening',
    (SELECT id FROM public.test_categories WHERE name = 'Serology & Immunology' LIMIT 1),
    'Single',
    'Specimen Pending Validation',
    'Specimen Pending Validation',
    'Container Pending Lab SOP',
    'Container Pending Lab SOP',
    'Rapid Immunochromatography (Rapid Screening Test)',
    NULL,
    'Routine',
    'ReactiveNonReactive',
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    FALSE, -- Reporting blocked pending approved specimen SOP
    'REQUIRES_VALIDATION',
    'PENDING_APPROVAL',
    'Requires Clinical Validation',
    'Active',
    NULL,
    ARRAY['hcv rapid', 'anti-hcv rapid', 'hcv rapid screening', 'hepatitis c rapid', 'हेपाटाइटिस सी र्‍यापिड'],
    45000,
    TRUE,
    FALSE,
    88
) ON CONFLICT (code) DO NOTHING;

INSERT INTO public.parameters (
    test_id,
    code,
    name,
    value_type,
    unit,
    options,
    option_set_id,
    interpretation_config,
    is_active,
    is_mandatory,
    display_order
)
SELECT
    id,
    'SER-0088',
    'HCV RAPID SCREENING TEST',
    'Select',
    NULL,
    '["Negative", "Reactive"]'::jsonb,
    (SELECT id FROM public.catalogue_option_sets WHERE code = 'REACTIVE_NON_REACTIVE' LIMIT 1),
    '{"control": "Select"}'::jsonb,
    TRUE,
    TRUE,
    1
FROM public.tests
WHERE code = 'SER-0088'
ON CONFLICT (test_id, code) DO NOTHING;

-- D. Reference Ranges (Qualitative Reference Metadata)
DELETE FROM public.reference_ranges
WHERE parameter_id IN (
    SELECT p.id FROM public.parameters p
    JOIN public.tests t ON t.id = p.test_id
    WHERE t.code IN ('SER-0086', 'SER-0087', 'SER-0088')
);

INSERT INTO public.reference_ranges (
    parameter_id,
    gender,
    age_min_days,
    age_max_days,
    normal_text,
    reference_text,
    is_active,
    is_approved,
    validation_state,
    validation_source
)
SELECT
    p.id,
    'All',
    0,
    43800,
    'Negative',
    'Negative',
    TRUE,
    FALSE,
    'LegacyDefaultRequiresValidation'::reference_range_validation_state_enum,
    'Standard Serological Screening Qualitative Policy (Negative / Non-Reactive)'
FROM public.parameters p
JOIN public.tests t ON t.id = p.test_id
WHERE t.code IN ('SER-0086', 'SER-0087', 'SER-0088');

-- E. Test Aliases
DO $$
DECLARE
    v_hiv_rapid_id UUID;
    v_hbsag_rapid_id UUID;
    v_hcv_rapid_id UUID;
BEGIN
    SELECT id INTO v_hiv_rapid_id FROM public.tests WHERE code = 'SER-0086';
    IF v_hiv_rapid_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_hiv_rapid_id, 'HIV Rapid', 'Synonym'),
        (v_hiv_rapid_id, 'HIV Rapid Screening', 'Synonym'),
        (v_hiv_rapid_id, 'HIV Screening', 'Synonym'),
        (v_hiv_rapid_id, 'HIV Rapid Test', 'Synonym'),
        (v_hiv_rapid_id, 'एचआईभी र्‍यापिड', 'Synonym'),
        (v_hiv_rapid_id, 'एचआईभी स्क्रिनिङ', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    SELECT id INTO v_hbsag_rapid_id FROM public.tests WHERE code = 'SER-0087';
    IF v_hbsag_rapid_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_hbsag_rapid_id, 'HBsAg Rapid', 'Synonym'),
        (v_hbsag_rapid_id, 'HBs Ag Rapid', 'Synonym'),
        (v_hbsag_rapid_id, 'HBsAg Rapid Screening', 'Synonym'),
        (v_hbsag_rapid_id, 'Hepatitis B Rapid', 'Synonym'),
        (v_hbsag_rapid_id, 'हेपाटाइटिस बी र्‍यापिड', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    SELECT id INTO v_hcv_rapid_id FROM public.tests WHERE code = 'SER-0088';
    IF v_hcv_rapid_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_hcv_rapid_id, 'HCV Rapid', 'Synonym'),
        (v_hcv_rapid_id, 'Anti-HCV Rapid', 'Synonym'),
        (v_hcv_rapid_id, 'HCV Rapid Screening', 'Synonym'),
        (v_hcv_rapid_id, 'Hepatitis C Rapid', 'Synonym'),
        (v_hcv_rapid_id, 'हेपाटाइटिस सी र्‍यापिड', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;
END $$;

-- 4. Post-Dry-Run Counts & Verification
SELECT
    (SELECT COUNT(*) FROM public.tests) AS tests_after,
    (SELECT COUNT(*) FROM public.tests WHERE test_type = 'Panel') AS panels_after,
    (SELECT COUNT(*) FROM public.catalogue_panel_components) AS panel_components_after,
    (SELECT COUNT(*) FROM public.parameters) AS parameters_after,
    (SELECT COUNT(*) FROM public.test_aliases) AS aliases_after,
    (SELECT COUNT(*) FROM public.reference_ranges) AS ref_ranges_after,
    (SELECT COUNT(*) FROM public.assay_specimen_governance_rules) AS specimen_rules_after,
    (SELECT COUNT(*) FROM (SELECT code FROM public.tests GROUP BY code HAVING COUNT(*) > 1) d) AS duplicate_test_codes_after;

-- 5. Verify preserved baseline tests remain unchanged
SELECT code, name, short_name, method, sample_type, is_active, billing_enabled, clinical_reporting_enabled
FROM public.tests
WHERE code IN ('SER-0001', 'SER-0004', 'SER-0010')
ORDER BY code;

-- 6. Verify newly inserted rapid tests
SELECT code, name, short_name, method, sample_type, is_active, billing_enabled, clinical_reporting_enabled, report_data_type, validation_status
FROM public.tests
WHERE code IN ('SER-0086', 'SER-0087', 'SER-0088')
ORDER BY code;

-- 7. Verify result default configuration in parameters
SELECT p.code, p.name, p.value_type, p.options, p.interpretation_config
FROM public.parameters p
JOIN public.tests t ON t.id = p.test_id
WHERE t.code IN ('SER-0086', 'SER-0087', 'SER-0088')
ORDER BY p.code;

-- 8. Rollback to keep live database completely untouched
ROLLBACK;
