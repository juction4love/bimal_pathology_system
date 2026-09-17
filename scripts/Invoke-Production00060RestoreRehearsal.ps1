[CmdletBinding()]
param(
  [string]$RestoreUser = 'bimal_restore_operator',
  [string]$HostName = '127.0.0.1',
  [int]$Port = 5432,
  [string]$MaintenanceDatabase = 'postgres'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$backupDir = Join-Path $root 'backups\production-00060-recovery-20260828-193500'
$archive = Join-Path $backupDir 'full.dump'
$verificationSql = Join-Path $PSScriptRoot 'restore-00060-verification.sql'
$expectedHash = '65f3a045e6ea11af5144a0611bcf00e8b15a73c0cf0919cb8827e3fc1d890f4c'
$bin = 'C:\Program Files\PostgreSQL\17\bin'
$psql = Join-Path $bin 'psql.exe'
$pgRestore = Join-Path $bin 'pg_restore.exe'

foreach ($file in @($archive,$verificationSql,$psql,$pgRestore)) {
  if (-not (Test-Path -LiteralPath $file)) { throw "Required file missing: $file" }
}
if ($HostName -ne '127.0.0.1' -or $Port -ne 5432) { throw 'Restore target is fail-closed to local PostgreSQL 127.0.0.1:5432.' }
if ($env:PGPASSWORD) { throw 'PGPASSWORD must not be set. This workflow requires native interactive authentication.' }

$actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash) { throw "BACKUP_HASH_MISMATCH: expected $expectedHash, got $actualHash" }
$toc = & $pgRestore --list $archive
if ($LASTEXITCODE -ne 0 -or $toc.Count -lt 900) { throw 'CUSTOM_ARCHIVE_VALIDATION_FAILED' }

$clientVersion = (& $psql --version) -join ''
$restoreVersion = (& $pgRestore --version) -join ''
$dbName = 'bimal_pathology_restore_00060_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
if ($dbName -notmatch '^bimal_pathology_restore_00060_[0-9]{8}_[0-9]{6}$') { throw 'Unsafe disposable database name.' }

Write-Host 'Interactive authentication is required. Codex/script does not receive or store the password.'
Write-Host "Checking local role compatibility on $HostName`:$Port ..."
$roleJson = & $psql -X -W -qAt -h $HostName -p $Port -U $RestoreUser -d $MaintenanceDatabase -c "SELECT json_build_object('server_version',current_setting('server_version'),'current_user',current_user,'missing_roles',ARRAY(SELECT x FROM unnest(ARRAY['anon','authenticated','service_role']) x WHERE NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=x)))::text;"
if ($LASTEXITCODE -ne 0) { throw 'LOCAL_AUTHENTICATION_OR_ROLE_PREFLIGHT_FAILED' }
$roleEvidence = ($roleJson | Select-Object -Last 1) | ConvertFrom-Json
if (@($roleEvidence.missing_roles).Count -gt 0) {
  throw "MISSING_SUPABASE_COMPATIBILITY_ROLES: $(@($roleEvidence.missing_roles) -join ', '). A human administrator must create only these as NOLOGIN roles."
}

$created = $false
$evidencePath = Join-Path $backupDir 'restore-rehearsal-00060.json'
try {
  Write-Host "Creating disposable local database $dbName ..."
  & $psql -X -W -v ON_ERROR_STOP=1 -h $HostName -p $Port -U $RestoreUser -d $MaintenanceDatabase -c "CREATE DATABASE $dbName ENCODING 'UTF8' TEMPLATE template0;"
  if ($LASTEXITCODE -ne 0) { throw 'DISPOSABLE_DATABASE_CREATE_FAILED' }
  $created = $true

  $started = Get-Date
  Write-Host 'Restoring custom archive. Any material pg_restore error stops the rehearsal.'
  & $pgRestore -W --exit-on-error --no-owner --no-privileges -h $HostName -p $Port -U $RestoreUser -d $dbName $archive
  $restoreExit = $LASTEXITCODE
  $duration = [math]::Round(((Get-Date)-$started).TotalSeconds,3)
  if ($restoreExit -ne 0) { throw "RESTORE_FAILED_EXIT_$restoreExit" }

  Write-Host 'Running migration, aggregate, lineage, schema and security verification ...'
  $verificationOutput = & $psql -X -W -qAt -v ON_ERROR_STOP=1 -h $HostName -p $Port -U $RestoreUser -d $dbName -f $verificationSql
  if ($LASTEXITCODE -ne 0) { throw 'RESTORE_VERIFICATION_SQL_FAILED' }
  $verification = ($verificationOutput | Where-Object { $_ -match '^\{' } | Select-Object -Last 1) | ConvertFrom-Json
  if ($verification.migration_head -ne '00060' -or [int]$verification.has_000565 -ne 1 -or [int]$verification.forbidden_versions -ne 0 -or [int]$verification.duplicate_versions -ne 0) { throw 'RESTORED_MIGRATION_LEDGER_MISMATCH' }
  $expectedCounts = @{patients=20;bills=21;clinical_orders=21;order_items=36;samples=26;results=165;reports=20;public_tokens=20;sms_rows=40;audit_rows=265}
  foreach($key in $expectedCounts.Keys){if([int]$verification.counts.$key -ne $expectedCounts[$key]){throw "RESTORED_COUNT_MISMATCH_$key"}}
  foreach($property in $verification.violations.PSObject.Properties){if([int]$property.Value -ne 0){throw "RESTORED_INTEGRITY_VIOLATION_$($property.Name)"}}
  if([int]$verification.objects.six_argument_save_results -ne 1 -or [int]$verification.objects.public_report_resolver -lt 1 -or [int]$verification.objects.collection_readiness_guard -lt 1 -or [int]$verification.objects.result_write_trigger -lt 1 -or [int]$verification.objects.protected_rls -lt 10){throw 'RESTORED_SECURITY_OBJECT_MISSING'}

  $evidence = [ordered]@{
    project_ref='rncjxstujioagcezvfkb'; production_head='00060'; backup_sha256=$actualHash
    local_host="$HostName`:$Port"; local_server_version=$roleEvidence.server_version; psql_version=$clientVersion; pg_restore_version=$restoreVersion
    restore_database=$dbName; restored_at=(Get-Date).ToString('o'); restore_duration_seconds=$duration; restore_exit_code=$restoreExit
    command_redacted="pg_restore -W --exit-on-error --no-owner --no-privileges -h 127.0.0.1 -p 5432 -U $RestoreUser -d <disposable-db> full.dump"
    verification=$verification; supabase_runtime_limitation='Application schemas, functions, policies and grants are restored locally; genuine hosted Auth/JWT/PostgREST behavior is outside this rehearsal.'
    cleanup=[ordered]@{database_dropped=$false}; gate='PASS_PENDING_CLEANUP'
  }
  $evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

  Write-Host 'Disconnecting and dropping only the disposable restore database ...'
  & $psql -X -W -v ON_ERROR_STOP=1 -h $HostName -p $Port -U $RestoreUser -d $MaintenanceDatabase -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$dbName' AND pid<>pg_backend_pid();"
  if ($LASTEXITCODE -ne 0) { throw 'DISPOSABLE_DATABASE_DISCONNECT_FAILED' }
  & $psql -X -W -v ON_ERROR_STOP=1 -h $HostName -p $Port -U $RestoreUser -d $MaintenanceDatabase -c "DROP DATABASE $dbName;"
  if ($LASTEXITCODE -ne 0) { throw 'DISPOSABLE_DATABASE_DROP_FAILED' }
  $created = $false
  $remaining = & $psql -X -W -qAt -h $HostName -p $Port -U $RestoreUser -d $MaintenanceDatabase -c "SELECT count(*) FROM pg_database WHERE datname='$dbName';"
  if ($LASTEXITCODE -ne 0 -or [int]($remaining|Select-Object -Last 1) -ne 0){throw 'DISPOSABLE_DATABASE_CLEANUP_NOT_PROVEN'}
  $evidence.cleanup.database_dropped=$true; $evidence.gate='PASS'
  $evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
  $evidenceHash=(Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-Host "RESTORE_GATE_PASS evidence=$evidencePath sha256=$evidenceHash"
}
catch {
  Write-Error $_
  if ($created) { Write-Warning "Disposable database $dbName may still exist. A human-authorized cleanup is required; the script will not hide the failed state." }
  exit 1
}
