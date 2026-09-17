[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$DataDirectory = "$env:ProgramData\BimalPathology\SmsGatewayV2"
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security

$evidencePath = Join-Path $ProjectRoot '.recovery-work\gateway-v2-production-authorization.json'
$provision = Get-Content -Raw (Join-Path $ProjectRoot '.recovery-work\gateway-v2-production-shadow-provision.json') | ConvertFrom-Json
$protected = [IO.File]::ReadAllBytes((Join-Path $DataDirectory 'gateway.secrets.bin'))
$plain = [Security.Cryptography.ProtectedData]::Unprotect($protected,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
try { $secret = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json }
finally { [Array]::Clear($plain,0,$plain.Length); [Array]::Clear($protected,0,$protected.Length) }

function Invoke-SafeRequest([string]$Name,[string]$Method,[string]$Path,[object]$Body=$null,[bool]$ExpectAllowed=$false) {
  $headers = @{ apikey=[string]$secret.supabasePublishableKey; Authorization="Bearer $script:token"; Prefer='return=minimal' }
  $params = @{ Uri="$($secret.supabaseUrl)$Path"; Method=$Method; Headers=$headers }
  if ($null -ne $Body) { $params.ContentType='application/json'; $params.Body=($Body | ConvertTo-Json -Depth 8 -Compress) }
  try { $response = Invoke-WebRequest @params }
  catch { if($_.Exception.Response){$response=$_.Exception.Response}else{throw} }
  $status=[int]$response.StatusCode
  $text=''
  if($response.PSObject.Properties.Name -contains 'Content'){$text=[string]$response.Content}
  $emptyRead = $false
  $rowCount=$null
  if($Method -eq 'GET' -and $status -ge 200 -and $status -lt 300){
    try{$parsed=$text|ConvertFrom-Json;$rowCount=if($null -eq $parsed){0}else{@($parsed).Count};$emptyRead=$rowCount -eq 0}catch{$emptyRead=$text.Trim() -eq '[]'}
  }
  $allowed = $status -ge 200 -and $status -lt 300 -and -not $emptyRead
  $passed = if($ExpectAllowed){$allowed}else{(-not $allowed) -or $emptyRead}
  $script:results += [ordered]@{name=$Name;status=$status;effective_empty=$emptyRead;row_count=$rowCount;expected=if($ExpectAllowed){'allowed'}else{'denied'};pass=$passed}
}

$login = Invoke-WebRequest -Uri "$($secret.supabaseUrl)/auth/v1/token?grant_type=password" -Method Post -Headers @{apikey=[string]$secret.supabasePublishableKey} -ContentType 'application/json' -Body (@{email=$secret.gatewayEmail;password=$secret.gatewayPassword}|ConvertTo-Json -Compress)
if($login.StatusCode -ne 200){throw "Gateway authentication failed (HTTP $($login.StatusCode))."}
$auth = $login.Content | ConvertFrom-Json
$script:token = [string]$auth.access_token
if(-not $script:token){throw 'Gateway authentication produced no access token.'}
$script:results = @([ordered]@{name='gateway_authentication';status=200;effective_empty=$false;expected='allowed';pass=$true})
$iid=[string]$provision.instance_id; $nil='00000000-0000-0000-0000-000000000000'
try {
  Invoke-SafeRequest 'gateway_preflight' POST '/rest/v1/rpc/sms_gateway_v2_preflight' @{p_instance_id=$iid} $true
  Invoke-SafeRequest 'gateway_heartbeat' POST '/rest/v1/rpc/heartbeat_sms_gateway_v2' @{p_instance_id=$iid;p_hostname=$env:COMPUTERNAME;p_gateway_version='2.0.0-shadow.1';p_provider_name='Sparrow';p_service_started_at=(Get-Date).ToUniversalTime().ToString('o');p_last_successful_queue_access_at=$null;p_last_provider_success_at=$null;p_provider_health='Unknown';p_safe_last_error_code=$null;p_active_job_count=0} $true
  Invoke-SafeRequest 'patients_select' GET '/rest/v1/patients?select=id&limit=1'
  Invoke-SafeRequest 'bills_select' GET '/rest/v1/bills?select=id&limit=1'
  Invoke-SafeRequest 'payments_select' GET '/rest/v1/payment_transactions?select=id&limit=1'
  Invoke-SafeRequest 'samples_select' GET '/rest/v1/samples?select=id&limit=1'
  Invoke-SafeRequest 'results_select' GET '/rest/v1/test_results?select=id&limit=1'
  Invoke-SafeRequest 'reports_select' GET '/rest/v1/diagnostic_reports?select=id&limit=1'
  Invoke-SafeRequest 'private_profiles_select' GET '/rest/v1/user_profiles?select=id&limit=1'
  Invoke-SafeRequest 'queue_select' GET '/rest/v1/sms_queue_items?select=id&limit=1'
  Invoke-SafeRequest 'queue_insert' POST '/rest/v1/sms_queue_items' @{id=$nil}
  Invoke-SafeRequest 'queue_update' PATCH "/rest/v1/sms_queue_items?id=eq.$nil" @{status='Pending'}
  Invoke-SafeRequest 'queue_delete' DELETE "/rest/v1/sms_queue_items?id=eq.$nil"
  Invoke-SafeRequest 'admin_health_rpc' POST '/rest/v1/rpc/get_sms_gateway_v2_health' @{}
  Invoke-SafeRequest 'role_management_rpc' POST '/rest/v1/rpc/replace_role_permission_matrix' @{p_matrix=@()}
  Invoke-SafeRequest 'user_management_rpc' POST '/rest/v1/rpc/update_user_access' @{p_user_id=$nil;p_is_active=$false;p_is_super_admin=$false;p_role_ids=@()}
  Invoke-SafeRequest 'billing_mutation_rpc' POST '/rest/v1/rpc/receive_bill_payment' @{p_bill_id=$nil;p_amount=0;p_payment_method='Cash';p_reference_number=$null;p_idempotency_key=[guid]::NewGuid().ToString()}
  Invoke-SafeRequest 'clinical_mutation_rpc' POST '/rest/v1/rpc/transition_sample_lifecycle' @{p_sample_id=$nil;p_target_status='Received';p_reason=$null}
  Invoke-SafeRequest 'report_signing_rpc' POST '/rest/v1/rpc/sign_and_queue_diagnostic_report' @{p_report_id=$nil;p_public_report_url='https://invalid.example/report'}
  Invoke-SafeRequest 'claiming_disabled' POST '/rest/v1/rpc/claim_sms_gateway_v2_batch' @{p_instance_id=$iid;p_worker_id=[guid]::NewGuid().ToString();p_lease_seconds=300;p_batch_size=1}
  Invoke-SafeRequest 'instance_impersonation' POST '/rest/v1/rpc/sms_gateway_v2_preflight' @{p_instance_id=[guid]::NewGuid().ToString()}
} finally {
  $script:token=$null; $auth=$null; $secret=$null
}
[ordered]@{tested_at=(Get-Date).ToUniversalTime().ToString('o');project_ref=$provision.project_ref;instance_id=$iid;passed=@($results|Where-Object pass).Count;failed=@($results|Where-Object{-not $_.pass}).Count;results=$results}|ConvertTo-Json -Depth 6 | Set-Content $evidencePath -Encoding utf8
if(@($results|Where-Object{-not $_.pass}).Count){throw "GATEWAY_V2_PRODUCTION_AUTHORIZATION_FAIL passed=$(@($results|Where-Object pass).Count) failed=$(@($results|Where-Object{-not $_.pass}).Count)"}
Write-Output "GATEWAY_V2_PRODUCTION_AUTHORIZATION_PASS count=$(@($results).Count)"
