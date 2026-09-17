[CmdletBinding()]
param([string]$ProjectRoot = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
$prior = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$login = (& npx supabase db dump --linked --data-only --dry-run --log-level error 2>&1 | Out-String)
$ErrorActionPreference = $prior
$dbHost = [regex]::Match($login, 'export PGHOST="([^"]+)"').Groups[1].Value
$dbPort = [regex]::Match($login, 'export PGPORT="([^"]+)"').Groups[1].Value
$dbUser = [regex]::Match($login, 'export PGUSER="([^"]+)"').Groups[1].Value
$dbPassword = [regex]::Match($login, 'export PGPASSWORD="([^"]+)"').Groups[1].Value
$dbName = [regex]::Match($login, 'export PGDATABASE="([^"]+)"').Groups[1].Value
$login = $null
$env:PGPASSWORD = $dbPassword

try {
    $psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'
    $sql = @"
SET ROLE postgres;
WITH expected(signature) AS (VALUES
 ('public.recover_stale_sms_gateway_items(integer)'),
 ('public.claim_next_sms_gateway_item(uuid,integer)'),
 ('public.mark_sms_provider_call_started(uuid,uuid)'),
 ('public.complete_sms_gateway_item(uuid,uuid,boolean,text,jsonb,text,text,text,boolean)')
)
SELECT json_build_object(
 'head',(SELECT max(version) FROM supabase_migrations.schema_migrations),
 'functions',(SELECT json_agg(json_build_object(
   'signature',e.signature,
   'exists',to_regprocedure(e.signature) IS NOT NULL,
   'service_role_execute',CASE WHEN to_regprocedure(e.signature) IS NULL THEN false ELSE has_function_privilege('service_role',e.signature,'EXECUTE') END,
   'security_definer',COALESCE(p.prosecdef,false),
   'search_path',COALESCE(array_to_string(p.proconfig,','),''),
   'owner',COALESCE(pg_get_userbyid(p.proowner),'')
 ) ORDER BY e.signature) FROM expected e LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.signature)),
 'service_role_table_select',has_table_privilege('service_role','public.sms_queue_items','SELECT'),
 'service_role_table_update',has_table_privilege('service_role','public.sms_queue_items','UPDATE'),
 'authenticated_table_mutation',has_table_privilege('authenticated','public.sms_queue_items','INSERT,UPDATE,DELETE')
);
"@
    $json = (& $psql -X -qAt -P pager=off -v ON_ERROR_STOP=1 -h $dbHost -p $dbPort -U $dbUser -d $dbName -c $sql | Select-Object -Last 1)
    if ($LASTEXITCODE) { throw 'Gateway 1.x RPC evidence query failed.' }
    $evidence = $json | ConvertFrom-Json
    $path = Join-Path $ProjectRoot '.recovery-work\gateway-v1-production-rpc-evidence.json'
    [ordered]@{captured_at=(Get-Date).ToUniversalTime().ToString('o');project_ref='rncjxstujioagcezvfkb';database=$evidence} |
        ConvertTo-Json -Depth 8 | Set-Content $path -Encoding utf8
    $failed = @($evidence.functions | Where-Object { -not $_.exists -or -not $_.service_role_execute -or -not $_.security_definer -or $_.search_path -notmatch 'search_path=public, pg_temp|search_path=public,pg_temp' })
    Write-Output "GATEWAY1_RPC_EVIDENCE head=$($evidence.head) functions=$(@($evidence.functions).Count) failures=$($failed.Count)"
} finally {
    $env:PGPASSWORD = $null
    $dbPassword = $null
}
