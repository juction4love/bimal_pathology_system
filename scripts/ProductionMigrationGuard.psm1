Set-StrictMode -Version Latest

function Remove-TerminalFormatting {
  param([Parameter(Mandatory)][string]$Text)

  $ansiPattern = ([string][char]27) + '\[[0-?]*[ -/]*[@-~]'
  $clean = [regex]::Replace($Text, $ansiPattern, '')
  return $clean.Replace([char]0x2502, '|').Replace([char]0x2503, '|')
}

function ConvertTo-MigrationVersion {
  param([AllowNull()][string]$Value)

  if ($null -eq $Value) { return $null }
  $candidate = $Value.Trim().Trim('`').Trim()
  if ($candidate -match '^(?<version>[0-9]{5})(?:_[A-Za-z0-9_.-]+\.sql)?$') {
    return $Matches.version
  }
  return $null
}

function New-MigrationLedgerResult {
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Local,
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Remote,
    [Parameter(Mandatory)][string]$Format
  )

  $localVersions = @($Local | Sort-Object)
  $remoteVersions = @($Remote | Sort-Object)
  if ($localVersions.Count -eq 0 -or $remoteVersions.Count -eq 0) {
    throw 'Migration ledger is incomplete: both local and remote version sets are required.'
  }
  if (@($localVersions | Select-Object -Unique).Count -ne $localVersions.Count) {
    throw 'Migration ledger is ambiguous: duplicate local versions were returned.'
  }
  if (@($remoteVersions | Select-Object -Unique).Count -ne $remoteVersions.Count) {
    throw 'Migration ledger is ambiguous: duplicate remote versions were returned.'
  }
  $unknownRemote = @($remoteVersions | Where-Object { $_ -notin $localVersions })
  if ($unknownRemote.Count -gt 0) {
    throw "Migration ledger contains remote versions absent locally: $($unknownRemote -join ', ')."
  }

  [pscustomobject]@{
    Format = $Format
    LocalVersions = $localVersions
    RemoteVersions = $remoteVersions
    LocalHead = $localVersions[-1]
    RemoteHead = $remoteVersions[-1]
    PendingVersions = @($localVersions | Where-Object { $_ -notin $remoteVersions })
  }
}

function ConvertFrom-SupabaseMigrationListOutput {
  param([Parameter(Mandatory)][string]$Output)

  $clean = Remove-TerminalFormatting -Text $Output
  $jsonCandidates = @($clean -split "`r?`n" | Where-Object { $_ -match '^\s*\{.*"migrations"\s*:' })
  if ($jsonCandidates.Count -gt 1) {
    throw 'Migration ledger is ambiguous: multiple JSON ledgers were returned.'
  }
  if ($jsonCandidates.Count -eq 1) {
    try { $payload = $jsonCandidates[0] | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Migration ledger JSON is malformed: $($_.Exception.Message)" }
    if ($null -eq $payload.migrations) { throw 'Migration ledger JSON does not contain migrations.' }
    $local = @()
    $remote = @()
    foreach ($entry in @($payload.migrations)) {
      $localVersion = ConvertTo-MigrationVersion -Value ([string]$entry.local)
      $remoteVersion = ConvertTo-MigrationVersion -Value ([string]$entry.remote)
      if ($entry.local -and -not $localVersion) { throw "Malformed local migration version '$($entry.local)'." }
      if ($entry.remote -and -not $remoteVersion) { throw "Malformed remote migration version '$($entry.remote)'." }
      if ($localVersion) { $local += $localVersion }
      if ($remoteVersion) { $remote += $remoteVersion }
    }
    return New-MigrationLedgerResult -Local $local -Remote $remote -Format 'json'
  }

  $lines = @($clean -split "`r?`n")
  $headerIndex = -1
  for ($index = 0; $index -lt $lines.Count; $index++) {
    $headerCells = @($lines[$index] -split '\|' | ForEach-Object { $_.Trim().Trim('`').Trim() })
    if ($headerCells.Count -ge 2 -and $headerCells[0] -eq 'Local' -and $headerCells[1] -eq 'Remote') {
      if ($headerIndex -ge 0) { throw 'Migration ledger is ambiguous: multiple table headers were returned.' }
      $headerIndex = $index
    }
  }
  if ($headerIndex -lt 0) { throw 'Unable to identify a Supabase migration ledger in CLI output.' }

  $local = @()
  $remote = @()
  $dataRows = 0
  foreach ($line in $lines[($headerIndex + 1)..($lines.Count - 1)]) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*[-+|: ]+\s*$') { continue }
    if ($line -notmatch '\|') { continue }
    $trimmedLine = $line.Trim()
    $cells = @($line -split '\|' | ForEach-Object { $_.Trim().Trim('`').Trim() })
    if ($trimmedLine.StartsWith('|') -and $cells.Count -gt 2) { $cells = @($cells[1..($cells.Count - 1)]) }
    if ($trimmedLine.EndsWith('|') -and $cells.Count -gt 2) { $cells = @($cells[0..($cells.Count - 2)]) }
    if ($cells.Count -lt 2) { throw "Malformed migration ledger row: '$line'." }
    $localVersion = ConvertTo-MigrationVersion -Value $cells[0]
    $remoteVersion = ConvertTo-MigrationVersion -Value $cells[1]
    if ($cells[0] -and -not $localVersion) { throw "Malformed local migration cell '$($cells[0])'." }
    if ($cells[1] -and -not $remoteVersion) { throw "Malformed remote migration cell '$($cells[1])'." }
    if (-not $localVersion -and -not $remoteVersion) { throw "Ambiguous empty migration ledger row: '$line'." }
    if ($localVersion) { $local += $localVersion }
    if ($remoteVersion) { $remote += $remoteVersion }
    $dataRows++
  }
  if ($dataRows -eq 0) { throw 'Migration ledger table contains no migration rows.' }
  return New-MigrationLedgerResult -Local $local -Remote $remote -Format 'table'
}

function Assert-ExactStringSet {
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Actual,
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Expected,
    [Parameter(Mandatory)][string]$Label
  )

  $actualSorted = @($Actual | Sort-Object)
  $expectedSorted = @($Expected | Sort-Object)
  if (($actualSorted -join '|') -ne ($expectedSorted -join '|')) {
    throw "$Label mismatch. Expected [$($expectedSorted -join ', ')], got [$($actualSorted -join ', ')]."
  }
}

function Assert-ProductionMigrationPlan {
  param(
    [Parameter(Mandatory)]$Ledger,
    [Parameter(Mandatory)][string[]]$ExpectedLocalVersions,
    [Parameter(Mandatory)][string]$ExpectedCurrentHead,
    [Parameter(Mandatory)][string]$ExpectedTargetHead,
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ExpectedPendingVersions
  )

  if ($Ledger.LocalHead -ne $ExpectedTargetHead) {
    throw "Local migration head mismatch. Expected $ExpectedTargetHead, got $($Ledger.LocalHead)."
  }
  if ($Ledger.RemoteHead -ne $ExpectedCurrentHead) {
    throw "Remote migration head mismatch. Expected $ExpectedCurrentHead, got $($Ledger.RemoteHead)."
  }
  Assert-ExactStringSet -Actual $Ledger.LocalVersions -Expected $ExpectedLocalVersions -Label 'Local migration ledger'
  Assert-ExactStringSet -Actual $Ledger.PendingVersions -Expected $ExpectedPendingVersions -Label 'Pending migration set'
  $expectedRemote = @($ExpectedLocalVersions | Where-Object { $_ -notin $ExpectedPendingVersions })
  Assert-ExactStringSet -Actual $Ledger.RemoteVersions -Expected $expectedRemote -Label 'Remote migration ledger'
}

function ConvertFrom-SupabaseDryRunOutput {
  param([Parameter(Mandatory)][string]$Output)

  $clean = Remove-TerminalFormatting -Text $Output
  $jsonCandidates = @($clean -split "`r?`n" | Where-Object { $_ -match '^\s*\{.*"migrations"\s*:' })
  if ($jsonCandidates.Count -gt 1) { throw 'Dry-run output is ambiguous: multiple JSON payloads were returned.' }
  if ($jsonCandidates.Count -eq 1) {
    try { $payload = $jsonCandidates[0] | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Dry-run JSON is malformed: $($_.Exception.Message)" }
    $files = @()
    foreach ($migration in @($payload.migrations)) {
      $name = if ($migration -is [string]) { $migration } elseif ($migration.name) { [string]$migration.name } else { '' }
      if ($name -notmatch '^(?<file>[0-9]{5}_[A-Za-z0-9_.-]+\.sql)$') { throw "Malformed dry-run migration '$name'." }
      $files += $Matches.file
    }
    return @($files)
  }

  $files = @()
  foreach ($line in ($clean -split "`r?`n")) {
    if ($line -match '^\s*[•*+\-]\s*`?(?<file>[0-9]{5}_[A-Za-z0-9_.-]+\.sql)`?\s*$') {
      $files += $Matches.file
    }
  }
  if ($files.Count -eq 0 -and $clean -notmatch '(?i)(up to date|no migrations|already current)') {
    throw 'Unable to identify the pending migration list in Supabase dry-run output.'
  }
  if (@($files | Select-Object -Unique).Count -ne $files.Count) {
    throw 'Dry-run output is ambiguous: duplicate migration filenames were returned.'
  }
  return @($files)
}

function Assert-ProductionProjectTarget {
  param(
    [Parameter(Mandatory)][string]$Environment,
    [Parameter(Mandatory)][string]$ProjectRef,
    [Parameter(Mandatory)][string]$ExpectedProjectRef
  )

  if ($Environment -cne 'production') { throw "Environment mismatch. Expected production, got '$Environment'." }
  if ($ProjectRef -cne $ExpectedProjectRef) { throw "Project ref mismatch. Expected $ExpectedProjectRef, got '$ProjectRef'." }
}

Export-ModuleMember -Function ConvertFrom-SupabaseMigrationListOutput, Assert-ProductionMigrationPlan, ConvertFrom-SupabaseDryRunOutput, Assert-ExactStringSet, Assert-ProductionProjectTarget
