-- Repair the confirmed New Bill follow-up view ACL while preserving RLS, and
-- enforce the two-active-role authorization boundary server-side.

CREATE OR REPLACE FUNCTION public.catalogue_test_result_readiness(p_test_id UUID)
RETURNS public.catalogue_result_readiness_enum LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
 SELECT CASE
  WHEN t.lifecycle_status='Archived' OR (NOT t.catalogue_approved AND NOT t.is_active) THEN 'Inactive'
  WHEN t.reporting_type='NoReporting' THEN 'NoReporting' WHEN NOT t.workflow_supported THEN 'SpecialistWorkflow'
  WHEN t.reporting_model='NarrativeDocument' THEN 'DocumentWorkflow'
  WHEN NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active') THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND (btrim(p.name)='' OR btrim(p.code)='')) THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type IN ('Numeric','Calculated') AND p.unit_validation_required AND btrim(COALESCE(p.unit,''))='') THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type IN ('Select','Boolean') AND (p.option_set_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.catalogue_option_values ov WHERE ov.option_set_id=p.option_set_id AND ov.is_active))) THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.catalogue_test_database_entries e WHERE e.configuration_test_id=t.id AND e.test_type='Multi parameter nested') AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.parent_parameter_id IS NOT NULL AND p.is_active) THEN 'Incomplete'
  ELSE 'Ready' END::public.catalogue_result_readiness_enum FROM public.tests t WHERE t.id=p_test_id
$$;

CREATE OR REPLACE VIEW public.catalogue_test_operational_state
WITH (security_invoker=true) AS
SELECT t.id test_id,public.catalogue_test_result_readiness(t.id) readiness,
 CASE public.catalogue_test_result_readiness(t.id)
  WHEN 'Ready' THEN 'Reportable & Ready' WHEN 'Incomplete' THEN 'Reportable · Result Structure Incomplete'
  WHEN 'SpecialistWorkflow' THEN 'Specialist workflow' WHEN 'DocumentWorkflow' THEN 'Specialist workflow'
  WHEN 'NoReporting' THEN 'Billing only · No Worklist' ELSE 'Inactive' END operational_state
FROM public.tests t;
REVOKE ALL ON public.catalogue_test_operational_state FROM PUBLIC,anon;
GRANT SELECT ON public.catalogue_test_operational_state TO authenticated;

CREATE OR REPLACE FUNCTION public.catalogue_expand_profile(p_profile_test_id UUID)
RETURNS TABLE(component_test_id UUID,component_parameter_id UUID,component_role TEXT,display_order INT,is_required BOOLEAN)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
 SELECT c.component_test_id,c.component_parameter_id,c.component_role,c.display_order,c.is_required
 FROM public.catalogue_profile_components c JOIN public.tests p ON p.id=c.profile_test_id
 WHERE c.profile_test_id=p_profile_test_id AND p.test_kind='Profile' ORDER BY c.display_order
$$;
REVOKE ALL ON FUNCTION public.catalogue_expand_profile(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.catalogue_expand_profile(UUID) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.replace_role_permission_matrix(p_matrix JSONB) RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE entry JSONB; role_row public.roles%ROWTYPE; seen UUID[]:=ARRAY[]::UUID[]; supplied TEXT[];
 admin_allowed CONSTANT TEXT[]:=ARRAY['can_view_dashboard','can_create_bill','can_edit_patient','can_collect_sample','can_receive_sample','can_reject_sample','can_enter_results','can_verify_results','can_acknowledge_critical','can_sign_reports','can_amend_reports','can_print_reports','can_manage_catalogue','can_configure_catalogue_technical','can_manage_ast_breakpoints','can_manage_referring_doctors','can_manage_personnel','can_view_financials','can_manage_users','can_manage_roles','can_view_audit_logs','can_manage_outsource_tracking','can_view_hmis_reports','can_edit_hmis_reports','can_finalize_hmis_reports'];
 technician_allowed CONSTANT TEXT[]:=ARRAY['can_view_dashboard','can_create_bill','can_edit_patient','can_collect_sample','can_receive_sample','can_reject_sample','can_enter_results','can_verify_results','can_acknowledge_critical','can_sign_reports','can_amend_reports','can_print_reports','can_manage_outsource_tracking','can_configure_catalogue_technical'];
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

CREATE OR REPLACE FUNCTION public.update_user_access(p_user_id UUID,p_is_active BOOLEAN,p_is_super_admin BOOLEAN,p_role_ids UUID[] DEFAULT ARRAY[]::UUID[])
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_target public.user_profiles%ROWTYPE; v_actor_name TEXT; v_role_count INT; v_distinct_count INT;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_manage_users') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_target FROM public.user_profiles WHERE id=p_user_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'User account was not found.' USING ERRCODE='P0002'; END IF;
 IF p_user_id=auth.uid() AND NOT p_is_active THEN RAISE EXCEPTION 'You cannot deactivate your own account.' USING ERRCODE='22023'; END IF;
 IF v_target.is_super_admin AND (NOT p_is_active OR NOT p_is_super_admin) AND NOT EXISTS(SELECT 1 FROM public.user_profiles x WHERE x.id<>p_user_id AND x.is_active AND x.is_super_admin) THEN RAISE EXCEPTION 'At least one active super administrator is required.' USING ERRCODE='23514'; END IF;
 SELECT count(*),count(DISTINCT r.id) INTO v_role_count,v_distinct_count FROM unnest(COALESCE(p_role_ids,ARRAY[]::UUID[]))q(id) JOIN public.roles r ON r.id=q.id AND r.code IN('admin','lab_technician');
 IF v_role_count<>cardinality(COALESCE(p_role_ids,ARRAY[]::UUID[])) OR v_distinct_count<>v_role_count THEN RAISE EXCEPTION 'Only Administrator and Lab Technician may be assigned.' USING ERRCODE='22023'; END IF;
 IF p_is_super_admin AND NOT EXISTS(SELECT 1 FROM public.roles r WHERE r.id=ANY(p_role_ids) AND r.code='admin') THEN RAISE EXCEPTION 'A Super Admin must hold the Administrator role.' USING ERRCODE='23514'; END IF;
 UPDATE public.user_profiles SET is_active=p_is_active,is_super_admin=p_is_super_admin,updated_at=now() WHERE id=p_user_id;
 DELETE FROM public.user_roles WHERE user_id=p_user_id;
 INSERT INTO public.user_roles(user_id,role_id) SELECT p_user_id,id FROM unnest(COALESCE(p_role_ids,ARRAY[]::UUID[]))q(id);
 SELECT COALESCE(full_name,'Administrator') INTO v_actor_name FROM public.user_profiles WHERE id=auth.uid();
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),v_actor_name,'USER_ACCESS_UPDATED','UserProfile',p_user_id::TEXT,jsonb_build_object('changed_fields',jsonb_build_array('is_active','is_super_admin','roles'),'role_count',v_role_count));
 RETURN jsonb_build_object('success',TRUE,'user_id',p_user_id);
END $$;

REVOKE ALL ON FUNCTION public.replace_role_permission_matrix(JSONB),public.update_user_access(UUID,BOOLEAN,BOOLEAN,UUID[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.replace_role_permission_matrix(JSONB),public.update_user_access(UUID,BOOLEAN,BOOLEAN,UUID[]) TO authenticated;
