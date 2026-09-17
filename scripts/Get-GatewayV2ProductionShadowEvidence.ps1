[CmdletBinding()]
param([string]$ProjectRoot=(Get-Location).Path)
$ErrorActionPreference='Stop'
$projectRef='rncjxstujioagcezvfkb'
$provision=Get-Content -Raw (Join-Path $ProjectRoot '.recovery-work\gateway-v2-production-shadow-provision.json')|ConvertFrom-Json
$prior=$ErrorActionPreference;$ErrorActionPreference='Continue'
$login=(& npx supabase db dump --linked --data-only --dry-run --log-level error 2>&1|Out-String)
$ErrorActionPreference=$prior
$dbHost=[regex]::Match($login,'export PGHOST="([^"]+)"').Groups[1].Value
$dbPort=[regex]::Match($login,'export PGPORT="([^"]+)"').Groups[1].Value
$dbUser=[regex]::Match($login,'export PGUSER="([^"]+)"').Groups[1].Value
$dbPassword=[regex]::Match($login,'export PGPASSWORD="([^"]+)"').Groups[1].Value
$dbName=[regex]::Match($login,'export PGDATABASE="([^"]+)"').Groups[1].Value
$login=$null;$env:PGPASSWORD=$dbPassword
try{
  $psql='C:\Program Files\PostgreSQL\17\bin\psql.exe'
  $iid=[string]$provision.instance_id;$uid=[string]$provision.auth_user_id
  $sql=@"
SET ROLE postgres;
SELECT json_build_object(
 'head',(SELECT max(version) FROM supabase_migrations.schema_migrations),
 'instance_count',(SELECT count(*) FROM public.sms_gateway_instances),
 'profile_policy_hardened',(SELECT count(*)=1 FROM pg_policies WHERE schemaname='public' AND tablename='user_profiles' AND policyname='user_profiles_select_own' AND qual LIKE '%is_active_user%'),
 'instance_matches',(SELECT count(*) FROM public.sms_gateway_instances WHERE instance_id='$iid'::uuid AND auth_user_id='$uid'::uuid AND is_enabled AND NOT claiming_enabled),
 'profile_rows',(SELECT count(*) FROM public.user_profiles WHERE id='$uid'::uuid),
 'active_profile_rows',(SELECT count(*) FROM public.user_profiles WHERE id='$uid'::uuid AND is_active),
 'user_role_rows',(SELECT count(*) FROM public.user_roles WHERE user_id='$uid'::uuid),
 'queue_total',(SELECT count(*) FROM public.sms_queue_items),
 'queue_by_status',(SELECT COALESCE(json_object_agg(status,row_count),'{}'::json) FROM (SELECT status,count(*) row_count FROM public.sms_queue_items GROUP BY status ORDER BY status) s),
 'processing',(SELECT count(*) FROM public.sms_queue_items WHERE status='Processing'),
 'stale_processing',(SELECT count(*) FROM public.sms_queue_items WHERE status='Processing' AND lease_expires_at<now()),
 'provider_outcome_unknown',(SELECT count(*) FROM public.sms_queue_items WHERE error_classification='ProviderOutcomeUnknown'),
 'provider_outcome_unknown_unreviewed',(SELECT count(*) FROM public.sms_queue_items WHERE error_classification='ProviderOutcomeUnknown' AND status='Processing'),
 'pending_due',(SELECT count(*) FROM public.sms_queue_items WHERE status='Pending' AND scheduled_at<=now()),
 'pending_future',(SELECT count(*) FROM public.sms_queue_items WHERE status='Pending' AND scheduled_at>now()),
 'pending_by_type',(SELECT COALESCE(json_object_agg(sms_type,row_count),'{}'::json) FROM (SELECT sms_type,count(*) row_count FROM public.sms_queue_items WHERE status='Pending' GROUP BY sms_type ORDER BY sms_type) s),
 'v2_leases',(SELECT count(*) FROM public.sms_queue_items WHERE lease_instance_id='$iid'::uuid),
 'v2_provider_started',(SELECT count(*) FROM public.sms_queue_items WHERE lease_instance_id='$iid'::uuid AND provider_call_started_at IS NOT NULL),
 'queue_fingerprint',(SELECT md5(COALESCE(string_agg(id::text||':'||status||':'||retry_count::text||':'||COALESCE(lease_owner::text,'')||':'||COALESCE(lease_instance_id::text,'')||':'||COALESCE(provider_call_started_at::text,''),'|' ORDER BY id),'')) FROM public.sms_queue_items),
 'last_heartbeat_present',(SELECT last_heartbeat_at IS NOT NULL FROM public.sms_gateway_instances WHERE instance_id='$iid'::uuid),
 'last_heartbeat_at',(SELECT last_heartbeat_at FROM public.sms_gateway_instances WHERE instance_id='$iid'::uuid),
 'service_started_at',(SELECT service_started_at FROM public.sms_gateway_instances WHERE instance_id='$iid'::uuid),
 'online',(SELECT last_heartbeat_at>=now()-interval '2 minutes' FROM public.sms_gateway_instances WHERE instance_id='$iid'::uuid),
 'claiming_enabled',(SELECT claiming_enabled FROM public.sms_gateway_instances WHERE instance_id='$iid'::uuid),
 'is_enabled',(SELECT is_enabled FROM public.sms_gateway_instances WHERE instance_id='$iid'::uuid)
);
"@
  $json=(& $psql -X -qAt -P pager=off -v ON_ERROR_STOP=1 -h $dbHost -p $dbPort -U $dbUser -d $dbName -c $sql|Select-Object -Last 1)
  if($LASTEXITCODE){throw 'Production evidence query failed.'}
  $obj=$json|ConvertFrom-Json
  [ordered]@{captured_at=(Get-Date).ToUniversalTime().ToString('o');project_ref=$projectRef;database=$obj;gateway1_service=(Get-Service BimalPathologySMSGateway|Select-Object Name,Status,StartType)}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $ProjectRoot '.recovery-work\gateway-v2-production-shadow-state.json') -Encoding utf8
  Write-Output "GATEWAY_V2_SHADOW_EVIDENCE_PASS head=$($obj.head) instance=$($obj.instance_matches) active_profile=$($obj.active_profile_rows) roles=$($obj.user_role_rows) v2_leases=$($obj.v2_leases)"
}finally{$env:PGPASSWORD=$null;$dbPassword=$null}
