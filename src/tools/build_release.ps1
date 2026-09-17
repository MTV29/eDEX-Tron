<#
.SYNOPSIS
    Build the release files into dist\.

.DESCRIPTION
    Produces, for the version in VERSION:

      dist\eDEX-Tron-Setup-v<ver>.exe     single-file installer
      dist\eDEX-Tron-v<ver>-source.zip    the same files as a plain zip
      dist\SHA256SUMS.txt

    The payload is exactly what is committed (git archive HEAD), so anything
    ignored -- your dock.txt, theme.json, registry backup, extracted fonts --
    can never leak into a release. Commit first; a dirty tree is refused.
#>
param([switch]$AllowDirty)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Root  = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ver   = (Get-Content (Join-Path $Root 'VERSION') | Select-Object -First 1).Trim()
$dist  = Join-Path $Root 'dist'
$work  = Join-Path $Root 'build\release'

Push-Location $Root
try {
    $ErrorActionPreference = 'Continue'
    $dirty = git status --porcelain
    $ErrorActionPreference = 'Stop'
    if ($dirty -and -not $AllowDirty) { throw "Uncommitted changes - commit them first (or pass -AllowDirty):`n$dirty" }

    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $dist, $work | Out-Null

    $payload = Join-Path $work 'payload.zip'
    $source  = Join-Path $dist "eDEX-Tron-v$ver-source.zip"
    git archive --format=zip -o $payload HEAD
    git archive --format=zip --prefix="eDEX-Tron-v$ver/" -o $source HEAD
    if ($LASTEXITCODE -ne 0) { throw 'git archive failed' }
    $z = [IO.Compression.ZipFile]::OpenRead($payload)
    "payload: {0:N0} bytes, {1} files" -f (Get-Item $payload).Length, $z.Entries.Count
    $z.Dispose()
} finally { Pop-Location }

# --- compile the installer ----------------------------------------------------
$csc = @("$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
         "$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319\csc.exe") |
       Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) { throw 'csc.exe (.NET Framework 4) not found' }

$cs = Join-Path $work 'setup_bootstrap.cs'
(Get-Content (Join-Path $PSScriptRoot 'setup_bootstrap.cs') -Raw).Replace('@VERSION@', $ver) |
    Set-Content $cs -Encoding UTF8

$exe  = Join-Path $dist "eDEX-Tron-Setup-v$ver.exe"
$icon = Join-Path $Root 'assets\icon\edex-tron.ico'
$args = @('/nologo', '/target:winexe', '/optimize+', "/out:$exe",
          "/resource:$payload,payload.zip",
          '/reference:System.dll', '/reference:System.Windows.Forms.dll',
          '/reference:System.IO.Compression.dll',
          '/reference:System.IO.Compression.FileSystem.dll', $cs)
if (Test-Path $icon) { $args = @("/win32icon:$icon") + $args }

$ErrorActionPreference = 'Continue'
$out = & $csc @args 2>&1
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) { throw "csc failed:`n$($out | Out-String)" }
"installer: $exe ({0:N0} bytes)" -f (Get-Item $exe).Length

# --- checksums ----------------------------------------------------------------
$sums = Get-ChildItem $dist -File | Where-Object { $_.Name -ne 'SHA256SUMS.txt' } | ForEach-Object {
    '{0}  {1}' -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name
}
$sums | Set-Content (Join-Path $dist 'SHA256SUMS.txt') -Encoding ascii
$sums
