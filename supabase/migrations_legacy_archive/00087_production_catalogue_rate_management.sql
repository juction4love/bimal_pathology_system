-- Production catalogue/rate-management convergence after authoritative panel billing 00086.
-- Schema/code only: this migration does not create, price, activate, archive, or delete business catalogue data.

CREATE OR REPLACE FUNCTION public.catalogue_require_manager() RETURNS VOID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT public.has_permission('can_manage_catalogue') THEN
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

CREATE OR REPLACE FUNCTION public.catalogue_search_rate_list(
  p_query TEXT DEFAULT NULL,
  p_category_id UUID DEFAULT NULL,
  p_lifecycle public.catalogue_lifecycle_enum DEFAULT NULL,
  p_priced BOOLEAN DEFAULT NULL,
  p_entity_type public.catalogue_billable_entity_enum DEFAULT NULL,
  p_sort TEXT DEFAULT 'name',
  p_desc BOOLEAN DEFAULT FALSE,
  p_offset INT DEFAULT 0,
  p_limit INT DEFAULT 25
) RETURNS TABLE(item JSONB,total_count BIGINT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT (
    public.has_permission('can_manage_catalogue') OR public.has_permission('can_configure_catalogue_technical')
  ) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_sort NOT IN ('name','code','rate','updated_at') THEN RAISE EXCEPTION 'Invalid rate-list sort.' USING ERRCODE='22023'; END IF;

  RETURN QUERY
  WITH entities AS (
    SELECT 'Test'::public.catalogue_billable_entity_enum entity_type,t.id entity_id,t.code::TEXT,t.name::TEXT,
      t.category_id,c.name::TEXT category,t.lifecycle_status,t.updated_at,t.price_configured
    FROM public.tests t LEFT JOIN public.test_categories c ON c.id=t.category_id
    UNION ALL
    SELECT 'Panel',s.id,s.code,s.name,s.category_id,c.name,s.lifecycle_status,s.updated_at,
      EXISTS(SELECT 1 FROM public.catalogue_rate_versions rv WHERE rv.panel_service_id=s.id AND rv.status='Active' AND rv.price_paisa IS NOT NULL)
    FROM public.catalogue_panel_services s LEFT JOIN public.test_categories c ON c.id=s.category_id
    UNION ALL
    SELECT 'Package',p.id,p.code::TEXT,p.name::TEXT,NULL::UUID,'Packages',p.lifecycle_status,p.updated_at,
      EXISTS(SELECT 1 FROM public.catalogue_rate_versions rv WHERE rv.package_id=p.id AND rv.status='Active' AND rv.price_paisa IS NOT NULL)
    FROM public.health_packages p
  ), selected AS (
    SELECT e.*,r.id rate_id,r.price_paisa,r.version_number,r.row_version rate_row_version,r.effective_from,r.status rate_status,r.updated_at rate_updated_at
    FROM entities e LEFT JOIN LATERAL (
      SELECT rv.* FROM public.catalogue_rate_versions rv
      WHERE (e.entity_type='Test' AND rv.test_id=e.entity_id)
         OR (e.entity_type='Panel' AND rv.panel_service_id=e.entity_id)
         OR (e.entity_type='Package' AND rv.package_id=e.entity_id)
      ORDER BY (rv.status='Active') DESC,rv.version_number DESC LIMIT 1
    ) r ON TRUE
    WHERE (p_query IS NULL OR btrim(p_query)='' OR e.code ILIKE '%'||btrim(p_query)||'%' OR e.name ILIKE '%'||btrim(p_query)||'%')
      AND (p_category_id IS NULL OR e.category_id=p_category_id)
      AND (p_lifecycle IS NULL OR e.lifecycle_status=p_lifecycle)
      AND (p_priced IS NULL OR (r.status='Active' AND r.price_paisa IS NOT NULL)=p_priced)
      AND (p_entity_type IS NULL OR e.entity_type=p_entity_type)
  ), counted AS (SELECT s.*,count(*) OVER() AS matched_count FROM selected s)
  SELECT jsonb_build_object(
    'entity_type',x.entity_type,'entity_id',x.entity_id,'code',x.code,'name',x.name,'category_id',x.category_id,
    'category',x.category,'entity_status',x.lifecycle_status,'rate_id',x.rate_id,'price_paisa',x.price_paisa,
    'version_number',x.version_number,'rate_row_version',x.rate_row_version,'effective_from',x.effective_from,
    'rate_status',x.rate_status,'updated_at',COALESCE(x.rate_updated_at,x.updated_at)
  ),x.matched_count
  FROM counted x
  ORDER BY
    CASE WHEN p_sort='name' AND NOT p_desc THEN lower(x.name) END ASC,
    CASE WHEN p_sort='name' AND p_desc THEN lower(x.name) END DESC,
    CASE WHEN p_sort='code' AND NOT p_desc THEN lower(x.code) END ASC,
    CASE WHEN p_sort='code' AND p_desc THEN lower(x.code) END DESC,
    CASE WHEN p_sort='rate' AND NOT p_desc THEN x.price_paisa END ASC NULLS LAST,
    CASE WHEN p_sort='rate' AND p_desc THEN x.price_paisa END DESC NULLS LAST,
    CASE WHEN p_sort='updated_at' AND NOT p_desc THEN COALESCE(x.rate_updated_at,x.updated_at) END ASC,
    CASE WHEN p_sort='updated_at' AND p_desc THEN COALESCE(x.rate_updated_at,x.updated_at) END DESC,
    x.entity_id
  OFFSET greatest(COALESCE(p_offset,0),0) LIMIT greatest(1,least(COALESCE(p_limit,25),100));
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_set_current_rate(
  p_entity_type public.catalogue_billable_entity_enum,
  p_entity_id UUID,
  p_price_paisa BIGINT,
  p_expected_rate_id UUID DEFAULT NULL,
  p_expected_rate_version BIGINT DEFAULT NULL,
  p_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE current_rate public.catalogue_rate_versions%ROWTYPE; new_rate public.catalogue_rate_versions%ROWTYPE; next_version INT;
BEGIN
  PERFORM public.catalogue_require_manager();
  IF p_entity_type NOT IN ('Test','Panel','Package') OR p_entity_id IS NULL THEN RAISE EXCEPTION 'Unsupported catalogue rate entity.' USING ERRCODE='22023'; END IF;
  IF p_price_paisa IS NULL OR p_price_paisa<=0 THEN RAISE EXCEPTION 'A configured billing rate must be a positive integer number of paisa.' USING ERRCODE='23514'; END IF;
  IF btrim(COALESCE(p_reason,''))='' THEN RAISE EXCEPTION 'Rate-change reason is required.' USING ERRCODE='23514'; END IF;

  IF p_entity_type='Test' THEN PERFORM 1 FROM public.tests WHERE id=p_entity_id FOR UPDATE;
  ELSIF p_entity_type='Panel' THEN PERFORM 1 FROM public.catalogue_panel_services WHERE id=p_entity_id FOR UPDATE;
  ELSE PERFORM 1 FROM public.health_packages WHERE id=p_entity_id FOR UPDATE; END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'Catalogue entity not found.' USING ERRCODE='P0002'; END IF;

  SELECT * INTO current_rate FROM public.catalogue_rate_versions r
  WHERE (p_entity_type='Test' AND r.test_id=p_entity_id) OR (p_entity_type='Panel' AND r.panel_service_id=p_entity_id) OR (p_entity_type='Package' AND r.package_id=p_entity_id)
  ORDER BY (r.status='Active') DESC,r.version_number DESC LIMIT 1 FOR UPDATE;
  IF p_expected_rate_id IS DISTINCT FROM current_rate.id OR p_expected_rate_version IS DISTINCT FROM current_rate.row_version THEN
    RAISE EXCEPTION 'Rate changed. Refresh and review the latest value.' USING ERRCODE='PT409';
  END IF;
  IF current_rate.status='Active' AND current_rate.price_paisa=p_price_paisa THEN RAISE EXCEPTION 'New rate is unchanged.' USING ERRCODE='22023'; END IF;

  SELECT COALESCE(max(r.version_number),0)+1 INTO next_version FROM public.catalogue_rate_versions r
  WHERE (p_entity_type='Test' AND r.test_id=p_entity_id) OR (p_entity_type='Panel' AND r.panel_service_id=p_entity_id) OR (p_entity_type='Package' AND r.package_id=p_entity_id);
  UPDATE public.catalogue_rate_versions r SET status='Inactive',effective_to=COALESCE(effective_to,now()),row_version=row_version+1,updated_at=now()
  WHERE r.status='Active' AND ((p_entity_type='Test' AND r.test_id=p_entity_id) OR (p_entity_type='Panel' AND r.panel_service_id=p_entity_id) OR (p_entity_type='Package' AND r.package_id=p_entity_id));
  INSERT INTO public.catalogue_rate_versions(entity_type,test_id,panel_service_id,package_id,version_number,price_paisa,effective_from,status,created_by)
  VALUES(p_entity_type,CASE WHEN p_entity_type='Test' THEN p_entity_id END,CASE WHEN p_entity_type='Panel' THEN p_entity_id END,
    CASE WHEN p_entity_type='Package' THEN p_entity_id END,next_version,p_price_paisa,now(),'Active',auth.uid()) RETURNING * INTO new_rate;

  IF p_entity_type='Test' THEN UPDATE public.tests SET price_paisa=p_price_paisa,price_configured=TRUE,pricing_policy='Fixed',allow_manual_price=FALSE,allow_zero_price_billing=FALSE,row_version=row_version+1,updated_at=now() WHERE id=p_entity_id;
  ELSIF p_entity_type='Package' THEN UPDATE public.health_packages SET price_paisa=p_price_paisa,pricing_policy='Fixed',row_version=row_version+1,updated_at=now() WHERE id=p_entity_id;
  END IF;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data)
  VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_RATE_CHANGED',p_entity_type::TEXT,p_entity_id::TEXT,
    jsonb_build_object('rate_id',current_rate.id,'version_number',current_rate.version_number,'price_paisa',current_rate.price_paisa,'status',current_rate.status),
    jsonb_build_object('rate_id',new_rate.id,'version_number',new_rate.version_number,'price_paisa',new_rate.price_paisa,'status',new_rate.status,'reason',btrim(p_reason)));
  RETURN jsonb_build_object('rate_id',new_rate.id,'version_number',new_rate.version_number,'price_paisa',new_rate.price_paisa,'rate_row_version',new_rate.row_version);
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_bulk_set_current_rates(p_changes JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE change JSONB; result JSONB; results JSONB:='[]'::JSONB; seen TEXT[]:=ARRAY[]::TEXT[]; key TEXT;
BEGIN
  PERFORM public.catalogue_require_manager();
  IF jsonb_typeof(p_changes)<>'array' OR jsonb_array_length(p_changes)=0 OR jsonb_array_length(p_changes)>100 THEN RAISE EXCEPTION 'Provide between 1 and 100 reviewed rate changes.' USING ERRCODE='22023'; END IF;
  FOR change IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
    key:=(change->>'entity_type')||':'||(change->>'entity_id');
    IF key=ANY(seen) THEN RAISE EXCEPTION 'Duplicate entity in bulk rate review.' USING ERRCODE='22023'; END IF;
    seen:=array_append(seen,key);
    result:=public.catalogue_set_current_rate((change->>'entity_type')::public.catalogue_billable_entity_enum,(change->>'entity_id')::UUID,
      (change->>'price_paisa')::BIGINT,NULLIF(change->>'expected_rate_id','')::UUID,NULLIF(change->>'expected_rate_version','')::BIGINT,change->>'reason');
    results:=results||jsonb_build_array(result||jsonb_build_object('entity_type',change->>'entity_type','entity_id',change->>'entity_id'));
  END LOOP;
  RETURN jsonb_build_object('updated_count',jsonb_array_length(results),'changes',results);
END $$;

-- Safe delete must account for commercial grouping and all direct clinical/billing references.
CREATE OR REPLACE FUNCTION public.catalogue_delete_test(p_test_id UUID,p_expected_version BIGINT) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.tests%ROWTYPE;
BEGIN
  PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.tests WHERE id=p_test_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
  IF EXISTS(SELECT 1 FROM public.bill_items WHERE test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.clinical_order_items WHERE test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.test_results r JOIN public.parameters p ON p.id=r.parameter_id WHERE p.test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.health_package_components WHERE test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.catalogue_profile_components WHERE profile_test_id=p_test_id OR component_test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.catalogue_panel_components WHERE component_test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.bill_package_components WHERE test_id=p_test_id)
    OR EXISTS(SELECT 1 FROM public.bill_panel_components WHERE test_id=p_test_id)
  THEN RAISE EXCEPTION 'Referenced tests cannot be deleted. Archive this test.' USING ERRCODE='23503'; END IF;
  DELETE FROM public.catalogue_rate_versions WHERE test_id=p_test_id;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_TEST_DELETED','Test',p_test_id::TEXT,to_jsonb(v));
  DELETE FROM public.tests WHERE id=p_test_id;
END $$;

-- Commercial panel composition uses the same guarded full-catalogue authority.
CREATE OR REPLACE FUNCTION public.catalogue_save_panel_component(p_panel_id UUID,p_component_test_id UUID,p_component_parameter_id UUID,p_display_name TEXT,p_display_order INT,p_expected_panel_version BIGINT) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.catalogue_panels%ROWTYPE; old_components JSONB;
BEGIN
  PERFORM public.catalogue_require_manager(); SELECT * INTO p FROM public.catalogue_panels WHERE id=p_panel_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Panel not found.' USING ERRCODE='P0002'; END IF;
  IF p.row_version<>p_expected_panel_version THEN RAISE EXCEPTION 'Panel changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
  IF (p_component_test_id IS NOT NULL)::INT+(p_component_parameter_id IS NOT NULL)::INT<>1 THEN RAISE EXCEPTION 'Exactly one canonical component identity is required.' USING ERRCODE='23514'; END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.display_order),'[]') INTO old_components FROM public.catalogue_panel_components c WHERE c.panel_id=p_panel_id;
  INSERT INTO public.catalogue_panel_components(panel_id,component_test_id,component_parameter_id,display_name,display_order)
  VALUES(p_panel_id,p_component_test_id,p_component_parameter_id,btrim(p_display_name),p_display_order)
  ON CONFLICT(panel_id,display_order) DO UPDATE SET component_test_id=EXCLUDED.component_test_id,component_parameter_id=EXCLUDED.component_parameter_id,display_name=EXCLUDED.display_name;
  UPDATE public.catalogue_panels SET row_version=row_version+1,updated_at=now() WHERE id=p_panel_id;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PANEL_MEMBERSHIP_CHANGED','Panel',p_panel_id::TEXT,old_components,(SELECT jsonb_agg(to_jsonb(c) ORDER BY c.display_order) FROM public.catalogue_panel_components c WHERE c.panel_id=p_panel_id));
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_remove_panel_component(p_panel_id UUID,p_display_order INT,p_expected_panel_version BIGINT) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.catalogue_panels%ROWTYPE; old_components JSONB;
BEGIN
  PERFORM public.catalogue_require_manager(); SELECT * INTO p FROM public.catalogue_panels WHERE id=p_panel_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Panel not found.' USING ERRCODE='P0002'; END IF;
  IF p.row_version<>p_expected_panel_version THEN RAISE EXCEPTION 'Panel changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
  IF EXISTS(SELECT 1 FROM public.bill_panel_selections WHERE panel_id=p_panel_id) THEN RAISE EXCEPTION 'Historically billed panel composition cannot be changed; archive it and create a new definition.' USING ERRCODE='23503'; END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.display_order),'[]') INTO old_components FROM public.catalogue_panel_components c WHERE c.panel_id=p_panel_id;
  DELETE FROM public.catalogue_panel_components WHERE panel_id=p_panel_id AND display_order=p_display_order;
  UPDATE public.catalogue_panels SET row_version=row_version+1,updated_at=now() WHERE id=p_panel_id;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PANEL_MEMBER_REMOVED','Panel',p_panel_id::TEXT,old_components,(SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.display_order),'[]') FROM public.catalogue_panel_components c WHERE c.panel_id=p_panel_id));
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_reorder_panel_components(p_panel_id UUID,p_component_ids UUID[],p_expected_panel_version BIGINT) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.catalogue_panels%ROWTYPE; old_components JSONB;
BEGIN
  PERFORM public.catalogue_require_manager(); SELECT * INTO p FROM public.catalogue_panels WHERE id=p_panel_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Panel not found.' USING ERRCODE='P0002'; END IF;
  IF p.row_version<>p_expected_panel_version THEN RAISE EXCEPTION 'Panel changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
  IF cardinality(p_component_ids)<>(SELECT count(*) FROM public.catalogue_panel_components WHERE panel_id=p_panel_id)
    OR EXISTS(SELECT 1 FROM unnest(p_component_ids) id LEFT JOIN public.catalogue_panel_components c ON c.panel_id=p_panel_id AND COALESCE(c.component_test_id,c.component_parameter_id)=id WHERE c.panel_id IS NULL)
  THEN RAISE EXCEPTION 'Complete canonical component order is required.' USING ERRCODE='23514'; END IF;
  SELECT jsonb_agg(to_jsonb(c) ORDER BY c.display_order) INTO old_components FROM public.catalogue_panel_components c WHERE c.panel_id=p_panel_id;
  UPDATE public.catalogue_panel_components SET display_order=display_order+10000 WHERE panel_id=p_panel_id;
  UPDATE public.catalogue_panel_components c SET display_order=x.ord FROM unnest(p_component_ids) WITH ORDINALITY x(id,ord) WHERE c.panel_id=p_panel_id AND COALESCE(c.component_test_id,c.component_parameter_id)=x.id;
  UPDATE public.catalogue_panels SET row_version=row_version+1,updated_at=now() WHERE id=p_panel_id;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PANEL_REORDERED','Panel',p_panel_id::TEXT,old_components,(SELECT jsonb_agg(to_jsonb(c) ORDER BY c.display_order) FROM public.catalogue_panel_components c WHERE c.panel_id=p_panel_id));
END $$;

REVOKE ALL ON FUNCTION public.catalogue_search_rate_list(TEXT,UUID,public.catalogue_lifecycle_enum,BOOLEAN,public.catalogue_billable_entity_enum,TEXT,BOOLEAN,INT,INT) FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION public.catalogue_set_current_rate(public.catalogue_billable_entity_enum,UUID,BIGINT,UUID,BIGINT,TEXT) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.catalogue_bulk_set_current_rates(JSONB) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.catalogue_delete_test(UUID,BIGINT) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.catalogue_save_panel_component(UUID,UUID,UUID,TEXT,INT,BIGINT) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.catalogue_remove_panel_component(UUID,INT,BIGINT) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.catalogue_reorder_panel_components(UUID,UUID[],BIGINT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.catalogue_search_rate_list(TEXT,UUID,public.catalogue_lifecycle_enum,BOOLEAN,public.catalogue_billable_entity_enum,TEXT,BOOLEAN,INT,INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_set_current_rate(public.catalogue_billable_entity_enum,UUID,BIGINT,UUID,BIGINT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_bulk_set_current_rates(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_delete_test(UUID,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_save_panel_component(UUID,UUID,UUID,TEXT,INT,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_remove_panel_component(UUID,INT,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_reorder_panel_components(UUID,UUID[],BIGINT) TO authenticated;

-- ============================================================================
-- Final operational authorization model: Super Admin bypass + one assignable
-- Lab Technician role. Compatibility role rows and historical memberships stay
-- intact, but only Lab Technician memberships contribute normal permissions.
-- ============================================================================
DO $final_operator_permissions$
DECLARE
  technician_role CONSTANT UUID:='00000000-0000-0000-0000-000000000004';
  operational_permissions CONSTANT TEXT[]:=ARRAY[
    'can_view_dashboard','can_create_bill','can_edit_patient','can_collect_sample','can_receive_sample','can_reject_sample',
    'can_enter_results','can_verify_results','can_acknowledge_critical','can_sign_reports','can_amend_reports','can_print_reports',
    'can_manage_catalogue','can_configure_catalogue_technical','can_manage_ast_breakpoints','can_manage_referring_doctors',
    'can_manage_personnel','can_view_financials','can_view_audit_logs','can_manage_outsource_tracking','can_view_hmis_reports',
    'can_edit_hmis_reports','can_finalize_hmis_reports'
  ];
  old_permissions TEXT[];
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.roles WHERE id=technician_role AND code='lab_technician') THEN
    RAISE EXCEPTION 'Canonical Lab Technician role is missing.' USING ERRCODE='23514';
  END IF;
  SELECT COALESCE(array_agg(permission_key ORDER BY permission_key),ARRAY[]::TEXT[]) INTO old_permissions FROM public.role_permissions WHERE role_id=technician_role;
  DELETE FROM public.role_permissions WHERE role_id=technician_role;
  INSERT INTO public.role_permissions(role_id,permission_key) SELECT technician_role,p FROM unnest(operational_permissions)p;

  -- Preserve compatibility memberships, but ensure existing active human users
  -- relying on a former operational role continue through the canonical role.
  INSERT INTO public.user_roles(user_id,role_id)
  SELECT DISTINCT ur.user_id,technician_role FROM public.user_roles ur JOIN public.roles legacy ON legacy.id=ur.role_id
  JOIN public.user_profiles up ON up.id=ur.user_id AND up.is_active AND NOT up.is_super_admin
  WHERE legacy.code IN('admin','verifier','signatory') ON CONFLICT DO NOTHING;

  UPDATE public.roles SET description=CASE code
    WHEN 'admin' THEN 'Compatibility-only historical role. Normal operational assignment is disabled; Super Admin is a server-side owner flag.'
    WHEN 'verifier' THEN 'Compatibility-only historical role. Normal assignment is disabled.'
    WHEN 'signatory' THEN 'Compatibility-only historical role. Normal assignment is disabled.'
    ELSE description END
  WHERE code IN('admin','verifier','signatory');
  UPDATE public.roles SET description='System-defined operational laboratory role for all day-to-day LIS workflows.' WHERE id=technician_role;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data)
  VALUES(NULL,'Database migration 00087','FINAL_LAB_OPERATOR_MODEL_APPLIED','Role','lab_technician',
    jsonb_build_object('permissions',old_permissions),jsonb_build_object('permissions',operational_permissions,'assignable_roles',jsonb_build_array('lab_technician')));
END $final_operator_permissions$;

CREATE OR REPLACE FUNCTION public.has_permission(p_permission_key VARCHAR) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
DECLARE direct_value BOOLEAN;
BEGIN
  IF NOT public.is_active_user() THEN RETURN FALSE; END IF;
  IF public.is_super_admin() THEN RETURN TRUE; END IF;
  SELECT is_granted INTO direct_value FROM public.user_direct_permissions WHERE user_id=auth.uid() AND permission_key=p_permission_key;
  IF direct_value IS NOT NULL THEN RETURN direct_value; END IF;
  RETURN EXISTS(
    SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
    JOIN public.role_permissions rp ON rp.role_id=r.id
    WHERE ur.user_id=auth.uid() AND r.code='lab_technician' AND rp.permission_key=p_permission_key
  );
END $$;

CREATE OR REPLACE FUNCTION public.update_user_access(p_user_id UUID,p_is_active BOOLEAN,p_is_super_admin BOOLEAN,p_role_ids UUID[] DEFAULT ARRAY[]::UUID[])
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE target public.user_profiles%ROWTYPE; role_count INT; technician_role CONSTANT UUID:='00000000-0000-0000-0000-000000000004';
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() OR NOT public.is_active_user() THEN RAISE EXCEPTION 'System Owner authority is required.' USING ERRCODE='42501'; END IF;
  SELECT * INTO target FROM public.user_profiles WHERE id=p_user_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'User account was not found.' USING ERRCODE='P0002'; END IF;
  IF p_user_id=auth.uid() AND NOT p_is_active THEN RAISE EXCEPTION 'You cannot deactivate your own account.' USING ERRCODE='22023'; END IF;
  IF target.is_super_admin AND (NOT p_is_active OR NOT p_is_super_admin) AND NOT EXISTS(SELECT 1 FROM public.user_profiles u WHERE u.id<>p_user_id AND u.is_active AND u.is_super_admin) THEN RAISE EXCEPTION 'At least one active Super Admin is required.' USING ERRCODE='23514'; END IF;
  SELECT count(*) INTO role_count FROM unnest(COALESCE(p_role_ids,ARRAY[]::UUID[])) r(id);
  IF role_count>1 OR (role_count=1 AND p_role_ids[1]<>technician_role) THEN RAISE EXCEPTION 'Lab Technician is the only normally assignable role.' USING ERRCODE='22023'; END IF;
  UPDATE public.user_profiles SET is_active=p_is_active,is_super_admin=p_is_super_admin,updated_at=now() WHERE id=p_user_id;
  DELETE FROM public.user_roles WHERE user_id=p_user_id AND role_id=technician_role;
  IF role_count=1 THEN INSERT INTO public.user_roles(user_id,role_id) VALUES(p_user_id,technician_role) ON CONFLICT DO NOTHING; END IF;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'USER_ACCESS_UPDATED','UserProfile',p_user_id::TEXT,jsonb_build_object('changed_fields',jsonb_build_array('is_active','is_super_admin','lab_technician_assignment'),'lab_technician_assigned',role_count=1));
  RETURN jsonb_build_object('success',TRUE,'user_id',p_user_id);
END $$;

CREATE OR REPLACE FUNCTION public.replace_role_permission_matrix(p_matrix JSONB) RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() OR NOT public.is_active_user() THEN RAISE EXCEPTION 'System Owner authority is required.' USING ERRCODE='42501'; END IF;
  RAISE EXCEPTION 'The Lab Technician operational capability set is system-defined and cannot be edited as a role matrix.' USING ERRCODE='0A000';
END $$;

COMMENT ON TABLE public.roles IS 'Lab Technician is the only normal assignable role. Administrator, Verifier and Signatory rows are retained for historical compatibility. Super Admin is the user_profiles.is_super_admin server-side owner bypass.';

-- Billing stores the suggested catalogue rate separately from the immutable
-- agreed amount already stored in unit_price_paisa/net_price_paisa snapshots.
ALTER TABLE public.bill_items ADD COLUMN catalogue_price_paisa_snapshot BIGINT CHECK(catalogue_price_paisa_snapshot IS NULL OR catalogue_price_paisa_snapshot>=0);
ALTER TABLE public.bill_package_selections ADD COLUMN catalogue_package_price_paisa BIGINT CHECK(catalogue_package_price_paisa IS NULL OR catalogue_package_price_paisa>=0);
ALTER TABLE public.bill_panel_selections ADD COLUMN catalogue_panel_price_paisa BIGINT CHECK(catalogue_panel_price_paisa IS NULL OR catalogue_panel_price_paisa>=0);

-- Replace the package-aware browser boundary: every positive submitted rate is
-- an authorized agreed rate. Catalogue prices are suggestions, never overrides.
CREATE OR REPLACE FUNCTION public.create_patient_bill_order_with_packages(p_patient_data JSONB,p_bill_data JSONB,p_items_data JSONB[],p_payment_data JSONB,p_idempotency_key TEXT,p_packages JSONB DEFAULT '[]') RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE response JSONB; bill_uuid UUID; pkg JSONB; component UUID; selection_uuid UUID; expected_ids UUID[]; supplied_ids UUID[]:=ARRAY(SELECT DISTINCT (x->>'test_id')::UUID FROM unnest(p_items_data)x); package_seen UUID[]:=ARRAY[]::UUID[]; manual_ids UUID[]:=ARRAY[]::UUID[]; package_row public.health_packages%ROWTYPE; agreed_price BIGINT; component_sum BIGINT;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF cardinality(p_items_data)<>cardinality(supplied_ids) THEN RAISE EXCEPTION 'A canonical service may be selected only once.' USING ERRCODE='23505'; END IF;
  IF EXISTS(SELECT 1 FROM unnest(p_items_data)i LEFT JOIN public.tests t ON t.id=(i->>'test_id')::UUID WHERE t.id IS NULL OR t.lifecycle_status<>'Active' OR NOT t.is_active OR NOT t.billing_enabled) THEN RAISE EXCEPTION 'Only active, billing-enabled catalogue services may be billed.' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM unnest(p_items_data)i WHERE (i->>'unit_price_paisa') IS NULL OR (i->>'unit_price_paisa')::BIGINT<0) THEN RAISE EXCEPTION 'Every item requires a valid agreed rate.' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM unnest(p_items_data)i JOIN public.tests t ON t.id=(i->>'test_id')::UUID WHERE (i->>'unit_price_paisa')::BIGINT=0 AND (NOT t.allow_zero_price_billing OR NOT COALESCE((i->>'zero_price_acknowledged')::BOOLEAN,FALSE))) THEN RAISE EXCEPTION 'Zero-price billing requires explicit catalogue authorization and acknowledgement.' USING ERRCODE='23514'; END IF;
  FOR pkg IN SELECT value FROM jsonb_array_elements(COALESCE(p_packages,'[]')) LOOP
    SELECT * INTO package_row FROM public.health_packages WHERE id=(pkg->>'package_id')::UUID AND lifecycle_status='Active' FOR SHARE; IF NOT FOUND THEN RAISE EXCEPTION 'Only active packages may be billed.' USING ERRCODE='23514'; END IF;
    SELECT array_agg(c.test_id ORDER BY c.display_order) INTO expected_ids FROM public.health_package_components c JOIN public.tests t ON t.id=c.test_id WHERE c.package_id=package_row.id AND t.lifecycle_status='Active' AND t.is_active AND t.billing_enabled;
    IF expected_ids IS NULL OR expected_ids<>ARRAY(SELECT x::UUID FROM jsonb_array_elements_text(pkg->'component_ids')x) THEN RAISE EXCEPTION 'Package definition changed. Refresh billing catalogue.' USING ERRCODE='PT409'; END IF;
    agreed_price:=(pkg->>'agreed_price_paisa')::BIGINT; IF agreed_price<=0 THEN RAISE EXCEPTION 'A package requires a positive agreed price.' USING ERRCODE='23514'; END IF;
    FOREACH component IN ARRAY expected_ids LOOP IF component=ANY(package_seen) OR NOT component=ANY(supplied_ids) THEN RAISE EXCEPTION 'Package components are duplicated or missing.' USING ERRCODE='23514'; END IF; package_seen:=array_append(package_seen,component); END LOOP;
    SELECT COALESCE(sum((i->>'unit_price_paisa')::BIGINT),0) INTO component_sum FROM unnest(p_items_data)i WHERE (i->>'test_id')::UUID=ANY(expected_ids); IF component_sum<>agreed_price THEN RAISE EXCEPTION 'Package component prices must equal the agreed package price.' USING ERRCODE='23514'; END IF;
  END LOOP;
  PERFORM 1 FROM public.tests t WHERE t.id=ANY(supplied_ids) ORDER BY t.id FOR UPDATE;
  SELECT COALESCE(array_agg(id ORDER BY id),ARRAY[]::UUID[]) INTO manual_ids FROM public.tests WHERE id=ANY(supplied_ids) AND NOT allow_manual_price;
  UPDATE public.tests SET allow_manual_price=TRUE WHERE id=ANY(manual_ids);
  response:=public.create_patient_bill_and_order(p_patient_data,p_bill_data,p_items_data,p_payment_data,p_idempotency_key); bill_uuid:=(response->>'bill_id')::UUID;
  UPDATE public.bill_items bi SET catalogue_price_paisa_snapshot=t.price_paisa FROM public.tests t WHERE bi.bill_id=bill_uuid AND bi.test_id=t.id;
  UPDATE public.tests SET allow_manual_price=FALSE WHERE id=ANY(manual_ids);
  FOR pkg IN SELECT value FROM jsonb_array_elements(COALESCE(p_packages,'[]')) LOOP
    INSERT INTO public.bill_package_selections(bill_id,package_id,package_code_snapshot,package_name_snapshot,package_price_paisa,catalogue_package_price_paisa)
    SELECT bill_uuid,p.id,p.code,p.name,(pkg->>'agreed_price_paisa')::BIGINT,p.price_paisa FROM public.health_packages p WHERE p.id=(pkg->>'package_id')::UUID
    ON CONFLICT(bill_id,package_id) DO NOTHING RETURNING id INTO selection_uuid;
    IF selection_uuid IS NOT NULL THEN INSERT INTO public.bill_package_components(bill_package_selection_id,bill_item_id,test_id) SELECT selection_uuid,bi.id,bi.test_id FROM public.bill_items bi WHERE bi.bill_id=bill_uuid AND bi.test_id=ANY(ARRAY(SELECT x::UUID FROM jsonb_array_elements_text(pkg->'component_ids')x)); END IF;
  END LOOP;
  RETURN response||jsonb_build_object('packages_recorded',jsonb_array_length(COALESCE(p_packages,'[]')));
END $$;

CREATE OR REPLACE FUNCTION public.create_patient_bill_order_with_panel_service(p_patient_data JSONB,p_bill_data JSONB,p_payment_data JSONB,p_idempotency_key TEXT,p_panel_service_id UUID,p_expected_panel_version BIGINT,p_agreed_panel_price_paisa BIGINT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE svc public.catalogue_panel_services%ROWTYPE; pnl public.catalogue_panels%ROWTYPE; rate public.catalogue_rate_versions%ROWTYPE; items JSONB[]; response JSONB; bill_uuid UUID; selection_uuid UUID; component_snapshot JSONB; component_ids UUID[]; manual_ids UUID[]:=ARRAY[]::UUID[];
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
  IF p_agreed_panel_price_paisa IS NULL OR p_agreed_panel_price_paisa<=0 THEN RAISE EXCEPTION 'A panel requires a positive agreed price.' USING ERRCODE='23514'; END IF;
  SELECT * INTO svc FROM public.catalogue_panel_services WHERE id=p_panel_service_id AND lifecycle_status='Active' FOR SHARE; IF NOT FOUND THEN RAISE EXCEPTION 'Panel service is inactive or missing.' USING ERRCODE='23503'; END IF;
  SELECT * INTO pnl FROM public.catalogue_panels WHERE id=svc.panel_id AND lifecycle_status='Active' FOR SHARE; IF pnl.row_version<>p_expected_panel_version THEN RAISE EXCEPTION 'Panel definition changed. Refresh billing catalogue.' USING ERRCODE='PT409'; END IF;
  SELECT * INTO rate FROM public.catalogue_rate_versions WHERE panel_service_id=svc.id AND status='Active' AND price_paisa IS NOT NULL AND COALESCE(effective_from,now())<=now() AND(effective_to IS NULL OR effective_to>now()) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'A panel catalogue default must be active before billing.' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM public.catalogue_panel_service_components(svc.id)c WHERE c.readiness<>'Ready') THEN RAISE EXCEPTION 'Result Structure Incomplete. Configure the panel before billing.' USING ERRCODE='23514'; END IF;
  SELECT array_agg(jsonb_build_object('test_id',c.test_id,'unit_price_paisa',CASE WHEN c.display_order=x.min_ord THEN p_agreed_panel_price_paisa ELSE 0 END,'manual_price_paisa',CASE WHEN c.display_order=x.min_ord THEN p_agreed_panel_price_paisa ELSE 0 END,'discount_paisa',0,'zero_price_acknowledged',TRUE) ORDER BY c.display_order),
    jsonb_agg(jsonb_build_object('test_id',c.test_id,'test_code',c.test_code,'test_name',c.test_name,'display_order',c.display_order) ORDER BY c.display_order),array_agg(c.test_id ORDER BY c.test_id)
  INTO items,component_snapshot,component_ids FROM public.catalogue_panel_service_components(svc.id)c CROSS JOIN(SELECT min(display_order)min_ord FROM public.catalogue_panel_service_components(svc.id))x;
  IF items IS NULL THEN RAISE EXCEPTION 'Panel has no canonical component tests.' USING ERRCODE='23514'; END IF;
  PERFORM 1 FROM public.tests WHERE id=ANY(component_ids) ORDER BY id FOR UPDATE;
  SELECT COALESCE(array_agg(id ORDER BY id),ARRAY[]::UUID[]) INTO manual_ids FROM public.tests WHERE id=ANY(component_ids) AND NOT allow_manual_price;
  UPDATE public.tests SET allow_manual_price=TRUE WHERE id=ANY(manual_ids);
  response:=public.create_patient_bill_and_order(p_patient_data,p_bill_data,items,p_payment_data,p_idempotency_key); bill_uuid:=(response->>'bill_id')::UUID;
  UPDATE public.bill_items bi SET catalogue_price_paisa_snapshot=t.price_paisa FROM public.tests t WHERE bi.bill_id=bill_uuid AND bi.test_id=t.id;
  UPDATE public.tests SET allow_manual_price=FALSE WHERE id=ANY(manual_ids);
  INSERT INTO public.bill_panel_selections(bill_id,panel_service_id,panel_id,service_code_snapshot,panel_name_snapshot,panel_price_paisa,catalogue_panel_price_paisa,rate_version_id,component_snapshot)
  VALUES(bill_uuid,svc.id,pnl.id,svc.code,pnl.name,p_agreed_panel_price_paisa,rate.price_paisa,rate.id,component_snapshot)
  ON CONFLICT(bill_id,panel_service_id) DO NOTHING RETURNING id INTO selection_uuid;
  IF selection_uuid IS NULL THEN SELECT id INTO selection_uuid FROM public.bill_panel_selections WHERE bill_id=bill_uuid AND panel_service_id=svc.id; ELSE
    INSERT INTO public.bill_panel_components(bill_panel_selection_id,bill_item_id,test_id,display_order) SELECT selection_uuid,bi.id,bi.test_id,(x->>'display_order')::INT FROM jsonb_array_elements(component_snapshot)x JOIN public.bill_items bi ON bi.bill_id=bill_uuid AND bi.test_id=(x->>'test_id')::UUID;
  END IF;
  RETURN response||jsonb_build_object('panel_selection_id',selection_uuid,'panel_service_id',svc.id,'rate_version_id',rate.id);
END $$;

REVOKE ALL ON FUNCTION public.create_patient_bill_order_with_panel_service(JSONB,JSONB,JSONB,TEXT,UUID,BIGINT) FROM authenticated;
REVOKE ALL ON FUNCTION public.create_patient_bill_order_with_panel_service(JSONB,JSONB,JSONB,TEXT,UUID,BIGINT,BIGINT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_order_with_panel_service(JSONB,JSONB,JSONB,TEXT,UUID,BIGINT,BIGINT) TO authenticated;
REVOKE ALL ON FUNCTION public.create_patient_bill_order_with_packages(JSONB,JSONB,JSONB[],JSONB,TEXT,JSONB) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_order_with_packages(JSONB,JSONB,JSONB[],JSONB,TEXT,JSONB) TO authenticated;
