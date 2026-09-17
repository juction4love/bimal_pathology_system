-- Migration 00105: CounCell 23 Excel Hematology Analyzer Integration
--
-- Analyzer Specifications:
-- - Model: CounCell 23 Excel
-- - Manufacturer: Coral Clinical Systems / Tulip Diagnostics
-- - Analyzer Type: Automated 3-Part Differential Hematology Analyzer
-- - Specimen: EDTA Whole Blood (Lavender Top K2/K3-EDTA)
-- - Reagents: CounCell Diluent & Cyanide-free Lyse
-- - Sample Volume: 9 µL
-- - Throughput: Up to 60 samples/hour
--
-- Analytical Governance:
-- - 3-Part Differential Only: LYM%, LYM#, MID%, MID#, GRAN%, GRAN#
-- - 5-Part Differential (Neutrophils, Eosinophils, Basophils, Monocytes) strictly marked MANUAL_MICROSCOPY
-- - Result Source Metadata: ANALYZER, CALCULATED, MANUAL

BEGIN;

-- 1. Create or Update CounCell 23 Excel Analyzer Master Record
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
    'Coral Clinical Systems / Tulip Diagnostics',
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
    row_version = public.analyzers.row_version + 1,
    updated_at = NOW();

-- 2. Ensure test_results supports result_source metadata
ALTER TABLE public.test_results
    ADD COLUMN IF NOT EXISTS result_source VARCHAR(50) DEFAULT 'MANUAL';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_test_results_result_source'
    ) THEN
        ALTER TABLE public.test_results
            ADD CONSTRAINT chk_test_results_result_source
            CHECK (result_source IN ('ANALYZER', 'CALCULATED', 'MANUAL'));
    END IF;
END $$;

-- 3. Create Analyzer Parameter Channel Mappings Table
CREATE TABLE IF NOT EXISTS public.analyzer_parameter_mappings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    analyzer_id UUID NOT NULL REFERENCES public.analyzers(id) ON DELETE CASCADE,
    channel_code VARCHAR(50) NOT NULL,
    channel_name VARCHAR(255) NOT NULL,
    test_id UUID REFERENCES public.tests(id) ON DELETE SET NULL,
    parameter_id UUID REFERENCES public.parameters(id) ON DELETE SET NULL,
    measurement_type VARCHAR(50) NOT NULL CHECK (measurement_type IN ('DIRECT_MEASURED', 'ANALYZER_CALCULATED', 'ANALYZER_DERIVED', 'MANUAL_MICROSCOPY')),
    analytical_method VARCHAR(255) NOT NULL,
    unit VARCHAR(50),
    differential_type VARCHAR(50) NOT NULL DEFAULT '3-Part' CHECK (differential_type IN ('3-Part', '5-Part Manual', 'Not Applicable')),
    is_automated_5part_supported BOOLEAN NOT NULL DEFAULT FALSE,
    row_version BIGINT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_analyzer_channel UNIQUE (analyzer_id, channel_code)
);

CREATE INDEX IF NOT EXISTS idx_analyzer_param_mappings_analyzer ON public.analyzer_parameter_mappings(analyzer_id);
CREATE INDEX IF NOT EXISTS idx_analyzer_param_mappings_test ON public.analyzer_parameter_mappings(test_id);

ALTER TABLE public.analyzer_parameter_mappings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS analyzer_param_mappings_select ON public.analyzer_parameter_mappings;
CREATE POLICY analyzer_param_mappings_select ON public.analyzer_parameter_mappings
    FOR SELECT TO authenticated USING (public.is_active_user());

-- 4. Populate CounCell 23 Excel Parameter Channel Mappings
DO $$
DECLARE
    v_analyzer_id UUID;
    v_cbc_id UUID;
    v_hgb_id UUID;
    v_rbc_id UUID;
    v_wbc_id UUID;
    v_plt_id UUID;
    v_hct_id UUID;
    v_mcv_id UUID;
    v_mch_id UUID;
    v_mchc_id UUID;
    v_rdw_cv_id UUID;
    v_rdw_sd_id UUID;
    v_mpv_id UUID;
    v_pdw_id UUID;
    v_pct_id UUID;
    v_neut_id UUID;
    v_lym_id UUID;
    v_mono_id UUID;
    v_eos_id UUID;
    v_baso_id UUID;
    v_anc_id UUID;
    v_alc_id UUID;
    v_aec_id UUID;
BEGIN
    SELECT id INTO v_analyzer_id FROM public.analyzers WHERE code = 'COUNCELL_23_EXCEL';
    
    SELECT id INTO v_cbc_id FROM public.tests WHERE code = 'HEM-0001';
    SELECT id INTO v_hgb_id FROM public.tests WHERE code = 'HEM-0002';
    SELECT id INTO v_hct_id FROM public.tests WHERE code = 'HEM-0003';
    SELECT id INTO v_rbc_id FROM public.tests WHERE code = 'HEM-0004';
    SELECT id INTO v_wbc_id FROM public.tests WHERE code = 'HEM-0005';
    SELECT id INTO v_plt_id FROM public.tests WHERE code = 'HEM-0006';
    SELECT id INTO v_mcv_id FROM public.tests WHERE code = 'HEM-0007';
    SELECT id INTO v_mch_id FROM public.tests WHERE code = 'HEM-0008';
    SELECT id INTO v_mchc_id FROM public.tests WHERE code = 'HEM-0009';
    SELECT id INTO v_rdw_cv_id FROM public.tests WHERE code = 'HEM-0010';
    SELECT id INTO v_rdw_sd_id FROM public.tests WHERE code = 'HEM-0011';
    SELECT id INTO v_mpv_id FROM public.tests WHERE code = 'HEM-0012';
    SELECT id INTO v_pdw_id FROM public.tests WHERE code = 'HEM-0013';
    SELECT id INTO v_pct_id FROM public.tests WHERE code = 'HEM-0014';
    SELECT id INTO v_neut_id FROM public.tests WHERE code = 'HEM-0015';
    SELECT id INTO v_lym_id FROM public.tests WHERE code = 'HEM-0016';
    SELECT id INTO v_mono_id FROM public.tests WHERE code = 'HEM-0017';
    SELECT id INTO v_eos_id FROM public.tests WHERE code = 'HEM-0018';
    SELECT id INTO v_baso_id FROM public.tests WHERE code = 'HEM-0019';
    SELECT id INTO v_anc_id FROM public.tests WHERE code = 'HEM-0020';
    SELECT id INTO v_alc_id FROM public.tests WHERE code = 'HEM-0021';
    SELECT id INTO v_aec_id FROM public.tests WHERE code = 'HEM-0022';

    -- A. Direct Measured Parameters (Electrical Impedance & Colorimetry)
    INSERT INTO public.analyzer_parameter_mappings (
        analyzer_id, channel_code, channel_name, test_id, parameter_id,
        measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
    ) VALUES
    (v_analyzer_id, 'WBC', 'Total Leukocyte Count', v_wbc_id, (SELECT id FROM public.parameters WHERE test_id = v_wbc_id LIMIT 1), 'DIRECT_MEASURED', 'Electrical Impedance', '10^3/µL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'RBC', 'Red Blood Cell Count', v_rbc_id, (SELECT id FROM public.parameters WHERE test_id = v_rbc_id LIMIT 1), 'DIRECT_MEASURED', 'Electrical Impedance', '10^6/µL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'HGB', 'Hemoglobin', v_hgb_id, (SELECT id FROM public.parameters WHERE test_id = v_hgb_id LIMIT 1), 'DIRECT_MEASURED', 'Cyanide-free Colorimetry', 'g/dL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'PLT', 'Platelet Count', v_plt_id, (SELECT id FROM public.parameters WHERE test_id = v_plt_id LIMIT 1), 'DIRECT_MEASURED', 'Electrical Impedance', '10^3/µL', 'Not Applicable', FALSE)
    ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
        test_id = EXCLUDED.test_id,
        parameter_id = EXCLUDED.parameter_id,
        measurement_type = EXCLUDED.measurement_type,
        analytical_method = EXCLUDED.analytical_method,
        unit = EXCLUDED.unit;

    -- B. Analyzer Derived & Calculated Parameters
    INSERT INTO public.analyzer_parameter_mappings (
        analyzer_id, channel_code, channel_name, test_id, parameter_id,
        measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
    ) VALUES
    (v_analyzer_id, 'HCT', 'Hematocrit / PCV', v_hct_id, (SELECT id FROM public.parameters WHERE test_id = v_hct_id LIMIT 1), 'ANALYZER_CALCULATED', 'Calculated: (RBC * MCV) / 10', '%', 'Not Applicable', FALSE),
    (v_analyzer_id, 'MCV', 'Mean Corpuscular Volume', v_mcv_id, (SELECT id FROM public.parameters WHERE test_id = v_mcv_id LIMIT 1), 'ANALYZER_DERIVED', 'Derived from RBC histogram peak', 'fL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'MCH', 'Mean Corpuscular Hemoglobin', v_mch_id, (SELECT id FROM public.parameters WHERE test_id = v_mch_id LIMIT 1), 'ANALYZER_CALCULATED', 'Calculated: (HGB * 10) / RBC', 'pg', 'Not Applicable', FALSE),
    (v_analyzer_id, 'MCHC', 'Mean Corpuscular Hemoglobin Concentration', v_mchc_id, (SELECT id FROM public.parameters WHERE test_id = v_mchc_id LIMIT 1), 'ANALYZER_CALCULATED', 'Calculated: (HGB * 100) / HCT', 'g/dL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'RDW_CV', 'Red Cell Distribution Width (CV)', v_rdw_cv_id, (SELECT id FROM public.parameters WHERE test_id = v_rdw_cv_id LIMIT 1), 'ANALYZER_DERIVED', 'RBC size histogram analysis', '%', 'Not Applicable', FALSE),
    (v_analyzer_id, 'RDW_SD', 'Red Cell Distribution Width (SD)', v_rdw_sd_id, (SELECT id FROM public.parameters WHERE test_id = v_rdw_sd_id LIMIT 1), 'ANALYZER_DERIVED', 'RBC size histogram analysis', 'fL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'MPV', 'Mean Platelet Volume', v_mpv_id, (SELECT id FROM public.parameters WHERE test_id = v_mpv_id LIMIT 1), 'ANALYZER_DERIVED', 'PLT size histogram analysis', 'fL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'PDW', 'Platelet Distribution Width', v_pdw_id, (SELECT id FROM public.parameters WHERE test_id = v_pdw_id LIMIT 1), 'ANALYZER_DERIVED', 'PLT histogram distribution', 'fL', 'Not Applicable', FALSE),
    (v_analyzer_id, 'PCT', 'Plateletcrit', v_pct_id, (SELECT id FROM public.parameters WHERE test_id = v_pct_id LIMIT 1), 'ANALYZER_CALCULATED', 'Calculated: (PLT * MPV) / 10000', '%', 'Not Applicable', FALSE)
    ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
        test_id = EXCLUDED.test_id,
        parameter_id = EXCLUDED.parameter_id,
        measurement_type = EXCLUDED.measurement_type,
        analytical_method = EXCLUDED.analytical_method,
        unit = EXCLUDED.unit;

    -- C. 3-Part Differential Channels
    INSERT INTO public.analyzer_parameter_mappings (
        analyzer_id, channel_code, channel_name, test_id, parameter_id,
        measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
    ) VALUES
    (v_analyzer_id, 'LYM_PERCENT', 'Lymphocyte % (3-Part)', v_lym_id, (SELECT id FROM public.parameters WHERE test_id = v_lym_id LIMIT 1), 'DIRECT_MEASURED', 'Electrical Impedance (Small cell cluster)', '%', '3-Part', FALSE),
    (v_analyzer_id, 'LYM_ABS', 'Absolute Lymphocyte Count (3-Part)', v_alc_id, (SELECT id FROM public.parameters WHERE test_id = v_alc_id LIMIT 1), 'ANALYZER_CALCULATED', 'Calculated: (WBC * LYM%) / 100', '10^3/µL', '3-Part', FALSE),
    (v_analyzer_id, 'MID_PERCENT', 'Mid-Cell % (Monocytes/Eos/Baso cluster)', NULL, NULL, 'DIRECT_MEASURED', 'Electrical Impedance (Mid-size cell cluster)', '%', '3-Part', FALSE),
    (v_analyzer_id, 'MID_ABS', 'Absolute Mid-Cell Count', NULL, NULL, 'ANALYZER_CALCULATED', 'Calculated: (WBC * MID%) / 100', '10^3/µL', '3-Part', FALSE),
    (v_analyzer_id, 'GRAN_PERCENT', 'Granulocyte % (Neutrophils/Eos/Baso)', NULL, NULL, 'DIRECT_MEASURED', 'Electrical Impedance (Large cell cluster)', '%', '3-Part', FALSE),
    (v_analyzer_id, 'GRAN_ABS', 'Absolute Granulocyte Count', NULL, NULL, 'ANALYZER_CALCULATED', 'Calculated: (WBC * GRAN%) / 100', '10^3/µL', '3-Part', FALSE)
    ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
        test_id = EXCLUDED.test_id,
        parameter_id = EXCLUDED.parameter_id,
        measurement_type = EXCLUDED.measurement_type,
        analytical_method = EXCLUDED.analytical_method,
        unit = EXCLUDED.unit;

    -- D. 5-Part Differential Parameters: Explicitly Guarded as MANUAL_MICROSCOPY
    INSERT INTO public.analyzer_parameter_mappings (
        analyzer_id, channel_code, channel_name, test_id, parameter_id,
        measurement_type, analytical_method, unit, differential_type, is_automated_5part_supported
    ) VALUES
    (v_analyzer_id, 'NEUT_PERCENT', 'Neutrophils % (Manual Differential)', v_neut_id, (SELECT id FROM public.parameters WHERE test_id = v_neut_id LIMIT 1), 'MANUAL_MICROSCOPY', 'Leishman/Giemsa Stain Microscopy', '%', '5-Part Manual', FALSE),
    (v_analyzer_id, 'MONO_PERCENT', 'Monocytes % (Manual Differential)', v_mono_id, (SELECT id FROM public.parameters WHERE test_id = v_mono_id LIMIT 1), 'MANUAL_MICROSCOPY', 'Leishman/Giemsa Stain Microscopy', '%', '5-Part Manual', FALSE),
    (v_analyzer_id, 'EOS_PERCENT', 'Eosinophils % (Manual Differential)', v_eos_id, (SELECT id FROM public.parameters WHERE test_id = v_eos_id LIMIT 1), 'MANUAL_MICROSCOPY', 'Leishman/Giemsa Stain Microscopy', '%', '5-Part Manual', FALSE),
    (v_analyzer_id, 'BASO_PERCENT', 'Basophils % (Manual Differential)', v_baso_id, (SELECT id FROM public.parameters WHERE test_id = v_baso_id LIMIT 1), 'MANUAL_MICROSCOPY', 'Leishman/Giemsa Stain Microscopy', '%', '5-Part Manual', FALSE),
    (v_analyzer_id, 'ANC', 'Absolute Neutrophil Count', v_anc_id, (SELECT id FROM public.parameters WHERE test_id = v_anc_id LIMIT 1), 'ANALYZER_CALCULATED', 'Calculated: (WBC * Manual Neutrophil %) / 100', '10^3/µL', '5-Part Manual', FALSE),
    (v_analyzer_id, 'AEC', 'Absolute Eosinophil Count', v_aec_id, (SELECT id FROM public.parameters WHERE test_id = v_aec_id LIMIT 1), 'ANALYZER_CALCULATED', 'Calculated: (WBC * Manual Eosinophil %) / 100', 'cells/µL', '5-Part Manual', FALSE)
    ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
        test_id = EXCLUDED.test_id,
        parameter_id = EXCLUDED.parameter_id,
        measurement_type = EXCLUDED.measurement_type,
        analytical_method = EXCLUDED.analytical_method,
        unit = EXCLUDED.unit;

    -- 5. Link Test Analyzer Configurations
    IF v_cbc_id IS NOT NULL THEN
        INSERT INTO public.test_analyzer_configurations (
            test_id, analyzer_id, method, assay_identifier,
            configuration_version, effective_from, validation_state,
            validation_source, is_clinically_approved, lifecycle_status
        ) VALUES (
            v_cbc_id, v_analyzer_id, 'Electrical Impedance & Cyanide-free Colorimetry', 'COUNCELL_23_CBC',
            'COUNCELL_23_V1', CURRENT_DATE, 'ClinicallyValidated',
            'CounCell 23 Excel Manufacturer Manual & Standard Hematology Protocol', FALSE, 'Active'
        )
        ON CONFLICT (test_id, parameter_id, analyzer_id, configuration_version) DO NOTHING;
    END IF;

    -- Update CBC method description in catalogue
    UPDATE public.tests
    SET method = 'Electrical Impedance & Cyanide-free Colorimetry (CounCell 23 Excel)'
    WHERE id = v_cbc_id;

END $$;

-- 5. Update save_test_results_unversioned_internal to persist result_source
CREATE OR REPLACE FUNCTION public.save_test_results_unversioned_internal(
    p_order_item_id UUID,
    p_results JSONB,
    p_target_status public.result_status_enum,
    p_amended_from_report_id UUID DEFAULT NULL,
    p_amendment_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_item public.clinical_order_items%ROWTYPE;
    v_order public.clinical_orders%ROWTYPE;
    v_test public.tests%ROWTYPE;
    v_parent public.diagnostic_reports%ROWTYPE;
    v_result JSONB;
    v_parameter public.parameters%ROWTYPE;
    v_existing public.test_results%ROWTYPE;
    v_user_name TEXT;
    v_is_amendment BOOLEAN := FALSE;
    v_count INT := 0;
    v_item_status TEXT;
    v_unval_comp RECORD;
    v_source TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;
    IF jsonb_typeof(p_results) <> 'array' OR jsonb_array_length(p_results) = 0 THEN
        RAISE EXCEPTION 'At least one result is required.' USING ERRCODE = '22023';
    END IF;
    IF p_target_status NOT IN ('Draft', 'SubmittedForVerification', 'ReturnedForCorrection', 'Verified') THEN
        RAISE EXCEPTION 'Unsupported result workflow state.' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_item FROM public.clinical_order_items
    WHERE id = p_order_item_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Result work item was not found.' USING ERRCODE = 'P0002';
    END IF;
    SELECT * INTO v_order FROM public.clinical_orders WHERE id = v_item.order_id FOR UPDATE;
    SELECT * INTO v_test FROM public.tests WHERE id = v_item.test_id;

    -- Strict Clinical Guard: Verification requires formal clinical validation
    IF p_target_status = 'Verified' THEN
        IF v_test.validation_status <> 'VALIDATED' THEN
            RAISE EXCEPTION 'Cannot verify results: Test % (%) has not received formal clinical validation. Save as Draft while awaiting clinical approval.', v_test.name, v_test.code USING ERRCODE = '23514';
        END IF;

        -- For panels, all child component tests must be validated
        IF v_test.test_kind = 'Profile' THEN
            FOR v_unval_comp IN
                SELECT t.code, t.name
                FROM public.catalogue_panel_components cpc
                JOIN public.tests t ON cpc.component_test_id = t.id
                WHERE cpc.panel_test_id = v_test.id AND t.validation_status <> 'VALIDATED'
            LOOP
                RAISE EXCEPTION 'Cannot verify panel: Component test % (%) is not clinically validated.', v_unval_comp.name, v_unval_comp.code USING ERRCODE = '23514';
            END LOOP;
        END IF;
    END IF;

    IF p_amended_from_report_id IS NOT NULL THEN
        SELECT * INTO v_parent FROM public.diagnostic_reports
        WHERE id = p_amended_from_report_id AND order_id = v_item.order_id
          AND status IN ('SignedOff', 'Amended');
        IF NOT FOUND OR NULLIF(btrim(p_amendment_reason), '') IS NULL
           OR NOT public.has_permission('can_amend_reports') THEN
            RAISE EXCEPTION 'A valid authorized amendment and reason are required.' USING ERRCODE = '42501';
        END IF;
        v_is_amendment := TRUE;
    END IF;

    IF p_target_status IN ('Draft', 'SubmittedForVerification')
       AND NOT (public.has_permission('can_enter_results') OR public.has_permission('can_verify_results')) THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;
    IF p_target_status IN ('ReturnedForCorrection', 'Verified')
       AND NOT public.has_permission('can_verify_results') THEN
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE = '42501';
    END IF;
    IF v_item.status = 'SignedOff' AND NOT v_is_amendment THEN
        RAISE EXCEPTION 'This result can no longer be modified.' USING ERRCODE = '55000';
    END IF;

    IF p_target_status = 'ReturnedForCorrection'
       AND NOT EXISTS (SELECT 1 FROM public.test_results WHERE order_item_id = p_order_item_id AND status IN ('SubmittedForVerification', 'Verified')) THEN
        RAISE EXCEPTION 'Only submitted results may be returned for correction.' USING ERRCODE = '55000';
    END IF;

    IF p_target_status = 'Verified' AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_results) r
        WHERE COALESCE((r->>'is_critical')::BOOLEAN, FALSE)
          AND NOT COALESCE((r->>'critical_acknowledged')::BOOLEAN, FALSE)
    ) THEN
        RAISE EXCEPTION 'Critical results must be acknowledged before verification.' USING ERRCODE = '55000';
    END IF;

    SELECT COALESCE(full_name, 'Lab Staff') INTO v_user_name
    FROM public.user_profiles WHERE id = auth.uid();

    FOR v_result IN SELECT value FROM jsonb_array_elements(p_results)
    LOOP
        SELECT p.* INTO v_parameter
        FROM public.parameters p
        WHERE p.id = (v_result->>'parameter_id')::UUID
          AND p.test_id = v_item.test_id
          AND p.is_active = TRUE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'A submitted parameter is not valid for this investigation.' USING ERRCODE = '22023';
        END IF;

        v_source := COALESCE(v_result->>'result_source', CASE WHEN v_parameter.value_type = 'Calculated' THEN 'CALCULATED' ELSE 'MANUAL' END);
        IF v_source NOT IN ('ANALYZER', 'CALCULATED', 'MANUAL') THEN
            v_source := 'MANUAL';
        END IF;

        SELECT * INTO v_existing FROM public.test_results
        WHERE order_item_id = p_order_item_id
          AND parameter_id = v_parameter.id
        FOR UPDATE;

        IF FOUND THEN
            UPDATE public.test_results
            SET display_value = COALESCE(v_result->>'display_value', ''),
                numeric_value = CASE
                    WHEN v_parameter.value_type = 'Numeric' AND NULLIF(btrim(COALESCE(v_result->>'display_value', '')), '') IS NOT NULL
                    THEN (v_result->>'display_value')::NUMERIC
                    ELSE NULL
                END,
                text_value = CASE
                    WHEN v_parameter.value_type <> 'Numeric'
                    THEN v_result->>'display_value'
                    ELSE NULL
                END,
                flag = COALESCE((v_result->>'flag')::public.result_flag_enum, 'Normal'),
                is_critical = COALESCE((v_result->>'is_critical')::BOOLEAN, FALSE),
                critical_acknowledged = COALESCE((v_result->>'critical_acknowledged')::BOOLEAN, FALSE),
                result_source = v_source,
                status = p_target_status,
                entered_by = CASE WHEN p_target_status IN ('Draft', 'SubmittedForVerification') THEN auth.uid() ELSE entered_by END,
                entered_by_name = CASE WHEN p_target_status IN ('Draft', 'SubmittedForVerification') THEN v_user_name ELSE entered_by_name END,
                entered_at = CASE WHEN p_target_status IN ('Draft', 'SubmittedForVerification') THEN NOW() ELSE entered_at END,
                verified_by = CASE WHEN p_target_status = 'Verified' THEN auth.uid() ELSE verified_by END,
                verified_by_name = CASE WHEN p_target_status = 'Verified' THEN v_user_name ELSE verified_by_name END,
                verified_at = CASE WHEN p_target_status = 'Verified' THEN NOW() ELSE verified_at END,
                updated_at = NOW()
            WHERE id = v_existing.id;
        ELSE
            INSERT INTO public.test_results (
                order_item_id,
                parameter_id,
                parameter_name,
                unit,
                display_value,
                numeric_value,
                text_value,
                flag,
                is_critical,
                critical_acknowledged,
                result_source,
                status,
                entered_by,
                entered_by_name,
                entered_at,
                verified_by,
                verified_by_name,
                verified_at
            ) VALUES (
                p_order_item_id,
                v_parameter.id,
                v_parameter.name,
                v_parameter.unit,
                COALESCE(v_result->>'display_value', ''),
                CASE
                    WHEN v_parameter.value_type = 'Numeric' AND NULLIF(btrim(COALESCE(v_result->>'display_value', '')), '') IS NOT NULL
                    THEN (v_result->>'display_value')::NUMERIC
                    ELSE NULL
                END,
                CASE
                    WHEN v_parameter.value_type <> 'Numeric'
                    THEN v_result->>'display_value'
                    ELSE NULL
                END,
                COALESCE((v_result->>'flag')::public.result_flag_enum, 'Normal'),
                COALESCE((v_result->>'is_critical')::BOOLEAN, FALSE),
                COALESCE((v_result->>'critical_acknowledged')::BOOLEAN, FALSE),
                v_source,
                p_target_status,
                auth.uid(),
                v_user_name,
                NOW(),
                CASE WHEN p_target_status = 'Verified' THEN auth.uid() ELSE NULL END,
                CASE WHEN p_target_status = 'Verified' THEN v_user_name ELSE NULL END,
                CASE WHEN p_target_status = 'Verified' THEN NOW() ELSE NULL END
            );
        END IF;
        v_count := v_count + 1;
    END LOOP;

    -- Update clinical order item status
    v_item_status := CASE
        WHEN p_target_status = 'Draft' THEN 'InProgress'
        WHEN p_target_status = 'SubmittedForVerification' THEN 'Completed'
        WHEN p_target_status = 'ReturnedForCorrection' THEN 'InProgress'
        WHEN p_target_status = 'Verified' THEN 'Verified'
        ELSE v_item.status
    END;

    UPDATE public.clinical_order_items
    SET status = v_item_status,
        result_revision = result_revision + 1,
        updated_at = NOW()
    WHERE id = p_order_item_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'order_item_id', p_order_item_id,
        'target_status', p_target_status,
        'saved_count', v_count,
        'result_revision', v_item.result_revision + 1
    );
END;
$$;

-- 6. Update sign_report_group to freeze result_source
CREATE OR REPLACE FUNCTION public.sign_report_group(p_report_group_id UUID,p_performed_by_id UUID,p_signed_by_id UUID DEFAULT NULL,p_amendment_reason TEXT DEFAULT NULL,p_amended_from_report_id UUID DEFAULT NULL) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE g public.clinical_report_groups%ROWTYPE; o public.clinical_orders%ROWTYPE; b public.bills%ROWTYPE; patient public.patients%ROWTYPE; performer public.reporting_personnel%ROWTYPE; signer public.reporting_personnel%ROWTYPE; parent public.diagnostic_reports%ROWTYPE; ready JSONB; investigations JSONB; snapshot JSONB; version_no INT; report_id UUID; report_no TEXT; integrity TEXT; is_amendment BOOLEAN:=p_amended_from_report_id IS NOT NULL; item RECORD;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_sign_reports') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 SELECT * INTO g FROM public.clinical_report_groups WHERE id=p_report_group_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Report group not found.' USING ERRCODE='P0002'; END IF;
 SELECT * INTO o FROM public.clinical_orders WHERE id=g.order_id; SELECT * INTO b FROM public.bills WHERE id=o.bill_id; SELECT * INTO patient FROM public.patients WHERE id=o.patient_id;
 SELECT * INTO performer FROM public.reporting_personnel WHERE id=p_performed_by_id AND is_active;
 IF NOT FOUND THEN RAISE EXCEPTION 'Active reporting personnel is required.' USING ERRCODE='23514'; END IF;
 IF p_signed_by_id IS NOT NULL THEN SELECT * INTO signer FROM public.reporting_personnel WHERE id=p_signed_by_id AND is_active AND can_sign_reports; IF NOT FOUND THEN RAISE EXCEPTION 'Active authorized signatory is required.' USING ERRCODE='23514'; END IF; END IF;
 ready:=public.check_report_group_readiness(g.id);
 IF NOT (ready->>'is_ready')::boolean THEN RAISE EXCEPTION 'Report group is not ready: %',ready USING ERRCODE='23514'; END IF;
 IF is_amendment THEN
   IF NOT public.has_permission('can_amend_reports') OR btrim(coalesce(p_amendment_reason,''))='' THEN RAISE EXCEPTION 'Amendment permission and reason are required.' USING ERRCODE='42501'; END IF;
   SELECT * INTO parent FROM public.diagnostic_reports WHERE id=p_amended_from_report_id AND report_group_id=g.id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Amendment parent is outside this report group.' USING ERRCODE='23514'; END IF;
   version_no:=parent.version+1; UPDATE public.diagnostic_reports SET status='Amended',updated_at=now() WHERE id=parent.id;
 ELSE
   IF EXISTS(SELECT 1 FROM public.diagnostic_reports WHERE report_group_id=g.id AND status='SignedOff') THEN RAISE EXCEPTION 'This report group is already signed.' USING ERRCODE='23505'; END IF;
   SELECT coalesce(max(version),0)+1 INTO version_no FROM public.diagnostic_reports WHERE report_group_id=g.id;
 END IF;
 FOR item IN SELECT oi.id FROM public.clinical_report_group_items gi JOIN public.clinical_order_items oi ON oi.id=gi.order_item_id WHERE gi.report_group_id=g.id LOOP PERFORM public.recompute_order_item_calculated_results(item.id); END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('order_item_id',x.order_item_id,'test_id',x.test_id,'test_name',x.test_name,'test_code',x.test_code,'department',x.department,'reporting_type',x.reporting_type,'execution_route',x.execution_route,'outsource_lab_name',x.outsource_lab_name,'outsource_external_reference',x.outsource_external_reference,'outsource_source_report_reference',x.outsource_source_report_reference,'outsource_method',x.outsource_method,'outsource_interpretation',x.outsource_interpretation,'outsource_result_payload',x.outsource_result_payload,'method',x.method,'interpretation_template',x.interpretation_template,'specimen_type',x.specimen_type,'container_type',x.container_type,'results',x.results) ORDER BY x.item_order),'[]'::jsonb)
 INTO investigations FROM (
   SELECT oi.id order_item_id,oi.test_id,gi.frozen_test_name test_name,gi.frozen_test_code test_code,oi.department,oi.reporting_type,oi.execution_route,oi.outsource_lab_name,oi.outsource_external_reference,oi.outsource_source_report_reference,oi.outsource_method,oi.outsource_interpretation,oi.outsource_result_payload,t.method,t.interpretation_template,oi.specimen_type,oi.container_type,gi.display_order item_order,
   coalesce(jsonb_agg(jsonb_build_object('parameter_id',tr.parameter_id,'code',p.code,'name',tr.parameter_name,'value_type',tr.value_type,'display_value',tr.display_value,'numeric_value',tr.numeric_value,'unit',tr.unit,'formula',p.formula,'flag',tr.flag,'is_critical',tr.is_critical,'result_source',tr.result_source,'reference_range',coalesce(case when tr.normal_min is not null and tr.normal_max is not null then tr.normal_min::text||' - '||tr.normal_max::text end,tr.normal_range_text,'Standard'),'normal_min',tr.normal_min,'normal_max',tr.normal_max,'critical_low',tr.critical_low,'critical_high',tr.critical_high) ORDER BY p.display_order) FILTER(WHERE tr.id IS NOT NULL),'[]'::jsonb) results
   FROM public.clinical_report_group_items gi JOIN public.clinical_order_items oi ON oi.id=gi.order_item_id JOIN public.tests t ON t.id=oi.test_id LEFT JOIN public.test_results tr ON tr.order_item_id=oi.id LEFT JOIN public.parameters p ON p.id=tr.parameter_id WHERE gi.report_group_id=g.id GROUP BY oi.id,gi.frozen_test_name,gi.frozen_test_code,t.method,t.interpretation_template,gi.display_order
 ) x;
 IF jsonb_array_length(investigations)=0 THEN RAISE EXCEPTION 'Report group contains no reportable investigations.' USING ERRCODE='23514'; END IF;
 snapshot:=jsonb_build_object('organization',jsonb_build_object('name_en','BIMAL PATHOLOGY & DIAGNOSTIC CENTER','name_ne','बिमल प्याथोलोजी एण्ड run_command','address_en','Bharatpur-7, Chitwan, Nepal','reg_no','7-1496','pan_no','302481477','phone','056-593288'),'patient',jsonb_build_object('uhid',patient.uhid,'full_name',patient.full_name,'title',patient.title,'mobile',patient.mobile,'gender',patient.gender,'dob',patient.dob,'age_years',patient.age_years,'age_months',patient.age_months,'age_days',patient.age_days,'address',patient.address),'order',jsonb_build_object('order_number',o.order_number,'bill_number',b.bill_number,'registered_date_ad',o.order_date_ad,'registered_date_bs',o.order_date_bs,'reported_at',now(),'referring_doctor_name',coalesce(b.referring_doctor_name_snapshot,'Self / Walk-in')),'report_group',jsonb_build_object('id',g.id,'key',g.group_key,'title',g.title,'clinical_section',g.clinical_section,'configuration_version',g.configuration_version),'signatories',jsonb_build_object('performed_by',jsonb_build_object('id',performer.id,'full_name',performer.full_name,'qualification',performer.qualification,'professional_type',performer.professional_type,'registration_council',performer.registration_council,'registration_number',performer.registration_number,'signature_url',performer.signature_url),'authorized_by',case when signer.id is null then null else jsonb_build_object('id',signer.id,'full_name',signer.full_name,'qualification',signer.qualification,'professional_type',signer.professional_type,'registration_council',signer.registration_council,'registration_number',signer.registration_number,'signature_url',signer.signature_url) end),'investigations',investigations,'meta',jsonb_build_object('version',version_no,'is_amendment',is_amendment,'amendment_reason',p_amendment_reason,'amended_from_report_id',p_amended_from_report_id,'signed_at',now(),'signed_by_user_id',auth.uid()));
 integrity:=encode(extensions.digest(convert_to(o.order_number||'|'||g.group_key||'|v'||version_no||'|'||snapshot::text,'UTF8'),'sha256'),'hex');
 report_no:='REP-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('report_seq')::text,5,'0');
 INSERT INTO public.diagnostic_reports(order_id,report_group_id,patient_id,report_number,version,is_amendment,amendment_reason,amended_from_report_id,status,integrity_hash,performed_by_personnel_id,performed_by_personnel_name,verified_by_personnel_id,verified_by_personnel_name,signed_by_personnel_id,signed_by_personnel_name,signed_at,pdf_storage_path,clinical_snapshot_json)
 VALUES(o.id,g.id,o.patient_id,report_no,version_no,is_amendment,p_amendment_reason,p_amended_from_report_id,'SignedOff',integrity,performer.id,performer.full_name,signer.id,signer.full_name,signer.id,signer.full_name,now(),'reports/'||o.id||'/'||g.group_key||'/v'||version_no||'/report.pdf',snapshot) RETURNING id INTO report_id;
 UPDATE public.clinical_order_items oi SET status='SignedOff',outsource_state=CASE WHEN oi.execution_route='OUTSOURCE' THEN 'Signed'::public.outsource_item_state_enum ELSE oi.outsource_state END,updated_at=now() FROM public.clinical_report_group_items gi WHERE gi.report_group_id=g.id AND gi.order_item_id=oi.id;
 UPDATE public.test_results tr SET status='SignedOff',signed_off_by=auth.uid(),signed_off_name=coalesce(signer.full_name,performer.full_name),signed_off_at=now(),updated_at=now() FROM public.clinical_report_group_items gi WHERE gi.report_group_id=g.id AND gi.order_item_id=tr.order_item_id;
 UPDATE public.clinical_report_groups SET lifecycle_state=CASE WHEN is_amendment THEN 'Amended' ELSE 'Signed' END,updated_at=now(),row_version=row_version+1 WHERE id=g.id;
 UPDATE public.clinical_orders SET status=public.derive_order_reporting_state(o.id),updated_at=now() WHERE id=o.id;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),performer.full_name,case when is_amendment then 'REPORT_GROUP_AMENDMENT_SIGNED' else 'REPORT_GROUP_SIGNED' end,'ClinicalReportGroup',g.id::text,jsonb_build_object('report_id',report_id,'order_id',o.id,'group_key',g.group_key,'version',version_no,'integrity_hash',integrity));
 RETURN jsonb_build_object('success',true,'report_id',report_id,'report_group_id',g.id,'report_group_key',g.group_key,'report_number',report_no,'version',version_no,'integrity_hash',integrity,'snapshot',snapshot,'order_reporting_state',public.derive_order_reporting_state(o.id));
END $$;

COMMIT;
