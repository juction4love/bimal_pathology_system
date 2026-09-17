# PowerShell Installer for Bimal Pathology SMS Gateway Windows Service
param(
    [string]$ServiceBinaryPath = "C:\BimalPathology\SmsGateway\BimalPathology.SmsGateway.exe"
)

$ServiceName = "BimalPathologySMSGateway"
$DisplayName = "Bimal Pathology Transactional SMS Gateway"
$Description = "Pulls and dispatches transactional SMS notifications for Bimal Pathology Cloud LIS."

New-Service -Name $ServiceName -BinaryPathName $ServiceBinaryPath -DisplayName $DisplayName -Description $Description -StartupType Automatic
Write-Host "Service $ServiceName registered successfully with StartupType Automatic."
