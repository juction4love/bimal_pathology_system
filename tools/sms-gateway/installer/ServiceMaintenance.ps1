param(
    [string]$Action = "InstallOrRepair",
    [string]$BinaryPath = "C:\Program Files\Bimal Pathology\SmsGateway\BimalPathology.SmsGateway.exe",
    [int]$TimeoutSeconds = 30
)

$ServiceName = 'BimalPathologySMSGateway'
$dataDirectory = "$env:ProgramData\BimalPathology\SmsGateway"
$logDirectory = Join-Path $dataDirectory 'Logs'
if (-not (Test-Path $logDirectory)) { New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null }
$logFile = Join-Path $logDirectory 'service-maintenance.log'

function Write-DiagLog($msg) {
    Add-Content -Path $logFile -Value "[$(Get-Date -Format o)] $msg"
    Write-Host "Diagnostic log: $msg"
}

function Invoke-Sc($argsList) {
    & sc.exe $argsList
}

function Stop-ServiceSafely($name) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Stopped') {
        Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
    }
}

function Normalize-ServiceBinaryPath($path) {
    if (-not $path) { return "" }
    return $path.Trim().Trim('"')
}

function Wait-ServiceState([string]$DesiredState, [switch]$Starting) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastState = ""
    while ((Get-Date) -lt $deadline) {
        $current = Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'"
        if ($current) {
            $lastState = $current.State
            if ($current.State -notin @('Start Pending', 'Continue Pending')) {
                if ($current.ExitCode -ne 0 -or $current.ServiceSpecificExitCode -ne 0) {
                    Write-DiagLog "Service exited with code $($current.ExitCode) / $($current.ServiceSpecificExitCode)"
                }
                if ($lastState -eq $DesiredState) { return $true }
            }
        }
        Start-Sleep -Milliseconds 750
    }
    return $lastState -eq $DesiredState
}

if ($Action -eq 'InstallOrRepair') {
    Stop-ServiceSafely $ServiceName
    $existing = Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'"
    if ($existing) {
        $quotedBinaryPath = "`"$BinaryPath`""
        $normExisting = Normalize-ServiceBinaryPath $existing.PathName
        $normTarget = Normalize-ServiceBinaryPath $BinaryPath
        if (-not [string]::Equals($normExisting, $normTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
            Invoke-Sc @('config', $ServiceName, "binPath= $quotedBinaryPath")
        }
        if ($existing.StartMode -ne 'Auto') {
            Set-Service -Name $ServiceName -StartupType Automatic
        }
    } else {
        New-Service -Name $ServiceName -BinaryPathName "`"$BinaryPath`"" -DisplayName "Bimal Pathology SMS Gateway" -StartupType Automatic
        Invoke-Sc @('config', $ServiceName, 'obj=', 'LocalSystem')
    }
    Invoke-Sc @('failure', $ServiceName, 'reset= 86400', 'actions= restart/60000/restart/60000/restart/300000')
} elseif ($Action -eq 'Remove') {
    Stop-ServiceSafely $ServiceName
    Invoke-Sc @('delete', $ServiceName)
} elseif ($Action -eq 'Start') {
    Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
    Wait-ServiceState -DesiredState 'Running' -Starting
}
