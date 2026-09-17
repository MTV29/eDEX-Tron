<#
.SYNOPSIS
    Prepare fonts and sounds that the project does not redistribute.

.DESCRIPTION
    eDEX-UI's United Sans typeface is commercial, and its sound effects belong
    to the eDEX-UI project, so neither is shipped here. If eDEX-UI is installed
    on this machine, they are copied out of *that* install (its app.asar) and
    converted for Windows. Otherwise the theme falls back to Windows' own
    Bahnschrift and Consolas, and the optional sound scheme is unavailable.

    Safe to re-run.
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tools = $PSScriptRoot

$candidates = @(
    (Join-Path ${env:ProgramFiles} 'eDEX-UI\resources\app.asar'),
    (Join-Path $env:LOCALAPPDATA 'Programs\eDEX-UI\resources\app.asar')
)
$asar = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

$ttf      = Join-Path $Root 'build\ttf'
$skinFont = Join-Path $Root 'skins\eDEX-Tron\@Resources\Fonts'
New-Item -ItemType Directory -Force -Path $ttf, $skinFont | Out-Null

function Invoke-Py {
    $ErrorActionPreference = 'Continue'
    $out = & python @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "python $($args[0]) failed:`n$($out | Out-String)" }
}

if ($asar) {
    "eDEX-UI found: $asar"
    Push-Location $Root
    try {
        New-Item -ItemType Directory -Force -Path 'assets\fonts', 'assets\sounds' | Out-Null
        Invoke-Py (Join-Path $tools 'asar_extract.py') $asar extract 'assets/fonts/' 'assets\fonts'
        Invoke-Py (Join-Path $tools 'asar_extract.py') $asar extract 'assets/audio/' 'assets\sounds'
        Invoke-Py (Join-Path $tools 'woff2ttf.py')
    } finally { Pop-Location }
    Copy-Item (Join-Path $ttf '*.ttf') $skinFont -Force
    "  fonts: United Sans + Fira Mono (from your eDEX-UI)"
    "  sounds: $((Get-ChildItem (Join-Path $Root 'assets\sounds') -Filter *.wav).Count) extracted"
} else {
    "eDEX-UI not installed: using Windows' Bahnschrift and Consolas"
    "  (install eDEX-UI and re-run this for its original typeface and sounds)"
}
