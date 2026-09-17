[CmdletBinding()]
param([string]$DataDirectory="$env:ProgramData\BimalPathology\SmsGatewayClean")
$ErrorActionPreference='Stop'
function Read-Protected([string]$Prompt){$secure=Read-Host $Prompt -AsSecureString;$ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure);try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}}
Add-Type -AssemblyName System.Security
$url=Read-Host 'Supabase project URL';$key=Read-Protected 'Supabase publishable key';$email=Read-Host 'Dedicated Gateway Auth email';$password=Read-Protected 'Dedicated Gateway Auth password';$token=Read-Protected 'Sparrow token';$sender=Read-Host 'Sparrow sender'
$payload=@{supabaseUrl=$url;supabasePublishableKey=$key;gatewayEmail=$email;gatewayPassword=$password;sparrowToken=$token;sparrowSender=$sender}|ConvertTo-Json -Compress
$plain=[Text.Encoding]::UTF8.GetBytes($payload);try{$cipher=[Security.Cryptography.ProtectedData]::Protect($plain,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine);New-Item -ItemType Directory -Force $DataDirectory|Out-Null;[IO.File]::WriteAllText((Join-Path $DataDirectory 'gateway.secrets.dpapi'),[Convert]::ToBase64String($cipher),[Text.Encoding]::ASCII)}finally{[Array]::Clear($plain,0,$plain.Length);$password=$null;$token=$null;$key=$null}
Write-Output 'Clean Gateway secrets provisioned with machine-scope DPAPI; no value displayed.'
