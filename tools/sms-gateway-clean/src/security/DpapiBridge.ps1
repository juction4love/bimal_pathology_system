param([Parameter(Mandatory=$true)][ValidateSet('Protect','Unprotect')][string]$Action)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Security
$inputText=[Console]::In.ReadToEnd()
if($Action-eq'Protect'){
  $plain=[Text.Encoding]::UTF8.GetBytes($inputText)
  try{$cipher=[Security.Cryptography.ProtectedData]::Protect($plain,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine);[Console]::Out.Write([Convert]::ToBase64String($cipher))}
  finally{[Array]::Clear($plain,0,$plain.Length)}
}else{
  $cipher=[Convert]::FromBase64String($inputText.Trim())
  $plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  try{[Console]::Out.Write([Text.Encoding]::UTF8.GetString($plain))}
  finally{[Array]::Clear($plain,0,$plain.Length)}
}
