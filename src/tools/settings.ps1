<#
.SYNOPSIS
    Read and change every setting in theme.json, and rebuild what each change
    affects.

.DESCRIPTION
    The settings window in eDEX-Tron.exe is a front end for this script: all
    the JSON handling and all the decisions about what needs regenerating live
    here, so the dialog stays a dialog. It is also perfectly usable on its own.

        .\src\tools\settings.ps1 -Get
        .\src\tools\settings.ps1 -Panels gpu,disk -Off toplist
        .\src\tools\settings.ps1 -Folder 'D:\Games' -KeyClick on

    -Get prints one key=value per line, which is a format both the dialog and
    a person can read. It includes "noroom", the panels that are switched on
    but did not fit on this screen, so the dialog can say why one is missing.

    Only what actually changed is rebuilt: colours go the long way round
    (retheme.ps1 re-renders the wallpaper and the app themes), layout changes
    just re-run relayout.ps1, and a behaviour toggle only needs the launcher's
    watcher restarted to pick it up.

    Run it outside any app container -- see run_outside.ps1.
#>
param(
    [switch]$Get,
    [string]$Accent,
    [string]$Background,
    [string]$IconColor,
    [ValidateSet('on', 'off')][string]$Grid,
    [string]$Folder,
    # Which typeface set the HUD uses. 'unitedsans' needs eDEX-UI installed
    # for its commercial typeface; 'fira' ships with the project.
    [ValidateSet('auto', 'unitedsans', 'fira', 'windows')][string]$Font,
    # Layout profiles: a named set of panels to switch between, e.g. one for
    # gaming and one for working. -Profile applies one, -SaveProfile stores
    # whatever is on now under that name, -DeleteProfile removes one.
    [string]$Profile,
    [string]$SaveProfile,
    [string]$DeleteProfile,
    # Comma-separated, or 'none' to clear. Unset means "leave alone".
    [string]$Panels,
    [string]$Off,
    [ValidateSet('on', 'off')][string]$KeyClick,
    [ValidateSet('on', 'off')][string]$Hotkeys,
    [ValidateSet('on', 'off')][string]$BootScreen,
    [ValidateSet('on', 'off')][string]$SnapShell,
    [ValidateSet('on', 'off')][string]$ShellAltTab,
    [ValidateSet('on', 'off')][string]$Autostart,
    # Skip the rebuild and only write theme.json (the dialog batches changes).
    [switch]$NoRebuild
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tools = $PSScriptRoot
$cfgPath = Join-Path $Root 'theme.json'
$planFile = Join-Path $Root 'runtime\layout.json'
$launcher = Join-Path $Root 'eDEX-Tron.exe'

# Every optional panel, and every standard one that can be switched off. Kept
# in step with OPTIONAL / LEFT_STACK / RIGHT_STACK in gen_rainmeter_ini.py.
$optional = @('gpu', 'power', 'disk', 'ports')
$standard = @('clock', 'cpuinfo', 'netstat', 'ramwatcher', 'conninfo', 'toplist')
# Defaults for anything theme.json does not mention yet.
$toggleDefaults = @{ keyclick = $false; hotkeys = $true; bootscreen = $true
                     snapshell = $true; shellalttab = $false }

function Read-Config {
    if (Test-Path $cfgPath) {
        return Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    [pscustomobject]@{}
}

function Set-Key($cfg, $name, $value) {
    if ($cfg.PSObject.Properties[$name]) { $cfg.$name = $value }
    else { $cfg | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}

function Get-Toggle($cfg, $name) {
    if ($cfg.PSObject.Properties[$name] -and $null -ne $cfg.$name) {
        return [bool]$cfg.$name
    }
    $toggleDefaults[$name]
}

function Split-List($text) {
    if (-not $text) { return @() }
    if ($text.Trim().ToLower() -eq 'none') { return @() }
    @($text -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
}

# Which font sets this machine can actually render. 'unitedsans' needs the
# commercial typeface, which only bootstrap_assets.ps1 can produce and only
# when eDEX-UI is installed; without it the set silently falls back, so the
# dialog greys it out instead of offering a choice that does nothing.
function Get-AvailableFonts {
    $ttf = Join-Path $Root 'build\ttf'
    $sets = @('auto', 'windows')
    if (Test-Path (Join-Path $ttf 'united_sans_medium.ttf')) { $sets += 'unitedsans' }
    if (Test-Path (Join-Path $ttf 'fira_mono.ttf')) { $sets += 'fira' }
    ($sets | Sort-Object) -join ','
}

# Profiles live in theme.json as an object of name -> { panels, off }. They
# deliberately hold only the panel choice: that is what "a gaming layout" means
# here, and a profile that also carried colours or a folder path would make
# switching one a bigger surprise than the name suggests.
function Get-Profiles($cfg) {
    if ($cfg.PSObject.Properties['profiles'] -and $cfg.profiles) { return $cfg.profiles }
    [pscustomobject]@{}
}

function Get-ProfileNames($cfg) {
    @(Get-Profiles $cfg | ForEach-Object { $_.PSObject.Properties.Name }) | Sort-Object
}

function Test-Autostart {
    Test-Path (Join-Path ([Environment]::GetFolderPath('Startup')) 'eDEX-Tron Theme.lnk')
}

$cfg = Read-Config

# --------------------------------------------------------------------- read ---
if ($Get) {
    $noRoom = @()
    if (Test-Path $planFile) {
        try {
            $plan = Get-Content $planFile -Raw | ConvertFrom-Json
            if ($plan.no_room) { $noRoom = @($plan.no_room | ForEach-Object { $_.ToLower() }) }
        } catch { }
    }
    $panelList = if ($null -ne $cfg.panels) { @($cfg.panels) } else { $optional }
    $folderPath = if ($cfg.folder) { $cfg.folder } else { '%USERPROFILE%\Desktop\Games' }

    "accent=$(if ($cfg.accent) { $cfg.accent } else { '#aacfd1' })"
    "background=$(if ($cfg.background) { $cfg.background } else { '#05080d' })"
    "icon=$(if ($cfg.icon) { $cfg.icon } else { '#4f9dff' })"
    "grid=$(if ($cfg.grid) { 'on' } else { 'off' })"
    "folder=$([Environment]::ExpandEnvironmentVariables($folderPath))"
    "folderraw=$folderPath"
    "font=$(if ($cfg.font) { ([string]$cfg.font).ToLower() } else { 'auto' })"
    "fonts=auto,unitedsans,fira,windows"
    "fontavailable=$(Get-AvailableFonts)"
    "profile=$(if ($cfg.profile) { $cfg.profile } else { '' })"
    "profiles=$((Get-ProfileNames $cfg) -join ',')"
    "panels=$(($panelList | ForEach-Object { $_.ToLower() }) -join ',')"
    "off=$((@($cfg.off) | Where-Object { $_ } | ForEach-Object { $_.ToLower() }) -join ',')"
    "noroom=$($noRoom -join ',')"
    "optional=$($optional -join ',')"
    "standard=$($standard -join ',')"
    foreach ($t in $toggleDefaults.Keys) {
        "$t=$(if (Get-Toggle $cfg $t) { 'on' } else { 'off' })"
    }
    "autostart=$(if (Test-Autostart) { 'on' } else { 'off' })"
    "theme=$cfgPath"
    return
}

# -------------------------------------------------------------------- write ---
$colourChanged = $false
$layoutChanged = $false
$toggleChanged = $false

foreach ($pair in @(@('accent', $Accent), @('background', $Background), @('icon', $IconColor))) {
    if ($pair[1]) {
        if ($pair[1] -notmatch '^#?[0-9a-fA-F]{6}$') { throw "$($pair[0]) must be a #RRGGBB colour" }
        $colourChanged = $true
    }
}
if ($Grid) { $colourChanged = $true }

if ($Folder) {
    $expanded = [Environment]::ExpandEnvironmentVariables($Folder)
    if (-not (Test-Path $expanded)) { throw "folder not found: $expanded" }
    Set-Key $cfg 'folder' $Folder
    $layoutChanged = $true
}
if ($Font) {
    Set-Key $cfg 'font' $Font.ToLower()
    $layoutChanged = $true
}
# --- profiles ---------------------------------------------------------------
# Order matters: -SaveProfile captures what is on *now*, before any -Panels or
# -Profile on the same command line changes it; -Profile then applies a stored
# set, and an explicit -Panels after that still wins, so the dialog can switch
# profile and adjust in one go.
if ($SaveProfile) {
    $profiles = Get-Profiles $cfg
    $current = [pscustomobject]@{
        panels = @(if ($null -ne $cfg.panels) { $cfg.panels } else { $optional })
        off    = @(@($cfg.off) | Where-Object { $_ })
    }
    if ($profiles.PSObject.Properties[$SaveProfile]) { $profiles.$SaveProfile = $current }
    else { $profiles | Add-Member -NotePropertyName $SaveProfile -NotePropertyValue $current }
    Set-Key $cfg 'profiles' $profiles
    Set-Key $cfg 'profile' $SaveProfile
    $layoutChanged = $true
    "profile saved: $SaveProfile"
}

if ($DeleteProfile) {
    $profiles = Get-Profiles $cfg
    if (-not $profiles.PSObject.Properties[$DeleteProfile]) {
        throw "no such profile: $DeleteProfile"
    }
    $profiles.PSObject.Properties.Remove($DeleteProfile)
    Set-Key $cfg 'profiles' $profiles
    if ($cfg.profile -eq $DeleteProfile) { Set-Key $cfg 'profile' '' }
    $layoutChanged = $true
    "profile deleted: $DeleteProfile"
}

if ($Profile) {
    $profiles = Get-Profiles $cfg
    if (-not $profiles.PSObject.Properties[$Profile]) {
        throw ("no such profile: $Profile (have: " + ((Get-ProfileNames $cfg) -join ', ') + ")")
    }
    $wanted = $profiles.$Profile
    # A profile written by a version that flattened the arrays comes back as
    # one space-separated string; accept that as well as a real array.
    function Expand-List($v) {
        if ($null -eq $v) { return @() }
        @($v) | ForEach-Object { $_ -split '[ ,]+' } | Where-Object { $_ }
    }
    Set-Key $cfg 'panels' @(Expand-List $wanted.panels | Where-Object { $optional -contains $_ })
    Set-Key $cfg 'off'    @(Expand-List $wanted.off    | Where-Object { $standard -contains $_ })
    Set-Key $cfg 'profile' $Profile
    $layoutChanged = $true
    "profile applied: $Profile"
}

if ($PSBoundParameters.ContainsKey('Panels')) {
    $list = @(Split-List $Panels | Where-Object { $optional -contains $_ })
    Set-Key $cfg 'panels' $list
    $layoutChanged = $true
    # Changing the panels by hand means the layout is no longer the profile it
    # claims to be. Say so rather than quietly drifting from the stored set.
    if (-not $Profile -and -not $SaveProfile -and $cfg.profile) { Set-Key $cfg 'profile' '' }
}
if ($PSBoundParameters.ContainsKey('Off')) {
    $list = @(Split-List $Off | Where-Object { $standard -contains $_ })
    Set-Key $cfg 'off' $list
    $layoutChanged = $true
}
foreach ($pair in @(@('keyclick', $KeyClick), @('hotkeys', $Hotkeys),
                    @('bootscreen', $BootScreen), @('snapshell', $SnapShell),
                    @('shellalttab', $ShellAltTab))) {
    if ($pair[1]) {
        Set-Key $cfg $pair[0] ($pair[1] -eq 'on')
        $toggleChanged = $true
    }
}

# Colours are written by retheme.ps1, which owns the defaults; everything else
# is written here. Save before rebuilding so the generators read the new values.
if ($layoutChanged -or $toggleChanged) {
    # -Depth matters: the default of 2 flattens "profiles" (an object of
    # objects of arrays) into space-joined strings, silently and without an
    # error, and the file only looks wrong the next time it is read back.
    $cfg | ConvertTo-Json -Depth 6 | Set-Content $cfgPath -Encoding utf8
    'theme.json saved'
}

if ($Autostart) {
    $args = if ($Autostart -eq 'off') { @('-Remove') } else { @() }
    & (Join-Path $tools 'setup_autostart.ps1') @args | ForEach-Object { "  $_" }
}

if ($NoRebuild) { 'rebuild skipped'; return }

if ($colourChanged) {
    # retheme.ps1 re-renders the wallpaper and the app themes and then calls
    # relayout.ps1 itself, so it covers a layout change too.
    $a = @{}
    if ($Accent) { $a['Accent'] = $Accent }
    if ($Background) { $a['Background'] = $Background }
    if ($IconColor) { $a['IconColor'] = $IconColor }
    if ($Grid) { $a['Grid'] = $Grid }
    & (Join-Path $PSScriptRoot '..\retheme.ps1') @a
} elseif ($layoutChanged) {
    & (Join-Path $tools 'relayout.ps1')
}

# The launcher reads the toggles when its watcher starts, so a toggle only
# takes effect once that is restarted. Harmless when the theme is off.
if ($toggleChanged -and (Test-Path $launcher) -and
    (Get-Process Rainmeter -ErrorAction SilentlyContinue)) {
    & $launcher 'restart-watcher'
    'watcher restarted'
}
'done'
