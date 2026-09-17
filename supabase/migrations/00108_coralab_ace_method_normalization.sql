-- Migration 00108: CORALAB ACE Analytical Method Normalization Pass
--
-- Normalizes test analytical methods so that active report methods represent
-- a single canonical active assay method instead of composite alternative strings (e.g. "Method A / Method B").
-- Supported alternative methods are stored in `alternative_methods` metadata.
-- `method_selection_status` tracks confirmation state ('CONFIRMED' or 'REQUIRES_CONFIRMATION').

BEGIN;

-- 1. Add method governance columns if not present
ALTER TABLE public.tests
    ADD COLUMN IF NOT EXISTS method_selection_status VARCHAR(50) DEFAULT 'CONFIRMED'
    CHECK (method_selection_status IN ('CONFIRMED', 'REQUIRES_CONFIRMATION')),
    ADD COLUMN IF NOT EXISTS alternative_methods TEXT[] DEFAULT ARRAY[]::TEXT[];

ALTER TABLE public.analyzer_parameter_mappings
    ADD COLUMN IF NOT EXISTS method_selection_status VARCHAR(50) DEFAULT 'CONFIRMED'
    CHECK (method_selection_status IN ('CONFIRMED', 'REQUIRES_CONFIRMATION')),
    ADD COLUMN IF NOT EXISTS alternative_methods TEXT[] DEFAULT ARRAY[]::TEXT[];

-- 2. Method Normalization for CORALAB ACE Routine Chemistry Assays
DO $$
DECLARE
    v_analyzer_id UUID;
BEGIN
    SELECT id INTO v_analyzer_id FROM public.analyzers WHERE code = 'CORALAB_ACE';

    -- A. Creatinine (BIO-0010): Primary = Modified Jaffe Kinetic; Alternative = Enzymatic Creatinine
    UPDATE public.tests
    SET method = 'Modified Jaffe Kinetic',
        alternative_methods = ARRAY['Enzymatic Creatinine'],
        method_selection_status = 'CONFIRMED'
    WHERE code = 'BIO-0010';

    UPDATE public.analyzer_parameter_mappings
    SET analytical_method = 'Modified Jaffe Kinetic',
        alternative_methods = ARRAY['Enzymatic Creatinine'],
        method_selection_status = 'CONFIRMED'
    WHERE analyzer_id = v_analyzer_id AND channel_code = 'CREAT';

    UPDATE public.test_analyzer_configurations
    SET method = 'Modified Jaffe Kinetic'
    WHERE analyzer_id = v_analyzer_id AND test_id IN (SELECT id FROM public.tests WHERE code = 'BIO-0010');

    -- B. Urea (BIO-0008): Primary = Urease-GLDH UV Kinetic; Alternative = Berthelot Urease
    UPDATE public.tests
    SET method = 'Urease-GLDH UV Kinetic',
        alternative_methods = ARRAY['Berthelot Urease'],
        method_selection_status = 'CONFIRMED'
    WHERE code = 'BIO-0008';

    UPDATE public.analyzer_parameter_mappings
    SET analytical_method = 'Urease-GLDH UV Kinetic',
        alternative_methods = ARRAY['Berthelot Urease'],
        method_selection_status = 'CONFIRMED'
    WHERE analyzer_id = v_analyzer_id AND channel_code = 'UREA';

    UPDATE public.test_analyzer_configurations
    SET method = 'Urease-GLDH UV Kinetic'
    WHERE analyzer_id = v_analyzer_id AND test_id IN (SELECT id FROM public.tests WHERE code = 'BIO-0008');

    -- C. HDL Cholesterol (BIO-0029): Primary = Direct Clearance (Immunoinhibition); Alternative = PEG Precipitation
    UPDATE public.tests
    SET method = 'Direct Clearance (Immunoinhibition)',
        alternative_methods = ARRAY['PEG Precipitation'],
        method_selection_status = 'CONFIRMED'
    WHERE code = 'BIO-0029';

    UPDATE public.analyzer_parameter_mappings
    SET analytical_method = 'Direct Clearance (Immunoinhibition)',
        alternative_methods = ARRAY['PEG Precipitation'],
        method_selection_status = 'CONFIRMED'
    WHERE analyzer_id = v_analyzer_id AND channel_code = 'HDL';

    UPDATE public.test_analyzer_configurations
    SET method = 'Direct Clearance (Immunoinhibition)'
    WHERE analyzer_id = v_analyzer_id AND test_id IN (SELECT id FROM public.tests WHERE code = 'BIO-0029');

    -- D. Calcium, Total (BIO-0041): Primary = Arsenazo III Photometric; Alternative = O-CPC Colorimetric
    UPDATE public.tests
    SET method = 'Arsenazo III Photometric',
        alternative_methods = ARRAY['O-CPC Colorimetric'],
        method_selection_status = 'CONFIRMED'
    WHERE code = 'BIO-0041';

    UPDATE public.analyzer_parameter_mappings
    SET analytical_method = 'Arsenazo III Photometric',
        alternative_methods = ARRAY['O-CPC Colorimetric'],
        method_selection_status = 'CONFIRMED'
    WHERE analyzer_id = v_analyzer_id AND channel_code = 'CALC';

    UPDATE public.test_analyzer_configurations
    SET method = 'Arsenazo III Photometric'
    WHERE analyzer_id = v_analyzer_id AND test_id IN (SELECT id FROM public.tests WHERE code = 'BIO-0041');

    -- E. Total Bilirubin (BIO-0017): Primary = Modified Jendrassik-Grof; Alternative = DCA Photometric
    UPDATE public.tests
    SET method = 'Modified Jendrassik-Grof',
        alternative_methods = ARRAY['DCA Photometric'],
        method_selection_status = 'CONFIRMED'
    WHERE code = 'BIO-0017';

    UPDATE public.analyzer_parameter_mappings
    SET analytical_method = 'Modified Jendrassik-Grof',
        alternative_methods = ARRAY['DCA Photometric'],
        method_selection_status = 'CONFIRMED'
    WHERE analyzer_id = v_analyzer_id AND channel_code = 'TBIL';

    UPDATE public.test_analyzer_configurations
    SET method = 'Modified Jendrassik-Grof'
    WHERE analyzer_id = v_analyzer_id AND test_id IN (SELECT id FROM public.tests WHERE code = 'BIO-0017');

    -- F. Alkaline Phosphatase / ALP (BIO-0022): Primary = Kinetic p-NPP (IFCC); Alternative = AMP Buffer Kinetic
    UPDATE public.tests
    SET method = 'Kinetic p-NPP (IFCC)',
        alternative_methods = ARRAY['AMP Buffer Kinetic', 'DGKC Kinetic'],
        method_selection_status = 'CONFIRMED'
    WHERE code = 'BIO-0022';

    UPDATE public.analyzer_parameter_mappings
    SET analytical_method = 'Kinetic p-NPP (IFCC)',
        alternative_methods = ARRAY['AMP Buffer Kinetic', 'DGKC Kinetic'],
        method_selection_status = 'CONFIRMED'
    WHERE analyzer_id = v_analyzer_id AND channel_code = 'ALP';

    UPDATE public.test_analyzer_configurations
    SET method = 'Kinetic p-NPP (IFCC)'
    WHERE analyzer_id = v_analyzer_id AND test_id IN (SELECT id FROM public.tests WHERE code = 'BIO-0022');

    -- G. Magnesium (BIO-0044): Primary = Calmagite Photometric; Alternative = Xylidyl Blue
    UPDATE public.tests
    SET method = 'Calmagite Photometric',
        alternative_methods = ARRAY['Xylidyl Blue'],
        method_selection_status = 'CONFIRMED'
    WHERE code = 'BIO-0044';

    UPDATE public.analyzer_parameter_mappings
    SET analytical_method = 'Calmagite Photometric',
        alternative_methods = ARRAY['Xylidyl Blue'],
        method_selection_status = 'CONFIRMED'
    WHERE analyzer_id = v_analyzer_id AND channel_code = 'MAG';

    UPDATE public.test_analyzer_configurations
    SET method = 'Calmagite Photometric'
    WHERE analyzer_id = v_analyzer_id AND test_id IN (SELECT id FROM public.tests WHERE code = 'BIO-0044');

    -- H. CK Total (BIO-0060): Primary = CK-NAC Kinetic (IFCC); Alternative = Modified IFCC Kinetic
    UPDATE public.tests
    SET method = 'CK-NAC Kinetic (IFCC)',
        alternative_methods = ARRAY['Modified IFCC Kinetic'],
        method_selection_status = 'CONFIRMED'
    WHERE code = 'BIO-0060';

    UPDATE public.analyzer_parameter_mappings
    SET analytical_method = 'CK-NAC Kinetic (IFCC)',
        alternative_methods = ARRAY['Modified IFCC Kinetic'],
        method_selection_status = 'CONFIRMED'
    WHERE analyzer_id = v_analyzer_id AND channel_code = 'CK_TOTAL';

    UPDATE public.test_analyzer_configurations
    SET method = 'CK-NAC Kinetic (IFCC)'
    WHERE analyzer_id = v_analyzer_id AND test_id IN (SELECT id FROM public.tests WHERE code = 'BIO-0060');

    -- I. LDH (BIO-0024): Primary = IFCC UV Kinetic; Alternative = DGKC Kinetic
    UPDATE public.tests
    SET method = 'IFCC UV Kinetic',
        alternative_methods = ARRAY['DGKC Kinetic'],
        method_selection_status = 'CONFIRMED'
    WHERE code = 'BIO-0024';

    UPDATE public.analyzer_parameter_mappings
    SET analytical_method = 'IFCC UV Kinetic',
        alternative_methods = ARRAY['DGKC Kinetic'],
        method_selection_status = 'CONFIRMED'
    WHERE analyzer_id = v_analyzer_id AND channel_code = 'LDH';

    UPDATE public.test_analyzer_configurations
    SET method = 'IFCC UV Kinetic'
    WHERE analyzer_id = v_analyzer_id AND test_id IN (SELECT id FROM public.tests WHERE code = 'BIO-0024');

END $$;

COMMIT;
