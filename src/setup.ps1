<#
.SYNOPSIS
    First-time setup for eDEX-Tron on a new machine.

.DESCRIPTION
    eDEX-Tron-Setup.exe unpacks the project to Documents\eDEX-Tron and runs
    this. It can also be run directly from a clone in that same folder.

      1. installs Rainmeter, TranslucentTB and Python (via winget) if missing
      2. installs the Python packages the generators need
      3. prepares fonts/sounds (from your eDEX-UI install, if you have one)
      4. renders the wallpaper and icon for your screen
      5. builds eDEX-Tron.exe (the on/off switch) for this machine
      6. applies the theme (install.ps1) and lays the HUD out for your screen
      7. adds Desktop / Start menu / login shortcuts and turns the theme on

    Your previous settings are backed up first; src\uninstall.ps1 reverts.
    Windows may ask for permission (UAC) while the helper apps install.
#>
$ErrorActionPreference = 'Stop'
$Root  = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $PSScriptRoot 'tools'
$version = (Get-Content (Join-Path $Root 'VERSION') -ErrorAction SilentlyContinue | Select-Object -First 1)

function Step($n, $msg) { Write-Host "`n[$n/7] $msg" -ForegroundColor Cyan }
function Ok($msg)       { Write-Host "      $msg" -ForegroundColor DarkCyan }
function Warn($msg)     { Write-Host "      $msg" -ForegroundColor Yellow }
function Fail($msg)     { Write-Host "`n  $msg`n" -ForegroundColor Red; Read-Host 'Press Enter to close' | Out-Null; exit 1 }

Write-Host ''
Write-Host "  eDEX-Tron $version  ::  setup" -ForegroundColor Cyan
Write-Host '  a Windows desktop theme based on eDEX-UI by Gabriel Saillard' -ForegroundColor DarkCyan

# The helper scripts that Rainmeter and the launcher call look for the
# project in this exact place.
$expected = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'eDEX-Tron'
if ((Resolve-Path $Root).Path.TrimEnd('\') -ne $expected.TrimEnd('\')) {
    Fail "eDEX-Tron must live in $expected (it is in $Root). Move or clone it there and run this again."
}
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Fail 'winget (App Installer) is required. Install "App Installer" from the Microsoft Store, then run this again.'
}

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Test-Python {
    # "python" may be the Microsoft Store alias, which just opens the Store.
    $ErrorActionPreference = 'Continue'
    & python -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)" 2>$null
    return $LASTEXITCODE -eq 0
}

function Ensure-Winget($id, $label, $check) {
    if (& $check) { Ok "$label already installed"; return }
    Ok "installing $label ..."
    $ErrorActionPreference = 'Continue'
    winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements | Out-Null
    $ErrorActionPreference = 'Stop'
    Refresh-Path
    if (& $check) { Ok "$label installed" } else { Warn "$label did not install - continuing without it" }
}

# --- 1 ------------------------------------------------------------------------
Step 1 'Helper apps'
Ensure-Winget 'Rainmeter.Rainmeter' 'Rainmeter' { Test-Path (Join-Path ${env:ProgramFiles} 'Rainmeter\Rainmeter.exe') }
Ensure-Winget 'CharlesMilette.TranslucentTB' 'TranslucentTB' { [bool](Get-AppxPackage -Name '*TranslucentTB*' -ErrorAction SilentlyContinue) }
Ensure-Winget 'Python.Python.3.12' 'Python' { Test-Python }
if (-not (Test-Python)) { Fail 'Python 3 is required and could not be installed. Install it from python.org and run this again.' }
if (-not (Test-Path (Join-Path ${env:ProgramFiles} 'Rainmeter\Rainmeter.exe'))) {
    Fail 'Rainmeter is required for the desktop HUD. Install it from rainmeter.net and run this again.'
}

# --- 2 ------------------------------------------------------------------------
Step 2 'Python packages'
$ErrorActionPreference = 'Continue'
& python -m pip install --user --quiet --disable-pip-version-check --no-warn-script-location `
    pillow numpy fonttools brotli 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'
& python -c "import PIL, numpy, fontTools" 2>$null
if ($LASTEXITCODE -ne 0) { Fail 'Could not install Pillow/numpy/fonttools. Run:  python -m pip install --user pillow numpy fonttools brotli' }
Ok 'pillow, numpy, fonttools ready'

# --- 3 ------------------------------------------------------------------------
Step 3 'Fonts, sounds and your settings files'
& (Join-Path $tools 'bootstrap_assets.ps1') | ForEach-Object { Ok $_ }
$dock = Join-Path $Root 'dock.txt'
if (-not (Test-Path $dock)) { Copy-Item (Join-Path $Root 'dock.default.txt') $dock; Ok 'dock.txt created from dock.default.txt' }
$cfg = Join-Path $Root 'theme.json'
if (-not (Test-Path $cfg)) { Copy-Item (Join-Path $Root 'theme.default.json') $cfg; Ok 'theme.json created from theme.default.json' }

# --- 4 ------------------------------------------------------------------------
Step 4 'Wallpaper and icon for your screen'
Add-Type -Namespace Setup -Name Screen -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
'@
[void][Setup.Screen]::SetProcessDPIAware()
$pw = [Setup.Screen]::GetSystemMetrics(0); $ph = [Setup.Screen]::GetSystemMetrics(1)
$ErrorActionPreference = 'Continue'
& python (Join-Path $tools 'make_wallpaper.py') --config $cfg --width $pw --height $ph | Out-Null
$wpOk = $LASTEXITCODE -eq 0
& python (Join-Path $tools 'gen_icon.py') --config $cfg | Out-Null
$icOk = $LASTEXITCODE -eq 0
$ErrorActionPreference = 'Stop'
if (-not $wpOk) { Fail 'Rendering the wallpaper failed (make_wallpaper.py).' }
Ok "wallpaper ${pw}x${ph}"
if ($icOk) { Ok 'icon rendered' } else { Warn 'icon render failed - keeping the bundled icon' }

# --- 5 ------------------------------------------------------------------------
Step 5 'Building eDEX-Tron.exe for this machine'
& (Join-Path $tools 'build_launcher.ps1') | Select-Object -First 1 | ForEach-Object { Ok $_ }

# --- 6 ------------------------------------------------------------------------
Step 6 'Applying the theme (Explorer will restart once)'
& (Join-Path $PSScriptRoot 'install.ps1')

# --- 7 ------------------------------------------------------------------------
Step 7 'Shortcuts, and switching the theme on'
& (Join-Path $tools 'setup_autostart.ps1') | ForEach-Object { Ok $_ }
$exe = Join-Path $Root 'eDEX-Tron.exe'
if (Test-Path $exe) { Start-Process $exe -ArgumentList 'start'; Ok 'theme started' }

Write-Host ''
Write-Host '  Done.' -ForegroundColor Cyan
Write-Host '  - Toggle the theme with "eDEX-Tron Theme" (Desktop / Start menu) or the Theme tile in the dock.'
Write-Host '  - Change colours:  src\retheme.ps1 -Accent "#ff9f1c"'
Write-Host '  - Undo everything: src\uninstall.ps1'
Write-Host ''
Read-Host 'Press Enter to close' | Out-Null
