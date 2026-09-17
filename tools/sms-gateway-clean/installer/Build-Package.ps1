[CmdletBinding()]
param([string]$NodeVersion='24.20.0')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent;$stage=Join-Path $root 'artifacts\package';$cache=Join-Path $root 'artifacts\cache';New-Item -ItemType Directory -Force $cache|Out-Null
function Get-Sha256([string]$Path){$stream=[IO.File]::OpenRead($Path);try{$sha=[Security.Cryptography.SHA256]::Create();try{return([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}finally{$stream.Dispose()}}
& npm --prefix $root run build;if($LASTEXITCODE){throw 'Clean Gateway build failed.'}
& (Join-Path $root 'native-service-host\Build-NativeHost.ps1');if($LASTEXITCODE){throw 'Native host build failed.'}
$nodeZip=Join-Path $cache "node-v$NodeVersion-win-x64.zip";$sums=Join-Path $cache "SHASUMS256-$NodeVersion.txt"
if(-not(Test-Path $nodeZip)-or-not(Test-Path $sums)){throw 'Verified Node 24 archive and official SHASUMS file must be staged in artifacts/cache.'}
$expected=((Select-String $sums -Pattern "  node-v$([regex]::Escape($NodeVersion))-win-x64.zip$").Line-split'\s+')[0].ToLowerInvariant()
if((Get-Sha256 $nodeZip)-ne$expected){throw 'Node runtime hash failed.'}
if(Test-Path $stage){Remove-Item $stage -Recurse -Force};New-Item -ItemType Directory -Force (Join-Path $stage 'runtime'),(Join-Path $stage 'app')|Out-Null
Expand-Archive $nodeZip (Join-Path $stage 'node-expanded');$nodeDir=Get-ChildItem (Join-Path $stage 'node-expanded') -Directory|Select-Object -First 1
Copy-Item (Join-Path $nodeDir.FullName 'node.exe') (Join-Path $stage 'runtime\node.exe');Copy-Item (Join-Path $root 'dist\src') (Join-Path $stage 'app') -Recurse
Copy-Item (Join-Path $root 'src\security\DpapiBridge.ps1') (Join-Path $stage 'app\src\security\DpapiBridge.ps1') -Force
Copy-Item (Join-Path $root 'native-service-host\bin\BimalPathologySmsGatewayCleanService.exe') $stage
Copy-Item (Join-Path $PSScriptRoot 'Install-Service.ps1'),(Join-Path $PSScriptRoot 'Provision-Secrets.ps1') $stage
Remove-Item (Join-Path $stage 'node-expanded') -Recurse -Force
Get-ChildItem $stage -Recurse -File|ForEach-Object{"$(Get-Sha256 $_.FullName)  $($_.FullName.Substring($stage.Length+1))"}|Set-Content (Join-Path $stage 'SHA256SUMS.txt') -Encoding ascii
$zip=Join-Path (Split-Path $stage -Parent) 'BimalPathology_SMSGateway_Clean_2.0.0_win-x64.zip';if(Test-Path $zip){Remove-Item $zip -Force};Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
Write-Output "CLEAN_GATEWAY_PACKAGE_PASS zip=$zip sha256=$(Get-Sha256 $zip)"
