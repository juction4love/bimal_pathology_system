[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('selftest','encrypt','decrypt')][string]$Mode,
  [string]$InputPath,
  [string]$OutputPath,
  [string]$KeyPath = 'recovery\keys\production-recovery-key.dpapi'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
function Resolve-WorkspacePath([string]$Path) {
  $full = [IO.Path]::GetFullPath((Join-Path $root $Path))
  if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'RECOVERY_PATH_OUTSIDE_WORKSPACE'
  }
  return $full
}
function Ensure-Parent([string]$Path) { [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null }
function New-RandomBytes([int]$Length) { $bytes=New-Object byte[] $Length; $rng=[Security.Cryptography.RandomNumberGenerator]::Create(); try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}; return $bytes }
function Get-Key([string]$ProtectedKeyPath) {
  if (-not (Test-Path -LiteralPath $ProtectedKeyPath)) {
    $key = New-RandomBytes 32
    try {
      $protected = [Security.Cryptography.ProtectedData]::Protect($key,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
      Ensure-Parent $ProtectedKeyPath
      [IO.File]::WriteAllBytes($ProtectedKeyPath,$protected)
    } finally { if ($key) { [Array]::Clear($key,0,$key.Length) } }
  }
  $blob = [IO.File]::ReadAllBytes($ProtectedKeyPath)
  try { return [Security.Cryptography.ProtectedData]::Unprotect($blob,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine) }
  finally { [Array]::Clear($blob,0,$blob.Length) }
}
function Encrypt-File([string]$Source,[string]$Destination,[string]$ProtectedKeyPath) {
  $plain = [IO.File]::ReadAllBytes($Source); $key = Get-Key $ProtectedKeyPath
  $nonce = New-RandomBytes 12; $tag = New-Object byte[] 16; $cipher = New-Object byte[] $plain.Length
  try {
    $aes = [Security.Cryptography.AesGcm]::new($key,16)
    try { $aes.Encrypt($nonce,$plain,$cipher,$tag) } finally { $aes.Dispose() }
    Ensure-Parent $Destination
    $stream = [IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $magic=[Text.Encoding]::ASCII.GetBytes('BPDR1'); $stream.Write($magic,0,$magic.Length); $stream.Write($nonce,0,$nonce.Length); $stream.Write($tag,0,$tag.Length); $stream.Write($cipher,0,$cipher.Length) } finally { $stream.Dispose() }
  } finally { [Array]::Clear($plain,0,$plain.Length); [Array]::Clear($key,0,$key.Length); [Array]::Clear($cipher,0,$cipher.Length) }
}
function Decrypt-File([string]$Source,[string]$Destination,[string]$ProtectedKeyPath) {
  $all=[IO.File]::ReadAllBytes($Source); $key=Get-Key $ProtectedKeyPath
  try {
    if ($all.Length -lt 33 -or [Text.Encoding]::ASCII.GetString($all,0,5) -ne 'BPDR1') { throw 'RECOVERY_ARCHIVE_HEADER_INVALID' }
    $nonce=$all[5..16]; $tag=$all[17..32]; $cipher=$all[33..($all.Length-1)]; $plain=New-Object byte[] $cipher.Length
    $aes=[Security.Cryptography.AesGcm]::new($key,16)
    try { $aes.Decrypt($nonce,$cipher,$tag,$plain) } finally { $aes.Dispose() }
    Ensure-Parent $Destination; [IO.File]::WriteAllBytes($Destination,$plain)
  } finally { if($plain){[Array]::Clear($plain,0,$plain.Length)}; [Array]::Clear($key,0,$key.Length); [Array]::Clear($all,0,$all.Length) }
}

$keyFull=Resolve-WorkspacePath $KeyPath
if ($Mode -eq 'selftest') {
  $dir=Resolve-WorkspacePath '.recovery-work\encryption-selftest'; [IO.Directory]::CreateDirectory($dir)|Out-Null
  $plain=Join-Path $dir 'plain.bin'; $encrypted=Join-Path $dir 'encrypted.bpdr'; $restored=Join-Path $dir 'restored.bin'
  try {
    [IO.File]::WriteAllBytes($plain,(New-RandomBytes 4096))
    Encrypt-File $plain $encrypted $keyFull; Decrypt-File $encrypted $restored $keyFull
    if ((Get-FileHash $plain -Algorithm SHA256).Hash -ne (Get-FileHash $restored -Algorithm SHA256).Hash) { throw 'RECOVERY_ENCRYPTION_SELFTEST_MISMATCH' }
    Write-Output 'RECOVERY_ENCRYPTION_SELFTEST_PASS'
  } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
  exit 0
}
$inputFull=Resolve-WorkspacePath $InputPath; $outputFull=Resolve-WorkspacePath $OutputPath
if ($Mode -eq 'encrypt') { Encrypt-File $inputFull $outputFull $keyFull; Write-Output 'RECOVERY_ENCRYPT_PASS' }
else { Decrypt-File $inputFull $outputFull $keyFull; Write-Output 'RECOVERY_DECRYPT_PASS' }
