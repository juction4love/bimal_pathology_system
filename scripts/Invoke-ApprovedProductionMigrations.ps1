param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('DryRun')]
    [string]$Operation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]$env:FOUNDATION_PROJECT_REF -cne 'rncjxstujioagcezvfkb') {
    throw 'FOUNDATION_PROJECT_REF must be the exact production project.'
}
if ([string]$env:FOUNDATION_TARGET_ENVIRONMENT -cne 'production-cutover') {
    throw 'FOUNDATION_TARGET_ENVIRONMENT must be production-cutover.'
}

Write-Host '[NOTICE] This compatibility entry point performs the guarded 00075-to-00079 dry-run only.'
Write-Host '[NOTICE] Deferred cloud-SMS 00070 must remain outside deployable migrations.'
& node (Join-Path $PSScriptRoot 'production-foundation-cutover-guard.js')
if ($LASTEXITCODE -ne 0) {
    throw "Production candidate dry-run guard failed with exit code $LASTEXITCODE."
}
