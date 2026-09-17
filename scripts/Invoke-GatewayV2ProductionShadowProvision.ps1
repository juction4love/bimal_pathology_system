[CmdletBinding()]
param(
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
  [string]$DataDirectory = "$env:ProgramData\BimalPathology\SmsGatewayV2"
)
$ErrorActionPreference='Stop';Add-Type -AssemblyName System.Security
if(-not([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator rights are required.'}
$projectRef='rncjxstujioagcezvfkb';$url='https://rncjxstujioagcezvfkb.supabase.co';$email='gateway-v2-production@service.bimalpathology.internal'
$envPath=Join-Path $ProjectRoot '.env.production';$v1Path="$env:ProgramData\BimalPathology\SmsGateway\gateway.secrets.bin"
foreach($p in @($envPath,$v1Path)){if(-not(Test-Path -LiteralPath $p)){throw "Required protected input missing: $p"}}
$v1Protected=[IO.File]::ReadAllBytes($v1Path);$entropy=[Text.Encoding]::UTF8.GetBytes('BimalPathology.SmsGateway.v1');$v1Plain=[Security.Cryptography.ProtectedData]::Unprotect($v1Protected,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
try{$v1=([Text.Encoding]::UTF8.GetString($v1Plain)|ConvertFrom-Json);$sparrowToken=[string]$v1.SparrowSmsToken;$sparrowSender=[string]$v1.SparrowSmsFrom;if(-not$sparrowSender){$sparrowSender='TheAlert'}}finally{[Array]::Clear($v1Plain,0,$v1Plain.Length);[Array]::Clear($v1Protected,0,$v1Protected.Length)}
$keyJson=(& npx supabase projects api-keys --project-ref $projectRef --output json 2>&1|Out-String)|ConvertFrom-Json;$serviceKey=[string](($keyJson|Where-Object{$_.id-eq'service_role' -and $_.type-eq'legacy'}|Select-Object -First 1).api_key);$keyJson=$null
$publishable=((Get-Content $envPath|Where-Object{$_-match '^VITE_SUPABASE_ANON_KEY='}|Select-Object -First 1)-split'=',2)[1].Trim()
if(-not$serviceKey-or-not$publishable){throw 'Supabase credential source is incomplete.'}
$headers=@{apikey=$serviceKey;Authorization="Bearer $serviceKey"};$existing=Invoke-RestMethod "$url/auth/v1/admin/users?page=1&per_page=1000" -Headers $headers
if(@($existing.users|Where-Object{$_.email-eq$email}).Count){throw 'Dedicated Gateway production Auth identity already exists; refusing duplicate provisioning.'}
$random=New-Object byte[] 48;[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($random);$password=[Convert]::ToBase64String($random).TrimEnd('=').Replace('+','-').Replace('/','_');[Array]::Clear($random,0,$random.Length)
$user=$null;$registered=$false
try{
  $body=@{email=$email;password=$password;email_confirm=$true;app_metadata=@{service_identity='sms_gateway_v2';project_ref=$projectRef;human=$false}}|ConvertTo-Json -Depth 5 -Compress
  $user=Invoke-RestMethod "$url/auth/v1/admin/users" -Method Post -Headers $headers -ContentType 'application/json' -Body $body
  if(-not$user.id){throw 'Gateway Auth identity creation returned no UID.'}
  $instanceId=[guid]::NewGuid().ToString();$hostname=[Environment]::MachineName
  [IO.Directory]::CreateDirectory($DataDirectory)|Out-Null;[IO.Directory]::CreateDirectory((Join-Path $DataDirectory 'logs'))|Out-Null
  & icacls.exe $DataDirectory '/inheritance:r' '/grant:r' 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' 'LOCAL SERVICE:(OI)(CI)M'|Out-Null;if($LASTEXITCODE){throw 'Gateway V2 ProgramData ACL failed.'}
  if(-not$sparrowToken){throw 'Gateway 1.x Sparrow token was not recognized.'}
  $secretJson=@{supabaseUrl=$url;supabasePublishableKey=$publishable;gatewayEmail=$email;gatewayPassword=$password;sparrowToken=$sparrowToken;sparrowSender=$sparrowSender}|ConvertTo-Json -Compress;$plain=[Text.Encoding]::UTF8.GetBytes($secretJson);$protected=[Security.Cryptography.ProtectedData]::Protect($plain,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  try{$secretPath=Join-Path $DataDirectory 'gateway.secrets.bin';[IO.File]::WriteAllBytes("$secretPath.new",$protected);Move-Item "$secretPath.new" $secretPath -Force;& icacls.exe $secretPath '/inheritance:r' '/grant:r' 'SYSTEM:F' 'Administrators:F' 'LOCAL SERVICE:R'|Out-Null;if($LASTEXITCODE){throw 'Gateway V2 secret ACL failed.'}}finally{[Array]::Clear($plain,0,$plain.Length);[Array]::Clear($protected,0,$protected.Length)}
  $config=[ordered]@{instanceId=$instanceId;version='2.0.0-shadow.1';mode='shadow';pollMs=3000;heartbeatMs=45000;rpcTimeoutMs=15000;providerTimeoutMs=30000;leaseSeconds=300;claimBatchSize=2;maxConcurrency=2;maxSegments=4;shutdownMs=45000;dataDirectory=$DataDirectory};$config|ConvertTo-Json|Set-Content (Join-Path $DataDirectory 'gateway.config.json') -Encoding utf8
  $login=(& npx supabase db dump --linked --data-only --dry-run --log-level error 2>&1|Out-String);$dbHost=[regex]::Match($login,'export PGHOST="([^"]+)"').Groups[1].Value;$dbPort=[regex]::Match($login,'export PGPORT="([^"]+)"').Groups[1].Value;$dbUser=[regex]::Match($login,'export PGUSER="([^"]+)"').Groups[1].Value;$dbPassword=[regex]::Match($login,'export PGPASSWORD="([^"]+)"').Groups[1].Value;$dbName=[regex]::Match($login,'export PGDATABASE="([^"]+)"').Groups[1].Value;$login=$null;$env:PGPASSWORD=$dbPassword
  try{$psql='C:\Program Files\PostgreSQL\17\bin\psql.exe';$admin=(& $psql -X -qAt -P pager=off -v ON_ERROR_STOP=1 -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SET ROLE postgres;SELECT id FROM public.user_profiles WHERE is_active AND is_super_admin ORDER BY created_at LIMIT 1;"|Select-Object -Last 1).Trim();if($LASTEXITCODE-or-not$admin){throw 'No active Super Admin is available for guarded registration.'};$claims=(@{sub=$admin;role='authenticated'}|ConvertTo-Json -Compress).Replace("'","''");$sql="SET ROLE postgres;SELECT set_config('request.jwt.claims','$claims',false);SET ROLE authenticated;SELECT public.register_sms_gateway_v2_instance('$instanceId'::uuid,'$($user.id)'::uuid,'$hostname','2.0.0-shadow.1','Sparrow');";& $psql -X -qAt -P pager=off -v ON_ERROR_STOP=1 -h $dbHost -p $dbPort -U $dbUser -d $dbName -c $sql|Out-Null;if($LASTEXITCODE){throw 'Guarded Gateway registration failed.'};$registered=$true}finally{$env:PGPASSWORD=$null;$dbPassword=$null}
  [ordered]@{project_ref=$projectRef;auth_user_id=$user.id;instance_id=$instanceId;service_email=$email;mode='shadow';claiming_enabled=$false;version='2.0.0-shadow.1';created_at=(Get-Date).ToUniversalTime().ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $ProjectRoot '.recovery-work\gateway-v2-production-shadow-provision.json') -Encoding utf8
  Write-Output "GATEWAY_V2_SHADOW_PROVISION_PASS uid=$($user.id) instance=$instanceId"
}catch{
  if($user-and-not$registered){try{Invoke-RestMethod "$url/auth/v1/admin/users/$($user.id)" -Method Delete -Headers $headers|Out-Null}catch{}}
  throw
}finally{$password=$null;$serviceKey=$null;$publishable=$null;$sparrowToken=$null;$sparrowSender=$null;$secretJson=$null;$body=$null}
