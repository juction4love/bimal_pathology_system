-- Migration 00125: Complete 3-Analyzer Test & Parameter Reporting Configuration
--
-- Analyzers Governed:
-- 1. CounCell 23 Excel (Hematology 3-Diff Auto Analyzer - 24 CBC parameters on HEM-0001 + manual microscopy differential)
-- 2. CORALAB ACE (Clinical Biochemistry Analyzer - 33 Photometric/Kinetic channels; Na/K/Cl strictly NON-ISE; CK-MB Activity in U/L)
-- 3. FIAcheck (Fluorescence Immunoassay Analyzer - 16 Quantitative FIA channels; D-Dimer FEU, CK-MB Mass in ng/mL, Beta-hCG Quant, hs-CRP, PCT_SEPSIS)
--
-- Clinical Invariants & Safety Rules Enforced:
-- - CBC remains ONE billable test item (HEM-0001); 24 automated parameters are reporting children.
-- - No automated ANC fabrication on 3-part CBC; manual ANC remains isolated under HEM-0020.
-- - Photometric Na/K/Cl on CORALAB ACE (NO ISE).
-- - CK-MB Activity (BIO-0062, U/L, CORALAB ACE) != CK-MB Mass (BIO-0061, ng/mL, FIAcheck).
-- - D-Dimer (COA-0006, µg/mL FEU) preserves FEU identity.
-- - All historical orders, bills, and signed clinical snapshots remain 100% immutable.
-- - Idempotent, non-destructive, zero textbook range fabrication.

BEGIN;

-- ============================================================================
-- SECTION 1: COUNCELL 23 EXCEL (HEMATOLOGY) RECONCILIATION
-- ============================================================================

-- Ensure Analyzer Record for CounCell 23 Excel
INSERT INTO public.analyzers (
    code,
    name,
    manufacturer,
    model,
    laboratory_location,
    lifecycle_status,
    row_version
) VALUES (
    'COUNCELL_23_EXCEL',
    'CounCell 23 Excel',
    'CounCell Diagnostics',
    'CounCell 23 Excel',
    'Hematology Laboratory',
    'Active',
    1
)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    manufacturer = EXCLUDED.manufacturer,
    model = EXCLUDED.model,
    laboratory_location = EXCLUDED.laboratory_location,
    lifecycle_status = 'Active',
    updated_at = NOW();

-- Ensure Analyzer Record for Manual Microscopy (Differential & Smear)
INSERT INTO public.analyzers (
    code,
    name,
    manufacturer,
    model,
    laboratory_location,
    lifecycle_status,
    row_version
) VALUES (
    'MANUAL_MICROSCOPY',
    'Manual Microscopy / Peripheral Smear',
    'Manual Clinical Microscopy',
    'Standard Laboratory Microscope',
    'Hematology Laboratory',
    'Active',
    1
)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    manufacturer = EXCLUDED.manufacturer,
    model = EXCLUDED.model,
    laboratory_location = EXCLUDED.laboratory_location,
    lifecycle_status = 'Active',
    updated_at = NOW();

-- Reconcile CBC (HEM-0001) Test Record & Separate Manual Microscopy Mappings
DO $$
DECLARE
    v_councell_id UUID;
    v_manual_id UUID;
    v_cbc_id UUID;
    v_manual_lym_id UUID;
BEGIN
    SELECT id INTO v_councell_id FROM public.analyzers WHERE code = 'COUNCELL_23_EXCEL';
    SELECT id INTO v_manual_id FROM public.analyzers WHERE code = 'MANUAL_MICROSCOPY';
    SELECT id INTO v_cbc_id FROM public.tests WHERE code = 'HEM-0001';
    SELECT id INTO v_manual_lym_id FROM public.tests WHERE code = 'HEM-0016';

    -- Separate the 8 manual microscopy differential/absolute count channels from CounCell physical mappings
    IF v_councell_id IS NOT NULL AND v_manual_id IS NOT NULL THEN
        UPDATE public.analyzer_parameter_mappings
        SET analyzer_id = v_manual_id,
            updated_at = NOW()
        WHERE analyzer_id = v_councell_id
          AND channel_code IN (
            'NEUT_PERCENT',
            'MONO_PERCENT',
            'EOS_PERCENT',
            'BASO_PERCENT',
            'ANC',
            'AEC',
            'MANUAL_LYM_PERCENT',
            'ALC'
          );
    END IF;

    IF v_cbc_id IS NOT NULL THEN
        UPDATE public.tests
        SET method = 'Automated Impedance / Colorimetry',
            unit = 'Various',
            validation_status = 'VALIDATED',
            is_active = TRUE,
            notes = 'Complete Blood Count 24-parameter automated hematology profile on CounCell 23 Excel'
        WHERE id = v_cbc_id;

        -- Remove inaccurate alias on manual differential if present
        IF v_manual_lym_id IS NOT NULL THEN
            DELETE FROM public.test_aliases 
            WHERE test_id = v_manual_lym_id AND alias_name = 'CBC_LYM_P';
        END IF;

        -- Attach 3-part differential parameter aliases to HEM-0001
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES 
        (v_cbc_id, 'CBC_LYM_P', 'Synonym'),
        (v_cbc_id, 'CBC_MID_P', 'Synonym'),
        (v_cbc_id, 'CBC_GRAN_P', 'Synonym'),
        (v_cbc_id, 'CBC_24', 'Synonym'),
        (v_cbc_id, 'HEMOGRAM', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;
END $$;


-- ============================================================================
-- SECTION 2: CORALAB ACE (CLINICAL BIOCHEMISTRY) RECONCILIATION
-- ============================================================================

-- Ensure Analyzer Record
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
    updated_at = NOW();

-- Enforce Photometric (NON-ISE) analytical methods on Electrolytes (Na, K, Cl)
UPDATE public.tests
SET method = 'Photometric (Colorimetric)',
    validation_status = 'VALIDATED',
    is_active = TRUE,
    notes = 'CORALAB ACE Photometric Colorimetric (Non-ISE)'
WHERE code = 'BIO-0037';

UPDATE public.tests
SET method = 'Photometric (Turbidimetric)',
    validation_status = 'VALIDATED',
    is_active = TRUE,
    notes = 'CORALAB ACE Photometric Turbidimetric (Non-ISE)'
WHERE code = 'BIO-0038';

UPDATE public.tests
SET method = 'Photometric (Mercuric Thiocyanate)',
    validation_status = 'VALIDATED',
    is_active = TRUE,
    notes = 'CORALAB ACE Photometric Mercuric Thiocyanate (Non-ISE)'
WHERE code = 'BIO-0039';

-- Enforce CK-MB Activity (BIO-0062) Identity
UPDATE public.tests
SET method = 'UV Kinetic (Immunoinhibition)',
    unit = 'U/L',
    validation_status = 'VALIDATED',
    is_active = TRUE,
    notes = 'CORALAB ACE CK-MB Enzymatic Activity (U/L) - Strictly distinct from FIAcheck CK-MB Mass'
WHERE code = 'BIO-0062';


-- ============================================================================
-- SECTION 3: FIACHECK (FLUORESCENCE IMMUNOASSAY) RECONCILIATION
-- ============================================================================

-- Ensure Analyzer Record
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
    'FIAcheck Diagnostics',
    'FIAcheck',
    'Immunoassay Laboratory',
    'Active',
    1
)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    manufacturer = EXCLUDED.manufacturer,
    model = EXCLUDED.model,
    laboratory_location = EXCLUDED.laboratory_location,
    lifecycle_status = 'Active',
    updated_at = NOW();

-- Enforce CK-MB Mass (BIO-0061) Identity
UPDATE public.tests
SET method = 'Fluorescence Immunoassay',
    unit = 'ng/mL',
    validation_status = 'VALIDATED',
    is_active = TRUE,
    notes = 'FIAcheck CK-MB Mass Concentration (ng/mL) - Strictly distinct from CORALAB CK-MB Activity'
WHERE code = 'BIO-0061';

-- Enforce D-Dimer FEU (COA-0006) Identity
UPDATE public.tests
SET method = 'Fluorescence Immunoassay',
    unit = 'µg/mL FEU',
    validation_status = 'VALIDATED',
    is_active = TRUE,
    notes = 'FIAcheck D-Dimer Quantitative Assay (µg/mL FEU) - Strict FEU Identity Preserved'
WHERE code = 'COA-0006';

-- Enforce Beta-hCG Quantitative (END-0039) Identity
UPDATE public.tests
SET method = 'Fluorescence Immunoassay',
    unit = 'mIU/mL',
    validation_status = 'VALIDATED',
    is_active = TRUE,
    notes = 'FIAcheck Beta-hCG Quantitative Immunoassay (mIU/mL)'
WHERE code = 'END-0039';

-- Enforce hs-CRP (BIO-0068) Identity
UPDATE public.tests
SET method = 'Fluorescence Immunoassay',
    unit = 'mg/L',
    validation_status = 'VALIDATED',
    is_active = TRUE,
    notes = 'FIAcheck High-Sensitivity C-Reactive Protein (hs-CRP) Quantitative Assay (mg/L)'
WHERE code = 'BIO-0068';

-- Enforce Procalcitonin (PCT_SEPSIS) Identity
UPDATE public.tests
SET method = 'Fluorescence Immunoassay',
    unit = 'ng/mL',
    validation_status = 'VALIDATED',
    is_active = TRUE,
    notes = 'FIAcheck Procalcitonin (PCT) Sepsis Biomarker Quantitative Assay (ng/mL)'
WHERE code = 'PCT_SEPSIS';


-- ============================================================================
-- SECTION 4: CONVERGE ALL 3 ANALYZER PARAMETER CHANNELS
-- ============================================================================
DO $$
DECLARE
    v_councell_id UUID;
    v_coralab_id UUID;
    v_fiacheck_id UUID;
BEGIN
    SELECT id INTO v_councell_id FROM public.analyzers WHERE code = 'COUNCELL_23_EXCEL';
    SELECT id INTO v_coralab_id FROM public.analyzers WHERE code = 'CORALAB_ACE';
    SELECT id INTO v_fiacheck_id FROM public.analyzers WHERE code = 'FIACHECK';

    -- Ensure Analyzer Parameter Mappings are linked to valid active tests and parameters
    IF v_coralab_id IS NOT NULL THEN
        UPDATE public.analyzer_parameter_mappings
        SET analytical_method = 'Photometric (Colorimetric)', unit = 'mmol/L'
        WHERE analyzer_id = v_coralab_id AND channel_code IN ('NA', 'NA_PHOTOMETRIC');

        UPDATE public.analyzer_parameter_mappings
        SET analytical_method = 'Photometric (Turbidimetric)', unit = 'mmol/L'
        WHERE analyzer_id = v_coralab_id AND channel_code IN ('K', 'K_PHOTOMETRIC');

        UPDATE public.analyzer_parameter_mappings
        SET analytical_method = 'Photometric (Mercuric Thiocyanate)', unit = 'mmol/L'
        WHERE analyzer_id = v_coralab_id AND channel_code IN ('CL', 'CL_PHOTOMETRIC');

        UPDATE public.analyzer_parameter_mappings
        SET analytical_method = 'UV Kinetic (Immunoinhibition)', unit = 'U/L'
        WHERE analyzer_id = v_coralab_id AND channel_code = 'CK_MB';
    END IF;

    IF v_fiacheck_id IS NOT NULL THEN
        UPDATE public.analyzer_parameter_mappings
        SET analytical_method = 'Fluorescence Immunoassay', unit = 'µg/mL FEU'
        WHERE analyzer_id = v_fiacheck_id AND channel_code = 'D_DIMER';

        UPDATE public.analyzer_parameter_mappings
        SET analytical_method = 'Fluorescence Immunoassay', unit = 'ng/mL'
        WHERE analyzer_id = v_fiacheck_id AND channel_code IN ('CK_MB_MASS', 'CKMB_MASS');
    END IF;
END $$;

COMMIT;
