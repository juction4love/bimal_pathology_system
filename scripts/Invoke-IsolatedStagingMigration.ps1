param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Reconcile00051', 'DryRun', 'Push', 'DryRun00052', 'Push00052', 'DryRun00053', 'Push00053', 'Verify00053')]
    [string]$Operation
)

$ErrorActionPreference = 'Stop'
$expectedProjectRef = 'ilcnctiaumrjbnlmnise'
$retiredProjectRef = 'qvuidmgddjoircheapzk'
$productionProjectRef = 'rncjxstujioagcezvfkb'
$expectedConfirmation = "I_CONFIRM_SYNTHETIC_STAGING_$expectedProjectRef"

if ($env:STAGING_ENVIRONMENT -ne 'isolated-staging') {
    throw 'STAGING_ENVIRONMENT must equal isolated-staging.'
}
if ($env:STAGING_PROJECT_REF -eq $retiredProjectRef) {
    throw 'Retired staging project qvuidmgddjoircheapzk is permanently refused.'
}
if ($env:STAGING_PROJECT_REF -ne $expectedProjectRef) {
    throw "Refusing project '$($env:STAGING_PROJECT_REF)'; expected isolated staging '$expectedProjectRef'."
}
if ($env:STAGING_PROJECT_REF -eq $productionProjectRef) {
    throw 'Production project reference detected. Aborting before mutation.'
}
if ($env:STAGING_CONFIRMATION -ne $expectedConfirmation) {
    throw 'Explicit isolated-staging confirmation is missing or invalid.'
}

$ledgerOutput = & npx supabase migration list --project-ref $expectedProjectRef
if ($LASTEXITCODE -ne 0) { throw 'Unable to read isolated staging migration ledger.' }
$ledgerJsonLine = $ledgerOutput | Where-Object { $_ -match '^\{"migrations"' } | Select-Object -Last 1
if (-not $ledgerJsonLine) { throw 'Supabase CLI did not return a machine-readable migration ledger.' }
$ledger = $ledgerJsonLine | ConvertFrom-Json
$remoteVersions = @($ledger.migrations | Where-Object { $_.remote } | ForEach-Object { $_.remote } | Sort-Object)
$head = $remoteVersions | Select-Object -Last 1

$proof = [ordered]@{
    environment = $env:STAGING_ENVIRONMENT
    project_ref = $env:STAGING_PROJECT_REF
    expected_project_ref = $expectedProjectRef
    production_project_ref = $productionProjectRef
    migration_head = $head
    operation = $Operation
    mutation_guard = 'PASS'
}
Write-Host "[STAGING MUTATION GUARD] $($proof | ConvertTo-Json -Compress)"

switch ($Operation) {
    'Reconcile00051' {
        if ($head -ne '00051') { throw "Reconcile00051 requires staging head 00051; actual head is '$head'." }
        & npx supabase migration repair 00051 --status reverted --project-ref $expectedProjectRef
    }
    'DryRun' {
        if ($head -ne '00050') { throw "DryRun requires staging head 00050 after explicit reconciliation; actual head is '$head'." }
        & npx supabase db push --dry-run --project-ref $expectedProjectRef
    }
    'Push' {
        if ($head -ne '00050') { throw "Push requires staging head 00050 after explicit reconciliation; actual head is '$head'." }
        & npx supabase db push --project-ref $expectedProjectRef
    }
    'DryRun00052' {
        if ($head -ne '00051') { throw "DryRun00052 requires staging head 00051; actual head is '$head'." }
        & npx supabase db push --dry-run --project-ref $expectedProjectRef
    }
    'Push00052' {
        if ($head -ne '00051') { throw "Push00052 requires staging head 00051; actual head is '$head'." }
        & npx supabase db push --project-ref $expectedProjectRef
    }
    'DryRun00053' {
        if ($head -ne '00052') { throw "DryRun00053 requires staging head 00052; actual head is '$head'." }
        & npx supabase db push --dry-run --project-ref $expectedProjectRef
    }
    'Push00053' {
        if ($head -ne '00052') { throw "Push00053 requires staging head 00052; actual head is '$head'." }
        & npx supabase db push --project-ref $expectedProjectRef
    }
    'Verify00053' {
        if ($head -ne '00053') { throw "Verify00053 requires staging head 00053; actual head is '$head'." }
    }
}

if ($LASTEXITCODE -ne 0) { throw "Supabase CLI operation '$Operation' failed." }
