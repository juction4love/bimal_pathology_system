[CmdletBinding()]
param([ValidateSet('Install','Uninstall','Start','Stop')][string]$Action='Install',[string]$SourceRoot=$PSScriptRoot,[string]$InstallDirectory="$env:ProgramFiles\BimalPathology\SmsGatewayClean")
$ErrorActionPreference='Stop'
$service='BimalPathologySMSGatewayClean'
$data=Join-Path $env:ProgramData 'BimalPathology\SmsGatewayClean'
if(-not([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator rights are required.'}
function Wait-State([string]$State,[int]$Seconds=60){$until=(Get-Date).AddSeconds($Seconds);do{$s=Get-Service $service -ErrorAction SilentlyContinue;if($s-and$s.Status.ToString()-eq$State){return};Start-Sleep -Milliseconds 500}while((Get-Date)-lt$until);throw "Service did not reach $State."}
switch($Action){
 'Install'{
  $source=(Resolve-Path $SourceRoot).Path
  foreach($required in 'runtime\node.exe','app\src\main.js','BimalPathologySmsGatewayCleanService.exe','SHA256SUMS.txt'){if(-not(Test-Path (Join-Path $source $required))){throw "Clean Gateway package is incomplete: $required"}}
  if(Test-Path $InstallDirectory){throw 'Clean Gateway binaries already exist.'}
  New-Item -ItemType Directory -Force $InstallDirectory|Out-Null;Copy-Item (Join-Path $source '*') $InstallDirectory -Recurse -Force
  New-Item -ItemType Directory -Force $data,(Join-Path $data 'logs')|Out-Null
  & icacls.exe $data '/inheritance:r' '/grant:r' 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' 'LOCAL SERVICE:(OI)(CI)M'|Out-Null;if($LASTEXITCODE){throw 'ProgramData ACL failed.'}
  $hostExe=Join-Path $InstallDirectory 'BimalPathologySmsGatewayCleanService.exe';$quoted='"'+$hostExe+'"'
  & sc.exe create $service binPath= $quoted start= auto obj= 'NT AUTHORITY\LocalService' DisplayName= 'Bimal Pathology SMS Gateway Clean'|Out-Null;if($LASTEXITCODE){throw 'Native service creation failed.'}
  & sc.exe description $service 'Bimal Pathology clean SMS Gateway native host.'|Out-Null
  & sc.exe failure $service reset=3600 actions=restart/10000/restart/30000/restart/60000|Out-Null
 }
 'Uninstall'{if(Get-Service $service -ErrorAction SilentlyContinue){Stop-Service $service -ErrorAction SilentlyContinue;& sc.exe delete $service|Out-Null};Write-Output 'Protected ProgramData was preserved.'}
 'Start'{Start-Service $service;Wait-State Running}
 'Stop'{Stop-Service $service;Wait-State Stopped}
}
