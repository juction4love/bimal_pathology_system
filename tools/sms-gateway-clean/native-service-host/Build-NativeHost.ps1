[CmdletBinding()]
param([string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot 'bin' }
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'MSVC Build Tools discovery is unavailable.' }
$vs = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
if (-not $vs) { throw 'MSVC x64 build tools are required.' }
$dev = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$source = Join-Path $PSScriptRoot 'ServiceHost.cpp'
$output = Join-Path (Resolve-Path $OutputDirectory) 'BimalPathologySmsGatewayCleanService.exe'
$command = "call `"$dev`" -arch=x64 -host_arch=x64 >nul && cl.exe /nologo /std:c++20 /EHsc /W4 /WX /O2 /MT /DUNICODE /D_UNICODE `"$source`" /Fe:`"$output`" /link /SUBSYSTEM:CONSOLE advapi32.lib"
& cmd.exe /d /s /c $command
if ($LASTEXITCODE -or -not (Test-Path $output)) { throw 'Native clean Gateway service host build failed.' }
$selfTest = Start-Process -FilePath $output -ArgumentList '--self-test' -NoNewWindow -Wait -PassThru
if ($selfTest.ExitCode) { throw 'Native host self-test failed.' }
Write-Output "CLEAN_NATIVE_HOST_PASS output=$output"
