-- Migration 00113: Create Distinct Canonical Rapid Serology Screening Tests (HIV Rapid, HBsAg Rapid, HCV Rapid)
--
-- Clinical & Governance Objectives:
-- 1. Preserves existing canonical tests and their specific clinical identities unchanged:
--    - SER-0001: HIV 1/2 Ag/Ab 4th Generation (4th Gen Combo Antigen/Antibody)
--    - SER-0004: HBsAg (Automated/General Serology)
--    - SER-0010: Anti-HCV (Automated/General Serology)
-- 2. Creates distinct canonical rapid screening tests with sequential canonical codes in Serology:
--    - SER-0086: HUMAN IMMUNODEFICIENCY VIRUS (HIV), RAPID SCREENING TEST (Short Name: HIV Rapid)
--    - SER-0087: HEPATITIS B SURFACE ANTIGEN (HBsAg), RAPID SCREENING TEST (Short Name: HBsAg Rapid)
--    - SER-0088: HCV RAPID SCREENING TEST (Short Name: HCV Rapid)
-- 3. Controlled qualitative Select result type ('Negative', 'Reactive') with NO default pre-selected patient result:
--    - Initial entry value is strictly NULL/blank, requiring explicit operator action.
--    - No arbitrary numeric ranges or S/CO ratios copied into rapid tests.
-- 4. Specimen governance:
--    - SER-0086 (HIV Rapid): Specimen = Serum; container per approved laboratory SOP; no unverified handling rules.
--    - SER-0087 (HBsAg Rapid): Specimen = Serum; container per approved laboratory SOP; no unverified handling rules.
--    - SER-0088 (HCV Rapid): Specimen pending validation; container pending lab SOP; no unverified handling rules.
--    - Specimen governance table delta = 0 (count remains 64 -> 64).
-- 5. Lifecycle & Verification Policy:
--    - In accordance with constraint `chk_tests_reporting_requires_validated`, clinical_reporting_enabled is FALSE while validation_status is 'REQUIRES_VALIDATION'.
--    - Tests are orderable/billable (billing_enabled = TRUE, is_active = TRUE) but final report release is blocked until formal Lab Director validation sign-off.
--    - Zero clinical approval records inserted (pending authorized sign-off).
-- 6. Seeds unambiguous bilingual billing search aliases without displacing existing generic test aliases.
-- 7. Preserves master catalogue invariants (Catalogue count increments 1,125 -> 1,128; 0 duplicate codes).

BEGIN;

-- ============================================================================
-- 1. INSERT DISTINCT CANONICAL RAPID SEROLOGY SCREENING TESTS
-- ============================================================================

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

-- Parameter for SER-0086 (No default patient result; operator must select explicitly)
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

-- Parameter for SER-0087 (No default patient result; operator must select explicitly)
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


-- C. HCV Rapid Screening -> SER-0088 (Specimen Pending Validation; Clinical Reporting Disabled)
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

-- Parameter for SER-0088 (No default patient result; operator must select explicitly)
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


-- ============================================================================
-- 2. REFERENCE RANGES (QUALITATIVE REFERENCE METADATA)
-- ============================================================================

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


-- ============================================================================
-- 3. SEED BILLING SEARCH ALIASES (TEST_ALIASES)
-- ============================================================================

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


-- ============================================================================
-- 4. CATALOGUE STANDARD PRESETS
-- ============================================================================

INSERT INTO public.catalogue_standard_presets (
    test_code,
    test_name,
    department,
    report_data_type,
    specimen,
    container,
    method,
    unit,
    tat_hours,
    qualitative_interpretation,
    reference_ranges
) VALUES
(
    'SER-0086',
    'HUMAN IMMUNODEFICIENCY VIRUS (HIV), RAPID SCREENING TEST',
    'Serology / Infectious Disease',
    'ReactiveNonReactive',
    'Serum',
    'Container per approved laboratory SOP',
    'Rapid Immunochromatography (Rapid Screening Test)',
    NULL,
    2,
    'Negative',
    '[{"gender": "All", "text": "Negative"}]'::jsonb
),
(
    'SER-0087',
    'HEPATITIS B SURFACE ANTIGEN (HBsAg), RAPID SCREENING TEST',
    'Serology / Infectious Disease',
    'ReactiveNonReactive',
    'Serum',
    'Container per approved laboratory SOP',
    'Rapid Immunochromatography (Rapid Screening Test)',
    NULL,
    2,
    'Negative',
    '[{"gender": "All", "text": "Negative"}]'::jsonb
),
(
    'SER-0088',
    'HCV RAPID SCREENING TEST',
    'Serology / Infectious Disease',
    'ReactiveNonReactive',
    'Specimen Pending Validation',
    'Container Pending Lab SOP',
    'Rapid Immunochromatography (Rapid Screening Test)',
    NULL,
    2,
    'Negative',
    '[{"gender": "All", "text": "Negative"}]'::jsonb
)
ON CONFLICT (test_code) DO UPDATE SET
    test_name = EXCLUDED.test_name,
    department = EXCLUDED.department,
    report_data_type = EXCLUDED.report_data_type,
    specimen = EXCLUDED.specimen,
    container = EXCLUDED.container,
    method = EXCLUDED.method,
    unit = EXCLUDED.unit,
    tat_hours = EXCLUDED.tat_hours,
    qualitative_interpretation = EXCLUDED.qualitative_interpretation,
    reference_ranges = EXCLUDED.reference_ranges;

COMMIT;
