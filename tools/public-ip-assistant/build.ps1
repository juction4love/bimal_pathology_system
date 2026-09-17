$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = Join-Path $root 'BimalPathology.PublicIpAssistant.csproj'
$publish = Join-Path $root 'publish'
dotnet publish $project -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o $publish
if ($LASTEXITCODE -ne 0) { throw 'Public IP Assistant publish failed.' }
& (Join-Path $publish 'BimalPathology.PublicIpAssistant.exe') --self-test
if ($LASTEXITCODE -ne 0) { throw 'Public IP Assistant self-tests failed.' }
$iscc = Get-Command iscc.exe -ErrorAction SilentlyContinue
if ($iscc) {
    & $iscc.Source (Join-Path $root 'installer\BimalPathologyPublicIpAssistant.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
} else {
    Write-Warning 'Inno Setup is not installed; the self-contained executable was built, but Setup.exe was not compiled.'
}

