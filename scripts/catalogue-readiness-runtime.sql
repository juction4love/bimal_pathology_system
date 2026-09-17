\set ON_ERROR_STOP on
BEGIN;
SET LOCAL session_replication_role=replica;
INSERT INTO public.user_profiles(id,email,full_name,is_active,is_super_admin) VALUES
 ('75000000-0000-0000-0000-000000000001','catalogue-tech@local.invalid','Synthetic Catalogue Technician',TRUE,FALSE),
 ('75000000-0000-0000-0000-000000000002','catalogue-admin@local.invalid','Synthetic Catalogue Super Admin',TRUE,TRUE);
SET LOCAL session_replication_role=origin;
INSERT INTO public.user_roles(user_id,role_id) SELECT '75000000-0000-0000-0000-000000000001',id FROM public.roles WHERE code='lab_technician';

DO $$ DECLARE c UUID:=(SELECT id FROM public.tests WHERE code='CBC'); BEGIN
 IF NOT (SELECT clinical_reporting_enabled AND reporting_type='InHouse' AND workflow_supported FROM public.tests WHERE id=c) THEN RAISE EXCEPTION 'CBC_NOT_REPORTABLE'; END IF;
 IF (SELECT count(*) FROM public.parameters WHERE test_id=c AND code IN ('RBC','HB','PCV','MCV','MCH','MCHC','RDW','TLC','NEUT','LYMPH','MONO','EOSIN','BASO','PLT','MPV','PDW') AND is_active)<>16 THEN RAISE EXCEPTION 'CBC_PARAMETER_SET_INVALID'; END IF;
 IF (SELECT count(*) FROM public.catalogue_profile_components WHERE profile_test_id=c)<>16 THEN RAISE EXCEPTION 'CBC_PROFILE_COMPOSITION_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM public.catalogue_profile_components WHERE profile_test_id=c GROUP BY display_order HAVING count(*)>1) THEN RAISE EXCEPTION 'CBC_PROFILE_ORDER_DUPLICATE'; END IF;
 IF EXISTS(SELECT 1 FROM public.reference_ranges rr JOIN public.parameters p ON p.id=rr.parameter_id WHERE p.test_id=c AND rr.is_active AND rr.method='Default reference interval - verify with analyzer/reagent') THEN RAISE EXCEPTION 'PLACEHOLDER_EXPOSED_AS_METHOD'; END IF;
 IF (SELECT count(*) FROM public.reference_ranges rr WHERE rr.is_active AND rr.is_approved AND rr.validation_state='ClinicallyValidated' AND rr.validation_source LIKE '%Default reference interval - verify with analyzer/reagent%')<>105 THEN RAISE EXCEPTION 'PLACEHOLDER_PROVENANCE_COUNT_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM public.reference_ranges rr JOIN public.parameters p ON p.id=rr.parameter_id WHERE p.test_id=c AND rr.is_active GROUP BY p.code,rr.gender,rr.age_min_days,rr.age_max_days HAVING count(*)>1) THEN RAISE EXCEPTION 'DUPLICATE_CBC_RANGE'; END IF;
END $$;
DO $$ DECLARE p UUID:=(SELECT id FROM public.catalogue_panels WHERE code='CBC_WITH_ESR'); BEGIN
 IF p IS NULL THEN RAISE EXCEPTION 'CBC_WITH_ESR_PANEL_MISSING'; END IF;
 IF (SELECT count(*) FROM public.catalogue_panel_components WHERE panel_id=p)<>15 THEN RAISE EXCEPTION 'CBC_WITH_ESR_COMPONENT_COUNT_INVALID'; END IF;
 IF (SELECT string_agg(display_name,'|' ORDER BY display_order) FROM public.catalogue_panel_components WHERE panel_id=p) <> 'Hemoglobin|Total Leukocyte Count|Differential Leucocyte Count|Platelet Count|Total RBC Count|Hematocrit Value, Hct|Mean Corpuscular Volume, MCV|Mean Cell Haemoglobin, MCH|Mean Cell Haemoglobin CON, MCHC|Mean Platelet Volume, MPV|R.D.W. - SD|R.D.W. - CV|P-LCR|P.D.W.|Erythrocyte Sedimentation Rate (Wintrobe)' THEN RAISE EXCEPTION 'CBC_WITH_ESR_COMPONENT_ORDER_INVALID'; END IF;
 IF (SELECT count(*) FROM public.catalogue_panel_ratelist_links WHERE panel_id=p)<>4 THEN RAISE EXCEPTION 'CBC_WITH_ESR_RATELIST_INVALID'; END IF;
 IF (SELECT count(*) FROM public.catalogue_panels WHERE code='CBC_WITH_ESR')<>1 THEN RAISE EXCEPTION 'CBC_WITH_ESR_DUPLICATE_PANEL'; END IF;
END $$;
DO $$ DECLARE p UUID:=(SELECT id FROM public.catalogue_panels WHERE code='BT_CT'); t UUID:=(SELECT id FROM public.tests WHERE code='BT_CT'); BEGIN
 IF p IS NULL OR p<>t THEN RAISE EXCEPTION 'BT_CT_CANONICAL_PROFILE_NOT_REUSED'; END IF;
 IF (SELECT count(*) FROM public.catalogue_panel_components WHERE panel_id=p)<>2 THEN RAISE EXCEPTION 'BT_CT_COMPONENT_COUNT_INVALID'; END IF;
 IF (SELECT string_agg(display_name,'|' ORDER BY display_order) FROM public.catalogue_panel_components WHERE panel_id=p)<>'Bleeding Time|Clotting Time' THEN RAISE EXCEPTION 'BT_CT_COMPONENT_ORDER_INVALID'; END IF;
 IF (SELECT count(DISTINCT component_parameter_id) FROM public.catalogue_panel_components WHERE panel_id=p)<>2 THEN RAISE EXCEPTION 'BT_CT_COMPONENT_IDENTITY_DUPLICATE'; END IF;
 IF (SELECT count(*) FROM public.catalogue_panel_ratelist_links WHERE panel_id=p AND ratelist_name='BT & CT' AND operator_rate_npr=200)<>1 THEN RAISE EXCEPTION 'BT_CT_RATELIST_INVALID'; END IF;
 IF position('Recommended test is Prothrombin Time (PT)' IN (SELECT clinical_notes FROM public.catalogue_panels WHERE id=p))=0 THEN RAISE EXCEPTION 'BT_CT_NOTE_MISSING'; END IF;
END $$;
DO $$ DECLARE p UUID:=(SELECT id FROM public.catalogue_panels WHERE code='BLOOD_SUGAR_FASTING_PP'); hp UUID; BEGIN
 IF p IS NULL THEN RAISE EXCEPTION 'GLUCOSE_PANEL_MISSING'; END IF;
 IF (SELECT string_agg(t.code,'|' ORDER BY c.display_order) FROM public.catalogue_panel_components c JOIN public.tests t ON t.id=c.component_test_id WHERE c.panel_id=p)<>'FBS|PPBS' THEN RAISE EXCEPTION 'GLUCOSE_PANEL_COMPONENT_ORDER_INVALID'; END IF;
 IF (SELECT count(*) FROM public.catalogue_panel_components WHERE panel_id=p)<>2 THEN RAISE EXCEPTION 'GLUCOSE_PANEL_COMPONENT_COUNT_INVALID'; END IF;
 IF (SELECT count(*) FROM public.catalogue_panel_ratelist_links WHERE panel_id=p)<>2 THEN RAISE EXCEPTION 'GLUCOSE_PANEL_RATELIST_INVALID'; END IF;
 SELECT health_package_id INTO hp FROM public.catalogue_panel_ratelist_links WHERE panel_id=p AND ratelist_name='Blood Sugar Fasting & PP';
 IF hp IS NULL OR (SELECT string_agg(t.code,'|' ORDER BY c.display_order) FROM public.health_package_components c JOIN public.tests t ON t.id=c.test_id WHERE c.package_id=hp)<>'FBS|PPBS' THEN RAISE EXCEPTION 'GLUCOSE_DIRECT_BOOKING_EXPANSION_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM public.reference_ranges rr JOIN public.parameters prm ON prm.id=rr.parameter_id JOIN public.tests t ON t.id=prm.test_id WHERE t.code IN('FBS','PPBS') AND (rr.normal_min IN(100,126) OR rr.normal_max IN(199,200))) THEN RAISE EXCEPTION 'PANEL_INTERPRETATION_LEAKED_INTO_RANGES'; END IF;
 IF (SELECT interpretation_rows->0->>'diagnosis' FROM public.catalogue_panels WHERE id=p)<>'Normal' THEN RAISE EXCEPTION 'GLUCOSE_INTERPRETATION_MISSING'; END IF;
END $$;
DO $$ DECLARE p UUID:=(SELECT id FROM public.catalogue_panels WHERE code='LFT'); BEGIN
 IF p IS NULL OR p<>(SELECT id FROM public.tests WHERE code='LFT') THEN RAISE EXCEPTION 'LFT_CANONICAL_PROFILE_NOT_REUSED'; END IF;
 IF (SELECT count(*) FROM public.catalogue_panel_components WHERE panel_id=p)<>11 THEN RAISE EXCEPTION 'LFT_COMPONENT_COUNT_INVALID'; END IF;
 IF (SELECT string_agg(display_name,'|' ORDER BY display_order) FROM public.catalogue_panel_components WHERE panel_id=p)<>'Serum Bilirubin (Total)|Serum Bilirubin (Direct)|Serum Bilirubin (Indirect)|SGOT (AST)|SGPT (ALT)|SGOT/SGPT|Serum Alkaline Phosphatase|Serum Protein|Serum Albumin|Globulin|A/G Ratio' THEN RAISE EXCEPTION 'LFT_COMPONENT_ORDER_INVALID'; END IF;
 IF (SELECT count(DISTINCT component_parameter_id) FROM public.catalogue_panel_components WHERE panel_id=p)<>11 THEN RAISE EXCEPTION 'LFT_COMPONENT_IDENTITY_DUPLICATE'; END IF;
 IF (SELECT count(*) FROM public.catalogue_panel_ratelist_links WHERE panel_id=p)<>4 THEN RAISE EXCEPTION 'LFT_RATELIST_INVALID'; END IF;
 IF NOT (SELECT clinical_reporting_enabled AND reporting_type='InHouse' AND workflow_supported AND price_paisa=100000 FROM public.tests WHERE id=p) THEN RAISE EXCEPTION 'LFT_DIRECT_BOOKING_INVALID'; END IF;
 IF position('Liver Function Blood Test gives an insight into your liver health' IN (SELECT clinical_notes FROM public.catalogue_panels WHERE id=p))=0 THEN RAISE EXCEPTION 'LFT_NOTE_MISSING'; END IF;
 IF (SELECT count(*) FROM public.clinical_calculation_formula_versions f JOIN public.parameters prm ON prm.id=f.output_parameter_id WHERE prm.test_id=p)<>0 THEN RAISE EXCEPTION 'UNAPPROVED_LFT_FORMULA_CREATED'; END IF;
 IF (SELECT string_agg(code,'|' ORDER BY display_order) FROM public.parameters WHERE test_id=p AND is_active)<>'TBIL|DBIL|IBIL|SGOT|SGPT|SGOT_SGPT_RATIO|ALP|TP|ALB|GLOB|AG_RATIO' THEN RAISE EXCEPTION 'LFT_PARAMETER_ORDER_INVALID'; END IF;
END $$;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.catalogue_panels WHERE display_order BETWEEN 1 AND 31)<>31 THEN RAISE EXCEPTION 'MASTER_PANEL_COUNT_INVALID'; END IF;
 IF EXISTS(SELECT display_order FROM public.catalogue_panels WHERE display_order BETWEEN 1 AND 31 GROUP BY display_order HAVING count(*)>1) THEN RAISE EXCEPTION 'MASTER_PANEL_ORDER_DUPLICATE'; END IF;
 IF EXISTS(SELECT panel_id,component_test_id FROM public.catalogue_panel_components WHERE component_test_id IS NOT NULL GROUP BY panel_id,component_test_id HAVING count(*)>1) THEN RAISE EXCEPTION 'MASTER_TEST_COMPONENT_DUPLICATE'; END IF;
 IF EXISTS(SELECT panel_id,component_parameter_id FROM public.catalogue_panel_components WHERE component_parameter_id IS NOT NULL GROUP BY panel_id,component_parameter_id HAVING count(*)>1) THEN RAISE EXCEPTION 'MASTER_PARAMETER_COMPONENT_DUPLICATE'; END IF;
 IF (SELECT count(*) FROM public.catalogue_panel_components c JOIN public.catalogue_panels p ON p.id=c.panel_id WHERE p.code='COAG_PROFILE')<>4 THEN RAISE EXCEPTION 'COAG_PROFILE_COUNT_INVALID'; END IF;
 IF (SELECT count(*) FROM public.catalogue_panel_components c JOIN public.catalogue_panels p ON p.id=c.panel_id WHERE p.code='KFT')<>11 THEN RAISE EXCEPTION 'KFT_COUNT_INVALID'; END IF;
 IF (SELECT count(*) FROM public.catalogue_panel_components c JOIN public.catalogue_panels p ON p.id=c.panel_id WHERE p.code='LIPID_PROFILE')<>9 THEN RAISE EXCEPTION 'LIPID_COUNT_INVALID'; END IF;
 IF (SELECT count(*) FROM public.catalogue_panel_components c JOIN public.catalogue_panels p ON p.id=c.panel_id WHERE p.code IN('THYROID_PROFILE','THYROID_ECLIA','UPCR','EGFR') GROUP BY p.code HAVING count(*)<>3)>0 THEN RAISE EXCEPTION 'THREE_COMPONENT_PROFILE_INVALID'; END IF;
 IF (SELECT count(*) FROM public.catalogue_panel_components WHERE unresolved_reason IS NOT NULL)<>0 THEN RAISE EXCEPTION 'UNRESOLVED_COMPONENT_INVENTORY_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM public.catalogue_panels WHERE code IN('PUS_CULTURE_AND_SENSITIVITY','GENETIC_TEST') AND (workflow_supported OR clinical_reporting_enabled)) THEN RAISE EXCEPTION 'SPECIALIST_PANEL_FORCED_GENERIC'; END IF;
END $$;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.catalogue_test_database_entries)<>256 THEN RAISE EXCEPTION 'TEST_DATABASE_COUNT_INVALID'; END IF;
 IF (SELECT min(source_order) FROM public.catalogue_test_database_entries)<>1 OR (SELECT max(source_order) FROM public.catalogue_test_database_entries)<>256 THEN RAISE EXCEPTION 'TEST_DATABASE_ORDER_INVALID'; END IF;
 IF (SELECT count(DISTINCT source_order) FROM public.catalogue_test_database_entries)<>256 THEN RAISE EXCEPTION 'TEST_DATABASE_ORDER_DUPLICATE'; END IF;
 IF EXISTS(SELECT 1 FROM public.catalogue_test_database_entries WHERE configuration_test_id IS NULL) THEN RAISE EXCEPTION 'TEST_DATABASE_IDENTITY_UNRESOLVED'; END IF;
 IF (SELECT count(*) FROM public.catalogue_test_database_entries WHERE test_type='Single parameter')<>204 OR (SELECT count(*) FROM public.catalogue_test_database_entries WHERE test_type='Multi parameter')<>39 OR (SELECT count(*) FROM public.catalogue_test_database_entries WHERE test_type='Multi parameter nested')<>4 OR (SELECT count(*) FROM public.catalogue_test_database_entries WHERE test_type='Document')<>9 THEN RAISE EXCEPTION 'TEST_DATABASE_TYPE_COUNTS_INVALID'; END IF;
 IF (SELECT count(*) FROM public.catalogue_test_database_entries WHERE canonical_parameter_id IS NOT NULL)<>35 THEN RAISE EXCEPTION 'TEST_DATABASE_PARAMETER_REUSE_COUNT_INVALID'; END IF;
 IF (SELECT short_name FROM public.catalogue_test_database_entries WHERE source_order=1)<>'Hb' OR (SELECT short_name FROM public.catalogue_test_database_entries WHERE source_order=24)<>'PT/INR' OR (SELECT short_name FROM public.catalogue_test_database_entries WHERE source_order=247)<>'FT3' THEN RAISE EXCEPTION 'TEST_DATABASE_SHORT_NAME_INVALID'; END IF;
 IF (SELECT count(*) FROM public.catalogue_test_templates)<>111 OR (SELECT count(DISTINCT source_order) FROM public.catalogue_test_templates)<>111 THEN RAISE EXCEPTION 'TEST_TEMPLATE_COUNT_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM public.catalogue_test_templates t LEFT JOIN public.catalogue_test_database_entries d ON d.source_order=t.test_database_source_order WHERE d.source_order IS NULL OR t.configuration_test_id<>d.configuration_test_id OR t.canonical_parameter_id IS DISTINCT FROM d.canonical_parameter_id) THEN RAISE EXCEPTION 'TEST_TEMPLATE_CANONICAL_MAPPING_INVALID'; END IF;
 IF (SELECT count(*) FROM public.catalogue_test_template_drafts)<>0 THEN RAISE EXCEPTION 'TEST_TEMPLATE_RECONCILIATION_CREATED_DRAFTS'; END IF;
END $$;

UPDATE public.tests SET clinical_reporting_enabled=FALSE WHERE code='ANTI_HCV';
UPDATE public.catalogue_service_readiness SET state='NeedsConfiguration' WHERE test_id=(SELECT id FROM public.tests WHERE code='ANTI_HCV');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','75000000-0000-0000-0000-000000000001',TRUE);
SELECT set_config('request.jwt.claims','{"sub":"75000000-0000-0000-0000-000000000001","role":"authenticated"}',TRUE);
DO $$ DECLARE t UUID:=(SELECT id FROM public.tests WHERE code='ANTI_HCV'); rv BIGINT; v BIGINT; BEGIN
 IF NOT public.has_permission('can_configure_catalogue_technical') OR public.has_permission('can_manage_catalogue') THEN RAISE EXCEPTION 'TECHNICIAN_PERMISSION_SPLIT_INVALID'; END IF;
 SELECT row_version INTO rv FROM public.tests WHERE id=t;
 BEGIN PERFORM public.catalogue_technical_update_test(t,'{"price_paisa":1}',rv,'Injection test'); RAISE EXCEPTION 'PROTECTED_FIELD_ACCEPTED'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM public.catalogue_technical_update_test(t,'{"sample_type":"Serum","container":"Plain tube","method":""}',rv,'Local technical configuration');
 SELECT x.configuration_version INTO v FROM jsonb_to_record((SELECT item FROM public.catalogue_readiness_inventory(NULL,'ANTI_HCV') item WHERE item->>'code'='ANTI_HCV')) x(configuration_version BIGINT);
 BEGIN PERFORM public.catalogue_decide_readiness(t,'Approve','Technician must not approve.',v); RAISE EXCEPTION 'TECHNICIAN_APPROVAL_ACCEPTED'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ DECLARE evidence_id UUID; BEGIN
 SELECT id INTO evidence_id FROM public.catalogue_configuration_evidence LIMIT 1;
 BEGIN UPDATE public.catalogue_configuration_evidence SET reason='mutated' WHERE id=evidence_id; RAISE EXCEPTION 'EVIDENCE_MUTATION_ACCEPTED'; EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
ROLLBACK;
SELECT 'CATALOGUE_READINESS_RUNTIME_PASS' AS result;
