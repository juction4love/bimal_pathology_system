[CmdletBinding()]
param([string]$DataDirectory="$env:ProgramData\BimalPathology\SmsGatewayClean")
$ErrorActionPreference='Stop';Add-Type -AssemblyName System.Security
$identity=Get-Content (Join-Path $PSScriptRoot 'production-shadow-identity.json') -Raw|ConvertFrom-Json
$cipher=[Convert]::FromBase64String(([IO.File]::ReadAllText((Join-Path $DataDirectory 'gateway.secrets.dpapi'))).Trim());$plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
try{$secret=[Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json}finally{[Array]::Clear($plain,0,$plain.Length);[Array]::Clear($cipher,0,$cipher.Length)}
function Invoke-Safe([string]$Name,[string]$Method,[string]$Path,[object]$Body=$null,[bool]$Allowed=$false){$headers=@{apikey=[string]$secret.supabasePublishableKey;Authorization="Bearer $script:token";Prefer='return=minimal'};$params=@{Uri="$($secret.supabaseUrl)$Path";Method=$Method;Headers=$headers};if($null-ne$Body){$params.ContentType='application/json';$params.Body=$Body|ConvertTo-Json -Depth 8 -Compress};try{$response=Invoke-WebRequest @params}catch{if($_.Exception.Response){$response=$_.Exception.Response}else{throw}};$status=[int]$response.StatusCode;$content=if($response.PSObject.Properties.Name-contains'Content'){[string]$response.Content}else{''};$script:lastContent=$content;$empty=$false;if($Method-eq'GET'-and$status-ge200-and$status-lt300){try{$parsed=$content|ConvertFrom-Json;$empty=@($parsed).Count-eq0}catch{$empty=$content.Trim()-eq'[]'}};$effective=$status-ge200-and$status-lt300-and-not$empty;$pass=if($Allowed){$effective}else{-not$effective-or$empty};$script:results+=[ordered]@{name=$Name;status=$status;expected=if($Allowed){'allowed'}else{'denied'};effective_empty=$empty;pass=$pass}}
$login=Invoke-WebRequest "$($secret.supabaseUrl)/auth/v1/token?grant_type=password" -Method Post -Headers @{apikey=[string]$secret.supabasePublishableKey} -ContentType 'application/json' -Body (@{email=$secret.gatewayEmail;password=$secret.gatewayPassword}|ConvertTo-Json -Compress);if($login.StatusCode-ne200){throw "Clean Gateway authentication failed (HTTP $($login.StatusCode))."};$auth=$login.Content|ConvertFrom-Json;$script:token=[string]$auth.access_token;if(-not$script:token){throw 'No clean Gateway access token returned.'}
$results=@([ordered]@{name='authentication';status=200;expected='allowed';effective_empty=$false;pass=$true});$iid=[string]$identity.instance_id;$experimental='40190975-bce2-4926-a7d7-20e2ae6d0c27';$nil='00000000-0000-0000-0000-000000000000'
try{
 $healthPath=Join-Path $DataDirectory 'health.json';$health=if(Test-Path $healthPath){Get-Content $healthPath -Raw|ConvertFrom-Json}else{$null}
 Invoke-Safe 'preflight' POST '/rest/v1/rpc/sms_gateway_v2_preflight' @{p_instance_id=$iid} $true
 $preflightContent=$script:lastContent
 Invoke-Safe 'heartbeat' POST '/rest/v1/rpc/heartbeat_sms_gateway_v2' @{p_instance_id=$iid;p_hostname=$env:COMPUTERNAME;p_gateway_version='2.0.0-clean.1';p_provider_name='Sparrow';p_service_started_at=if($health.serviceStartedAt){$health.serviceStartedAt}else{(Get-Date).ToUniversalTime().ToString('o')};p_last_successful_queue_access_at=$health.lastQueueAccessAt;p_last_provider_success_at=$health.lastProviderSuccessAt;p_provider_health=if($health){$health.providerHealth}else{'Unknown'};p_safe_last_error_code=$health.safeLastErrorCode;p_active_job_count=if($health){$health.activeJobs}else{0}} $true
 foreach($table in 'patients','bills','payment_transactions','samples','test_results','diagnostic_reports','user_profiles','sms_queue_items'){Invoke-Safe "${table}_select" GET "/rest/v1/${table}?select=id&limit=1"}
 Invoke-Safe 'queue_insert' POST '/rest/v1/sms_queue_items' @{id=$nil}
 Invoke-Safe 'queue_update' PATCH "/rest/v1/sms_queue_items?id=eq.$nil" @{status='Pending'}
 Invoke-Safe 'queue_delete' DELETE "/rest/v1/sms_queue_items?id=eq.$nil"
 Invoke-Safe 'admin_rpc' POST '/rest/v1/rpc/get_sms_gateway_v2_health' @{}
 Invoke-Safe 'role_management' POST '/rest/v1/rpc/replace_role_permission_matrix' @{p_matrix=@()}
 Invoke-Safe 'user_management' POST '/rest/v1/rpc/update_user_access' @{p_user_id=$nil;p_is_active=$false;p_is_super_admin=$false;p_role_ids=@()}
 Invoke-Safe 'billing_mutation' POST '/rest/v1/rpc/receive_bill_payment' @{p_bill_id=$nil;p_amount=0;p_payment_method='Cash';p_reference_number=$null;p_idempotency_key=[guid]::NewGuid().ToString()}
 Invoke-Safe 'clinical_mutation' POST '/rest/v1/rpc/transition_sample_lifecycle' @{p_sample_id=$nil;p_target_status='Received';p_reason=$null}
 Invoke-Safe 'report_signing' POST '/rest/v1/rpc/sign_and_queue_diagnostic_report' @{p_report_id=$nil;p_public_report_url='https://invalid.example/report'}
 $runtimeConfig=Get-Content (Join-Path $DataDirectory 'gateway.config.json') -Raw|ConvertFrom-Json
 if($runtimeConfig.mode-eq'active'){$preflight=$preflightContent|ConvertFrom-Json;$claiming=[bool]$preflight.claiming_enabled;$results+=[ordered]@{name='active_claiming_contract';status=200;expected='enabled_via_preflight';effective_empty=$false;pass=$claiming}}
 else{Invoke-Safe 'claiming_disabled' POST '/rest/v1/rpc/claim_sms_gateway_v2_batch' @{p_instance_id=$iid;p_worker_id=[guid]::NewGuid().ToString();p_lease_seconds=300;p_batch_size=1}}
 Invoke-Safe 'experimental_instance_impersonation' POST '/rest/v1/rpc/sms_gateway_v2_preflight' @{p_instance_id=$experimental}
 Invoke-Safe 'other_instance_impersonation' POST '/rest/v1/rpc/sms_gateway_v2_preflight' @{p_instance_id=[guid]::NewGuid().ToString()}
}finally{$script:token=$null;$auth=$null;$secret=$null}
[ordered]@{tested_at=(Get-Date).ToUniversalTime().ToString('o');project_ref=$identity.project_ref;instance_id=$iid;passed=@($results|Where-Object pass).Count;failed=@($results|Where-Object{-not$_.pass}).Count;results=$results}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot 'production-authorization-evidence.json') -Encoding utf8
$failed=@($results|Where-Object{-not$_.pass}).Count;if($failed){throw "CLEAN_GATEWAY_AUTHORIZATION_FAIL passed=$(@($results|Where-Object pass).Count) failed=$failed"};Write-Output "CLEAN_GATEWAY_AUTHORIZATION_PASS count=$(@($results).Count)"
