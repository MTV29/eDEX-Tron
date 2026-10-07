# Make the taskbar part of the theme.
#
# Setup installs TranslucentTB and the launcher starts it, but nothing ever
# said what it should look like -- so a fresh install got whatever defaults
# TranslucentTB ships, and the taskbar matched the theme only by luck.
#
# This writes a configuration tinted with theme.json's background: acrylic
# rather than fully clear, so the taskbar reads as part of the HUD's dark
# surface instead of a hole in it, and the same whether the desktop is showing
# or a window is maximised -- a taskbar that changes appearance as you open
# things is the thing people notice.
#
# The original file is kept beside it so uninstall can put it back.
#
# Must run OUTSIDE any app container -- see run_outside.ps1 -- or it writes
# into the container's private copy of the package data.
param(
    [string]$Background = '',
    [switch]$Restore,
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$pkg = Get-AppxPackage -Name '*TranslucentTB*' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $pkg) { 'TranslucentTB is not installed; nothing to configure'; return }

$dir = Join-Path $env:LOCALAPPDATA "Packages\$($pkg.PackageFamilyName)\RoamingState"
$cfg = Join-Path $dir 'settings.json'
$backup = Join-Path $dir 'settings.json.edex-backup'

function Restart-Ttb {
    if ($NoRestart) { return }
    # It reads the file at startup, so a change needs a restart to show.
    Get-Process TranslucentTB -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 600
    try {
        Start-Process "shell:AppsFolder\$($pkg.PackageFamilyName)!TranslucentTB"
        'TranslucentTB restarted'
    } catch { Write-Warning "could not restart TranslucentTB: $($_.Exception.Message)" }
}

if ($Restore) {
    if (Test-Path $backup) {
        Move-Item $backup $cfg -Force
        'TranslucentTB settings restored'
    } elseif (Test-Path $cfg) {
        Remove-Item $cfg -Force
        'TranslucentTB settings removed (there was nothing to restore)'
    } else {
        'nothing to restore'
    }
    Restart-Ttb
    return
}

# --- the colour -------------------------------------------------------------
if (-not $Background) {
    $Background = '#05080d'
    try {
        $theme = Get-Content (Join-Path $Root 'theme.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($theme.background) { $Background = [string]$theme.background }
    } catch { }
}
$hex = $Background.TrimStart('#')
if ($hex.Length -ne 6) { throw "background must be #RRGGBB, got '$Background'" }
# TranslucentTB takes #AARRGGBB. A little under half opacity: enough for the
# dark surface to read, little enough to still be translucent.
$colour = '#73' + $hex.ToUpper()

New-Item -ItemType Directory -Force -Path $dir | Out-Null
if ((Test-Path $cfg) -and -not (Test-Path $backup)) {
    Copy-Item $cfg $backup -Force
    "kept the original as $(Split-Path $backup -Leaf)"
}

# Every state the same, so the taskbar does not change as windows open and
# close. show_line off: the separator reads as a seam against the HUD.
$state = @'
    "enabled": true,
    "accent": "acrylic",
    "color": "COLOUR",
    "show_peek": false,
    "show_line": false,
    "blur_radius": 9.0
'@ -replace 'COLOUR', $colour

$json = @"
// Written by eDEX-Tron (src\tools\set_taskbar.ps1). The original, if there
// was one, is in settings.json.edex-backup; uninstall puts it back.
{
  "`$schema": "https://TranslucentTB.github.io/settings.schema.json",
  "desktop_appearance": {
$state
  },
  "visible_window_appearance": {
$state
  },
  "maximized_window_appearance": {
$state
  },
  "start_opened_appearance": {
$state
  },
  "search_opened_appearance": {
$state
  },
  "task_view_opened_appearance": {
$state
  },
  "battery_saver_appearance": {
    "enabled": false,
    "accent": "opaque",
    "color": "#00000000",
    "show_peek": false,
    "show_line": false,
    "blur_radius": 9.0
  },
  "ignored_windows": { "window_class": [], "window_title": [], "process_name": [] },
  "disable_saving": false,
  "verbosity": "warn"
}
"@

Set-Content -Path $cfg -Value $json -Encoding UTF8
"taskbar set to acrylic $colour"
Restart-Ttb
