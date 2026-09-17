\set ON_ERROR_STOP on
DO $$
DECLARE v_tables INT; v_rls INT; v_bad_paths INT; v_tech TEXT[]; v_admin TEXT[];
BEGIN
 SELECT count(*) FILTER(WHERE c.relkind IN('r','p')),count(*) FILTER(WHERE c.relkind IN('r','p') AND c.relrowsecurity)
 INTO v_tables,v_rls FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public';
 IF v_tables<>v_rls THEN RAISE EXCEPTION 'Not every public table has RLS: %/%',v_rls,v_tables; END IF;
 SELECT count(*) INTO v_bad_paths FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.prosecdef AND NOT EXISTS(SELECT 1 FROM unnest(COALESCE(p.proconfig,ARRAY[]::TEXT[])) x WHERE x LIKE 'search_path=%pg_temp%');
 IF v_bad_paths<>0 THEN RAISE EXCEPTION '% SECURITY DEFINER functions lack a fixed pg_temp search_path',v_bad_paths; END IF;
 IF NOT has_table_privilege('authenticated','public.catalogue_test_operational_state','SELECT')
    OR has_table_privilege('anon','public.catalogue_test_operational_state','SELECT') THEN RAISE EXCEPTION 'Operational-state view ACL mismatch'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='catalogue_test_operational_state' AND 'security_invoker=true'=ANY(COALESCE(c.reloptions,ARRAY[]::TEXT[]))) THEN RAISE EXCEPTION 'Operational-state view is not security_invoker'; END IF;
 SELECT array_agg(permission_key ORDER BY permission_key) INTO v_admin FROM public.role_permissions WHERE role_id='00000000-0000-0000-0000-000000000001';
 SELECT array_agg(permission_key ORDER BY permission_key) INTO v_tech FROM public.role_permissions WHERE role_id='00000000-0000-0000-0000-000000000004';
 IF cardinality(v_admin)<>25 OR cardinality(v_tech)<>14 THEN RAISE EXCEPTION 'Canonical matrix count mismatch admin=% technician=%',cardinality(v_admin),cardinality(v_tech); END IF;
END $$;

SELECT c.relname,c.relkind,c.relrowsecurity,
 has_table_privilege('authenticated',c.oid,'SELECT') authenticated_select,
 has_table_privilege('anon',c.oid,'SELECT') anon_select
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind IN('r','p','v') ORDER BY c.relkind,c.relname;
SELECT tablename,policyname,cmd,roles,qual,with_check FROM pg_policies WHERE schemaname='public' ORDER BY tablename,policyname;
SELECT p.proname,pg_get_function_identity_arguments(p.oid) arguments,
 CASE WHEN p.prosecdef THEN 'DEFINER' ELSE 'INVOKER' END security_mode,
 pg_get_userbyid(p.proowner) owner,p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' ORDER BY p.proname,arguments;
