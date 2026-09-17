Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ProductionMigrationGuard.psm1') -Force

$passed = 0
function Pass([string]$Name) {
    $script:passed++
    Write-Host "PASS: $Name"
}
function Expect-Throw([string]$Name, [scriptblock]$Action, [string]$Pattern) {
    try {
        & $Action
        throw "Expected failure did not occur: $Name"
    } catch {
        if ($_.Exception.Message -like 'Expected failure did not occur:*') { throw }
        if ($_.Exception.Message -notmatch $Pattern) {
            throw "Unexpected failure for '$Name': $($_.Exception.Message)"
        }
        Pass $Name
    }
}

$versions = @('00049', '00050', '00051', '00052', '00053')
$normalTable = @'
Connecting to remote database...

  Local | Remote | Time (UTC)
 --------|--------|------------
  00049 | 00049  |
  00050 | 00050  |
  00051 | 00051  |
  00052 | 00052  |
  00053 |        |
'@
$ledger = ConvertFrom-SupabaseMigrationListOutput -Output $normalTable
Assert-ProductionMigrationPlan -Ledger $ledger -ExpectedLocalVersions $versions -ExpectedCurrentHead '00052' -ExpectedTargetHead '00053' -ExpectedPendingVersions @('00053')
if ($ledger.Format -ne 'table') { throw 'Normal table was not parsed as table format.' }
Pass 'normal table output'

$escape = [char]27
$ansiTable = "$escape[32m``Local``$escape[0m │ ``Remote`` │ Time (UTC)`n────────┼────────┼──────────`n``00049`` │ ``00049`` │`n``00050`` │ ``00050`` │`n``00051`` │ ``00051`` │`n``00052`` │ ``00052`` │`n``00053`` │ `` ``     │"
$ansiLedger = ConvertFrom-SupabaseMigrationListOutput -Output $ansiTable
Assert-ProductionMigrationPlan -Ledger $ansiLedger -ExpectedLocalVersions $versions -ExpectedCurrentHead '00052' -ExpectedTargetHead '00053' -ExpectedPendingVersions @('00053')
Pass 'ANSI and backtick table output'

$missingRemote = @'
 Local | Remote
-------|-------
 00049 | 00049
 00050 |
 00051 |
 00052 |
 00053 |
'@
Expect-Throw 'missing expected remote version' {
    $item = ConvertFrom-SupabaseMigrationListOutput -Output $missingRemote
    Assert-ProductionMigrationPlan -Ledger $item -ExpectedLocalVersions $versions -ExpectedCurrentHead '00052' -ExpectedTargetHead '00053' -ExpectedPendingVersions @('00053')
} 'Remote migration head mismatch'

$unexpectedHead = @'
 Local | Remote
-------|-------
 00049 | 00049
 00050 | 00050
 00051 | 00051
 00052 |
 00053 |
'@
Expect-Throw 'unexpected remote head' {
    $item = ConvertFrom-SupabaseMigrationListOutput -Output $unexpectedHead
    Assert-ProductionMigrationPlan -Ledger $item -ExpectedLocalVersions $versions -ExpectedCurrentHead '00052' -ExpectedTargetHead '00053' -ExpectedPendingVersions @('00053')
} 'Remote migration head mismatch'

$extraVersions = @('00049', '00050', '00051', '00052', '00053', '00054')
$extraPending = @'
 Local | Remote
-------|-------
 00049 | 00049
 00050 | 00050
 00051 | 00051
 00052 | 00052
 00053 |
 00054 |
'@
Expect-Throw 'extra pending migration' {
    $item = ConvertFrom-SupabaseMigrationListOutput -Output $extraPending
    Assert-ProductionMigrationPlan -Ledger $item -ExpectedLocalVersions $extraVersions -ExpectedCurrentHead '00052' -ExpectedTargetHead '00053' -ExpectedPendingVersions @('00053')
} 'Local migration head mismatch'

Expect-Throw 'malformed CLI output' {
    ConvertFrom-SupabaseMigrationListOutput -Output 'Connected successfully, but no ledger was rendered.'
} 'Unable to identify'

Expect-Throw 'production/staging project mismatch' {
    Assert-ProductionProjectTarget -Environment 'production' -ProjectRef 'qvuidmgddjoircheapzk' -ExpectedProjectRef 'rncjxstujioagcezvfkb'
} 'Project ref mismatch'

$dryRun = @'
DRY RUN: migrations would be applied:
 • `00053_technician_rbac_convergence.sql`
'@
$dryRunFiles = @(ConvertFrom-SupabaseDryRunOutput -Output $dryRun)
Assert-ExactStringSet -Actual $dryRunFiles -Expected @('00053_technician_rbac_convergence.sql') -Label 'Dry-run fixture'
Pass 'normal dry-run output'

$jsonLedger = '{"migrations":[{"local":"00049","remote":"00049"},{"local":"00050","remote":"00050"},{"local":"00051","remote":"00051"},{"local":"00052","remote":"00052"},{"local":"00053","remote":null}]}'
$jsonResult = ConvertFrom-SupabaseMigrationListOutput -Output $jsonLedger
Assert-ProductionMigrationPlan -Ledger $jsonResult -ExpectedLocalVersions $versions -ExpectedCurrentHead '00052' -ExpectedTargetHead '00053' -ExpectedPendingVersions @('00053')
Pass 'machine-readable output compatibility'

if ($passed -ne 9) { throw "Expected 9 guard tests, passed $passed." }
Write-Host "Production migration guard regression: $passed/9 PASS"
