$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Security
$data=Join-Path $env:ProgramData 'BimalPathology\SmsGatewayV2'
$input=Join-Path $data 'gateway.secrets.bin'
$output=Join-Path $data 'dpapi-runtime-test.json'
$protected=[IO.File]::ReadAllBytes($input)
$plain=[Security.Cryptography.ProtectedData]::Unprotect($protected,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
try{
  $payload=[Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json
  $valid=[bool]($payload.supabaseUrl -and $payload.supabasePublishableKey -and $payload.gatewayEmail -and $payload.gatewayPassword -and $payload.sparrowToken -and $payload.sparrowSender)
  if(-not $valid){throw 'Protected Gateway payload is incomplete.'}
  [ordered]@{passed=$true;identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name;tested_at=(Get-Date).ToUniversalTime().ToString('o')}|ConvertTo-Json|Set-Content $output -Encoding utf8
}finally{
  [Array]::Clear($plain,0,$plain.Length);[Array]::Clear($protected,0,$protected.Length);$payload=$null
}
