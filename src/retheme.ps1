<#
.SYNOPSIS
    Change the theme's colours (and grid) in one go.

.DESCRIPTION
    Colours live in theme.json in the project root. This updates that file
    from the parameters you pass, then pushes the change everywhere it shows:

      * the wallpaper, re-rendered at this screen's resolution
      * every Rainmeter panel, the dock and the Desktop grid
      * the Windows accent, Windows Terminal and VS Code themes
      * the launcher icon (eDEX-Tron.exe, and so the dock and shortcuts)

        .\src\retheme.ps1 -Accent '#ff9f1c'          # amber
        .\src\retheme.ps1 -Accent '#7cffb2'          # green
        .\src\retheme.ps1 -IconColor '#4f9dff'       # keep the icon blue
        .\src\retheme.ps1 -Grid on                   # bring the grid back
        .\src\retheme.ps1                            # re-apply theme.json

    -Accent also moves the icon colour, unless you pass -IconColor too.

    The theme is dark by design: a light -Background is refused.

    Run it from a normal PowerShell window (not from inside a packaged app),
    or through src\tools\run_outside.ps1.
#>
param(
    [string]$Accent,
    [string]$Background,
    [string]$IconColor,
    [ValidateSet('on', 'off')][string]$Grid
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $PSScriptRoot 'tools'
$cfgPath = Join-Path $Root 'theme.json'

function Test-Hex($v) { $v -match '^#?[0-9a-fA-F]{6}$' }
function Norm-Hex($v) { '#' + $v.TrimStart('#').ToLower() }
function Get-Luma($hex) {
    $h = $hex.TrimStart('#')
    $r = [Convert]::ToInt32($h.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($h.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($h.Substring(4, 2), 16)
    (0.2126 * $r + 0.7152 * $g + 0.0722 * $b) / 255
}

# --- update theme.json -------------------------------------------------------
$cfg = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
foreach ($k in 'accent', 'background', 'icon', 'grid') {
    if (-not $cfg.PSObject.Properties[$k]) { $cfg | Add-Member -NotePropertyName $k -NotePropertyValue $null }
}
foreach ($pair in @(@('Accent', $Accent), @('Background', $Background), @('IconColor', $IconColor))) {
    if ($pair[1] -and -not (Test-Hex $pair[1])) { throw "-$($pair[0]) must be a #RRGGBB colour" }
}
if ($Background) {
    # Every surface in the theme is drawn assuming a dark ground; a light one
    # turns the panels and the shell unreadable.
    if ((Get-Luma $Background) -gt 0.25) {
        throw "-Background $Background is too light. The theme is dark-only; pick something darker (e.g. #05080d, #0a0a0a, #0b1020)."
    }
    $cfg.background = Norm-Hex $Background
}
if ($Accent) {
    $cfg.accent = Norm-Hex $Accent
    if (-not $IconColor) { $cfg.icon = $cfg.accent }
}
if ($IconColor) { $cfg.icon = Norm-Hex $IconColor }
if ($Grid) { $cfg.grid = ($Grid -eq 'on') }
if (-not $cfg.accent)     { $cfg.accent = '#aacfd1' }
if (-not $cfg.background) { $cfg.background = '#05080d' }
if (-not $cfg.icon)       { $cfg.icon = $cfg.accent }
if ($null -eq $cfg.grid)  { $cfg.grid = $false }
$cfg | ConvertTo-Json | Set-Content $cfgPath -Encoding utf8
"theme.json -> accent $($cfg.accent)  background $($cfg.background)  icon $($cfg.icon)  grid $($cfg.grid)"

function Invoke-Py {
    # PowerShell 5.1 turns native stderr into terminating errors under 'Stop';
    # judge python by its exit code instead.
    $ErrorActionPreference = 'Continue'
    $out = & python @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("python $($args[0]) failed. If it says 'No module named PIL', run:`n" +
               "  python -m pip install --user pillow`n`n" + ($out | Out-String))
    }
}

# --- wallpaper, at this screen's physical resolution -------------------------
Add-Type -Namespace Retheme -Name Screen -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
'@
[void][Retheme.Screen]::SetProcessDPIAware()
$pw = [Retheme.Screen]::GetSystemMetrics(0); $ph = [Retheme.Screen]::GetSystemMetrics(1)
$asset = Join-Path $Root 'assets\wallpaper\edex-tron-1920x1080.png'
Invoke-Py (Join-Path $tools 'make_wallpaper.py') --config $cfgPath --width $pw --height $ph --out $asset
$rt = Join-Path $Root 'runtime\wallpaper'
New-Item -ItemType Directory -Force -Path $rt | Out-Null
# Name it after the colours: Windows caches the background by path, so
# re-applying the same filename can leave the old image on screen.
$tag = ($cfg.accent + $cfg.background + $cfg.grid + $pw).Replace('#', '')
$wp = Join-Path $rt "edex-tron-$tag.jpg"
Get-ChildItem $rt -Filter 'edex-tron-*.jpg' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $wp -and $_.Name -notlike '*1920x1080*' } |
    Remove-Item -Force -ErrorAction SilentlyContinue
Copy-Item ([IO.Path]::ChangeExtension($asset, '.jpg')) $wp -Force
"wallpaper rendered at ${pw}x${ph}"

# --- Windows accent, Terminal and VS Code (install.ps1 reads theme.json) -----
& (Join-Path $PSScriptRoot 'install.ps1') -SkipRainmeter -NoRestartExplorer 6>$null | Out-Null
# install.ps1 applies its default wallpaper; put ours back
& (Join-Path $tools 'set_wallpaper.ps1') -Path $wp -Style Fill | Out-Null
"windows accent, terminal and vs code updated"

# --- launcher icon ------------------------------------------------------------
Invoke-Py (Join-Path $tools 'gen_icon.py') --config $cfgPath --out (Join-Path $Root 'assets\icon')
& (Join-Path $tools 'build_launcher.ps1') | Out-Null
"launcher icon rebuilt"

# --- panels, dock and Desktop grid, sized for this screen --------------------
& (Join-Path $tools 'relayout.ps1') | Out-Null
"panels rebuilt"
'done'
