-- Migration 00106: CounCell 23 Excel Canonical 21-Parameter Reconciliation & CBC Panel Governance
--
-- Reconciles the exact 21 automated parameters of CounCell 23 Excel:
-- 1. Direct Measured (4): WBC, RBC, HGB, PLT
-- 2. Analyzer Derived / Calculated (11): HCT, MCV, MCH, MCHC, RDW-CV, RDW-SD, MPV, PDW, PCT, P-LCR, P-LCC
-- 3. 3-Part Differential (6): LYM%, LYM#, MID%, MID#, GRAN%, GRAN#
--
-- Manual Microscopy 5-Part Differential (Strictly Separate & Optional):
-- - Neutrophils %, Lymphocytes % (Manual), Monocytes %, Eosinophils %, Basophils %
-- - ANC (Manual Calculated), AEC (Manual Calculated)
-- - Strictly guarded: Never auto-populated from 3-part GRAN% / MID%

BEGIN;

-- 1. Ensure P-LCR and P-LCC channels are registered in analyzer_parameter_mappings
DO $$
DECLARE
    v_analyzer_id UUID;
    v_cbc_id UUID;
    v_p_lcr_param_id UUID;
    v_p_lcc_param_id UUID;
BEGIN
    SELECT id INTO v_analyzer_id FROM public.analyzers WHERE code = 'COUNCELL_23_EXCEL';
    SELECT id INTO v_cbc_id FROM public.tests WHERE code = 'HEM-0001';

    -- Upsert 21 Canonical CounCell 23 Parameters
    -- A. Direct Measured Parameters (4)
    INSERT INTO public.analyzer_parameter_mappings (
        analyzer_id, channel_code, channel_name, measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
    ) VALUES
    (v_analyzer_id, 'WBC', 'Total Leukocyte Count (WBC)', 'DIRECT_MEASURED', 'Electrical Impedance', '10^3/µL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'RBC', 'Red Blood Cell Count (RBC)', 'DIRECT_MEASURED', 'Electrical Impedance', '10^6/µL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'HGB', 'Hemoglobin (HGB)', 'DIRECT_MEASURED', 'Cyanide-free Colorimetry', 'g/dL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'PLT', 'Platelet Count (PLT)', 'DIRECT_MEASURED', 'Electrical Impedance', '10^3/µL', 'Not Applicable', FALSE)
    ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
        channel_name = EXCLUDED.channel_name,
        measurement_type = EXCLUDED.measurement_type,
        analytical_method = EXCLUDED.analytical_method,
        unit = EXCLUDED.unit;

    -- B. Analyzer Derived & Calculated Parameters (11)
    INSERT INTO public.analyzer_parameter_mappings (
        analyzer_id, channel_code, channel_name, measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
    ) VALUES
    (v_analyzer_id, 'HCT', 'Hematocrit (HCT/PCV)', 'ANALYZER_CALCULATED', 'Calculated: (RBC * MCV) / 10', '%', 'Not Applicable', FALSE),
    (v_analyzer_id, 'MCV', 'Mean Corpuscular Volume (MCV)', 'ANALYZER_DERIVED', 'Derived from RBC histogram peak', 'fL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'MCH', 'Mean Corpuscular Hemoglobin (MCH)', 'ANALYZER_CALCULATED', 'Calculated: (HGB * 10) / RBC', 'pg', 'Not Applicable', FALSE),
    (v_analyzer_id, 'MCHC', 'Mean Corpuscular Hemoglobin Conc. (MCHC)', 'ANALYZER_CALCULATED', 'Calculated: (HGB * 100) / HCT', 'g/dL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'RDW_CV', 'Red Cell Distribution Width (RDW-CV)', 'ANALYZER_DERIVED', 'RBC size histogram analysis (CV)', '%', 'Not Applicable', FALSE),
    (v_analyzer_id, 'RDW_SD', 'Red Cell Distribution Width (RDW-SD)', 'ANALYZER_DERIVED', 'RBC size histogram analysis (SD)', 'fL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'MPV', 'Mean Platelet Volume (MPV)', 'ANALYZER_DERIVED', 'PLT size histogram analysis', 'fL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'PDW', 'Platelet Distribution Width (PDW)', 'ANALYZER_DERIVED', 'PLT histogram distribution', 'fL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'PCT', 'Plateletcrit (PCT)', 'ANALYZER_CALCULATED', 'Calculated: (PLT * MPV) / 10000', '%', 'Not Applicable', FALSE),
    (v_analyzer_id, 'P_LCR', 'Platelet Large Cell Ratio (P-LCR)', 'ANALYZER_DERIVED', 'PLT histogram analysis (>12 fL)', '%', 'Not Applicable', FALSE),
    (v_analyzer_id, 'P_LCC', 'Platelet Large Cell Count (P-LCC)', 'ANALYZER_CALCULATED', 'Calculated: (PLT * P-LCR) / 100', '10^3/µL', 'Not Applicable', FALSE)
    ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
        channel_name = EXCLUDED.channel_name,
        measurement_type = EXCLUDED.measurement_type,
        analytical_method = EXCLUDED.analytical_method,
        unit = EXCLUDED.unit;

    -- C. 3-Part Differential Channels (6)
    INSERT INTO public.analyzer_parameter_mappings (
        analyzer_id, channel_code, channel_name, measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
    ) VALUES
    (v_analyzer_id, 'LYM_PERCENT', 'Lymphocyte % (3-Part)', 'DIRECT_MEASURED', 'Electrical Impedance (Small cell cluster)', '%', '3-Part', FALSE),
    (v_analyzer_id, 'LYM_ABS', 'Absolute Lymphocyte Count (3-Part LYM#)', 'ANALYZER_CALCULATED', 'Calculated: (WBC * LYM%) / 100', '10^3/µL', '3-Part', FALSE),
    (v_analyzer_id, 'MID_PERCENT', 'Mid-Cell % (Monocytes/Eos/Baso cluster)', 'DIRECT_MEASURED', 'Electrical Impedance (Mid-size cell cluster)', '%', '3-Part', FALSE),
    (v_analyzer_id, 'MID_ABS', 'Absolute Mid-Cell Count (3-Part MID#)', 'ANALYZER_CALCULATED', 'Calculated: (WBC * MID%) / 100', '10^3/µL', '3-Part', FALSE),
    (v_analyzer_id, 'GRAN_PERCENT', 'Granulocyte % (Neutrophils/Eos/Baso)', 'DIRECT_MEASURED', 'Electrical Impedance (Large cell cluster)', '%', '3-Part', FALSE),
    (v_analyzer_id, 'GRAN_ABS', 'Absolute Granulocyte Count (3-Part GRAN#)', 'ANALYZER_CALCULATED', 'Calculated: (WBC * GRAN%) / 100', '10^3/µL', '3-Part', FALSE)
    ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
        channel_name = EXCLUDED.channel_name,
        measurement_type = EXCLUDED.measurement_type,
        analytical_method = EXCLUDED.analytical_method,
        unit = EXCLUDED.unit;

    -- D. Manual 5-Part Differential Channels (Guarded as MANUAL_MICROSCOPY)
    INSERT INTO public.analyzer_parameter_mappings (
        analyzer_id, channel_code, channel_name, measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
    ) VALUES
    (v_analyzer_id, 'NEUT_PERCENT', 'Neutrophils % (Manual Microscopy)', 'MANUAL_MICROSCOPY', 'Leishman/Giemsa Stain Microscopy', '%', '5-Part Manual', FALSE),
    (v_analyzer_id, 'MONO_PERCENT', 'Monocytes % (Manual Microscopy)', 'MANUAL_MICROSCOPY', 'Leishman/Giemsa Stain Microscopy', '%', '5-Part Manual', FALSE),
    (v_analyzer_id, 'EOS_PERCENT', 'Eosinophils % (Manual Microscopy)', 'MANUAL_MICROSCOPY', 'Leishman/Giemsa Stain Microscopy', '%', '5-Part Manual', FALSE),
    (v_analyzer_id, 'BASO_PERCENT', 'Basophils % (Manual Microscopy)', 'MANUAL_MICROSCOPY', 'Leishman/Giemsa Stain Microscopy', '%', '5-Part Manual', FALSE),
    (v_analyzer_id, 'ANC', 'Absolute Neutrophil Count (Manual ANC)', 'ANALYZER_CALCULATED', 'Calculated: (WBC * Manual Neutrophil %) / 100', '10^3/µL', '5-Part Manual', FALSE),
    (v_analyzer_id, 'AEC', 'Absolute Eosinophil Count (Manual AEC)', 'ANALYZER_CALCULATED', 'Calculated: (WBC * Manual Eosinophil %) / 100', 'cells/µL', '5-Part Manual', FALSE)
    ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
        channel_name = EXCLUDED.channel_name,
        measurement_type = EXCLUDED.measurement_type,
        analytical_method = EXCLUDED.analytical_method,
        unit = EXCLUDED.unit;

    -- 2. Audit and update CBC HEM-0001 panel components in catalogue_panel_components
    -- Automated CBC components are required; Manual microscopy differential components are optional
    UPDATE public.catalogue_panel_components
    SET is_required = TRUE,
        component_role = CASE
            WHEN component_test_id IN (SELECT id FROM public.tests WHERE code IN ('HEM-0003', 'HEM-0008', 'HEM-0009', 'HEM-0014')) THEN 'Calculated'
            ELSE 'Measured'
        END
    WHERE panel_id = v_cbc_id
      AND component_test_id IN (
        SELECT id FROM public.tests
        WHERE code IN (
            'HEM-0002', 'HEM-0004', 'HEM-0003', 'HEM-0007', 'HEM-0008', 'HEM-0009',
            'HEM-0010', 'HEM-0011', 'HEM-0005', 'HEM-0006', 'HEM-0012', 'HEM-0013', 'HEM-0014'
        )
      );

    UPDATE public.catalogue_panel_components
    SET is_required = FALSE,
        component_role = CASE
            WHEN component_test_id IN (SELECT id FROM public.tests WHERE code IN ('HEM-0020', 'HEM-0021', 'HEM-0022')) THEN 'Calculated'
            ELSE 'Measured'
        END
    WHERE panel_id = v_cbc_id
      AND component_test_id IN (
        SELECT id FROM public.tests
        WHERE code IN ('HEM-0015', 'HEM-0016', 'HEM-0017', 'HEM-0018', 'HEM-0019', 'HEM-0020', 'HEM-0021', 'HEM-0022')
      );

END $$;

COMMIT;
