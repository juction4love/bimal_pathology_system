# Build Script for SMS Gateway Installer
$ErrorActionPreference = "Stop"

Write-Host "Running tests..."
dotnet test

Write-Host "Publishing self-contained win-x64 binary..."
dotnet publish -c Release -r win-x64 --self-contained true -o ./publish

Write-Host "Compiling Inno Setup installer..."
$iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
$script = [scriptblock]::Create("& `"$iscc`" ./installer/BimalPathologySmsGateway.iss")
& $script

Write-Host "Verifying BimalPathology_SMSGateway_1.0.4_Updater.exe output..."
