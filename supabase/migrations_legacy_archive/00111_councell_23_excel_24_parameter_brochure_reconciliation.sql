-- Migration 00111: CounCell 23 Excel Official Brochure Reconciliation (24 Parameters + 3 Histograms)
--
-- Authoritative Brochure Specifications:
-- - Model: CounCell 23 Excel
-- - Type: 3-Diff Auto Hematology Analyzer
-- - Principles: Electrical impedance for WBC/RBC/PLT counting; Cyanide-free colorimetry for HGB estimation
-- - Parameters (24): WBC, LYM#, LYM%, MID#, MID%, GRAN#, GRAN%, RBC, HGB, HCT, MCV, MCH, MCHC,
--                    RDW-SD, RDW-CV, PLT, MPV, PCT, PDW-SD, PDW-CV, P-LCC, P-LCR, NLR, PLR
-- - Histograms (3): WBC, RBC, PLT
-- - Throughput: Up to 60 samples/hour
-- - Sample Volume: 9 µL
-- - Routine Reagents: Diluent, Lyse (Cyanide-free)
-- - Memory / Storage: 600,000 test values with parameters, histograms and patient info
-- - Connectivity Confirmed: USB, 1 Network Interface (LAN)
-- - Protocol Status: INTERFACE_PROTOCOL_PENDING_MANUFACTURER_DOCUMENTATION
--
-- Cross-Analyzer Semantic Fix:
-- - CBC_LYM_P -> CounCell 3-part LYM% analyzer parameter (NOT HEM-0016 Manual Lymphocyte %)
-- - CBC_MID_P -> CounCell 3-part MID% analyzer parameter
-- - CBC_GRAN_P -> CounCell 3-part GRAN% analyzer parameter
-- - Manual 5-part microscopy differential strictly isolated (8 optional manual fields)

BEGIN;

-- 1. Correct CBC_LYM_P Alias in public.test_aliases
DO $$
DECLARE
    v_cbc_id UUID;
    v_manual_lym_id UUID;
BEGIN
    SELECT id INTO v_cbc_id FROM public.tests WHERE code = 'HEM-0001';
    SELECT id INTO v_manual_lym_id FROM public.tests WHERE code = 'HEM-0016';

    -- Remove incorrect assignment of CBC_LYM_P to HEM-0016
    IF v_manual_lym_id IS NOT NULL THEN
        DELETE FROM public.test_aliases 
        WHERE test_id = v_manual_lym_id AND alias_name = 'CBC_LYM_P';
    END IF;

    -- Attach 3-part differential parameter aliases to HEM-0001 (CBC Panel)
    IF v_cbc_id IS NOT NULL THEN
        INSERT INTO public.test_aliases (test_id, alias_name, alias_type) VALUES 
        (v_cbc_id, 'CBC_LYM_P', 'Synonym'),
        (v_cbc_id, 'CBC_MID_P', 'Synonym'),
        (v_cbc_id, 'CBC_GRAN_P', 'Synonym')
        ON CONFLICT (test_id, alias_name) DO NOTHING;
    END IF;
END $$;

-- 2. Reconcile 24 Canonical CounCell 23 Excel Channels in public.analyzer_parameter_mappings
DO $$
DECLARE
    v_analyzer_id UUID;
    v_cbc_id UUID;
    v_wbc_id UUID;
    v_rbc_id UUID;
    v_hgb_id UUID;
    v_hct_id UUID;
    v_mcv_id UUID;
    v_mch_id UUID;
    v_mchc_id UUID;
    v_rdw_cv_id UUID;
    v_rdw_sd_id UUID;
    v_plt_id UUID;
    v_mpv_id UUID;
    v_pdw_id UUID;
    v_pct_id UUID;
    v_neut_id UUID;
    v_manual_lym_id UUID;
    v_mono_id UUID;
    v_eos_id UUID;
    v_baso_id UUID;
    v_anc_id UUID;
    v_aec_id UUID;
    v_manual_alc_id UUID;
BEGIN
    SELECT id INTO v_analyzer_id FROM public.analyzers WHERE code = 'COUNCELL_23_EXCEL';
    SELECT id INTO v_cbc_id FROM public.tests WHERE code = 'HEM-0001';

    -- Fetch Canonical Test IDs
    SELECT id INTO v_wbc_id FROM public.tests WHERE code = 'HEM-0005';
    SELECT id INTO v_rbc_id FROM public.tests WHERE code = 'HEM-0004';
    SELECT id INTO v_hgb_id FROM public.tests WHERE code = 'HEM-0002';
    SELECT id INTO v_hct_id FROM public.tests WHERE code = 'HEM-0003';
    SELECT id INTO v_mcv_id FROM public.tests WHERE code = 'HEM-0007';
    SELECT id INTO v_mch_id FROM public.tests WHERE code = 'HEM-0008';
    SELECT id INTO v_mchc_id FROM public.tests WHERE code = 'HEM-0009';
    SELECT id INTO v_rdw_cv_id FROM public.tests WHERE code = 'HEM-0010';
    SELECT id INTO v_rdw_sd_id FROM public.tests WHERE code = 'HEM-0011';
    SELECT id INTO v_plt_id FROM public.tests WHERE code = 'HEM-0006';
    SELECT id INTO v_mpv_id FROM public.tests WHERE code = 'HEM-0012';
    SELECT id INTO v_pdw_id FROM public.tests WHERE code = 'HEM-0013';
    SELECT id INTO v_pct_id FROM public.tests WHERE code = 'HEM-0014';

    SELECT id INTO v_neut_id FROM public.tests WHERE code = 'HEM-0015';
    SELECT id INTO v_manual_lym_id FROM public.tests WHERE code = 'HEM-0016';
    SELECT id INTO v_mono_id FROM public.tests WHERE code = 'HEM-0017';
    SELECT id INTO v_eos_id FROM public.tests WHERE code = 'HEM-0018';
    SELECT id INTO v_baso_id FROM public.tests WHERE code = 'HEM-0019';
    SELECT id INTO v_anc_id FROM public.tests WHERE code = 'HEM-0020';
    SELECT id INTO v_manual_alc_id FROM public.tests WHERE code = 'HEM-0021';
    SELECT id INTO v_aec_id FROM public.tests WHERE code = 'HEM-0022';

    -- Delete generic/stale PDW channel if present to replace with PDW-SD and PDW-CV
    DELETE FROM public.analyzer_parameter_mappings WHERE analyzer_id = v_analyzer_id AND channel_code = 'PDW';

    -- ------------------------------------------------------------------------
    -- A. Direct Measured Parameters (4)
    -- ------------------------------------------------------------------------
    INSERT INTO public.analyzer_parameter_mappings (
        analyzer_id, channel_code, channel_name, test_id, parameter_id,
        measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
    ) VALUES
    (v_analyzer_id, 'WBC', 'Total Leukocyte Count (WBC)', v_wbc_id, (SELECT id FROM public.parameters WHERE test_id = v_wbc_id LIMIT 1), 'DIRECT_MEASURED', 'Electrical Impedance', '10^3/µL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'RBC', 'Red Blood Cell Count (RBC)', v_rbc_id, (SELECT id FROM public.parameters WHERE test_id = v_rbc_id LIMIT 1), 'DIRECT_MEASURED', 'Electrical Impedance', '10^6/µL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'HGB', 'Hemoglobin (HGB)', v_hgb_id, (SELECT id FROM public.parameters WHERE test_id = v_hgb_id LIMIT 1), 'DIRECT_MEASURED', 'Cyanide-free Colorimetry', 'g/dL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'PLT', 'Platelet Count (PLT)', v_plt_id, (SELECT id FROM public.parameters WHERE test_id = v_plt_id LIMIT 1), 'DIRECT_MEASURED', 'Electrical Impedance', '10^3/µL', 'Not Applicable', FALSE)
    ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
        channel_name = EXCLUDED.channel_name,
        test_id = EXCLUDED.test_id,
        parameter_id = EXCLUDED.parameter_id,
        measurement_type = EXCLUDED.measurement_type,
        analytical_method = EXCLUDED.analytical_method,
        unit = EXCLUDED.unit;

    -- ------------------------------------------------------------------------
    -- B. 3-Part Differential Channels (6)
    -- ------------------------------------------------------------------------
    INSERT INTO public.analyzer_parameter_mappings (
        analyzer_id, channel_code, channel_name, test_id, parameter_id,
        measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
    ) VALUES
    (v_analyzer_id, 'LYM_PERCENT', 'Lymphocyte % (3-Part)', NULL, NULL, 'DIRECT_MEASURED', 'Electrical Impedance (Small cell cluster)', '%', '3-Part', FALSE),
    (v_analyzer_id, 'LYM_ABS', 'Absolute Lymphocyte Count (3-Part LYM#)', NULL, NULL, 'ANALYZER_CALCULATED', 'Analyzer Differential LYM#', '10^3/µL', '3-Part', FALSE),
    (v_analyzer_id, 'MID_PERCENT', 'Mid-Cell % (Monocytes/Eos/Baso cluster)', NULL, NULL, 'DIRECT_MEASURED', 'Electrical Impedance (Mid-size cell cluster)', '%', '3-Part', FALSE),
    (v_analyzer_id, 'MID_ABS', 'Absolute Mid-Cell Count (3-Part MID#)', NULL, NULL, 'ANALYZER_CALCULATED', 'Analyzer Differential MID#', '10^3/µL', '3-Part', FALSE),
    (v_analyzer_id, 'GRAN_PERCENT', 'Granulocyte % (Neutrophils/Eos/Baso)', NULL, NULL, 'DIRECT_MEASURED', 'Electrical Impedance (Large cell cluster)', '%', '3-Part', FALSE),
    (v_analyzer_id, 'GRAN_ABS', 'Absolute Granulocyte Count (3-Part GRAN#)', NULL, NULL, 'ANALYZER_CALCULATED', 'Analyzer Differential GRAN#', '10^3/µL', '3-Part', FALSE)
    ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
        channel_name = EXCLUDED.channel_name,
        test_id = NULL,
        parameter_id = NULL,
        measurement_type = EXCLUDED.measurement_type,
        analytical_method = EXCLUDED.analytical_method,
        unit = EXCLUDED.unit;

    -- ------------------------------------------------------------------------
    -- C. Analyzer Derived & Calculated Parameters (14)
    -- ------------------------------------------------------------------------
    INSERT INTO public.analyzer_parameter_mappings (
        analyzer_id, channel_code, channel_name, test_id, parameter_id,
        measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
    ) VALUES
    (v_analyzer_id, 'HCT', 'Hematocrit (HCT/PCV)', v_hct_id, (SELECT id FROM public.parameters WHERE test_id = v_hct_id LIMIT 1), 'ANALYZER_CALCULATED', 'Analyzer Calculated HCT', '%', 'Not Applicable', FALSE),
    (v_analyzer_id, 'MCV', 'Mean Corpuscular Volume (MCV)', v_mcv_id, (SELECT id FROM public.parameters WHERE test_id = v_mcv_id LIMIT 1), 'ANALYZER_DERIVED', 'Derived from RBC histogram peak', 'fL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'MCH', 'Mean Corpuscular Hemoglobin (MCH)', v_mch_id, (SELECT id FROM public.parameters WHERE test_id = v_mch_id LIMIT 1), 'ANALYZER_CALCULATED', 'Analyzer Calculated MCH', 'pg', 'Not Applicable', FALSE),
    (v_analyzer_id, 'MCHC', 'Mean Corpuscular Hemoglobin Conc. (MCHC)', v_mchc_id, (SELECT id FROM public.parameters WHERE test_id = v_mchc_id LIMIT 1), 'ANALYZER_CALCULATED', 'Analyzer Calculated MCHC', 'g/dL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'RDW_SD', 'Red Cell Distribution Width (RDW-SD)', v_rdw_sd_id, (SELECT id FROM public.parameters WHERE test_id = v_rdw_sd_id LIMIT 1), 'ANALYZER_DERIVED', 'RBC size histogram analysis (SD)', 'fL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'RDW_CV', 'Red Cell Distribution Width (RDW-CV)', v_rdw_cv_id, (SELECT id FROM public.parameters WHERE test_id = v_rdw_cv_id LIMIT 1), 'ANALYZER_DERIVED', 'RBC size histogram analysis (CV)', '%', 'Not Applicable', FALSE),
    (v_analyzer_id, 'MPV', 'Mean Platelet Volume (MPV)', v_mpv_id, (SELECT id FROM public.parameters WHERE test_id = v_mpv_id LIMIT 1), 'ANALYZER_DERIVED', 'PLT size histogram analysis', 'fL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'PCT', 'Plateletcrit (PCT)', v_pct_id, (SELECT id FROM public.parameters WHERE test_id = v_pct_id LIMIT 1), 'ANALYZER_CALCULATED', 'Analyzer Calculated PCT', '%', 'Not Applicable', FALSE),
    (v_analyzer_id, 'PDW_SD', 'Platelet Distribution Width (PDW-SD)', v_pdw_id, (SELECT id FROM public.parameters WHERE test_id = v_pdw_id LIMIT 1), 'ANALYZER_DERIVED', 'PLT histogram distribution SD', 'fL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'PDW_CV', 'Platelet Distribution Width (PDW-CV)', NULL, NULL, 'ANALYZER_DERIVED', 'PLT histogram distribution CV', '%', 'Not Applicable', FALSE),
    (v_analyzer_id, 'P_LCC', 'Platelet Large Cell Count (P-LCC)', NULL, NULL, 'ANALYZER_CALCULATED', 'Analyzer Calculated P-LCC', '10^3/µL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'P_LCR', 'Platelet Large Cell Ratio (P-LCR)', NULL, NULL, 'ANALYZER_DERIVED', 'PLT histogram analysis (>12 fL)', '%', 'Not Applicable', FALSE),
    (v_analyzer_id, 'NLR', 'Neutrophil-to-Lymphocyte Ratio (NLR)', NULL, NULL, 'ANALYZER_CALCULATED', 'Analyzer Calculated NLR', 'Ratio', 'Not Applicable', FALSE),
    (v_analyzer_id, 'PLR', 'Platelet-to-Lymphocyte Ratio (PLR)', NULL, NULL, 'ANALYZER_CALCULATED', 'Analyzer Calculated PLR', 'Ratio', 'Not Applicable', FALSE)
    ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
        channel_name = EXCLUDED.channel_name,
        test_id = EXCLUDED.test_id,
        parameter_id = EXCLUDED.parameter_id,
        measurement_type = EXCLUDED.measurement_type,
        analytical_method = EXCLUDED.analytical_method,
        unit = EXCLUDED.unit;

    -- ------------------------------------------------------------------------
    -- D. Manual 5-Part Differential Channels (Guarded as MANUAL_MICROSCOPY)
    -- ------------------------------------------------------------------------
    INSERT INTO public.analyzer_parameter_mappings (
        analyzer_id, channel_code, channel_name, test_id, parameter_id,
        measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
    ) VALUES
    (v_analyzer_id, 'NEUT_PERCENT', 'Neutrophils % (Manual Microscopy)', v_neut_id, (SELECT id FROM public.parameters WHERE test_id = v_neut_id LIMIT 1), 'MANUAL_MICROSCOPY', 'Leishman/Giemsa Stain Microscopy', '%', '5-Part Manual', FALSE),
    (v_analyzer_id, 'MANUAL_LYM_PERCENT', 'Lymphocytes % (Manual Microscopy)', v_manual_lym_id, (SELECT id FROM public.parameters WHERE test_id = v_manual_lym_id LIMIT 1), 'MANUAL_MICROSCOPY', 'Leishman/Giemsa Stain Microscopy', '%', '5-Part Manual', FALSE),
    (v_analyzer_id, 'MONO_PERCENT', 'Monocytes % (Manual Microscopy)', v_mono_id, (SELECT id FROM public.parameters WHERE test_id = v_mono_id LIMIT 1), 'MANUAL_MICROSCOPY', 'Leishman/Giemsa Stain Microscopy', '%', '5-Part Manual', FALSE),
    (v_analyzer_id, 'EOS_PERCENT', 'Eosinophils % (Manual Microscopy)', v_eos_id, (SELECT id FROM public.parameters WHERE test_id = v_eos_id LIMIT 1), 'MANUAL_MICROSCOPY', 'Leishman/Giemsa Stain Microscopy', '%', '5-Part Manual', FALSE),
    (v_analyzer_id, 'BASO_PERCENT', 'Basophils % (Manual Microscopy)', v_baso_id, (SELECT id FROM public.parameters WHERE test_id = v_baso_id LIMIT 1), 'MANUAL_MICROSCOPY', 'Leishman/Giemsa Stain Microscopy', '%', '5-Part Manual', FALSE),
    (v_analyzer_id, 'ANC', 'Absolute Neutrophil Count (Manual ANC)', v_anc_id, (SELECT id FROM public.parameters WHERE test_id = v_anc_id LIMIT 1), 'ANALYZER_CALCULATED', 'Calculated: (WBC * Manual Neutrophil %) / 100', '10^3/µL', '5-Part Manual', FALSE),
    (v_analyzer_id, 'ALC', 'Absolute Lymphocyte Count (Manual ALC)', v_manual_alc_id, (SELECT id FROM public.parameters WHERE test_id = v_manual_alc_id LIMIT 1), 'ANALYZER_CALCULATED', 'Calculated: (WBC * Manual Lymphocyte %) / 100', '10^3/µL', '5-Part Manual', FALSE),
    (v_analyzer_id, 'AEC', 'Absolute Eosinophil Count (Manual AEC)', v_aec_id, (SELECT id FROM public.parameters WHERE test_id = v_aec_id LIMIT 1), 'ANALYZER_CALCULATED', 'Calculated: (WBC * Manual Eosinophil %) / 100', 'cells/µL', '5-Part Manual', FALSE)
    ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
        channel_name = EXCLUDED.channel_name,
        test_id = EXCLUDED.test_id,
        parameter_id = EXCLUDED.parameter_id,
        measurement_type = EXCLUDED.measurement_type,
        analytical_method = EXCLUDED.analytical_method,
        unit = EXCLUDED.unit;

    -- ------------------------------------------------------------------------
    -- E. Update Test Analyzer Configuration with Official Brochure Specs
    -- ------------------------------------------------------------------------
    UPDATE public.test_analyzer_configurations
    SET 
        method = 'Electrical Impedance (WBC/RBC/PLT) & Cyanide-free Colorimetry (HGB)',
        validation_source = 'CounCell 23 Excel Official Brochure: 24 Parameters, 3 Histograms (WBC, RBC, PLT), 60 samples/hr, 9 µL sample volume, 600,000 test memory; Connectivity: USB, 1 Network Interface; Protocol Status: INTERFACE_PROTOCOL_PENDING_MANUFACTURER_DOCUMENTATION',
        updated_at = NOW()
    WHERE analyzer_id = v_analyzer_id AND test_id = v_cbc_id;

END $$;

COMMIT;
