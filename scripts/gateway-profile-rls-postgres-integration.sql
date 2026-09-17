\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(ok BOOLEAN, message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$ BEGIN IF NOT COALESCE(ok,FALSE) THEN RAISE EXCEPTION 'ASSERTION_FAILED: %',message; END IF; END $$;

INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
 ('92000000-0000-0000-0000-000000000001','owner.profile-rls@example.invalid','{"full_name":"RLS System Owner"}'),
 ('92000000-0000-0000-0000-000000000002','tech.profile-rls@example.invalid','{"full_name":"RLS Technician"}'),
 ('92000000-0000-0000-0000-000000000003','inactive.profile-rls@example.invalid','{"full_name":"RLS Inactive"}'),
 ('92000000-0000-0000-0000-000000000004','gateway.profile-rls@example.invalid','{"full_name":"Gateway Service"}'),
 ('92000000-0000-0000-0000-000000000005','unregistered.profile-rls@example.invalid','{"full_name":"Unregistered Auth"}')
ON CONFLICT (id) DO NOTHING;

UPDATE public.user_profiles SET is_active=TRUE,
 is_super_admin=(id='92000000-0000-0000-0000-000000000001')
WHERE id IN ('92000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000002');
UPDATE public.user_profiles SET is_active=FALSE,is_super_admin=FALSE
WHERE id IN ('92000000-0000-0000-0000-000000000003','92000000-0000-0000-0000-000000000004','92000000-0000-0000-0000-000000000005');
INSERT INTO public.user_roles(user_id,role_id) VALUES
 ('92000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000004')
ON CONFLICT DO NOTHING;
INSERT INTO public.sms_gateway_instances(instance_id,auth_user_id,hostname,gateway_version,provider_name,claiming_enabled,is_enabled)
VALUES('93000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000004','integration-host','2.0.0-shadow.1','Sparrow',FALSE,TRUE);

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claim.sub','92000000-0000-0000-0000-000000000001',TRUE);
SELECT pg_temp.assert_true(public.is_active_user(),'System Owner must be active');
SELECT pg_temp.assert_true((SELECT count(*) FROM public.user_profiles)=5,'System Owner must retain managed-profile read access');

SELECT set_config('request.jwt.claim.sub','92000000-0000-0000-0000-000000000002',TRUE);
SELECT pg_temp.assert_true(public.is_active_user(),'Technician must be active');
SELECT pg_temp.assert_true((SELECT count(*) FROM public.user_profiles)=1,'Technician must retain own active profile read only');
SELECT pg_temp.assert_true(EXISTS(SELECT 1 FROM public.user_profiles WHERE id=auth.uid()),'Technician own profile must be visible');

SELECT set_config('request.jwt.claim.sub','92000000-0000-0000-0000-000000000003',TRUE);
SELECT pg_temp.assert_true(NOT public.is_active_user(),'Inactive normal user must be inactive');
SELECT pg_temp.assert_true((SELECT count(*) FROM public.user_profiles)=0,'Inactive normal user must see zero profiles');

SELECT set_config('request.jwt.claim.sub','92000000-0000-0000-0000-000000000004',TRUE);
SELECT pg_temp.assert_true(NOT public.is_active_user(),'Gateway identity must not be an active LIS user');
SELECT pg_temp.assert_true((SELECT count(*) FROM public.user_profiles)=0,'Gateway identity must not read its inactive auto-profile');
SELECT pg_temp.assert_true((public.sms_gateway_v2_preflight('93000000-0000-0000-0000-000000000001')->>'success')::BOOLEAN,'Gateway preflight must remain allowed');
SELECT pg_temp.assert_true((public.heartbeat_sms_gateway_v2('93000000-0000-0000-0000-000000000001','integration-host','2.0.0-shadow.1','Sparrow',now(),NULL,NULL,'Unknown',NULL,0)->>'success')::BOOLEAN,'Gateway heartbeat must remain allowed');
DO $$ BEGIN
 BEGIN
  PERFORM public.claim_sms_gateway_v2_batch('93000000-0000-0000-0000-000000000001',gen_random_uuid(),300,1);
  RAISE EXCEPTION 'ASSERTION_FAILED: claiming-disabled Gateway claimed work';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
END $$;

SELECT set_config('request.jwt.claim.sub','92000000-0000-0000-0000-000000000005',TRUE);
SELECT pg_temp.assert_true(NOT public.is_active_user(),'Unregistered Auth identity must not be active');
SELECT pg_temp.assert_true((SELECT count(*) FROM public.user_profiles)=0,'Unregistered Auth identity must see zero profiles');
DO $$ BEGIN
 BEGIN
  PERFORM public.sms_gateway_v2_preflight('93000000-0000-0000-0000-000000000001');
  RAISE EXCEPTION 'ASSERTION_FAILED: unregistered identity passed Gateway preflight';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

RESET ROLE;
SELECT 'gateway profile RLS PostgreSQL integration: PASS' AS result;
ROLLBACK;
