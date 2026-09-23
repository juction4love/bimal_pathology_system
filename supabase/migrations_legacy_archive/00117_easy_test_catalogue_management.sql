-- Migration 00117: Complete Easy Test Catalogue Management & Permissions
-- Authorizes Administrator and Lab Technician to perform full routine CRUD on the test catalogue
-- Provides easy server-authoritative RPCs for Tests, Parameters, Reference Ranges, Prices, Aliases, Panels, and Analyzers.

BEGIN;

-- 1. Update Permissions & RBAC for Catalogue Management
-- Both Administrator and Lab Technician are authorized to manage operational catalogue
CREATE OR REPLACE FUNCTION public.catalogue_require_manager() RETURNS VOID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT (
    public.has_permission('can_manage_catalogue') OR public.has_permission('can_configure_catalogue_technical')
  ) THEN
    RAISE EXCEPTION 'Catalogue management requires an active authorized laboratory operator.' USING ERRCODE='42501';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_require_technical() RETURNS VOID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT (
    public.has_permission('can_configure_catalogue_technical') OR public.has_permission('can_manage_catalogue')
  ) THEN
    RAISE EXCEPTION 'Catalogue technical configuration requires an active authorized user.' USING ERRCODE='42501';
  END IF;
END $$;

-- Ensure role permission matrix allows can_manage_catalogue for lab_technician
CREATE OR REPLACE FUNCTION public.replace_role_permission_matrix(p_matrix JSONB) RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE entry JSONB; role_row public.roles%ROWTYPE; seen UUID[]:=ARRAY[]::UUID[]; supplied TEXT[];
 admin_allowed CONSTANT TEXT[]:=ARRAY['can_view_dashboard','can_create_bill','can_edit_patient','can_collect_sample','can_receive_sample','can_reject_sample','can_enter_results','can_verify_results','can_acknowledge_critical','can_sign_reports','can_amend_reports','can_print_reports','can_manage_catalogue','can_configure_catalogue_technical','can_manage_ast_breakpoints','can_manage_referring_doctors','can_manage_personnel','can_view_financials','can_manage_users','can_manage_roles','can_view_audit_logs','can_manage_outsource_tracking','can_view_hmis_reports','can_edit_hmis_reports','can_finalize_hmis_reports'];
 technician_allowed CONSTANT TEXT[]:=ARRAY['can_view_dashboard','can_create_bill','can_edit_patient','can_collect_sample','can_receive_sample','can_reject_sample','can_enter_results','can_verify_results','can_acknowledge_critical','can_sign_reports','can_amend_reports','can_print_reports','can_manage_outsource_tracking','can_configure_catalogue_technical','can_manage_catalogue'];
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_manage_roles') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF jsonb_typeof(COALESCE(p_matrix,'[]'))<>'array' THEN RAISE EXCEPTION 'Role permission matrix must be an array.' USING ERRCODE='22023'; END IF;
 FOR entry IN SELECT * FROM jsonb_array_elements(COALESCE(p_matrix,'[]')) LOOP
  SELECT * INTO role_row FROM public.roles WHERE id=(entry->>'role_id')::UUID FOR UPDATE;
  IF NOT FOUND OR role_row.code NOT IN('admin','lab_technician') THEN RAISE EXCEPTION 'Only active Administrator and Lab Technician roles may be submitted.' USING ERRCODE='22023'; END IF;
  IF role_row.id=ANY(seen) THEN RAISE EXCEPTION 'A role may occur only once.' USING ERRCODE='23505'; END IF;
  IF jsonb_typeof(COALESCE(entry->'permissions','[]'))<>'array' THEN RAISE EXCEPTION 'Permissions must be an array.' USING ERRCODE='22023'; END IF;
  SELECT COALESCE(array_agg(DISTINCT p ORDER BY p),ARRAY[]::TEXT[]) INTO supplied FROM jsonb_array_elements_text(COALESCE(entry->'permissions','[]'))p;
  IF role_row.code='admin' AND supplied<>ARRAY(SELECT p FROM unnest(admin_allowed)p ORDER BY p) THEN RAISE EXCEPTION 'Administrator must retain the complete operational permission set.' USING ERRCODE='23514'; END IF;
  IF role_row.code='lab_technician' AND supplied<>ARRAY(SELECT p FROM unnest(technician_allowed)p ORDER BY p) THEN RAISE EXCEPTION 'Lab Technician must retain the complete operational pathology permission set.' USING ERRCODE='23514'; END IF;
  seen:=array_append(seen,role_row.id);
 END LOOP;
 FOR entry IN SELECT * FROM jsonb_array_elements(COALESCE(p_matrix,'[]')) LOOP
  DELETE FROM public.role_permissions WHERE role_id=(entry->>'role_id')::UUID;
  INSERT INTO public.role_permissions(role_id,permission_key) SELECT (entry->>'role_id')::UUID,p FROM jsonb_array_elements_text(entry->'permissions')p;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'ROLE_PERMISSIONS_REPLACED','Role',entry->>'role_id',jsonb_build_object('permissions',entry->'permissions'));
 END LOOP;
 RETURN cardinality(seen);
END $$;

-- Grant can_manage_catalogue to lab_technician in role_permissions table
INSERT INTO public.role_permissions (role_id, permission_key)
SELECT r.id, 'can_manage_catalogue'
FROM public.roles r
WHERE r.code = 'lab_technician'
ON CONFLICT (role_id, permission_key) DO NOTHING;

-- Ensure RLS write permissions on analyzer_parameter_mappings
ALTER TABLE public.analyzer_parameter_mappings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS analyzer_param_mappings_write ON public.analyzer_parameter_mappings;
CREATE POLICY analyzer_param_mappings_write ON public.analyzer_parameter_mappings
  FOR ALL TO authenticated
  USING (public.has_permission('can_manage_catalogue') OR public.has_permission('can_configure_catalogue_technical'))
  WITH CHECK (public.has_permission('can_manage_catalogue') OR public.has_permission('can_configure_catalogue_technical'));

-- 2. Easy Test Save RPC (Create / Update test with full fields, price versioning, aliases)
CREATE OR REPLACE FUNCTION public.catalogue_save_test_easy(
  p_test JSONB,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_id UUID := NULLIF(p_test->>'id', '')::UUID;
  v_existing public.tests%ROWTYPE;
  v_code TEXT := upper(btrim(p_test->>'code'));
  v_name TEXT := btrim(p_test->>'name');
  v_short_name TEXT := NULLIF(btrim(p_test->>'short_name'), '');
  v_department TEXT := COALESCE(NULLIF(btrim(p_test->>'department'), ''), 'Clinical Pathology');
  v_category TEXT := COALESCE(NULLIF(btrim(p_test->>'category'), ''), 'General');
  v_category_id UUID := NULLIF(p_test->>'category_id', '')::UUID;
  v_test_kind public.catalogue_test_kind_enum := COALESCE((p_test->>'test_kind')::public.catalogue_test_kind_enum, 'Individual');
  v_reporting_type public.reporting_type_enum := COALESCE((p_test->>'reporting_type')::public.reporting_type_enum, 'InHouse');
  v_outsource_lab TEXT := NULLIF(btrim(p_test->>'outsource_lab_name'), '');
  v_sample_type TEXT := COALESCE(NULLIF(btrim(p_test->>'sample_type'), ''), 'Blood');
  v_container TEXT := COALESCE(NULLIF(btrim(p_test->>'container'), ''), 'EDTA');
  v_sample_volume TEXT := NULLIF(btrim(p_test->>'sample_volume'), '');
  v_method TEXT := NULLIF(btrim(p_test->>'method'), '');
  v_tat_hours INT := COALESCE((p_test->>'tat_hours')::INT, 24);
  v_display_order INT := COALESCE((p_test->>'display_order')::INT, 0);
  v_description TEXT := NULLIF(btrim(p_test->>'description'), '');
  v_configuration_notes TEXT := NULLIF(btrim(p_test->>'configuration_notes'), '');
  v_is_active BOOLEAN := COALESCE((p_test->>'is_active')::BOOLEAN, TRUE);
  v_billing_enabled BOOLEAN := COALESCE((p_test->>'billing_enabled')::BOOLEAN, TRUE);
  v_allow_zero_price BOOLEAN := COALESCE((p_test->>'allow_zero_price_billing')::BOOLEAN, FALSE);
  v_allow_manual_price BOOLEAN := COALESCE((p_test->>'allow_manual_price')::BOOLEAN, FALSE);
  v_pricing_policy public.catalogue_pricing_policy_enum := COALESCE((p_test->>'pricing_policy')::public.catalogue_pricing_policy_enum, 'Fixed');
  v_price_paisa BIGINT := COALESCE((p_test->>'price_paisa')::BIGINT, 0);
  v_aliases TEXT[] := ARRAY(SELECT DISTINCT lower(btrim(x)) FROM jsonb_array_elements_text(COALESCE(p_test->'search_aliases', '[]'::JSONB)) x WHERE btrim(x) <> '');
  v_result_id UUID;
  v_old_data JSONB;
  alias_item TEXT;
BEGIN
  PERFORM public.catalogue_require_manager();

  IF v_code IS NULL OR v_code = '' THEN
    RAISE EXCEPTION 'Test code is required.' USING ERRCODE='22023';
  END IF;
  IF v_name IS NULL OR v_name = '' THEN
    RAISE EXCEPTION 'Test name is required.' USING ERRCODE='22023';
  END IF;
  IF v_price_paisa < 0 THEN
    RAISE EXCEPTION 'Price cannot be negative.' USING ERRCODE='23514';
  END IF;

  IF v_id IS NOT NULL THEN
    -- Update existing test
    SELECT * INTO v_existing FROM public.tests WHERE id = v_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002';
    END IF;
    IF p_expected_version IS NOT NULL AND v_existing.row_version <> p_expected_version THEN
      RAISE EXCEPTION 'This test was updated by another user. Reload before saving.' USING ERRCODE='PT409';
    END IF;

    -- Check duplicate code on other tests
    IF EXISTS (SELECT 1 FROM public.tests WHERE code = v_code AND id <> v_id) THEN
      RAISE EXCEPTION 'Test code % is already in use by another test.', v_code USING ERRCODE='23505';
    END IF;

    v_old_data := to_jsonb(v_existing);

    UPDATE public.tests
    SET code = v_code,
        name = v_name,
        short_name = v_short_name,
        department = v_department,
        category = v_category,
        category_id = v_category_id,
        test_kind = v_test_kind,
        reporting_type = v_reporting_type,
        outsource_lab_name = CASE WHEN v_reporting_type = 'OutsourceWithBimalReport' THEN v_outsource_lab ELSE NULL END,
        sample_type = v_sample_type,
        container = v_container,
        sample_volume = v_sample_volume,
        method = v_method,
        tat_hours = v_tat_hours,
        display_order = v_display_order,
        description = v_description,
        configuration_notes = v_configuration_notes,
        is_active = v_is_active,
        lifecycle_status = CASE WHEN v_is_active THEN 'Active'::public.catalogue_lifecycle_enum ELSE 'Draft'::public.catalogue_lifecycle_enum END,
        billing_enabled = v_billing_enabled,
        clinical_reporting_enabled = (v_reporting_type <> 'NoReporting'),
        collection_required = (v_reporting_type <> 'NoReporting'),
        workflow_type = CASE WHEN v_reporting_type = 'NoReporting' THEN 'NoClinicalReport'::public.clinical_workflow_type_enum ELSE workflow_type END,
        price_paisa = v_price_paisa,
        price_configured = (v_price_paisa > 0),
        allow_zero_price_billing = v_allow_zero_price,
        allow_manual_price = v_allow_manual_price,
        pricing_policy = v_pricing_policy,
        search_aliases = v_aliases,
        row_version = row_version + 1,
        updated_at = NOW()
    WHERE id = v_id
    RETURNING id INTO v_result_id;

    -- If price changed or no active rate version exists, update catalogue_rate_versions
    IF v_existing.price_paisa IS DISTINCT FROM v_price_paisa OR NOT EXISTS (
      SELECT 1 FROM public.catalogue_rate_versions WHERE test_id = v_id AND status = 'Active' AND (effective_to IS NULL OR effective_to > now())
    ) THEN
      -- Inactivate current active rates
      UPDATE public.catalogue_rate_versions
      SET status = 'Inactive', effective_to = NOW(), updated_at = NOW(), row_version = row_version + 1
      WHERE test_id = v_id AND status = 'Active' AND (effective_to IS NULL OR effective_to > now());

      -- Insert new active rate version
      INSERT INTO public.catalogue_rate_versions (
        entity_type, test_id, ratelist_name, price_paisa, status, effective_from, row_version
      ) VALUES (
        'Test', v_id, 'Standard Patient Rate', v_price_paisa, 'Active', NOW(), 1
      );
    END IF;

  ELSE
    -- Insert new test
    IF EXISTS (SELECT 1 FROM public.tests WHERE code = v_code) THEN
      RAISE EXCEPTION 'Test code % already exists.', v_code USING ERRCODE='23505';
    END IF;

    INSERT INTO public.tests (
      code, name, short_name, department, category, category_id,
      test_kind, reporting_type, outsource_lab_name, sample_type, container,
      sample_volume, method, tat_hours, display_order, description,
      configuration_notes, is_active, lifecycle_status, billing_enabled,
      clinical_reporting_enabled, collection_required, workflow_type,
      price_paisa, price_configured, allow_zero_price_billing, allow_manual_price,
      pricing_policy, search_aliases, clinical_configuration_status, row_version
    ) VALUES (
      v_code, v_name, v_short_name, v_department, v_category, v_category_id,
      v_test_kind, v_reporting_type, CASE WHEN v_reporting_type = 'OutsourceWithBimalReport' THEN v_outsource_lab ELSE NULL END,
      v_sample_type, v_container, v_sample_volume, v_method, v_tat_hours, v_display_order,
      v_description, v_configuration_notes, v_is_active,
      CASE WHEN v_is_active THEN 'Active'::public.catalogue_lifecycle_enum ELSE 'Draft'::public.catalogue_lifecycle_enum END,
      v_billing_enabled, (v_reporting_type <> 'NoReporting'), (v_reporting_type <> 'NoReporting'),
      CASE WHEN v_reporting_type = 'NoReporting' THEN 'NoClinicalReport'::public.clinical_workflow_type_enum ELSE 'General'::public.clinical_workflow_type_enum END,
      v_price_paisa, (v_price_paisa > 0), v_allow_zero_price, v_allow_manual_price,
      v_pricing_policy, v_aliases, 'Configured', 1
    ) RETURNING id INTO v_result_id;

    -- Add default parameter for standalone reportable tests
    IF v_reporting_type <> 'NoReporting' THEN
      INSERT INTO public.parameters (
        test_id, code, name, value_type, display_order, is_mandatory, is_active, lifecycle_status, clinical_configuration_status, row_version
      ) VALUES (
        v_result_id, 'RESULT', 'Result', 'Text', 1, TRUE, TRUE, 'Active', 'Configured', 1
      ) ON CONFLICT DO NOTHING;
    END IF;

    -- Create initial rate version
    INSERT INTO public.catalogue_rate_versions (
      entity_type, test_id, ratelist_name, price_paisa, status, effective_from, row_version
    ) VALUES (
      'Test', v_result_id, 'Standard Patient Rate', v_price_paisa, 'Active', NOW(), 1
    );

    -- Create catalogue_service_readiness record
    INSERT INTO public.catalogue_service_readiness (
      test_id, state, configuration_version, approved_by, approved_at, decision_reason
    ) VALUES (
      v_result_id, 'Approved', 1, auth.uid(), NOW(), 'Created via Easy Test Catalogue Editor'
    ) ON CONFLICT (test_id) DO NOTHING;
  END IF;

  -- Sync test_aliases table
  DELETE FROM public.test_aliases WHERE test_id = v_result_id;
  FOREACH alias_item IN ARRAY v_aliases LOOP
    INSERT INTO public.test_aliases (test_id, alias_name)
    VALUES (v_result_id, alias_item)
    ON CONFLICT (test_id, alias_name) DO NOTHING;
  END LOOP;

  -- Audit log
  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, old_data, new_data
  ) VALUES (
    auth.uid(),
    public.catalogue_actor_name(),
    CASE WHEN v_old_data IS NULL THEN 'CATALOGUE_TEST_CREATED' ELSE 'CATALOGUE_TEST_UPDATED' END,
    'Test',
    v_result_id::TEXT,
    v_old_data,
    (SELECT to_jsonb(x) FROM public.tests x WHERE x.id = v_result_id)
  );

  RETURN (SELECT to_jsonb(t) FROM public.tests t WHERE t.id = v_result_id);
END;
$$;

-- 3. Guarded Test Deletion RPC (hard delete only if unused, error if used)
CREATE OR REPLACE FUNCTION public.catalogue_delete_test_guarded(
  p_test_id UUID,
  p_expected_version BIGINT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.tests%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager();

  SELECT * INTO v FROM public.tests WHERE id = p_test_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  IF v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'This test was updated by another user. Reload before deleting.' USING ERRCODE='PT409';
  END IF;

  -- Strict reference check: if used anywhere historically, deny hard delete
  IF EXISTS (SELECT 1 FROM public.bill_items WHERE test_id = p_test_id)
     OR EXISTS (SELECT 1 FROM public.clinical_order_items WHERE test_id = p_test_id)
     OR EXISTS (SELECT 1 FROM public.test_results r JOIN public.parameters p ON p.id = r.parameter_id WHERE p.test_id = p_test_id)
     OR EXISTS (SELECT 1 FROM public.health_package_components WHERE test_id = p_test_id)
     OR EXISTS (SELECT 1 FROM public.catalogue_profile_components WHERE profile_test_id = p_test_id OR component_test_id = p_test_id)
     OR EXISTS (SELECT 1 FROM public.catalogue_panel_components WHERE component_test_id = p_test_id)
     OR EXISTS (SELECT 1 FROM public.bill_package_components WHERE test_id = p_test_id)
     OR EXISTS (SELECT 1 FROM public.bill_panel_components WHERE test_id = p_test_id)
  THEN
    RAISE EXCEPTION 'Referenced tests cannot be deleted permanently. Archive this test instead to preserve audit lineage.' USING ERRCODE='23503';
  END IF;

  -- Safe hard deletion of child records for unused test
  DELETE FROM public.test_aliases WHERE test_id = p_test_id;
  DELETE FROM public.reference_ranges WHERE parameter_id IN (SELECT id FROM public.parameters WHERE test_id = p_test_id);
  DELETE FROM public.analyzer_parameter_mappings WHERE test_id = p_test_id;
  DELETE FROM public.parameters WHERE test_id = p_test_id;
  DELETE FROM public.catalogue_rate_versions WHERE test_id = p_test_id;
  DELETE FROM public.catalogue_service_readiness WHERE test_id = p_test_id;
  DELETE FROM public.catalogue_test_approval_events WHERE test_id = p_test_id;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, old_data
  ) VALUES (
    auth.uid(), public.catalogue_actor_name(), 'CATALOGUE_TEST_DELETED_PERMANENTLY', 'Test', p_test_id::TEXT, to_jsonb(v)
  );

  DELETE FROM public.tests WHERE id = p_test_id;
END;
$$;

-- 4. Duplicate / Clone Test RPC (copies configuration to new code and name)
CREATE OR REPLACE FUNCTION public.catalogue_clone_test_easy(
  p_source_test_id UUID,
  p_new_code TEXT,
  p_new_name TEXT,
  p_new_price_paisa BIGINT DEFAULT 0
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  source public.tests%ROWTYPE;
  target_id UUID;
  p RECORD;
  new_p_id UUID;
  r RECORD;
  code_clean TEXT := upper(btrim(p_new_code));
  name_clean TEXT := btrim(p_new_name);
BEGIN
  PERFORM public.catalogue_require_manager();

  IF code_clean IS NULL OR code_clean = '' THEN
    RAISE EXCEPTION 'A unique new test code is required.' USING ERRCODE='22023';
  END IF;
  IF name_clean IS NULL OR name_clean = '' THEN
    RAISE EXCEPTION 'A test name is required.' USING ERRCODE='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.tests WHERE code = code_clean) THEN
    RAISE EXCEPTION 'Test code % already exists. Please choose a unique code.', code_clean USING ERRCODE='23505';
  END IF;

  SELECT * INTO source FROM public.tests WHERE id = p_source_test_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Source test was not found.' USING ERRCODE='P0002';
  END IF;

  INSERT INTO public.tests (
    code, name, short_name, description, department, category, category_id,
    test_kind, reporting_type, outsource_lab_name, price_paisa, sample_type,
    container, sample_volume, method, tat_hours, display_order, is_active,
    lifecycle_status, configuration_notes, price_configured, clinical_configuration_status,
    billing_enabled, clinical_reporting_enabled, collection_required, workflow_type,
    allow_zero_price_billing, allow_manual_price, pricing_policy, search_aliases, row_version
  ) VALUES (
    code_clean, name_clean, source.short_name, source.description, source.department,
    source.category, source.category_id, source.test_kind, source.reporting_type,
    source.outsource_lab_name, COALESCE(p_new_price_paisa, source.price_paisa),
    source.sample_type, source.container, source.sample_volume, source.method,
    source.tat_hours, source.display_order, TRUE, 'Active',
    'Cloned from ' || source.code, (COALESCE(p_new_price_paisa, source.price_paisa) > 0),
    'Configured', TRUE, (source.reporting_type <> 'NoReporting'),
    (source.reporting_type <> 'NoReporting'), source.workflow_type,
    source.allow_zero_price_billing, source.allow_manual_price, source.pricing_policy,
    source.search_aliases, 1
  ) RETURNING id INTO target_id;

  -- Create initial rate version
  INSERT INTO public.catalogue_rate_versions (
    entity_type, test_id, ratelist_name, price_paisa, status, effective_from, row_version
  ) VALUES (
    'Test', target_id, 'Standard Patient Rate', COALESCE(p_new_price_paisa, source.price_paisa), 'Active', NOW(), 1
  );

  -- Copy parameters and their reference ranges
  FOR p IN SELECT * FROM public.parameters WHERE test_id = p_source_test_id AND lifecycle_status <> 'Archived' ORDER BY display_order LOOP
    INSERT INTO public.parameters (
      test_id, code, name, value_type, unit, options, formula, formula_dependencies,
      calculation_identifier, decimal_precision, interpretation_config, display_order,
      is_mandatory, is_active, lifecycle_status, clinical_configuration_status, row_version
    ) VALUES (
      target_id, p.code, p.name, p.value_type, p.unit, p.options, p.formula, p.formula_dependencies,
      p.calculation_identifier, p.decimal_precision, p.interpretation_config, p.display_order,
      p.is_mandatory, TRUE, 'Active', 'Configured', 1
    ) RETURNING id INTO new_p_id;

    -- Copy ranges for this parameter
    FOR r IN SELECT * FROM public.reference_ranges WHERE parameter_id = p.id AND lifecycle_status <> 'Archived' LOOP
      INSERT INTO public.reference_ranges (
        parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max,
        critical_low, critical_high, normal_text, reference_text, method, unit,
        is_active, is_approved, lifecycle_status, validation_state, row_version
      ) VALUES (
        new_p_id, r.gender, r.age_min_days, r.age_max_days, r.normal_min, r.normal_max,
        r.critical_low, r.critical_high, r.normal_text, r.reference_text, r.method, r.unit,
        r.is_active, TRUE, 'Active', 'ClinicallyValidated', 1
      );
    END LOOP;
  END LOOP;

  -- Create readiness record
  INSERT INTO public.catalogue_service_readiness (
    test_id, state, configuration_version, approved_by, approved_at, decision_reason
  ) VALUES (
    target_id, 'Approved', 1, auth.uid(), NOW(), 'Cloned from ' || source.code
  );

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, new_data
  ) VALUES (
    auth.uid(), public.catalogue_actor_name(), 'CATALOGUE_TEST_CLONED', 'Test', target_id::TEXT,
    jsonb_build_object('source_id', p_source_test_id, 'source_code', source.code, 'new_code', code_clean)
  );

  RETURN target_id;
END;
$$;

-- 5. Easy Parameter Save RPC
CREATE OR REPLACE FUNCTION public.catalogue_save_parameter_easy(
  p_parameter JSONB,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_id UUID := NULLIF(p_parameter->>'id', '')::UUID;
  v_test_id UUID := (p_parameter->>'test_id')::UUID;
  v_code TEXT := upper(btrim(p_parameter->>'code'));
  v_name TEXT := btrim(p_parameter->>'name');
  v_value_type TEXT := COALESCE(NULLIF(btrim(p_parameter->>'value_type'), ''), 'Text');
  v_unit TEXT := NULLIF(btrim(p_parameter->>'unit'), '');
  v_options JSONB := p_parameter->'options';
  v_formula TEXT := NULLIF(btrim(p_parameter->>'formula'), '');
  v_calc_id TEXT := NULLIF(btrim(p_parameter->>'calculation_identifier'), '');
  v_precision SMALLINT := COALESCE((p_parameter->>'decimal_precision')::SMALLINT, 2);
  v_display_order INT := COALESCE((p_parameter->>'display_order')::INT, 0);
  v_is_mandatory BOOLEAN := COALESCE((p_parameter->>'is_mandatory')::BOOLEAN, TRUE);
  v_is_active BOOLEAN := COALESCE((p_parameter->>'is_active')::BOOLEAN, TRUE);
  v_interp JSONB := p_parameter->'interpretation_config';
  v_existing public.parameters%ROWTYPE;
  v_result_id UUID;
  v_old_data JSONB;
BEGIN
  PERFORM public.catalogue_require_manager();

  IF v_code IS NULL OR v_code = '' THEN
    RAISE EXCEPTION 'Parameter code is required.' USING ERRCODE='22023';
  END IF;
  IF v_name IS NULL OR v_name = '' THEN
    RAISE EXCEPTION 'Parameter name is required.' USING ERRCODE='22023';
  END IF;

  IF v_value_type = 'Calculated' AND (v_formula IS NULL OR v_calc_id IS NULL) THEN
    RAISE EXCEPTION 'Calculated parameters require a calculation identifier and formula.' USING ERRCODE='23514';
  END IF;

  IF v_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.parameters WHERE id = v_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Parameter was not found.' USING ERRCODE='P0002';
    END IF;
    IF p_expected_version IS NOT NULL AND v_existing.row_version <> p_expected_version THEN
      RAISE EXCEPTION 'This parameter was updated by another user. Reload before saving.' USING ERRCODE='PT409';
    END IF;

    v_old_data := to_jsonb(v_existing);

    UPDATE public.parameters
    SET code = v_code,
        name = v_name,
        value_type = v_value_type,
        unit = v_unit,
        options = v_options,
        formula = v_formula,
        calculation_identifier = v_calc_id,
        decimal_precision = v_precision,
        display_order = v_display_order,
        is_mandatory = v_is_mandatory,
        is_active = v_is_active,
        lifecycle_status = CASE WHEN v_is_active THEN 'Active'::public.catalogue_lifecycle_enum ELSE 'Draft'::public.catalogue_lifecycle_enum END,
        interpretation_config = v_interp,
        row_version = row_version + 1,
        updated_at = NOW()
    WHERE id = v_id
    RETURNING id INTO v_result_id;
  ELSE
    INSERT INTO public.parameters (
      test_id, code, name, value_type, unit, options, formula,
      calculation_identifier, decimal_precision, display_order,
      is_mandatory, is_active, lifecycle_status, clinical_configuration_status,
      interpretation_config, row_version
    ) VALUES (
      v_test_id, v_code, v_name, v_value_type, v_unit, v_options, v_formula,
      v_calc_id, v_precision, v_display_order,
      v_is_mandatory, v_is_active,
      CASE WHEN v_is_active THEN 'Active'::public.catalogue_lifecycle_enum ELSE 'Draft'::public.catalogue_lifecycle_enum END,
      'Configured', v_interp, 1
    ) RETURNING id INTO v_result_id;
  END IF;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, old_data, new_data
  ) VALUES (
    auth.uid(),
    public.catalogue_actor_name(),
    CASE WHEN v_old_data IS NULL THEN 'CATALOGUE_PARAMETER_CREATED' ELSE 'CATALOGUE_PARAMETER_UPDATED' END,
    'Parameter',
    v_result_id::TEXT,
    v_old_data,
    (SELECT to_jsonb(x) FROM public.parameters x WHERE x.id = v_result_id)
  );

  RETURN v_result_id;
END;
$$;

-- 6. Parameter Reorder RPC
CREATE OR REPLACE FUNCTION public.catalogue_reorder_parameters_easy(
  p_test_id UUID,
  p_parameter_ids UUID[]
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  i INT;
  param_id UUID;
BEGIN
  PERFORM public.catalogue_require_manager();

  FOR i IN 1..cardinality(p_parameter_ids) LOOP
    param_id := p_parameter_ids[i];
    UPDATE public.parameters
    SET display_order = i, updated_at = NOW()
    WHERE id = param_id AND test_id = p_test_id;
  END LOOP;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, new_data
  ) VALUES (
    auth.uid(), public.catalogue_actor_name(), 'CATALOGUE_PARAMETERS_REORDERED', 'Test', p_test_id::TEXT,
    jsonb_build_object('ordered_ids', p_parameter_ids)
  );
END;
$$;

-- 7. Guarded Parameter Delete RPC
CREATE OR REPLACE FUNCTION public.catalogue_delete_parameter_guarded(
  p_parameter_id UUID,
  p_expected_version BIGINT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.parameters%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager();

  SELECT * INTO v FROM public.parameters WHERE id = p_parameter_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  IF v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'This parameter was updated by another user. Reload before deleting.' USING ERRCODE='PT409';
  END IF;

  IF EXISTS (SELECT 1 FROM public.test_results WHERE parameter_id = p_parameter_id)
     OR EXISTS (SELECT 1 FROM public.catalogue_panel_components WHERE component_parameter_id = p_parameter_id)
  THEN
    RAISE EXCEPTION 'Referenced parameters cannot be deleted permanently. Archive this parameter instead.' USING ERRCODE='23503';
  END IF;

  DELETE FROM public.reference_ranges WHERE parameter_id = p_parameter_id;
  DELETE FROM public.analyzer_parameter_mappings WHERE parameter_id = p_parameter_id;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, old_data
  ) VALUES (
    auth.uid(), public.catalogue_actor_name(), 'CATALOGUE_PARAMETER_DELETED_PERMANENTLY', 'Parameter', p_parameter_id::TEXT, to_jsonb(v)
  );

  DELETE FROM public.parameters WHERE id = p_parameter_id;
END;
$$;

-- 8. Easy Reference Range Save RPC
CREATE OR REPLACE FUNCTION public.catalogue_save_range_easy(
  p_range JSONB,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_id UUID := NULLIF(p_range->>'id', '')::UUID;
  v_param_id UUID := (p_range->>'parameter_id')::UUID;
  v_gender TEXT := COALESCE(NULLIF(btrim(p_range->>'gender'), ''), 'All');
  v_age_min INT := COALESCE((p_range->>'age_min_days')::INT, 0);
  v_age_max INT := COALESCE((p_range->>'age_max_days')::INT, 43800);
  v_normal_min NUMERIC := NULLIF(p_range->>'normal_min', '')::NUMERIC;
  v_normal_max NUMERIC := NULLIF(p_range->>'normal_max', '')::NUMERIC;
  v_crit_low NUMERIC := NULLIF(p_range->>'critical_low', '')::NUMERIC;
  v_crit_high NUMERIC := NULLIF(p_range->>'critical_high', '')::NUMERIC;
  v_normal_text TEXT := NULLIF(btrim(p_range->>'normal_text'), '');
  v_ref_text TEXT := NULLIF(btrim(p_range->>'reference_text'), '');
  v_method TEXT := NULLIF(btrim(p_range->>'method'), '');
  v_unit TEXT := NULLIF(btrim(p_range->>'unit'), '');
  v_is_active BOOLEAN := COALESCE((p_range->>'is_active')::BOOLEAN, TRUE);
  v_existing public.reference_ranges%ROWTYPE;
  v_result_id UUID;
  v_old_data JSONB;
BEGIN
  PERFORM public.catalogue_require_manager();

  IF v_param_id IS NULL THEN
    RAISE EXCEPTION 'Parameter ID is required.' USING ERRCODE='22023';
  END IF;

  IF v_age_min > v_age_max THEN
    RAISE EXCEPTION 'Minimum age cannot exceed maximum age.' USING ERRCODE='23514';
  END IF;

  IF v_normal_min IS NOT NULL AND v_normal_max IS NOT NULL AND v_normal_min > v_normal_max THEN
    RAISE EXCEPTION 'Normal minimum (%) cannot exceed normal maximum (%).', v_normal_min, v_normal_max USING ERRCODE='23514';
  END IF;

  IF v_crit_low IS NOT NULL AND v_crit_high IS NOT NULL AND v_crit_low > v_crit_high THEN
    RAISE EXCEPTION 'Critical low (%) cannot exceed critical high (%).', v_crit_low, v_crit_high USING ERRCODE='23514';
  END IF;

  IF v_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.reference_ranges WHERE id = v_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Reference range was not found.' USING ERRCODE='P0002';
    END IF;
    IF p_expected_version IS NOT NULL AND v_existing.row_version <> p_expected_version THEN
      RAISE EXCEPTION 'This range was updated by another user. Reload before saving.' USING ERRCODE='PT409';
    END IF;

    v_old_data := to_jsonb(v_existing);

    UPDATE public.reference_ranges
    SET gender = v_gender,
        age_min_days = v_age_min,
        age_max_days = v_age_max,
        normal_min = v_normal_min,
        normal_max = v_normal_max,
        critical_low = v_crit_low,
        critical_high = v_crit_high,
        normal_text = v_normal_text,
        reference_text = v_ref_text,
        method = v_method,
        unit = v_unit,
        is_active = v_is_active,
        is_approved = TRUE,
        lifecycle_status = CASE WHEN v_is_active THEN 'Active'::public.catalogue_lifecycle_enum ELSE 'Draft'::public.catalogue_lifecycle_enum END,
        validation_state = 'ClinicallyValidated',
        row_version = row_version + 1,
        updated_at = NOW()
    WHERE id = v_id
    RETURNING id INTO v_result_id;
  ELSE
    INSERT INTO public.reference_ranges (
      parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max,
      critical_low, critical_high, normal_text, reference_text, method, unit,
      is_active, is_approved, lifecycle_status, validation_state, row_version
    ) VALUES (
      v_param_id, v_gender, v_age_min, v_age_max, v_normal_min, v_normal_max,
      v_crit_low, v_crit_high, v_normal_text, v_ref_text, v_method, v_unit,
      v_is_active, TRUE,
      CASE WHEN v_is_active THEN 'Active'::public.catalogue_lifecycle_enum ELSE 'Draft'::public.catalogue_lifecycle_enum END,
      'ClinicallyValidated', 1
    ) RETURNING id INTO v_result_id;
  END IF;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, old_data, new_data
  ) VALUES (
    auth.uid(),
    public.catalogue_actor_name(),
    CASE WHEN v_old_data IS NULL THEN 'CATALOGUE_RANGE_CREATED' ELSE 'CATALOGUE_RANGE_UPDATED' END,
    'ReferenceRange',
    v_result_id::TEXT,
    v_old_data,
    (SELECT to_jsonb(x) FROM public.reference_ranges x WHERE x.id = v_result_id)
  );

  RETURN v_result_id;
END;
$$;

-- 9. Guarded Reference Range Delete RPC
CREATE OR REPLACE FUNCTION public.catalogue_delete_range_guarded(
  p_range_id UUID,
  p_expected_version BIGINT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v public.reference_ranges%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager();

  SELECT * INTO v FROM public.reference_ranges WHERE id = p_range_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  IF p_expected_version IS NOT NULL AND v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'This range was updated by another user. Reload before deleting.' USING ERRCODE='PT409';
  END IF;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, old_data
  ) VALUES (
    auth.uid(), public.catalogue_actor_name(), 'CATALOGUE_RANGE_DELETED', 'ReferenceRange', p_range_id::TEXT, to_jsonb(v)
  );

  DELETE FROM public.reference_ranges WHERE id = p_range_id;
END;
$$;

-- 10. Easy Aliases Save RPC
CREATE OR REPLACE FUNCTION public.catalogue_save_test_aliases_easy(
  p_test_id UUID,
  p_aliases TEXT[]
) RETURNS TEXT[]
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  cleaned TEXT[];
  item TEXT;
BEGIN
  PERFORM public.catalogue_require_manager();

  SELECT COALESCE(array_agg(DISTINCT lower(btrim(x)) ORDER BY lower(btrim(x))), ARRAY[]::TEXT[])
  INTO cleaned
  FROM unnest(p_aliases) x
  WHERE btrim(x) <> '';

  DELETE FROM public.test_aliases WHERE test_id = p_test_id;

  FOREACH item IN ARRAY cleaned LOOP
    INSERT INTO public.test_aliases (test_id, alias_name)
    VALUES (p_test_id, item)
    ON CONFLICT (test_id, alias_name) DO NOTHING;
  END LOOP;

  UPDATE public.tests
  SET search_aliases = cleaned, row_version = row_version + 1, updated_at = NOW()
  WHERE id = p_test_id;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, new_data
  ) VALUES (
    auth.uid(), public.catalogue_actor_name(), 'CATALOGUE_ALIASES_UPDATED', 'Test', p_test_id::TEXT,
    jsonb_build_object('aliases', cleaned)
  );

  RETURN cleaned;
END;
$$;

-- 11. Easy Analyzer Mapping RPCs
CREATE OR REPLACE FUNCTION public.catalogue_save_analyzer_mapping_easy(
  p_mapping JSONB
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_id UUID := NULLIF(p_mapping->>'id', '')::UUID;
  v_analyzer_id UUID := (p_mapping->>'analyzer_id')::UUID;
  v_channel_code VARCHAR(50) := upper(btrim(p_mapping->>'channel_code'));
  v_channel_name VARCHAR(255) := btrim(p_mapping->>'channel_name');
  v_test_id UUID := NULLIF(p_mapping->>'test_id', '')::UUID;
  v_param_id UUID := NULLIF(p_mapping->>'parameter_id', '')::UUID;
  v_measurement_type VARCHAR(50) := COALESCE(NULLIF(p_mapping->>'measurement_type', ''), 'DIRECT_MEASURED');
  v_method VARCHAR(255) := COALESCE(NULLIF(btrim(p_mapping->>'analytical_method'), ''), 'Automated');
  v_unit VARCHAR(50) := NULLIF(btrim(p_mapping->>'unit'), '');
  v_differential_type VARCHAR(50) := COALESCE(NULLIF(p_mapping->>'differential_type', ''), 'Not Applicable');
  v_result_id UUID;
BEGIN
  PERFORM public.catalogue_require_manager();

  IF v_analyzer_id IS NULL OR v_channel_code IS NULL OR v_channel_name IS NULL THEN
    RAISE EXCEPTION 'Analyzer, Channel Code, and Channel Name are required.' USING ERRCODE='22023';
  END IF;

  IF v_id IS NOT NULL THEN
    UPDATE public.analyzer_parameter_mappings
    SET analyzer_id = v_analyzer_id,
        channel_code = v_channel_code,
        channel_name = v_channel_name,
        test_id = v_test_id,
        parameter_id = v_param_id,
        measurement_type = v_measurement_type,
        analytical_method = v_method,
        unit = v_unit,
        differential_type = v_differential_type,
        row_version = row_version + 1,
        updated_at = NOW()
    WHERE id = v_id
    RETURNING id INTO v_result_id;
  ELSE
    INSERT INTO public.analyzer_parameter_mappings (
      analyzer_id, channel_code, channel_name, test_id, parameter_id,
      measurement_type, analytical_method, unit, differential_type, row_version
    ) VALUES (
      v_analyzer_id, v_channel_code, v_channel_name, v_test_id, v_param_id,
      v_measurement_type, v_method, v_unit, v_differential_type, 1
    )
    ON CONFLICT (analyzer_id, channel_code) DO UPDATE SET
      channel_name = EXCLUDED.channel_name,
      test_id = EXCLUDED.test_id,
      parameter_id = EXCLUDED.parameter_id,
      measurement_type = EXCLUDED.measurement_type,
      analytical_method = EXCLUDED.analytical_method,
      unit = EXCLUDED.unit,
      differential_type = EXCLUDED.differential_type,
      row_version = public.analyzer_parameter_mappings.row_version + 1,
      updated_at = NOW()
    RETURNING id INTO v_result_id;
  END IF;

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, new_data
  ) VALUES (
    auth.uid(), public.catalogue_actor_name(), 'ANALYZER_MAPPING_SAVED', 'AnalyzerMapping', v_result_id::TEXT, p_mapping
  );

  RETURN v_result_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.catalogue_delete_analyzer_mapping_easy(
  p_mapping_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public.catalogue_require_manager();

  INSERT INTO public.audit_logs (
    user_id, user_name, action, entity_type, entity_id, old_data
  )
  SELECT auth.uid(), public.catalogue_actor_name(), 'ANALYZER_MAPPING_DELETED', 'AnalyzerMapping', p_mapping_id::TEXT, to_jsonb(m)
  FROM public.analyzer_parameter_mappings m WHERE m.id = p_mapping_id;

  DELETE FROM public.analyzer_parameter_mappings WHERE id = p_mapping_id;
END;
$$;

-- 12. Easy Test Audit History Function
CREATE OR REPLACE FUNCTION public.catalogue_get_test_history(p_test_id UUID)
RETURNS TABLE (
  id UUID,
  "timestamp" TIMESTAMPTZ,
  user_name TEXT,
  action TEXT,
  entity_type TEXT,
  old_data JSONB,
  new_data JSONB
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public.catalogue_require_manager();

  RETURN QUERY
  SELECT a.id, a.timestamp, a.user_name, a.action, a.entity_type, a.old_data, a.new_data
  FROM public.audit_logs a
  WHERE (a.entity_id = p_test_id::TEXT AND a.entity_type = 'Test')
     OR (a.entity_type = 'Parameter' AND a.entity_id IN (SELECT p.id::TEXT FROM public.parameters p WHERE p.test_id = p_test_id))
     OR (a.entity_type = 'ReferenceRange' AND a.entity_id IN (SELECT r.id::TEXT FROM public.reference_ranges r JOIN public.parameters p ON p.id = r.parameter_id WHERE p.test_id = p_test_id))
  ORDER BY a.timestamp DESC
  LIMIT 100;
END;
$$;

-- 13. Grants
REVOKE ALL ON FUNCTION public.catalogue_save_test_easy(JSONB, BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_save_test_easy(JSONB, BIGINT) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_delete_test_guarded(UUID, BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_delete_test_guarded(UUID, BIGINT) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_clone_test_easy(UUID, TEXT, TEXT, BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_clone_test_easy(UUID, TEXT, TEXT, BIGINT) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_save_parameter_easy(JSONB, BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_save_parameter_easy(JSONB, BIGINT) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_reorder_parameters_easy(UUID, UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_reorder_parameters_easy(UUID, UUID[]) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_delete_parameter_guarded(UUID, BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_delete_parameter_guarded(UUID, BIGINT) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_save_range_easy(JSONB, BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_save_range_easy(JSONB, BIGINT) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_delete_range_guarded(UUID, BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_delete_range_guarded(UUID, BIGINT) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_save_test_aliases_easy(UUID, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_save_test_aliases_easy(UUID, TEXT[]) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_save_analyzer_mapping_easy(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_save_analyzer_mapping_easy(JSONB) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_delete_analyzer_mapping_easy(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_delete_analyzer_mapping_easy(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.catalogue_get_test_history(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.catalogue_get_test_history(UUID) TO authenticated;

COMMIT;
