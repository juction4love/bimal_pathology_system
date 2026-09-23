-- Migration 00114: Laboratory Test Rate Catalogue Activation, Combo Panels & Search Governance
--
-- Objectives:
-- 1. Introduces 3 distinct canonical test shells for unconfigured laboratory assays:
--    - IMM-0093: Interleukin-6 (IL-6) [Immunology | Rate: NPR 3,000 | Pending Clinical Validation]
--    - BIO-0141: Cystatin C (CysC) [Biochemistry | Rate: NPR 1,200 | Pending Clinical Validation]
--    - SER-0089: Scrub Typhus (FIA IgM/IgG) [Serology | Rate: NPR 1,000 | Method: FIA | Pending Clinical Validation]
-- 2. Introduces 4 distinct billable multi-analyte combo panels:
--    - PRO-0026: CARDIAC MARKERS COMBO (Troponin I + CK-MB Mass + Myoglobin) [Rate: NPR 2,500]
--    - PRO-0027: PCT + CRP COMBO (Procalcitonin + CRP Quantitative) [Rate: NPR 3,000]
--    - PRO-0028: COMPLETE THYROID PROFILE (Total T3 + Total T4 + TSH) [Rate: NPR 1,200]
--    - PRO-0029: DENGUE COMBO (NS1 Ag + IgM + IgG) [Rate: NPR 1,200]
-- 3. Sets authoritative patient billing rates in NPR / paisa for 32 active clinical tests & 4 panels.
-- 4. Preserves clinical identity distinctions:
--    - Troponin I (BIO-0063) distinct from Troponin T (BIO-0064).
--    - CK-MB Mass (BIO-0061) distinct from CK-MB Activity (BIO-0062).
--    - D-Dimer FEU (COA-0006) preserved in µg/mL FEU without conversion to DDU.
--    - hs-CRP (BIO-0068) distinct from routine CRP Quantitative (IMM-0001).
--    - Rapid serology (SER-0087 HBsAg Rapid, SER-0088 HCV Rapid) priced at NPR 600 while general serology (SER-0004, SER-0010) remains unchanged.
-- 5. Strict governance & historical immutability:
--    - New unvalidated shells have validation_status = 'REQUIRES_VALIDATION', clinical_reporting_enabled = FALSE.
--    - No historical billing items, invoice totals, or receipts modified.
--    - New active rate records logged in public.catalogue_rate_versions.
--    - Catalogue count increments: 1,128 -> 1,135 (3 new singles + 4 new panels; 0 duplicate codes).

BEGIN;

-- ============================================================================
-- 1. INSERT 3 NEW GOVERNED CANONICAL TEST SHELLS
-- ============================================================================

-- A. Interleukin-6 (IL-6) -> IMM-0093
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
    'IMM-0093',
    'Interleukin-6 (IL-6)',
    'IL-6',
    'Immunology',
    'Immunology / Cytokines',
    'Serology & Immunology',
    (SELECT id FROM public.test_categories WHERE name = 'Serology & Immunology' LIMIT 1),
    'Single',
    'Specimen Pending Validation',
    'Specimen Pending Validation',
    'Container Pending Lab SOP',
    'Container Pending Lab SOP',
    'Method Pending Clinical Validation',
    NULL,
    'Routine',
    'Numeric',
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    FALSE,
    'REQUIRES_VALIDATION',
    'PENDING_APPROVAL',
    'Requires Clinical Validation',
    'Active',
    'Clinical configuration, specimen rules, reference ranges, and method validation pending laboratory director approval.',
    ARRAY['il-6', 'il6', 'interleukin 6', 'interleukin-6', 'इन्टरल्युकिन ६'],
    300000,
    TRUE,
    FALSE,
    93
) ON CONFLICT (code) DO NOTHING;

-- B. Cystatin C (CysC) -> BIO-0141
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
    'BIO-0141',
    'Cystatin C',
    'CysC',
    'Clinical Biochemistry',
    'Renal Markers',
    'Clinical Biochemistry',
    (SELECT id FROM public.test_categories WHERE name = 'Clinical Biochemistry' LIMIT 1),
    'Single',
    'Specimen Pending Validation',
    'Specimen Pending Validation',
    'Container Pending Lab SOP',
    'Container Pending Lab SOP',
    'Method Pending Clinical Validation',
    NULL,
    'Routine',
    'Numeric',
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    FALSE,
    'REQUIRES_VALIDATION',
    'PENDING_APPROVAL',
    'Requires Clinical Validation',
    'Active',
    'Clinical configuration, specimen rules, reference ranges, and method validation pending laboratory director approval.',
    ARRAY['cystatin c', 'cysc', 'cystatin', 'सिस्टाटिन सी'],
    120000,
    TRUE,
    FALSE,
    141
) ON CONFLICT (code) DO NOTHING;

-- C. Scrub Typhus (FIA IgM/IgG) -> SER-0089
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
    'SER-0089',
    'Scrub Typhus (FIA IgM/IgG)',
    'Scrub Typhus FIA',
    'Serology / Infectious Disease',
    'Serology / Vector-Borne',
    'Serology & Immunology',
    (SELECT id FROM public.test_categories WHERE name = 'Serology & Immunology' LIMIT 1),
    'Single',
    'Specimen Pending Validation',
    'Specimen Pending Validation',
    'Container Pending Lab SOP',
    'Container Pending Lab SOP',
    'Fluorescence Immunoassay (FIA)',
    NULL,
    'Routine',
    'PositiveNegative',
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    FALSE,
    'REQUIRES_VALIDATION',
    'PENDING_APPROVAL',
    'Requires Clinical Validation',
    'Active',
    'Method: Fluorescence Immunoassay (FIA). Result architecture, specimen rules, and clinical parameter configuration pending laboratory validation.',
    ARRAY['scrub typhus', 'scrub typhus fia', 'scrub typhus igm/igg', 'orientia tsutsugamushi', 'स्क्रब टाइफस'],
    100000,
    TRUE,
    FALSE,
    89
) ON CONFLICT (code) DO NOTHING;

-- ============================================================================
-- 2. INSERT 4 NEW BILLABLE MULTI-ANALYTE COMBO PANELS
-- ============================================================================

-- A. Cardiac Markers Combo -> PRO-0026
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
    'PRO-0026',
    'CARDIAC MARKERS COMBO',
    'Cardiac Combo',
    'Profiles / Packages',
    'Cardiology Profiles',
    'Profiles & Health Packages',
    (SELECT id FROM public.test_categories WHERE name = 'Profiles & Health Packages' LIMIT 1),
    'Panel',
    'Multiple specimens as applicable',
    'Serum / Plasma',
    'Standard Container',
    'SST / Heparin / Citrate',
    'Fluorescence Immunoassay (FIAcheck)',
    'Panel',
    'Stat / 1 hour',
    'Panel',
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    FALSE,
    'REQUIRES_VALIDATION',
    'PENDING_APPROVAL',
    'Requires Clinical Validation',
    'Active',
    'Components: Troponin I, High Sensitivity (BIO-0063); CK-MB Mass (BIO-0061); Myoglobin (BIO-0065).',
    ARRAY['cardiac markers combo', 'cardiac combo', 'troponin ckmb myo combo', 'troponin combo', 'कार्डियाक कम्बो'],
    250000,
    TRUE,
    FALSE,
    26
) ON CONFLICT (code) DO NOTHING;

-- B. PCT + CRP Combo -> PRO-0027
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
    'PRO-0027',
    'PCT + CRP COMBO',
    'PCT + CRP',
    'Profiles / Packages',
    'Inflammation Profiles',
    'Profiles & Health Packages',
    (SELECT id FROM public.test_categories WHERE name = 'Profiles & Health Packages' LIMIT 1),
    'Panel',
    'Multiple specimens as applicable',
    'Serum / Plasma',
    'Standard Container',
    'Plain / SST / Heparin',
    'Multi-method composite (FIAcheck + Quantitative CRP)',
    'Panel',
    'Routine / 2 hours',
    'Panel',
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    FALSE,
    'REQUIRES_VALIDATION',
    'PENDING_APPROVAL',
    'Requires Clinical Validation',
    'Active',
    'Components: Procalcitonin (PCT_SEPSIS); CRP, Quantitative (IMM-0001).',
    ARRAY['pct + crp combo', 'pct crp', 'pct crp combo', 'procalcitonin crp combo', 'पिसिटी सिआरपी कम्बो'],
    300000,
    TRUE,
    FALSE,
    27
) ON CONFLICT (code) DO NOTHING;

-- C. Complete Thyroid Profile -> PRO-0028
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
    'PRO-0028',
    'COMPLETE THYROID PROFILE (T3, T4, TSH)',
    'Thyroid Profile (Total)',
    'Profiles / Packages',
    'Endocrinology Profiles',
    'Profiles & Health Packages',
    (SELECT id FROM public.test_categories WHERE name = 'Profiles & Health Packages' LIMIT 1),
    'Panel',
    'Multiple specimens as applicable',
    'Serum / Plasma',
    'Standard Container',
    'SST / Plain',
    'Fluorescence Immunoassay (FIAcheck)',
    'Panel',
    'Same Day / 2 hours',
    'Panel',
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    FALSE,
    'REQUIRES_VALIDATION',
    'PENDING_APPROVAL',
    'Requires Clinical Validation',
    'Active',
    'Components: Total T3 (END-0005); Total T4 (END-0004); TSH (END-0001). Distinct from Free Thyroid Profile (PRO-0004).',
    ARRAY['complete thyroid profile', 'thyroid profile total', 't3 t4 tsh', 'thyroid profile (t3, t4, tsh)', 'थाइरोइड प्रोफाइल (टोटल)'],
    120000,
    TRUE,
    FALSE,
    28
) ON CONFLICT (code) DO NOTHING;

-- D. Dengue Combo -> PRO-0029
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
    'PRO-0029',
    'DENGUE COMBO (NS1 + IgM + IgG)',
    'Dengue Combo',
    'Profiles / Packages',
    'Infectious Disease Profiles',
    'Profiles & Health Packages',
    (SELECT id FROM public.test_categories WHERE name = 'Profiles & Health Packages' LIMIT 1),
    'Panel',
    'Multiple specimens as applicable',
    'Serum / Plasma',
    'Standard Container',
    'SST / Plain',
    'Multi-analyte Immunoassay / Rapid Combo',
    'Panel',
    'Stat / 1 hour',
    'Panel',
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    FALSE,
    'REQUIRES_VALIDATION',
    'PENDING_APPROVAL',
    'Requires Clinical Validation',
    'Active',
    'Components: Dengue NS1 Antigen (SER-0015); Dengue IgM (SER-0016); Dengue IgG (SER-0017).',
    ARRAY['dengue combo', 'dengue ns1 igm igg', 'dengue panel', 'dengue test combo', 'डेङ्गु कम्बो'],
    120000,
    TRUE,
    FALSE,
    29
) ON CONFLICT (code) DO NOTHING;

-- ============================================================================
-- 3. LINK PANEL COMPONENTS IN public.catalogue_panel_components
-- ============================================================================

DO $$
DECLARE
    v_panel_id UUID;
    v_c1_id UUID;
    v_c2_id UUID;
    v_c3_id UUID;
BEGIN
    -- A. PRO-0026 (CARDIAC MARKERS COMBO) -> BIO-0063, BIO-0061, BIO-0065
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0026';
    SELECT id INTO v_c1_id FROM public.tests WHERE code = 'BIO-0063';
    SELECT id INTO v_c2_id FROM public.tests WHERE code = 'BIO-0061';
    SELECT id INTO v_c3_id FROM public.tests WHERE code = 'BIO-0065';
    IF v_panel_id IS NOT NULL AND v_c1_id IS NOT NULL AND v_c2_id IS NOT NULL AND v_c3_id IS NOT NULL THEN
        INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required) VALUES
        (v_panel_id, v_panel_id, v_c1_id, 1, TRUE),
        (v_panel_id, v_panel_id, v_c2_id, 2, TRUE),
        (v_panel_id, v_panel_id, v_c3_id, 3, TRUE)
        ON CONFLICT (panel_id, component_test_id) DO NOTHING;
    END IF;

    -- B. PRO-0027 (PCT + CRP COMBO) -> PCT_SEPSIS, IMM-0001
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0027';
    SELECT id INTO v_c1_id FROM public.tests WHERE code = 'PCT_SEPSIS';
    SELECT id INTO v_c2_id FROM public.tests WHERE code = 'IMM-0001';
    IF v_panel_id IS NOT NULL AND v_c1_id IS NOT NULL AND v_c2_id IS NOT NULL THEN
        INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required) VALUES
        (v_panel_id, v_panel_id, v_c1_id, 1, TRUE),
        (v_panel_id, v_panel_id, v_c2_id, 2, TRUE)
        ON CONFLICT (panel_id, component_test_id) DO NOTHING;
    END IF;

    -- C. PRO-0028 (COMPLETE THYROID PROFILE) -> END-0005, END-0004, END-0001
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0028';
    SELECT id INTO v_c1_id FROM public.tests WHERE code = 'END-0005';
    SELECT id INTO v_c2_id FROM public.tests WHERE code = 'END-0004';
    SELECT id INTO v_c3_id FROM public.tests WHERE code = 'END-0001';
    IF v_panel_id IS NOT NULL AND v_c1_id IS NOT NULL AND v_c2_id IS NOT NULL AND v_c3_id IS NOT NULL THEN
        INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required) VALUES
        (v_panel_id, v_panel_id, v_c1_id, 1, TRUE),
        (v_panel_id, v_panel_id, v_c2_id, 2, TRUE),
        (v_panel_id, v_panel_id, v_c3_id, 3, TRUE)
        ON CONFLICT (panel_id, component_test_id) DO NOTHING;
    END IF;

    -- D. PRO-0029 (DENGUE COMBO) -> SER-0015, SER-0016, SER-0017
    SELECT id INTO v_panel_id FROM public.tests WHERE code = 'PRO-0029';
    SELECT id INTO v_c1_id FROM public.tests WHERE code = 'SER-0015';
    SELECT id INTO v_c2_id FROM public.tests WHERE code = 'SER-0016';
    SELECT id INTO v_c3_id FROM public.tests WHERE code = 'SER-0017';
    IF v_panel_id IS NOT NULL AND v_c1_id IS NOT NULL AND v_c2_id IS NOT NULL AND v_c3_id IS NOT NULL THEN
        INSERT INTO public.catalogue_panel_components (panel_id, panel_test_id, component_test_id, display_order, is_required) VALUES
        (v_panel_id, v_panel_id, v_c1_id, 1, TRUE),
        (v_panel_id, v_panel_id, v_c2_id, 2, TRUE),
        (v_panel_id, v_panel_id, v_c3_id, 3, TRUE)
        ON CONFLICT (panel_id, component_test_id) DO NOTHING;
    END IF;
END $$;

-- ============================================================================
-- 4. UPDATE PATIENT BILLING RATES ON public.tests
-- ============================================================================

-- A. CARDIAC MARKERS
UPDATE public.tests SET price_paisa = 120000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'BIO-0063'; -- Troponin I (NPR 1,200)
UPDATE public.tests SET price_paisa = 180000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'BIO-0064'; -- Troponin T (NPR 1,800)
UPDATE public.tests SET price_paisa = 70000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'BIO-0061'; -- CK-MB Mass (NPR 700)
UPDATE public.tests SET price_paisa = 300000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'BIO-0067'; -- NT-proBNP (NPR 3,000)
UPDATE public.tests SET price_paisa = 150000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'COA-0006'; -- D-Dimer (NPR 1,500)

-- B. INFLAMMATION & INFECTION
UPDATE public.tests SET price_paisa = 70000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'BIO-0068'; -- hs-CRP (NPR 700)
UPDATE public.tests SET price_paisa = 70000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'IMM-0001'; -- CRP Quantitative (NPR 700)
UPDATE public.tests SET price_paisa = 250000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'PCT_SEPSIS'; -- Procalcitonin (NPR 2,500)
UPDATE public.tests SET price_paisa = 100000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'BIO-0050'; -- Ferritin (NPR 1,000)

-- C. DIABETES & RENAL MARKERS
UPDATE public.tests SET price_paisa = 80000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'BIO-0006'; -- HbA1c (NPR 800)
UPDATE public.tests SET price_paisa = 80000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'BIO-0085'; -- Urine Microalbumin (NPR 800)

-- D. THYROID & HORMONES
UPDATE public.tests SET price_paisa = 50000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'END-0001'; -- TSH (NPR 500)
UPDATE public.tests SET price_paisa = 55000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'END-0003'; -- Free T3 (NPR 550)
UPDATE public.tests SET price_paisa = 55000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'END-0002'; -- Free T4 (NPR 550)
UPDATE public.tests SET price_paisa = 100000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'END-0039'; -- Beta-hCG Quant (NPR 1,000)
UPDATE public.tests SET price_paisa = 120000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'END-0031'; -- Testosterone Total (NPR 1,200)
UPDATE public.tests SET price_paisa = 80000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'END-0028'; -- LH (NPR 800)
UPDATE public.tests SET price_paisa = 80000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'END-0027'; -- FSH (NPR 800)
UPDATE public.tests SET price_paisa = 80000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'END-0025'; -- Prolactin (NPR 800)
UPDATE public.tests SET price_paisa = 350000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'END-0037'; -- AMH (NPR 3,500)
UPDATE public.tests SET price_paisa = 200000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'BIO-0053'; -- Vitamin D, 25-OH (NPR 2,000)

-- E. INFECTIOUS & FEVER
UPDATE public.tests SET price_paisa = 100000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'SER-0020'; -- Scrub Typhus IgM (NPR 1,000)
UPDATE public.tests SET price_paisa = 80000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'SER-0015'; -- Dengue NS1 Ag (NPR 800)
UPDATE public.tests SET price_paisa = 60000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'SER-0087'; -- HBsAg Rapid (NPR 600)
UPDATE public.tests SET price_paisa = 60000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'SER-0088'; -- HCV Rapid (NPR 600)
UPDATE public.tests SET price_paisa = 100000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'SER-0043'; -- H. pylori Stool Antigen (NPR 1,000)

-- F. RHEUMATISM & TUMOR MARKERS
UPDATE public.tests SET price_paisa = 220000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'IMM-0004'; -- Anti-CCP (NPR 2,200)
UPDATE public.tests SET price_paisa = 60000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'IMM-0003'; -- ASO Titer (NPR 600)
UPDATE public.tests SET price_paisa = 60000,  price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'IMM-0002'; -- RF (NPR 600)
UPDATE public.tests SET price_paisa = 120000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'IMM-0031'; -- Total IgE (NPR 1,200)
UPDATE public.tests SET price_paisa = 120000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'TUM-0007'; -- Total PSA (NPR 1,200)
UPDATE public.tests SET price_paisa = 140000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'TUM-0001'; -- AFP (NPR 1,400)
UPDATE public.tests SET price_paisa = 140000, price_configured = TRUE, is_active = TRUE, billing_enabled = TRUE WHERE code = 'TUM-0002'; -- CEA (NPR 1,400)

-- ============================================================================
-- 5. RECORD EFFECTIVE-DATED RATE VERSIONS IN public.catalogue_rate_versions
-- ============================================================================

DO $$
DECLARE
    r RECORD;
    v_next_version INT;
BEGIN
    FOR r IN (
        SELECT id AS test_id, price_paisa
        FROM public.tests
        WHERE code IN (
            'BIO-0063', 'BIO-0064', 'BIO-0061', 'BIO-0067', 'COA-0006',
            'BIO-0068', 'IMM-0001', 'PCT_SEPSIS', 'IMM-0093', 'BIO-0050',
            'BIO-0006', 'BIO-0085', 'BIO-0141',
            'END-0001', 'END-0003', 'END-0002', 'END-0039', 'END-0031', 'END-0028', 'END-0027', 'END-0025', 'END-0037', 'BIO-0053',
            'SER-0020', 'SER-0089', 'SER-0015', 'SER-0087', 'SER-0088', 'SER-0043',
            'IMM-0004', 'IMM-0003', 'IMM-0002', 'IMM-0031', 'TUM-0007', 'TUM-0001', 'TUM-0002',
            'PRO-0026', 'PRO-0027', 'PRO-0028', 'PRO-0029'
        ) AND price_paisa IS NOT NULL
    ) LOOP
        -- Deactivate prior active rate if present
        UPDATE public.catalogue_rate_versions
        SET status = 'Inactive', effective_to = NOW(), updated_at = NOW()
        WHERE test_id = r.test_id AND status = 'Active';

        -- Get next version number
        SELECT COALESCE(MAX(version_number), 0) + 1 INTO v_next_version
        FROM public.catalogue_rate_versions
        WHERE test_id = r.test_id;

        -- Insert active version
        INSERT INTO public.catalogue_rate_versions (
            entity_type,
            test_id,
            version_number,
            price_paisa,
            effective_from,
            status
        ) VALUES (
            'Test',
            r.test_id,
            v_next_version,
            r.price_paisa,
            NOW(),
            'Active'
        );
    END LOOP;
END $$;

-- ============================================================================
-- 6. SEED COMPREHENSIVE BILINGUAL SEARCH ALIASES
-- ============================================================================

DO $$
DECLARE
    v_tid UUID;
BEGIN
    -- Troponin I -> BIO-0063
    SELECT id INTO v_tid FROM public.tests WHERE code = 'BIO-0063';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'cTnI', 'Acronym'), (v_tid, 'Troponin I', 'Synonym'), (v_tid, 'Trop I', 'Synonym'), (v_tid, 'ट्रोपोनिन आई', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Troponin T -> BIO-0064
    SELECT id INTO v_tid FROM public.tests WHERE code = 'BIO-0064';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'cTnT', 'Acronym'), (v_tid, 'Troponin T', 'Synonym'), (v_tid, 'Trop T', 'Synonym'), (v_tid, 'ट्रोपोनिन टी', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- CK-MB Mass -> BIO-0061
    SELECT id INTO v_tid FROM public.tests WHERE code = 'BIO-0061';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'CK-MB', 'Acronym'), (v_tid, 'CKMB', 'Acronym'), (v_tid, 'CK-MB Mass', 'Synonym'), (v_tid, 'सीके-एमबी', 'Acronym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Myoglobin -> BIO-0065
    SELECT id INTO v_tid FROM public.tests WHERE code = 'BIO-0065';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'Myoglobin', 'Synonym'), (v_tid, 'Myo', 'Acronym'), (v_tid, 'मायोग्लोबिन', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- NT-proBNP -> BIO-0067
    SELECT id INTO v_tid FROM public.tests WHERE code = 'BIO-0067';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'NT-proBNP', 'Acronym'), (v_tid, 'proBNP', 'Acronym'), (v_tid, 'BNP', 'Acronym'), (v_tid, 'एनटी-प्रोबिएनपी', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- D-Dimer -> COA-0006
    SELECT id INTO v_tid FROM public.tests WHERE code = 'COA-0006';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'D-Dimer', 'Acronym'), (v_tid, 'D Dimer', 'Synonym'), (v_tid, 'D-Dimer FEU', 'Synonym'), (v_tid, 'डी-डाइमर', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- hs-CRP -> BIO-0068
    SELECT id INTO v_tid FROM public.tests WHERE code = 'BIO-0068';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'hsCRP', 'Acronym'), (v_tid, 'hs-CRP', 'Acronym'), (v_tid, 'High Sensitivity CRP', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- CRP Quantitative -> IMM-0001
    SELECT id INTO v_tid FROM public.tests WHERE code = 'IMM-0001';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'CRP', 'Acronym'), (v_tid, 'CRP Quantitative', 'Synonym'), (v_tid, 'C-Reactive Protein', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Procalcitonin -> PCT_SEPSIS
    SELECT id INTO v_tid FROM public.tests WHERE code = 'PCT_SEPSIS';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'PCT', 'Acronym'), (v_tid, 'Procalcitonin', 'Synonym'), (v_tid, 'प्रोकैल्सिटोनिन', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Interleukin-6 -> IMM-0093
    SELECT id INTO v_tid FROM public.tests WHERE code = 'IMM-0093';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'IL-6', 'Acronym'), (v_tid, 'IL6', 'Acronym'), (v_tid, 'Interleukin-6', 'Synonym'), (v_tid, 'Interleukin 6', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Ferritin -> BIO-0050
    SELECT id INTO v_tid FROM public.tests WHERE code = 'BIO-0050';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'Ferritin', 'Synonym'), (v_tid, 'Serum Ferritin', 'Synonym'), (v_tid, 'फेरिटीन', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- HbA1c -> BIO-0006
    SELECT id INTO v_tid FROM public.tests WHERE code = 'BIO-0006';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'HbA1c', 'Acronym'), (v_tid, 'Glycated Hemoglobin', 'Synonym'), (v_tid, 'A1c', 'Acronym'), (v_tid, 'एचबिएवानसी', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Urine Microalbumin -> BIO-0085
    SELECT id INTO v_tid FROM public.tests WHERE code = 'BIO-0085';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'Microalbumin', 'Synonym'), (v_tid, 'mAlb', 'Acronym'), (v_tid, 'Urine Microalbumin', 'Synonym'), (v_tid, 'Microalbumin Urine', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Cystatin C -> BIO-0141
    SELECT id INTO v_tid FROM public.tests WHERE code = 'BIO-0141';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'Cystatin C', 'Synonym'), (v_tid, 'CysC', 'Acronym'), (v_tid, 'Cystatin', 'Synonym'), (v_tid, 'सिस्टाटिन सी', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- TSH -> END-0001
    SELECT id INTO v_tid FROM public.tests WHERE code = 'END-0001';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'TSH', 'Acronym'), (v_tid, 'Thyroid Stimulating Hormone', 'Synonym'), (v_tid, 'थाइरोइड हर्मोन TSH', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Free T3 -> END-0003
    SELECT id INTO v_tid FROM public.tests WHERE code = 'END-0003';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'FT3', 'Acronym'), (v_tid, 'Free T3', 'Synonym'), (v_tid, 'Free Triiodothyronine', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Free T4 -> END-0002
    SELECT id INTO v_tid FROM public.tests WHERE code = 'END-0002';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'FT4', 'Acronym'), (v_tid, 'Free T4', 'Synonym'), (v_tid, 'Free Thyroxine', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Total T3 -> END-0005
    SELECT id INTO v_tid FROM public.tests WHERE code = 'END-0005';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'T3', 'Acronym'), (v_tid, 'Total T3', 'Synonym'), (v_tid, 'Triiodothyronine Total', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Total T4 -> END-0004
    SELECT id INTO v_tid FROM public.tests WHERE code = 'END-0004';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'T4', 'Acronym'), (v_tid, 'Total T4', 'Synonym'), (v_tid, 'Thyroxine Total', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Beta-hCG -> END-0039
    SELECT id INTO v_tid FROM public.tests WHERE code = 'END-0039';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'Beta HCG', 'Acronym'), (v_tid, 'beta-hCG', 'Acronym'), (v_tid, 'Beta-hCG Quantitative', 'Synonym'), (v_tid, 'HCG Quantitative', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Testosterone -> END-0031
    SELECT id INTO v_tid FROM public.tests WHERE code = 'END-0031';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'Testosterone', 'Synonym'), (v_tid, 'Total Testosterone', 'Synonym'), (v_tid, 'टेस्टोस्टेरोन', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- LH -> END-0028
    SELECT id INTO v_tid FROM public.tests WHERE code = 'END-0028';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'LH', 'Acronym'), (v_tid, 'Luteinizing Hormone', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- FSH -> END-0027
    SELECT id INTO v_tid FROM public.tests WHERE code = 'END-0027';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'FSH', 'Acronym'), (v_tid, 'Follicle Stimulating Hormone', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Prolactin -> END-0025
    SELECT id INTO v_tid FROM public.tests WHERE code = 'END-0025';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'Prolactin', 'Synonym'), (v_tid, 'PRL', 'Acronym'), (v_tid, 'प्रोल्याक्टिन', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- AMH -> END-0037
    SELECT id INTO v_tid FROM public.tests WHERE code = 'END-0037';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'AMH', 'Acronym'), (v_tid, 'Anti-Mullerian Hormone', 'Synonym'), (v_tid, 'Anti Mullerian Hormone', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Vitamin D -> BIO-0053
    SELECT id INTO v_tid FROM public.tests WHERE code = 'BIO-0053';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'Vitamin D', 'Synonym'), (v_tid, '25-OH Vitamin D', 'Synonym'), (v_tid, '25-OH-VD', 'Acronym'), (v_tid, 'भिटामिन डी', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Scrub Typhus IgM -> SER-0020
    SELECT id INTO v_tid FROM public.tests WHERE code = 'SER-0020';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'Scrub Typhus', 'Synonym'), (v_tid, 'Scrub Typhus IgM', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Scrub Typhus FIA -> SER-0089
    SELECT id INTO v_tid FROM public.tests WHERE code = 'SER-0089';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'Scrub Typhus FIA', 'Synonym'), (v_tid, 'Scrub Typhus (FIA IgM/IgG)', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Dengue NS1 Ag -> SER-0015
    SELECT id INTO v_tid FROM public.tests WHERE code = 'SER-0015';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'Dengue NS1', 'Synonym'), (v_tid, 'NS1', 'Acronym'), (v_tid, 'Dengue Antigen', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- H. pylori Stool Antigen -> SER-0043
    SELECT id INTO v_tid FROM public.tests WHERE code = 'SER-0043';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'H pylori', 'Synonym'), (v_tid, 'H. pylori', 'Synonym'), (v_tid, 'H. pylori Antigen (Stool)', 'Synonym'), (v_tid, 'H Pylori Stool', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Anti-CCP -> IMM-0004
    SELECT id INTO v_tid FROM public.tests WHERE code = 'IMM-0004';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'Anti CCP', 'Synonym'), (v_tid, 'Anti-CCP', 'Synonym'), (v_tid, 'CCP', 'Acronym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- ASO -> IMM-0003
    SELECT id INTO v_tid FROM public.tests WHERE code = 'IMM-0003';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'ASO', 'Acronym'), (v_tid, 'ASO Titer', 'Synonym'), (v_tid, 'ASO Quantitative', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- RF -> IMM-0002
    SELECT id INTO v_tid FROM public.tests WHERE code = 'IMM-0002';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'RF', 'Acronym'), (v_tid, 'Rheumatoid Factor', 'Synonym'), (v_tid, 'RF Quantitative', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Total IgE -> IMM-0031
    SELECT id INTO v_tid FROM public.tests WHERE code = 'IMM-0031';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'IgE', 'Acronym'), (v_tid, 'Total IgE', 'Synonym'), (v_tid, 'Immunoglobulin E', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- Total PSA -> TUM-0007
    SELECT id INTO v_tid FROM public.tests WHERE code = 'TUM-0007';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'PSA', 'Acronym'), (v_tid, 'Total PSA', 'Synonym'), (v_tid, 'PSA Total', 'Synonym'), (v_tid, 'Prostate Specific Antigen', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- AFP -> TUM-0001
    SELECT id INTO v_tid FROM public.tests WHERE code = 'TUM-0001';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'AFP', 'Acronym'), (v_tid, 'Alpha-Fetoprotein', 'Synonym'), (v_tid, 'Alpha Fetoprotein', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- CEA -> TUM-0002
    SELECT id INTO v_tid FROM public.tests WHERE code = 'TUM-0002';
    IF v_tid IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES
        (v_tid, 'CEA', 'Acronym'), (v_tid, 'Carcinoembryonic Antigen', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;
END $$;

COMMIT;
