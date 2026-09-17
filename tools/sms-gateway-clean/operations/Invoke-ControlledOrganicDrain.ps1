[CmdletBinding()]
param(
  [string]$InstanceId = 'a7c7e059-0dc9-4594-8d0d-a507d2b19ff1',
  [string]$DataDirectory = "$env:ProgramData\BimalPathology\SmsGatewayClean",
  [int]$TimeoutSeconds = 180
)
$ErrorActionPreference = 'Stop'
$psql = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'
$configPath = Join-Path $DataDirectory 'gateway.config.json'
$evidencePath = Join-Path $PSScriptRoot 'organic-drain-evidence.json'
$claimingWasEnabled = $false
$runtimeWasChanged = $false
$startedAt = (Get-Date).ToUniversalTime()
$states = @{}

function Invoke-Db([string]$Sql) {
  $lines = @(& $script:psql -X -qAt -P pager=off -F '|' -v ON_ERROR_STOP=1 -h $script:dbHost -p $script:dbPort -U $script:dbUser -d $script:dbName -c $Sql)
  if ($LASTEXITCODE) { throw 'Production database command failed.' }
  return $lines
}

function Set-Claiming([bool]$Enabled) {
  $admin = (@(Invoke-Db "SET ROLE postgres;SELECT id FROM public.user_profiles WHERE is_active AND is_super_admin ORDER BY created_at LIMIT 1;") | Select-Object -Last 1).Trim()
  if ($admin -notmatch '^[0-9a-f-]{36}$') { throw 'No active Super Admin is available for the guarded claiming operation.' }
  $confirmation = if ($Enabled) { 'ENABLE_SMS_GATEWAY_V2_CLAIMING' } else { 'DISABLE_SMS_GATEWAY_V2_CLAIMING' }
  $literal = if ($Enabled) { 'true' } else { 'false' }
  $sql = "SET ROLE postgres;SELECT set_config('request.jwt.claims',json_build_object('sub','$admin','role','authenticated')::text,false);SET ROLE authenticated;SELECT public.set_sms_gateway_v2_claiming('$script:InstanceId'::uuid,$literal,'$confirmation');"
  $null = Invoke-Db $sql
}

function Set-RuntimeMode([ValidateSet('shadow','active')][string]$Mode) {
  $config = Get-Content $script:configPath -Raw | ConvertFrom-Json
  $config.mode = $Mode
  $json = $config | ConvertTo-Json -Depth 10
  [IO.File]::WriteAllText($script:configPath, $json, [Text.UTF8Encoding]::new($false))
}

function Restart-CleanService {
  Restart-Service BimalPathologySMSGatewayClean
  (Get-Service BimalPathologySMSGatewayClean).WaitForStatus('Running', [TimeSpan]::FromSeconds(45))
}

function Hash-Id([string]$Value) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-','').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

try {
  $prior = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $dry = (& npx supabase db dump --linked --data-only --dry-run --log-level error 2>&1 | Out-String)
  $ErrorActionPreference = $prior
  $script:dbHost = [regex]::Match($dry, 'export PGHOST="([^"]+)"').Groups[1].Value
  $script:dbPort = [regex]::Match($dry, 'export PGPORT="([^"]+)"').Groups[1].Value
  $script:dbUser = [regex]::Match($dry, 'export PGUSER="([^"]+)"').Groups[1].Value
  $password = [regex]::Match($dry, 'export PGPASSWORD="([^"]+)"').Groups[1].Value
  $script:dbName = [regex]::Match($dry, 'export PGDATABASE="([^"]+)"').Groups[1].Value
  $dry = $null
  if (-not $script:dbHost -or -not $password) { throw 'Linked database authentication discovery failed.' }
  $env:PGPASSWORD = $password

  $head = (@(Invoke-Db 'SET ROLE postgres;SELECT max(version) FROM supabase_migrations.schema_migrations;') | Select-Object -Last 1).Trim()
  if ($head -ne '00080') { throw "Unexpected production migration head: $head" }
  $instance = @((Invoke-Db "SET ROLE postgres;SELECT is_enabled,claiming_enabled,(last_heartbeat_at>now()-interval '2 minutes'),active_job_count FROM public.sms_gateway_instances WHERE instance_id='$InstanceId'::uuid;") | Select-Object -Last 1)[0].Split('|')
  if ($instance.Count -ne 4 -or $instance[0] -ne 't' -or $instance[1] -ne 'f' -or $instance[2] -ne 't' -or $instance[3] -ne '0') { throw 'Clean instance failed the active-drain gate.' }
  $unsafe = @((Invoke-Db "SET ROLE postgres;SELECT count(*) FILTER(WHERE status='Processing'),count(*) FILTER(WHERE status='Processing' AND lease_expires_at<now()),count(*) FILTER(WHERE status='DeadLetter' AND error_classification='ProviderOutcomeUnknown'),count(*) FILTER(WHERE lease_instance_id='$InstanceId'::uuid) FROM public.sms_queue_items;") | Select-Object -Last 1)[0].Split('|')
  if (($unsafe | ForEach-Object {[int]$_} | Measure-Object -Sum).Sum -ne 0) { throw 'Processing, stale, unknown-outcome, or clean-lease safety gate failed.' }
  $rows = @(Invoke-Db "SET ROLE postgres;SELECT id,sms_type,status,delivery_attempt_count,retry_count FROM public.sms_queue_items WHERE status='Pending' AND scheduled_at<=now() ORDER BY scheduled_at,created_at,id;")
  if ($rows.Count -ne 2) { throw "Due queue changed before activation: $($rows.Count) rows." }
  $approved = @()
  foreach ($line in $rows) {
    $parts = $line.Split('|'); if ($parts.Count -ne 5) { throw 'Unexpected queue snapshot shape.' }
    $approved += [pscustomobject]@{ id=$parts[0]; type=$parts[1]; baselineAttempts=[int]$parts[3]; baselineRetries=[int]$parts[4] }
    $states[$parts[0]] = [ordered]@{ id_hash=(Hash-Id $parts[0]); type=$parts[1]; seen_processing=$false; seen_clean_lease=$false; seen_provider_fence=$false; terminal_status=$null; attempt_delta=0; retry_delta=0; provider_message_id_present=$false; completion_audits=0 }
  }
  if (@($approved | Where-Object type -eq 'BillRegistration').Count -ne 1 -or @($approved | Where-Object type -eq 'ReportReady').Count -ne 1) { throw 'Due queue types changed before activation.' }
  $otherClaimers = @(Invoke-Db "SET ROLE postgres;SELECT count(*) FROM public.sms_gateway_instances WHERE instance_id<>'$InstanceId'::uuid AND claiming_enabled;") | Select-Object -Last 1
  if ([int]$otherClaimers -ne 0) { throw 'Another Gateway v2 instance is enabled for claiming.' }

  Set-RuntimeMode active; $runtimeWasChanged = $true
  Set-Claiming $true; $claimingWasEnabled = $true
  Restart-CleanService

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $terminal = $false
  while ((Get-Date) -lt $deadline) {
    $idList = ($approved | ForEach-Object { "'$($_.id)'::uuid" }) -join ','
    $observed = @(Invoke-Db "SET ROLE postgres;SELECT id,status,coalesce(lease_instance_id::text,''),coalesce(lease_owner::text,''),(provider_call_started_at IS NOT NULL),delivery_attempt_count,retry_count,(provider_message_id IS NOT NULL) FROM public.sms_queue_items WHERE id IN ($idList) ORDER BY id;")
    foreach ($line in $observed) {
      $parts = $line.Split('|'); $state = $states[$parts[0]]
      if ($parts[1] -eq 'Processing') { $state.seen_processing = $true }
      if ($parts[2] -eq $InstanceId) { $state.seen_clean_lease = $true }
      if ($parts[4] -eq 't') { $state.seen_provider_fence = $true }
      $base = $approved | Where-Object id -eq $parts[0]
      $state.attempt_delta = [int]$parts[5] - $base.baselineAttempts
      $state.retry_delta = [int]$parts[6] - $base.baselineRetries
      $state.provider_message_id_present = $parts[7] -eq 't'
      if ($parts[1] -in @('Sent','DeadLetter','Failed')) { $state.terminal_status = $parts[1] }
    }
    $newDue = [int](@(Invoke-Db "SET ROLE postgres;SELECT count(*) FROM public.sms_queue_items WHERE status='Pending' AND scheduled_at<=now() AND id NOT IN ($idList);") | Select-Object -Last 1)
    if ($newDue -gt 0) { throw 'A new unrelated due queue item appeared during the bounded drain.' }
    if (@($states.Values | Where-Object { $_.terminal_status }).Count -eq 2) { $terminal = $true; break }
    Start-Sleep -Milliseconds 200
  }
  if (-not $terminal) { throw 'Controlled drain timed out before both approved rows reached safe terminal states.' }

  Set-Claiming $false; $claimingWasEnabled = $false
  Set-RuntimeMode shadow; $runtimeWasChanged = $false
  Restart-CleanService

  foreach ($row in $approved) {
    $audit = [int](@(Invoke-Db "SET ROLE postgres;SELECT count(*) FROM public.audit_logs WHERE entity_type='SmsQueueItem' AND entity_id='$($row.id)' AND action IN ('SMS_SENT','SMS_FAILED') AND new_data->>'gateway_instance_id'='$InstanceId';") | Select-Object -Last 1)
    $states[$row.id].completion_audits = $audit
  }
  $finalGate = @((Invoke-Db "SET ROLE postgres;SELECT claiming_enabled,(last_heartbeat_at>now()-interval '2 minutes'),active_job_count FROM public.sms_gateway_instances WHERE instance_id='$InstanceId'::uuid;") | Select-Object -Last 1)[0].Split('|')
  $finalQueue = @((Invoke-Db "SET ROLE postgres;SELECT count(*) FILTER(WHERE status='Processing'),count(*) FILTER(WHERE lease_instance_id='$InstanceId'::uuid) FROM public.sms_queue_items;") | Select-Object -Last 1)[0].Split('|')
  if ($finalGate[0] -ne 'f' -or $finalGate[1] -ne 't' -or $finalGate[2] -ne '0' -or $finalQueue[0] -ne '0' -or $finalQueue[1] -ne '0') { throw 'Post-drain shadow safety gate failed.' }

  [ordered]@{ started_at=$startedAt.ToString('o'); completed_at=(Get-Date).ToUniversalTime().ToString('o'); instance_id=$InstanceId; authorized_count=2; results=@($states.Values); final_claiming_enabled=$false; final_mode='shadow'; final_active_jobs=0; final_processing=0; final_clean_leases=0 } | ConvertTo-Json -Depth 7 | Set-Content $evidencePath -Encoding utf8
  $sent = @($states.Values | Where-Object terminal_status -eq 'Sent').Count
  Write-Output "CONTROLLED_ORGANIC_DRAIN_COMPLETE authorized=2 sent=$sent"
}
finally {
  try { if ($claimingWasEnabled) { Set-Claiming $false } } catch { Write-Error 'Emergency database claiming disable failed.' }
  try {
    $current = Get-Content $configPath -Raw | ConvertFrom-Json
    if ($runtimeWasChanged -or $current.mode -ne 'shadow') { Set-RuntimeMode shadow; Restart-CleanService }
  } catch { Write-Error 'Emergency runtime shadow restoration failed.' }
  $env:PGPASSWORD = $null; $password = $null
}
