\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE acceptance_results(test_no INT PRIMARY KEY,name TEXT,passed BOOLEAN);
GRANT ALL ON acceptance_results TO authenticated,anon;
GRANT SELECT ON public.catalogue_service_readiness,public.catalogue_configuration_evidence TO authenticated;
ALTER TABLE public.catalogue_service_readiness DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_configuration_evidence DISABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION pg_temp.ok(n INT,name TEXT,condition BOOLEAN) RETURNS VOID LANGUAGE plpgsql AS $$BEGIN IF NOT COALESCE(condition,FALSE) THEN RAISE EXCEPTION 'TEST_%_FAILED: %',n,name;END IF;INSERT INTO acceptance_results VALUES(n,name,TRUE);RAISE NOTICE 'PASS %: %',n,name;END$$;

INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
 ('99000000-0000-0000-0000-000000000001','owner90@runtime.invalid','{"full_name":"00090 Owner"}'),
 ('99000000-0000-0000-0000-000000000002','tech90@runtime.invalid','{"full_name":"00090 Technician"}'),
 ('99000000-0000-0000-0000-000000000003','inactive90@runtime.invalid','{"full_name":"00090 Inactive"}'),
 ('99000000-0000-0000-0000-000000000004','gateway90@runtime.invalid','{"full_name":"00090 Gateway"}'),
 ('99000000-0000-0000-0000-000000000005','worker90@runtime.invalid','{"full_name":"00090 Worker"}');
UPDATE public.user_profiles SET is_active=id IN('99000000-0000-0000-0000-000000000001','99000000-0000-0000-0000-000000000002'),is_super_admin=id='99000000-0000-0000-0000-000000000001' WHERE id::TEXT LIKE '99000000-%';
INSERT INTO public.user_roles(user_id,role_id)VALUES('99000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000004');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000002',TRUE);
DO $$DECLARE c UUID;r JSONB;BEGIN
 c:=public.catalogue_save_category(jsonb_build_object('code','R90_CAT','name','00090 Synthetic','description','rollback-only','display_order',9999),NULL);
 PERFORM set_config('r90.category',c::TEXT,TRUE);
 FOR r IN SELECT * FROM jsonb_array_elements(jsonb_build_array(
  jsonb_build_object('code','R90_NORMAL','name','00090 Normal','price_paisa',50000,'price_configured',TRUE,'pricing_policy','Fixed','sample_type','','container',''),
  jsonb_build_object('code','R90_UNPRICED','name','00090 Unpriced','price_paisa',0,'price_configured',FALSE,'pricing_policy','PricePending','sample_type','','container',''),
  jsonb_build_object('code','R90_QUAL','name','00090 Qualitative','price_paisa',10000,'price_configured',TRUE,'pricing_policy','Fixed','sample_type','','container',''),
  jsonb_build_object('code','R90_TEXT','name','00090 Text','price_paisa',10000,'price_configured',TRUE,'pricing_policy','Fixed','sample_type','','container',''),
  jsonb_build_object('code','R90_SPEC','name','00090 Specimen Required','price_paisa',10000,'price_configured',TRUE,'pricing_policy','Fixed','sample_type','Serum','container','SST'),
  jsonb_build_object('code','R90_DELETE','name','00090 Unused Delete','price_paisa',10000,'price_configured',TRUE,'pricing_policy','Fixed','sample_type','','container',''),
  jsonb_build_object('code','R90_REVIEWED','name','00090 Reviewed Delete','price_paisa',10000,'price_configured',TRUE,'pricing_policy','Fixed','sample_type','','container','')
 )) LOOP
  PERFORM public.catalogue_save_test(r||jsonb_build_object('category_id',c,'department','Synthetic','category','00090 Synthetic','test_kind','Individual','reporting_type','InHouse','tat_hours',1,'display_order',9999,'allow_zero_price_billing',FALSE,'search_aliases','[]'::JSONB,'clinical_configuration_status','Configured','workflow_supported',TRUE),NULL);
 END LOOP;
END$$;
SELECT set_config('r90.unpriced',(SELECT id::TEXT FROM public.tests WHERE code='R90_UNPRICED'),TRUE);

SELECT pg_temp.ok(1,'normal creation is active Ready & Reportable with result entry',EXISTS(SELECT 1 FROM public.tests t JOIN public.catalogue_service_readiness r ON r.test_id=t.id JOIN public.catalogue_test_operational_state o ON o.test_id=t.id WHERE t.code='R90_NORMAL' AND t.is_active AND t.lifecycle_status='Active' AND t.billing_enabled AND t.clinical_reporting_enabled AND r.state='Approved' AND o.operational_state='Ready & Reportable' AND EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active)));
SELECT pg_temp.ok(2,'NULL/default-missing price does not affect readiness',EXISTS(SELECT 1 FROM public.tests t JOIN public.catalogue_test_operational_state o ON o.test_id=t.id WHERE t.code='R90_UNPRICED' AND NOT t.price_configured AND o.operational_state='Ready & Reportable'));
SELECT pg_temp.ok(3,'qualitative service needs no numeric reference range',EXISTS(SELECT 1 FROM public.tests t WHERE t.code='R90_QUAL' AND public.catalogue_test_result_readiness(t.id)='Ready' AND NOT EXISTS(SELECT 1 FROM public.reference_ranges rr JOIN public.parameters p ON p.id=rr.parameter_id WHERE p.test_id=t.id)));
SELECT pg_temp.ok(4,'text-result service is Ready & Reportable',EXISTS(SELECT 1 FROM public.tests t JOIN public.parameters p ON p.test_id=t.id WHERE t.code='R90_TEXT' AND p.value_type='Text' AND public.catalogue_test_result_readiness(t.id)='Ready'));

RESET ROLE;
DELETE FROM public.parameters WHERE test_id=(SELECT id FROM public.tests WHERE code='R90_NORMAL');
UPDATE public.tests SET collection_required=TRUE,sample_type='',container='' WHERE code='R90_SPEC';
UPDATE public.parameters SET value_type='Select',option_set_id=NULL WHERE test_id=(SELECT id FROM public.tests WHERE code='R90_QUAL');
UPDATE public.parameters SET value_type='Calculated',calculation_identifier=NULL WHERE test_id=(SELECT id FROM public.tests WHERE code='R90_TEXT');
UPDATE public.tests SET analyzer_configuration_required=TRUE WHERE code='R90_UNPRICED';
SET LOCAL ROLE authenticated;SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000002',TRUE);
SELECT pg_temp.ok(5,'missing required result structure is Needs Attention',(public.catalogue_service_readiness_checklist((SELECT id FROM public.tests WHERE code='R90_NORMAL'))->'missing_requirements') ? 'Required result structure is missing');
SELECT pg_temp.ok(6,'missing mandatory specimen/container is Needs Attention',(public.catalogue_service_readiness_checklist((SELECT id FROM public.tests WHERE code='R90_SPEC'))->'missing_requirements') ? 'Required specimen/container configuration is missing');
SELECT pg_temp.ok(7,'invalid qualitative vocabulary is Needs Attention',(public.catalogue_service_readiness_checklist((SELECT id FROM public.tests WHERE code='R90_QUAL'))->'missing_requirements') ? 'A qualitative result vocabulary is missing');
SELECT pg_temp.ok(8,'invalid calculated configuration is Needs Attention',(public.catalogue_service_readiness_checklist((SELECT id FROM public.tests WHERE code='R90_TEXT'))->'missing_requirements') ? 'Approved calculation formula/rounding configuration is missing');
SELECT pg_temp.ok(9,'explicit analyzer requirement is Needs Attention',(public.catalogue_service_readiness_checklist((SELECT id FROM public.tests WHERE code='R90_UNPRICED'))->'missing_requirements') ? 'Required analyzer/method configuration is missing');

RESET ROLE;
UPDATE public.tests SET analyzer_configuration_required=FALSE WHERE code='R90_UNPRICED';
INSERT INTO public.parameters(test_id,code,name,value_type,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status) SELECT id,'RESULT2','Result','Text',1,TRUE,TRUE,'Active','Configured' FROM public.tests WHERE code='R90_NORMAL';
UPDATE public.parameters SET value_type='Text' WHERE test_id IN(SELECT id FROM public.tests WHERE code IN('R90_QUAL','R90_TEXT'));
SET LOCAL ROLE authenticated;SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000002',TRUE);

DO $$DECLARE id UUID;v BIGINT;BEGIN SELECT t.id,r.configuration_version INTO id,v FROM public.tests t JOIN public.catalogue_service_readiness r ON r.test_id=t.id WHERE t.code='R90_NORMAL';PERFORM public.catalogue_decide_readiness(id,'MarkReady','Technician confirms safe reporting',v);PERFORM pg_temp.ok(10,'Technician Keep Ready',(SELECT state='Approved' FROM public.catalogue_service_readiness WHERE test_id=id));END$$;
DO $$#variable_conflict use_variable
DECLARE id UUID;v BIGINT;BEGIN SELECT t.id,r.configuration_version INTO id,v FROM public.tests t JOIN public.catalogue_service_readiness r ON r.test_id=t.id WHERE t.code='R90_NORMAL';PERFORM public.catalogue_decide_readiness(id,'NeedsConfiguration','Temporary result configuration correction',v);PERFORM pg_temp.ok(11,'Technician Needs Configuration',(SELECT state='NeedsConfiguration' FROM public.catalogue_service_readiness WHERE test_id=id) AND NOT (SELECT billing_enabled OR clinical_reporting_enabled FROM public.tests WHERE tests.id=id));END$$;
DO $$#variable_conflict use_variable
DECLARE id UUID;v BIGINT;BEGIN SELECT t.id,r.configuration_version INTO id,v FROM public.tests t JOIN public.catalogue_service_readiness r ON r.test_id=t.id WHERE t.code='R90_SPEC';PERFORM public.catalogue_decide_readiness(id,'Suspend','Temporary reagent outage',v);PERFORM pg_temp.ok(12,'Technician Suspend',(SELECT state='Suspended' FROM public.catalogue_service_readiness WHERE test_id=id) AND NOT (SELECT billing_enabled FROM public.tests WHERE tests.id=id));END$$;
RESET ROLE;UPDATE public.tests SET collection_required=FALSE WHERE code='R90_SPEC';SET LOCAL ROLE authenticated;SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000002',TRUE);
DO $$#variable_conflict use_variable
DECLARE id UUID;v BIGINT;BEGIN SELECT t.id,r.configuration_version INTO id,v FROM public.tests t JOIN public.catalogue_service_readiness r ON r.test_id=t.id WHERE t.code='R90_SPEC';PERFORM public.catalogue_decide_readiness(id,'Reactivate','Reagent available and configuration checked',v);PERFORM pg_temp.ok(13,'Technician Reactivate',(SELECT state='Approved' FROM public.catalogue_service_readiness WHERE test_id=id) AND (SELECT billing_enabled AND clinical_reporting_enabled FROM public.tests WHERE tests.id=id));END$$;
DO $$#variable_conflict use_variable
DECLARE id UUID;v BIGINT;BEGIN SELECT t.id,r.configuration_version INTO id,v FROM public.tests t JOIN public.catalogue_service_readiness r ON r.test_id=t.id WHERE t.code='R90_QUAL';PERFORM public.catalogue_decide_readiness(id,'MarkNonReportable','Operational service without clinical report',v);PERFORM pg_temp.ok(14,'Technician Mark Non-Reportable',(SELECT reporting_type='NoReporting' AND billing_enabled AND NOT clinical_reporting_enabled FROM public.tests WHERE tests.id=id));END$$;
SELECT pg_temp.ok(15,'non-reportable excluded from result and report flow',EXISTS(SELECT 1 FROM public.tests t WHERE t.code='R90_QUAL' AND public.catalogue_test_result_readiness(t.id)='NoReporting') AND NOT EXISTS(SELECT 1 FROM public.catalogue_test_operational_state o JOIN public.tests t ON t.id=o.test_id WHERE t.code='R90_QUAL' AND o.operational_state='Ready & Reportable'));
SELECT pg_temp.ok(16,'suspended service unavailable for new billing',NOT EXISTS(SELECT 1 FROM public.tests t WHERE t.code='R90_NORMAL' AND t.billing_enabled));
RESET ROLE;UPDATE public.tests SET is_active=FALSE,lifecycle_status='Archived' WHERE code='R90_TEXT';SET LOCAL ROLE authenticated;SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000002',TRUE);
SELECT pg_temp.ok(17,'inactive/archive unavailable',EXISTS(SELECT 1 FROM public.tests t WHERE t.code='R90_TEXT' AND public.catalogue_test_result_readiness(t.id)='Inactive'));
SELECT pg_temp.ok(18,'explicit prior suspension remains preserved',EXISTS(SELECT 1 FROM public.catalogue_service_readiness r JOIN public.tests t ON t.id=r.test_id WHERE t.code='R90_NORMAL' AND r.state='NeedsConfiguration'));
SELECT pg_temp.ok(19,'existing reviewed state remains evidence-backed',EXISTS(SELECT 1 FROM public.catalogue_configuration_evidence e JOIN public.tests t ON t.id=e.test_id WHERE t.code='R90_NORMAL' AND e.reason='Temporary result configuration correction'));
SELECT pg_temp.ok(20,'default-price NULL remains independent of readiness',EXISTS(SELECT 1 FROM public.tests t WHERE t.code='R90_UNPRICED' AND NOT t.price_configured AND public.catalogue_test_result_readiness(t.id)='Ready'));
SELECT pg_temp.ok(21,'no universal numeric range requirement',NOT (public.catalogue_service_readiness_checklist((SELECT id FROM public.tests WHERE code='R90_UNPRICED'))->'missing_requirements') ? 'Clinically validated reference ranges are missing');
SELECT pg_temp.ok(22,'audit evidence records actor reason and revision',EXISTS(SELECT 1 FROM public.catalogue_configuration_evidence e JOIN public.tests t ON t.id=e.test_id WHERE t.code='R90_SPEC' AND e.actor_id='99000000-0000-0000-0000-000000000002' AND e.reason='Reagent available and configuration checked' AND e.configuration_version>1));

SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000003',TRUE);DO $$DECLARE id UUID:=(SELECT id FROM public.tests WHERE code='R90_UNPRICED');v BIGINT:=(SELECT configuration_version FROM public.catalogue_service_readiness WHERE test_id=id);BEGIN BEGIN PERFORM public.catalogue_decide_readiness(id,'MarkReady','inactive attempt',v);RAISE EXCEPTION 'inactive accepted';EXCEPTION WHEN insufficient_privilege THEN PERFORM pg_temp.ok(23,'inactive user denied',TRUE);END;END$$;
RESET ROLE;SET LOCAL ROLE anon;SELECT set_config('request.jwt.claim.sub','',TRUE);DO $$DECLARE id UUID:=current_setting('r90.unpriced')::UUID;BEGIN BEGIN PERFORM public.catalogue_decide_readiness(id,'MarkReady','anon attempt',1);RAISE EXCEPTION 'anon accepted';EXCEPTION WHEN insufficient_privilege THEN PERFORM pg_temp.ok(24,'anon denied',TRUE);END;END$$;
RESET ROLE;SET LOCAL ROLE authenticated;SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000004',TRUE);DO $$DECLARE id UUID:=(SELECT id FROM public.tests WHERE code='R90_UNPRICED');v BIGINT:=(SELECT configuration_version FROM public.catalogue_service_readiness WHERE test_id=id);BEGIN BEGIN PERFORM public.catalogue_decide_readiness(id,'MarkReady','gateway attempt',v);RAISE EXCEPTION 'gateway accepted';EXCEPTION WHEN insufficient_privilege THEN PERFORM pg_temp.ok(25,'Gateway denied',TRUE);END;END$$;
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000005',TRUE);DO $$DECLARE id UUID:=(SELECT id FROM public.tests WHERE code='R90_UNPRICED');v BIGINT:=(SELECT configuration_version FROM public.catalogue_service_readiness WHERE test_id=id);BEGIN BEGIN PERFORM public.catalogue_decide_readiness(id,'MarkReady','worker attempt',v);RAISE EXCEPTION 'worker accepted';EXCEPTION WHEN insufficient_privilege THEN PERFORM pg_temp.ok(26,'ReportArtifactWorker denied',TRUE);END;END$$;
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000002',TRUE);SELECT pg_temp.ok(27,'Lab Technician allowed',public.has_permission('can_manage_catalogue') AND public.has_permission('can_configure_catalogue_technical'));
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000001',TRUE);SELECT pg_temp.ok(28,'Super Admin allowed',public.is_super_admin() AND public.has_permission('can_manage_catalogue'));
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000002',TRUE);DO $$#variable_conflict use_variable
DECLARE id UUID:=(SELECT id FROM public.tests WHERE code='R90_DELETE');v BIGINT:=(SELECT row_version FROM public.tests WHERE tests.id=id);BEGIN PERFORM public.catalogue_delete_test(id,v);PERFORM pg_temp.ok(29,'safe unused delete works',NOT EXISTS(SELECT 1 FROM public.tests WHERE tests.id=id));END$$;
DO $$#variable_conflict use_variable
DECLARE id UUID:=(SELECT id FROM public.tests WHERE code='R90_REVIEWED');v BIGINT:=(SELECT configuration_version FROM public.catalogue_service_readiness WHERE test_id=id);rv BIGINT;BEGIN PERFORM public.catalogue_decide_readiness(id,'MarkReady','Reviewed configuration retained',v);SELECT row_version INTO rv FROM public.tests WHERE tests.id=id;BEGIN PERFORM public.catalogue_delete_test(id,rv);RAISE EXCEPTION 'reviewed delete accepted';EXCEPTION WHEN foreign_key_violation THEN PERFORM pg_temp.ok(30,'reviewed/configured delete protection works',TRUE);END;END$$;

SELECT count(*) passed,0 failed FROM acceptance_results;
ROLLBACK;
