-- Migration 00110: Final Cross-Analyzer Harmonization, Specimen Governance & Critical Policy Layer
--
-- Harmonizes:
-- 1. CounCell 23 Excel (Hematology)
-- 2. CORALAB ACE (Clinical Biochemistry)
-- 3. FIAcheck (Fluorescence Immunoassay)
--
-- Core Invariants:
-- - Canonical Test Identity & Harmonization Aliases (Preserves all canonical test IDs)
-- - Assay-Specific Pre-Analytical Specimen Governance & Tube Routing
-- - Unit Normalization & Analytical Temperature Binding (37°C enzymes)
-- - Versioned Reference Intervals (with multi-tier interpretation preservation)
-- - Laboratory Critical / Panic Policy Governance (Stored with LAB_APPROVAL_REQUIRED status)
-- - Critical Value Notification State Machine & Callout Escalation Model

BEGIN;

-- ============================================================================
-- 1. INTEROPERABILITY & HARMONIZATION ALIASES
-- ============================================================================

DO $$
DECLARE
    v_test_id UUID;
BEGIN
    -- CBC_WBC -> HEM-0005 (WBC Count / TLC)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'HEM-0005';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'CBC_WBC', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- CBC_RBC -> HEM-0004 (RBC Count)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'HEM-0004';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'CBC_RBC', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- CBC_HGB -> HEM-0002 (Hemoglobin (Hb))
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'HEM-0002';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'CBC_HGB', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- CBC_PLT -> HEM-0006 (Platelet Count)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'HEM-0006';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'CBC_PLT', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- CBC_GRAN_P -> HEM-0001 (CBC Panel 3-part Granulocyte % Channel)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'HEM-0001';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'CBC_GRAN_P', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'CBC_MID_P', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- CBC_LYM_P -> HEM-0016 (Lymphocyte %)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'HEM-0016';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'CBC_LYM_P', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- BIO_ALT -> BIO-0021 (ALT / SGPT)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0021';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'BIO_ALT', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- BIO_AST -> BIO-0020 (AST / SGOT)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0020';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'BIO_AST', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- BIO_TBIL -> BIO-0017 (Total Bilirubin)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0017';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'BIO_TBIL', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- BIO_CREAT -> BIO-0010 (Creatinine)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0010';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'BIO_CREAT', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- BIO_UREA -> BIO-0008 (Urea)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0008';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'BIO_UREA', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- BIO_URIC -> BIO-0012 (Uric Acid)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0012';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'BIO_URIC', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- BIO_GLU_F -> BIO-0001 (Glucose, Fasting)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0001';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'BIO_GLU_F', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- BIO_CHOL -> BIO-0027 (Total Cholesterol)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0027';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'BIO_CHOL', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- BIO_TRIG -> BIO-0028 (Triglycerides)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0028';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'BIO_TRIG', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- IMM_TSH -> END-0001 (TSH)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0001';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'IMM_TSH', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- IMM_FT4 -> END-0002 (Free T4 (FT4))
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0002';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'IMM_FT4', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- IMM_FT3 -> END-0003 (Free T3 (FT3))
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0003';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'IMM_FT3', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- IMM_VITD -> BIO-0053 (Vitamin D, 25-OH)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0053';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'IMM_VITD', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- IMM_B12 -> BIO-0051 (Vitamin B12)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0051';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'IMM_B12', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- IMM_CTNI -> BIO-0063 (Troponin I, High Sensitivity)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0063';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'IMM_CTNI', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;

    -- IMM_BNP -> BIO-0067 (NT-proBNP)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0067';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES (v_test_id, 'IMM_BNP', 'Synonym') ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;
END $$;

-- ============================================================================
-- 2. PRE-ANALYTICAL SPECIMEN GOVERNANCE SCHEMA & SEEDING
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.assay_specimen_governance_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
    analyzer_id UUID REFERENCES public.analyzers(id) ON DELETE SET NULL,
    preferred_specimen VARCHAR(100) NOT NULL,
    allowed_specimens VARCHAR(100)[] DEFAULT '{}',
    conditional_specimens VARCHAR(100)[] DEFAULT '{}',
    primary_tube_color VARCHAR(50) NOT NULL,
    primary_tube_additive VARCHAR(100) NOT NULL,
    allowed_tube_colors VARCHAR(50)[] DEFAULT '{}',
    do_not_centrifuge BOOLEAN DEFAULT FALSE,
    centrifugation_instructions TEXT,
    centrifugation_rcf NUMERIC(10,2) DEFAULT NULL, -- Explicitly NULL when RPM is rotor-dependent
    clot_formation_minutes INTEGER DEFAULT NULL,
    temperature_guidance VARCHAR(100),
    max_delay_hours NUMERIC(6,2),
    conditional_rules JSONB DEFAULT '{}',
    special_precautions TEXT,
    laboratory_sop_source TEXT,
    governance_version VARCHAR(50) DEFAULT 'SPECIMEN_GOV_V1',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(test_id, analyzer_id, governance_version)
);

CREATE INDEX IF NOT EXISTS idx_specimen_gov_test_analyzer ON public.assay_specimen_governance_rules(test_id, analyzer_id);

-- Enable RLS
ALTER TABLE public.assay_specimen_governance_rules ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'assay_specimen_governance_rules' 
        AND policyname = 'Allow read access to authenticated users on assay_specimen_governance_rules'
    ) THEN
        CREATE POLICY "Allow read access to authenticated users on assay_specimen_governance_rules"
        ON public.assay_specimen_governance_rules FOR SELECT TO authenticated USING (true);
    END IF;
END $$;

-- Seed Pre-Analytical Specimen Rules
DO $$
DECLARE
    v_councell_id UUID;
    v_coralab_id UUID;
    v_fiacheck_id UUID;
    v_test_id UUID;
BEGIN
    SELECT id INTO v_councell_id FROM public.analyzers WHERE code = 'COUNCELL_23_EXCEL';
    SELECT id INTO v_coralab_id FROM public.analyzers WHERE code = 'CORALAB_ACE';
    SELECT id INTO v_fiacheck_id FROM public.analyzers WHERE code = 'FIACHECK';

    -- A. CounCell 23 Excel / CBC Parameters
    FOR v_test_id IN 
        SELECT id FROM public.tests WHERE code LIKE 'HEM-00%' AND code IN ('HEM-0001', 'HEM-0002', 'HEM-0003', 'HEM-0004', 'HEM-0005', 'HEM-0006', 'HEM-0007', 'HEM-0008', 'HEM-0009', 'HEM-0010', 'HEM-0011', 'HEM-0012', 'HEM-0013', 'HEM-0014')
    LOOP
        INSERT INTO public.assay_specimen_governance_rules (
            test_id, analyzer_id, preferred_specimen, allowed_specimens, primary_tube_color, primary_tube_additive,
            do_not_centrifuge, temperature_guidance, max_delay_hours, special_precautions, laboratory_sop_source, governance_version
        ) VALUES (
            v_test_id, v_councell_id, 'EDTA Whole Blood', ARRAY['Capillary Blood'], 'Lavender', 'K2-EDTA',
            TRUE, '18-25°C (up to 8 hours) or 2-8°C (up to 24 hours)', 8.0,
            'Mix 8-10 gentle inversions immediately after phlebotomy. Do not centrifuge.',
            'CounCell 23 Excel Laboratory Handling SOP (Versioned)', 'SPECIMEN_GOV_V1'
        ) ON CONFLICT (test_id, analyzer_id, governance_version) DO UPDATE SET
            preferred_specimen = EXCLUDED.preferred_specimen,
            primary_tube_color = EXCLUDED.primary_tube_color,
            primary_tube_additive = EXCLUDED.primary_tube_additive,
            do_not_centrifuge = EXCLUDED.do_not_centrifuge,
            special_precautions = EXCLUDED.special_precautions;
    END LOOP;

    -- B. CORALAB ACE / Routine Serum Biochemistry
    FOR v_test_id IN 
        SELECT id FROM public.tests WHERE code IN (
            'BIO-0008', 'BIO-0009', 'BIO-0010', 'BIO-0012', 'BIO-0013', 'BIO-0014', 'BIO-0015', 'BIO-0016',
            'BIO-0017', 'BIO-0018', 'BIO-0019', 'BIO-0020', 'BIO-0021', 'BIO-0022', 'BIO-0023', 'BIO-0024',
            'BIO-0027', 'BIO-0028', 'BIO-0029', 'BIO-0030', 'BIO-0031', 'BIO-0032', 'BIO-0033', 'BIO-0037',
            'BIO-0038', 'BIO-0039', 'BIO-0041', 'BIO-0043', 'BIO-0044', 'BIO-0058', 'BIO-0060', 'BIO-0062'
        )
    LOOP
        INSERT INTO public.assay_specimen_governance_rules (
            test_id, analyzer_id, preferred_specimen, allowed_specimens, primary_tube_color, primary_tube_additive,
            do_not_centrifuge, clot_formation_minutes, centrifugation_instructions, centrifugation_rcf,
            temperature_guidance, max_delay_hours, special_precautions, laboratory_sop_source, governance_version
        ) VALUES (
            v_test_id, v_coralab_id, 'Serum', ARRAY['Heparin Plasma'], 'Gold / Red', 'SST / Clot Activator',
            FALSE, 30, '3000 RPM x 10 min (Laboratory SOP centrifugation)', NULL,
            '2-8°C (up to 48 hours) or -20°C for prolonged storage', 4.0,
            'Allow ~30 minutes clot formation before centrifugation. Avoid gross hemolysis, lipemia, or icterus. Reaction temperature bound to 37°C.',
            'CORALAB ACE Routine Clinical Biochemistry SOP', 'SPECIMEN_GOV_V1'
        ) ON CONFLICT (test_id, analyzer_id, governance_version) DO UPDATE SET
            preferred_specimen = EXCLUDED.preferred_specimen,
            primary_tube_color = EXCLUDED.primary_tube_color,
            primary_tube_additive = EXCLUDED.primary_tube_additive,
            centrifugation_instructions = EXCLUDED.centrifugation_instructions,
            special_precautions = EXCLUDED.special_precautions;
    END LOOP;

    -- C. Glucose (FBS, PPBS, RBS) — Conditional Fluoride Specimen Rule
    FOR v_test_id IN SELECT id FROM public.tests WHERE code IN ('BIO-0001', 'BIO-0002', 'BIO-0003')
    LOOP
        INSERT INTO public.assay_specimen_governance_rules (
            test_id, analyzer_id, preferred_specimen, allowed_specimens, conditional_specimens,
            primary_tube_color, primary_tube_additive, allowed_tube_colors,
            do_not_centrifuge, clot_formation_minutes, centrifugation_instructions,
            temperature_guidance, max_delay_hours, conditional_rules, special_precautions,
            laboratory_sop_source, governance_version
        ) VALUES (
            v_test_id, v_coralab_id, 'Serum', ARRAY['Fluoride Plasma', 'Heparin Plasma'], ARRAY['Fluoride Plasma'],
            'Gold / Red', 'SST / Clot Activator', ARRAY['Grey', 'Green'],
            FALSE, 30, '3000 RPM x 10 min',
            '18-25°C or 2-8°C', 1.0,
            '{"delayed_processing_gt_60_min": {"required_tube": "Grey", "required_additive": "Sodium Fluoride / Potassium Oxalate", "clinical_rationale": "Inhibits in-vitro glycolysis when serum separation exceeds 60 minutes"}}'::jsonb,
            'For rapid separation within 60 minutes, SST serum is acceptable. Grey (Sodium Fluoride/Potassium Oxalate) is mandatory if processing is delayed > 60 min.',
            'Bimal Pathology Pre-Analytical Glycolysis Governance Protocol', 'SPECIMEN_GOV_V1'
        ) ON CONFLICT (test_id, analyzer_id, governance_version) DO UPDATE SET
            conditional_rules = EXCLUDED.conditional_rules,
            special_precautions = EXCLUDED.special_precautions;
    END LOOP;

    -- D. FIAcheck Serum Immunoassays (TSH, FT3, FT4, TT3, TT4, Vit D, Vit B12, Ferritin, Beta-hCG)
    FOR v_test_id IN SELECT id FROM public.tests WHERE code IN ('END-0001', 'END-0002', 'END-0003', 'END-0004', 'END-0005', 'BIO-0050', 'BIO-0051', 'BIO-0053', 'END-0039')
    LOOP
        INSERT INTO public.assay_specimen_governance_rules (
            test_id, analyzer_id, preferred_specimen, allowed_specimens, primary_tube_color, primary_tube_additive,
            do_not_centrifuge, clot_formation_minutes, centrifugation_instructions,
            temperature_guidance, max_delay_hours, special_precautions, laboratory_sop_source, governance_version
        ) VALUES (
            v_test_id, v_fiacheck_id, 'Serum', ARRAY['Heparin Plasma'], 'Gold / Red', 'SST / Clot Activator',
            FALSE, 30, '3000 RPM x 10 min',
            '2-8°C (up to 72 hours) or -20°C', 6.0,
            'Allow complete clot formation. Protect Vitamin D and Vitamin B12 aliquots from direct light exposure (amber tube / foil wrap).',
            'FIAcheck Fluorescence Immunoassay Pre-Analytical SOP', 'SPECIMEN_GOV_V1'
        ) ON CONFLICT (test_id, analyzer_id, governance_version) DO UPDATE SET
            special_precautions = EXCLUDED.special_precautions;
    END LOOP;

    -- E. FIAcheck Cardiac & Sepsis Rapid Whole Blood/Plasma Assays (cTnI, NT-proBNP, hs-CRP, PCT, Myoglobin)
    FOR v_test_id IN SELECT id FROM public.tests WHERE code IN ('BIO-0063', 'BIO-0065', 'BIO-0067', 'BIO-0068', 'PCT_SEPSIS')
    LOOP
        INSERT INTO public.assay_specimen_governance_rules (
            test_id, analyzer_id, preferred_specimen, allowed_specimens, primary_tube_color, primary_tube_additive,
            allowed_tube_colors, do_not_centrifuge, temperature_guidance, max_delay_hours, special_precautions,
            laboratory_sop_source, governance_version
        ) VALUES (
            v_test_id, v_fiacheck_id, 'Serum', ARRAY['EDTA Whole Blood', 'EDTA Plasma', 'Heparin Plasma'], 'Gold / Red', 'SST / Clot Activator',
            ARRAY['Lavender', 'Green'], FALSE, '18-25°C (urgent run within 4 hours) or 2-8°C', 4.0,
            'Per-assay cartridge compatibility verified. EDTA whole blood/plasma supported where indicated on specific test cartridge.',
            'FIAcheck Emergency & Critical Biomarker SOP', 'SPECIMEN_GOV_V1'
        ) ON CONFLICT (test_id, analyzer_id, governance_version) DO UPDATE SET
            allowed_specimens = EXCLUDED.allowed_specimens,
            allowed_tube_colors = EXCLUDED.allowed_tube_colors,
            special_precautions = EXCLUDED.special_precautions;
    END LOOP;

    -- F. D-Dimer (COA-0006) — Citrated Plasma Protocol
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'COA-0006';
    IF v_test_id IS NOT NULL THEN
        INSERT INTO public.assay_specimen_governance_rules (
            test_id, analyzer_id, preferred_specimen, allowed_specimens, primary_tube_color, primary_tube_additive,
            do_not_centrifuge, centrifugation_instructions, centrifugation_rcf, temperature_guidance, max_delay_hours,
            special_precautions, laboratory_sop_source, governance_version
        ) VALUES (
            v_test_id, v_fiacheck_id, 'Citrated Plasma', ARRAY['Citrated Whole Blood'], 'Light Blue', '3.2% Sodium Citrate',
            FALSE, '1500-2000g x 15 min platelet-poor plasma separation', 1500.0,
            '18-25°C (up to 4 hours) or 2-8°C (up to 24 hours)', 4.0,
            'Strict 9:1 blood-to-anticoagulant ratio required. Underfilled tubes must be rejected. Results locked in µg/mL FEU (never DDU).',
            'Bimal Pathology Coagulation & D-Dimer Governance Protocol', 'SPECIMEN_GOV_V1'
        ) ON CONFLICT (test_id, analyzer_id, governance_version) DO UPDATE SET
            preferred_specimen = EXCLUDED.preferred_specimen,
            primary_tube_color = EXCLUDED.primary_tube_color,
            primary_tube_additive = EXCLUDED.primary_tube_additive,
            special_precautions = EXCLUDED.special_precautions;
    END IF;
END $$;

-- ============================================================================
-- 3. CRITICAL / PANIC VALUE POLICIES & AUDIT TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.critical_value_policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
    parameter_id UUID REFERENCES public.parameters(id) ON DELETE CASCADE,
    critical_low NUMERIC(12,4),
    critical_high NUMERIC(12,4),
    critical_operator VARCHAR(20) NOT NULL DEFAULT '< or >',
    unit VARCHAR(50) NOT NULL,
    action_threshold_text TEXT,
    critical_policy_status VARCHAR(50) NOT NULL DEFAULT 'LAB_APPROVAL_REQUIRED',
    approved_by UUID REFERENCES public.user_profiles(id),
    approved_at TIMESTAMPTZ,
    effective_from DATE DEFAULT CURRENT_DATE,
    version VARCHAR(50) DEFAULT 'CRIT_POL_V1',
    source TEXT DEFAULT 'Bimal Pathology Laboratory Proposed Panic Limits Policy',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(test_id, parameter_id, version)
);

CREATE TABLE IF NOT EXISTS public.critical_alert_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_item_id UUID NOT NULL REFERENCES public.clinical_order_items(id) ON DELETE CASCADE,
    test_id UUID REFERENCES public.tests(id),
    parameter_id UUID REFERENCES public.parameters(id),
    detected_value NUMERIC(12,4),
    detected_text TEXT,
    unit VARCHAR(50),
    alert_state VARCHAR(50) NOT NULL DEFAULT 'CRITICAL_DETECTED',
    critical_detected_at TIMESTAMPTZ DEFAULT NOW(),
    critical_confirmed_at TIMESTAMPTZ,
    original_result JSONB,
    repeat_result JSONB,
    verification_action TEXT,
    verified_by UUID REFERENCES public.user_profiles(id),
    verified_at TIMESTAMPTZ,
    comments TEXT,
    call_started_at TIMESTAMPTZ,
    call_completed_at TIMESTAMPTZ,
    caller_user_id UUID REFERENCES public.user_profiles(id),
    caller_name TEXT,
    recipient_type VARCHAR(50),
    recipient_name TEXT,
    recipient_contact TEXT,
    read_back_confirmed BOOLEAN DEFAULT FALSE,
    read_back_at TIMESTAMPTZ,
    escalation_required BOOLEAN DEFAULT FALSE,
    escalation_notes TEXT,
    sla_deadline_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.critical_value_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.critical_alert_events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'critical_value_policies' 
        AND policyname = 'Allow read access to authenticated on critical_value_policies'
    ) THEN
        CREATE POLICY "Allow read access to authenticated on critical_value_policies"
        ON public.critical_value_policies FOR SELECT TO authenticated USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'critical_alert_events' 
        AND policyname = 'Allow authenticated users full access to critical_alert_events'
    ) THEN
        CREATE POLICY "Allow authenticated users full access to critical_alert_events"
        ON public.critical_alert_events FOR ALL TO authenticated USING (true) WITH CHECK (true);
    END IF;
END $$;

-- Seed Laboratory Proposed Critical Thresholds (LAB_APPROVAL_REQUIRED)
DO $$
DECLARE
    v_test_id UUID;
    v_param_id UUID;
BEGIN
    -- 1. WBC (< 2.0 or > 30.0 x10^3/µL)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'HEM-0005';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, 2.0, 30.0, '< or >', '10^3/µL', '< 2.0 or > 30.0 x10^3/µL (Severe Leukopenia / Hyperleukocytosis)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 2. RBC (< 2.5 x10^6/µL)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'HEM-0004';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, 2.5, NULL, '<', '10^6/µL', '< 2.5 x10^6/µL (Severe Anemia Threshold)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 3. Hemoglobin (< 7.0 or > 20.0 g/dL)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'HEM-0002';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, 7.0, 20.0, '< or >', 'g/dL', '< 7.0 or > 20.0 g/dL (Critical Transfusion / Polycythemia Alert)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 4. Platelets (< 50 or > 1000 x10^3/µL)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'HEM-0006';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, 50.0, 1000.0, '< or >', '10^3/µL', '< 50 or > 1000 x10^3/µL (Severe Thrombocytopenia / Thrombocytosis)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 5. ALT (> 500 U/L)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0021';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, NULL, 500.0, '>', 'U/L', '> 500 U/L (Acute Hepatocellular Injury)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 6. AST (> 500 U/L)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0020';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, NULL, 500.0, '>', 'U/L', '> 500 U/L (Acute Hepatic / Tissue Necrosis Alert)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 7. Total Bilirubin (> 15.0 mg/dL)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0017';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, NULL, 15.0, '>', 'mg/dL', '> 15.0 mg/dL (Severe Hyperbilirubinemia / Kernicterus Risk in Neonates)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 8. Creatinine (> 4.0 mg/dL)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0010';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, NULL, 4.0, '>', 'mg/dL', '> 4.0 mg/dL (Severe Renal Failure / Acute Kidney Injury Alert)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 9. Urea (> 100 mg/dL)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0008';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, NULL, 100.0, '>', 'mg/dL', '> 100 mg/dL (Severe Uremia)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 10. Uric Acid (> 12.0 mg/dL)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0012';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, NULL, 12.0, '>', 'mg/dL', '> 12.0 mg/dL (Severe Hyperuricemia / Tumor Lysis Syndrome Risk)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 11. Fasting Glucose (< 50 or > 400 mg/dL)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0001';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, 50.0, 400.0, '< or >', 'mg/dL', '< 50 or > 400 mg/dL (Severe Hypoglycemia / Diabetic Ketoacidosis Alert)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 12. Triglycerides (> 500 mg/dL)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0028';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, NULL, 500.0, '>', 'mg/dL', '> 500 mg/dL (Severe Hypertriglyceridemia / Acute Pancreatitis Risk)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 13. TSH (< 0.05 or > 20.0 µIU/mL)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'END-0001';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, 0.05, 20.0, '< or >', 'µIU/mL', '< 0.05 or > 20.0 µIU/mL (Thyrotoxic Crisis / Severe Myxedema Alert)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 14. Vitamin D (< 10 ng/mL)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0053';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, 10.0, NULL, '<', 'ng/mL', '< 10 ng/mL (Severe Vitamin D Deficiency Action Threshold)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 15. Vitamin B12 (< 150 pg/mL)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0051';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, 150.0, NULL, '<', 'pg/mL', '< 150 pg/mL (Severe Cobalamin Deficiency / Neuro-hematologic Alert)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 16. Troponin I (>= 0.30 ng/mL)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0063';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, NULL, 0.30, '>=', 'ng/mL', '>= 0.30 ng/mL (Myocardial Infarction High-Level Panic Threshold)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;

    -- 17. NT-proBNP (> 5000 pg/mL)
    SELECT id INTO v_test_id FROM public.tests WHERE code = 'BIO-0067';
    IF v_test_id IS NOT NULL THEN
        SELECT id INTO v_param_id FROM public.parameters WHERE test_id = v_test_id LIMIT 1;
        INSERT INTO public.critical_value_policies (
            test_id, parameter_id, critical_low, critical_high, critical_operator, unit, action_threshold_text, critical_policy_status
        ) VALUES (
            v_test_id, v_param_id, NULL, 5000.0, '>', 'pg/mL', '> 5000 pg/mL (Severe Acute Decompensated Heart Failure Panic Threshold)', 'LAB_APPROVAL_REQUIRED'
        ) ON CONFLICT (test_id, parameter_id, version) DO NOTHING;
    END IF;
END $$;

COMMIT;
