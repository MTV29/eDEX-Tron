<#
.SYNOPSIS
    Install the eDEX-Tron Windows theme.

.DESCRIPTION
    Applies a Windows theme derived from eDEX-UI's `tron` palette:

      * per-user fonts (United Sans, Fira Mono) extracted from eDEX-UI
      * generated grid wallpaper
      * dark mode + #aacfd1 accent across title bars, buttons and highlights
      * eDEX sound scheme
      * the eDEX-Tron Rainmeter HUD, pinned at desktop level
      * matching Windows Terminal and VS Code colour schemes

    Every value it overwrites is captured to a backup JSON first, so
    uninstall.ps1 can put the machine back exactly as it was.

.PARAMETER AccentTitleBars
    Also tint window title bars with the accent (ColorPrevalence). Off by
    default: #aacfd1 is a light colour, so tinted title bars read as pale cyan
    chrome rather than eDEX's dark-surface-with-cyan-lines look.

.PARAMETER SkipRainmeter
    Don't touch Rainmeter skins or config.

.PARAMETER NoRestartExplorer
    Don't restart Explorer. Accent changes then apply only after your next
    sign-in.
#>
[CmdletBinding()]
param(
    [switch]$AccentTitleBars,
    [switch]$SkipRainmeter,
    [switch]$NoRestartExplorer,
    # Off by default: remapped system sounds get old fast, and the noisy events
    # are the ones that fire without you doing anything.
    [switch]$Sounds
)

$ErrorActionPreference = 'Stop'
$Root      = Split-Path -Parent $PSScriptRoot
# Runtime assets sit next to the project rather than under %LOCALAPPDATA% on
# purpose. Run from inside a packaged (MSIX) host, every write to AppData is
# silently redirected into that package's private container: Test-Path still
# reports success, but no other process sees the files, so the wallpaper
# renders black and the sound scheme points at paths that do not exist.
# Keeping everything beside the project makes the install self-contained.
$InstallTo  = Join-Path $Root 'runtime'
$BackupFile = Join-Path $InstallTo 'backup.json'

# The accent comes from theme.json in the project root -- the one place colours
# are chosen. Falls back to eDEX-UI's tron accent.
$AccentHex = '#aacfd1'
$BackgroundHex = '#05080d'
$themeCfg = Join-Path $Root 'theme.json'
if (Test-Path $themeCfg) {
    try {
        $cfgObj = Get-Content $themeCfg -Raw | ConvertFrom-Json
        if ($cfgObj.accent -match '^#?[0-9a-fA-F]{6}$') { $AccentHex = '#' + $cfgObj.accent.TrimStart('#').ToLower() }
        if ($cfgObj.background -match '^#?[0-9a-fA-F]{6}$') { $BackgroundHex = '#' + $cfgObj.background.TrimStart('#').ToLower() }
    } catch { }
}
$Accent = [pscustomobject]@{
    R = [Convert]::ToInt32($AccentHex.Substring(1, 2), 16)
    G = [Convert]::ToInt32($AccentHex.Substring(3, 2), 16)
    B = [Convert]::ToInt32($AccentHex.Substring(5, 2), 16)
}

function Write-Step($msg) { Write-Host "  [*] $msg" -ForegroundColor Cyan }
function Write-Ok  ($msg) { Write-Host "  [+] $msg" -ForegroundColor DarkCyan }
function Write-Warn2($msg){ Write-Host "  [!] $msg" -ForegroundColor Yellow }

# --------------------------------------------------------------------- P/Invoke
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace EdexTheme -Name Native -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool SystemParametersInfoW(uint uiAction, uint uiParam, string pvParam, uint fWinIni);

[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern int AddFontResourceW(string lpFilename);

[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeoutW(IntPtr hWnd, uint Msg, IntPtr wParam,
    string lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
'@

function Start-Detached([string]$commandLine) {
    # Win32_Process.Create parents the new process to the WMI host rather than
    # to us. That matters when this script is itself run through Task Scheduler
    # (see run_outside.ps1): the scheduler tears down the task's process tree
    # when the task finishes, which would otherwise kill Rainmeter moments
    # after we start it.
    try {
        $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create `
                              -Arguments @{ CommandLine = $commandLine } -ErrorAction Stop
        if ($r.ReturnValue -eq 0) { return $true }
    } catch { }
    try { Start-Process -FilePath $commandLine -ErrorAction Stop; return $true } catch { }
    return $false
}

function Set-Wallpaper([string]$path) {
    # SPI_SETDESKWALLPAPER = 0x0014, SPIF_UPDATEINIFILE|SPIF_SENDCHANGE = 0x03
    [void][EdexTheme.Native]::SystemParametersInfoW(0x0014, 0, $path, 0x03)
}

function Broadcast-SettingChange {
    $HWND_BROADCAST = [IntPtr]0xffff
    $out = [IntPtr]::Zero
    foreach ($topic in 'ImmersiveColorSet', 'WindowsThemeElement', 'Environment') {
        [void][EdexTheme.Native]::SendMessageTimeoutW(
            $HWND_BROADCAST, 0x001A, [IntPtr]::Zero, $topic, 2, 3000, [ref]$out)
    }
}

# ----------------------------------------------------------------------- Backup
function Get-RegValue($path, $name) {
    try { (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name } catch { $null }
}

function Save-Backup {
    if (Test-Path $BackupFile) {
        Write-Warn2 "Backup already exists, keeping the original: $BackupFile"
        return
    }
    $backup = [ordered]@{
        CreatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Wallpaper  = Get-RegValue 'HKCU:\Control Panel\Desktop' 'Wallpaper'
        WallpaperStyle = Get-RegValue 'HKCU:\Control Panel\Desktop' 'WallpaperStyle'
        TileWallpaper  = Get-RegValue 'HKCU:\Control Panel\Desktop' 'TileWallpaper'
        # 0 = picture, 1 = solid colour, 2 = slideshow, 3 = Windows Spotlight.
        # Anything but 0 overrides the wallpaper we set (a slideshow with no
        # valid folder just paints the desktop black).
        BackgroundType = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' 'BackgroundType'
        # "Automatically pick an accent colour from my background" -- if this is
        # left on, setting the wallpaper recomputes the accent and silently
        # overwrites ours.
        AutoColorization = Get-RegValue 'HKCU:\Control Panel\Desktop' 'AutoColorization'
        CurrentTheme   = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes' 'CurrentTheme'
        OfficeUITheme  = Get-RegValue 'HKCU:\Software\Microsoft\Office\16.0\Common' 'UI Theme'
        DWM = [ordered]@{
            AccentColor           = Get-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' 'AccentColor'
            AccentColorInactive   = Get-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' 'AccentColorInactive'
            ColorizationColor     = Get-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorizationColor'
            ColorizationAfterglow = Get-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorizationAfterglow'
            ColorPrevalence       = Get-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorPrevalence'
        }
        Personalize = [ordered]@{
            AppsUseLightTheme    = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme'
            SystemUsesLightTheme = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme'
            EnableTransparency   = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency'
        }
        Accent = [ordered]@{
            AccentColorMenu = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' 'AccentColorMenu'
            StartColorMenu  = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' 'StartColorMenu'
            AccentPalette   = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' 'AccentPalette'
        }
        Sounds = @{}
    }

    # capture the sound events we are about to repoint
    foreach ($evt in (Get-SoundMap).Keys) {
        $k = "HKCU:\AppEvents\Schemes\Apps\.Default\$evt\.Current"
        $backup.Sounds[$evt] = if (Test-Path $k) { (Get-ItemProperty $k).'(default)' } else { $null }
    }

    New-Item -ItemType Directory -Force -Path $InstallTo | Out-Null
    $backup | ConvertTo-Json -Depth 6 | Set-Content -Path $BackupFile -Encoding utf8
    Write-Ok "Backed up previous settings -> $BackupFile"
}

# ------------------------------------------------------------------ Accent maths
function Get-AccentDword([int]$r, [int]$g, [int]$b) {
    # DWM stores accent colours as 0xAABBGGRR. Build it in Int64 -- PowerShell
    # parses 0xFF000000 as a *negative* Int32, which overflows a UInt32 cast.
    return [uint32](4278190080L + ($b * 65536L) + ($g * 256L) + $r)
}

function Set-Dword($path, $name, [uint32]$value) {
    # The registry DWORD is unsigned, but .NET's DWord writer takes an Int32.
    # Reinterpret the bits rather than converting the number, so values above
    # 0x7FFFFFFF (anything with a full alpha byte) round-trip correctly.
    $signed = [BitConverter]::ToInt32([BitConverter]::GetBytes($value), 0)
    Set-ItemProperty -Path $path -Name $name -Value $signed -Type DWord
}

function New-AccentPalette([int]$r, [int]$g, [int]$b) {
    # 8 entries x 4 bytes, stored R,G,B,00, running light -> dark. Windows reads
    # the lighter entries for text/highlights on dark surfaces and the darker
    # ones for pressed states, so the ramp is centred on the true accent.
    $factors = @(1.22, 1.14, 1.07, 1.00, 0.82, 0.62, 0.42, 0.30)
    $bytes = New-Object System.Collections.Generic.List[byte]
    foreach ($f in $factors) {
        foreach ($c in @($r, $g, $b)) {
            $v = [math]::Round($c * $f)
            $bytes.Add([byte][math]::Max(0, [math]::Min(255, $v)))
        }
        $bytes.Add([byte]0)
    }
    return $bytes.ToArray()
}

# ------------------------------------------------------------------- Sound map
function Get-SoundMap {
    # Only events a person actually causes.
    #
    # '.Default' (the generic beep), 'Open' and 'Close' are deliberately absent:
    # they fire on ordinary window and process activity, including the hidden
    # PowerShell the TopList panel spawns on a timer, which turns the theme into
    # a metronome. Do not add them back.
    return [ordered]@{
        'SystemExclamation' = 'alarm.wav'
        'SystemHand'        = 'error.wav'
        'DeviceConnect'     = 'granted.wav'
        'DeviceDisconnect'  = 'denied.wav'
        'DeviceFail'        = 'error.wav'
        'EmptyRecycleBin'   = 'folder.wav'
    }
}

# ------------------------------------------------------------------------ Steps
function Install-Fonts {
    Write-Step 'Installing fonts (per-user, no admin needed)'
    & (Join-Path $PSScriptRoot 'tools\install_fonts.ps1') -SourceDir (Join-Path $Root 'build\ttf') | ForEach-Object { Write-Ok $_ }
}

function Install-Assets {
    Write-Step 'Copying wallpaper and sounds'
    New-Item -ItemType Directory -Force -Path "$InstallTo\wallpaper", "$InstallTo\sounds" | Out-Null
    # On a re-run the current wallpaper is held open by Explorer, so copy
    # file-by-file and keep an identical existing copy rather than failing.
    $pairs = @(
        @{ From = 'assets\wallpaper'; Filter = '*.png'; To = "$InstallTo\wallpaper" },
        @{ From = 'assets\wallpaper'; Filter = '*.jpg'; To = "$InstallTo\wallpaper" },
        @{ From = 'assets\sounds';    Filter = '*.wav'; To = "$InstallTo\sounds" }
    )
    $skipped = 0
    foreach ($p in $pairs) {
        $src = Join-Path $Root $p.From
        if (-not (Test-Path $src)) { continue }
        foreach ($f in Get-ChildItem $src -Filter $p.Filter -ErrorAction SilentlyContinue) {
            $target = Join-Path $p.To $f.Name
            if ((Test-Path $target) -and (Get-Item $target).Length -eq $f.Length) { continue }
            try { Copy-Item $f.FullName $target -Force -ErrorAction Stop }
            catch { $skipped++ }
        }
    }
    if ($skipped) { Write-Warn2 "$skipped asset(s) in use, kept the existing copy" }
    Write-Ok "Assets -> $InstallTo"
}

function Set-Appearance {
    Write-Step "Applying dark mode and the $AccentHex accent"

    # Must come before the accent is written: with this on, Windows derives the
    # accent from the wallpaper and overwrites whatever we set.
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' 'AutoColorization' 0 -Type DWord

    $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    New-Item -Path $personalize -Force | Out-Null
    Set-ItemProperty $personalize 'AppsUseLightTheme'    0 -Type DWord
    Set-ItemProperty $personalize 'SystemUsesLightTheme' 0 -Type DWord
    Set-ItemProperty $personalize 'EnableTransparency'   1 -Type DWord

    $dword = Get-AccentDword $Accent.R $Accent.G $Accent.B
    $dwm = 'HKCU:\Software\Microsoft\Windows\DWM'
    New-Item -Path $dwm -Force | Out-Null
    Set-Dword $dwm 'AccentColor'           $dword
    Set-Dword $dwm 'AccentColorInactive'   $dword
    Set-Dword $dwm 'ColorizationColor'     $dword
    Set-Dword $dwm 'ColorizationAfterglow' $dword
    Set-ItemProperty $dwm 'ColorPrevalence' ([int]$AccentTitleBars.IsPresent) -Type DWord

    $accentKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
    New-Item -Path $accentKey -Force | Out-Null
    Set-Dword $accentKey 'AccentColorMenu' $dword
    Set-Dword $accentKey 'StartColorMenu'  $dword
    Set-ItemProperty $accentKey 'AccentPalette' (New-AccentPalette $Accent.R $Accent.G $Accent.B) -Type Binary

    Write-Ok ("Accent 0x{0:X8} ({1})  title-bar tint: {2}" -f $dword, $AccentHex,
              $(if ($AccentTitleBars) { 'on' } else { 'off' }))
}

function Set-Background {
    Write-Step 'Setting wallpaper'
    # Prefer the JPEG: Windows transcodes it more reliably than PNG.
    $wp = Get-ChildItem "$InstallTo\wallpaper\*.jpg", "$InstallTo\wallpaper\*.png" -ErrorAction SilentlyContinue |
          Select-Object -First 1
    if (-not $wp) { Write-Warn2 'No wallpaper found, skipping'; return }

    $previous = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' 'BackgroundType'
    if ($previous -and $previous -ne 0) {
        Write-Ok "Background type $previous (slideshow/Spotlight) -> 0 (picture)"
    }
    # set_wallpaper.ps1 handles the background type and prefers the shell COM
    # interface, which is far more reliable here than SystemParametersInfo.
    & (Join-Path $PSScriptRoot 'tools\set_wallpaper.ps1') -Path $wp.FullName -Style Fill |
        ForEach-Object { Write-Ok $_ }
    Write-Ok "Wallpaper -> $($wp.Name)"
}

function Install-ThemeFile {
    # Writes a .theme pointing at the installed wallpaper, so the theme shows up
    # in Settings > Personalization and can be re-applied by double-clicking it.
    #
    # It is deliberately NOT applied automatically: there is no silent way to
    # apply a .theme (it opens the Settings app), and it is not needed. Windows
    # re-derives DWM\AccentColor from the active theme, so that value stays the
    # stock blue -- but DWM only uses it to tint title bars, which this theme
    # leaves off. The accent apps actually read (UISettings/AccentColorMenu) is
    # ours; src\dev\accent_effective.ps1 confirms the whole ramp.
    Write-Step 'Writing the theme file'

    $wp = Get-ChildItem "$InstallTo\wallpaper\*.jpg", "$InstallTo\wallpaper\*.png" -ErrorAction SilentlyContinue |
          Select-Object -First 1
    if (-not $wp) { Write-Warn2 'No wallpaper to reference; skipping theme file'; return }

    $themeFile = Join-Path $InstallTo 'eDEX-Tron.theme'
    # .theme colours are 0xAARRGGBB (unlike DWM's 0xAABBGGRR)
    $argb = '0X{0:X2}{1:X2}{2:X2}{3:X2}' -f 255, $Accent.R, $Accent.G, $Accent.B

    @"
; Generated by install.ps1 - applying this is what makes the accent persist.
[Theme]
DisplayName=eDEX Tron

[Control Panel\Desktop]
Wallpaper=$($wp.FullName)
TileWallpaper=0
WallpaperStyle=10
AutoColorization=0
Pattern=

[VisualStyles]
Path=%SystemRoot%\resources\themes\Aero\Aero.msstyles
ColorStyle=NormalColor
Size=NormalSize
AutoColorization=0
ColorizationColor=$argb
SystemMode=Dark
AppMode=Dark

[MasterThemeSelector]
MTSM=RJSPBS
"@ | Set-Content $themeFile -Encoding utf8

    Write-Ok "Theme file written ($argb) -> $themeFile"
}

function Install-Sounds {
    if (-not $Sounds) {
        Write-Warn2 'Sound scheme skipped (pass -Sounds to enable it)'
        return
    }
    Write-Step 'Registering the eDEX sound scheme'
    $schemeName = 'eDEX-Tron'
    New-Item -Path "HKCU:\AppEvents\Schemes\Names\$schemeName" -Force | Out-Null
    Set-ItemProperty "HKCU:\AppEvents\Schemes\Names\$schemeName" '(default)' 'eDEX Tron'

    foreach ($entry in (Get-SoundMap).GetEnumerator()) {
        $wav = Join-Path "$InstallTo\sounds" $entry.Value
        if (-not (Test-Path $wav)) { continue }
        foreach ($scheme in @('.Current', $schemeName)) {
            $k = "HKCU:\AppEvents\Schemes\Apps\.Default\$($entry.Key)\$scheme"
            New-Item -Path $k -Force | Out-Null
            Set-ItemProperty $k '(default)' $wav
        }
    }
    Set-ItemProperty 'HKCU:\AppEvents\Schemes' '(default)' $schemeName
    Write-Ok "$((Get-SoundMap).Count) sound events mapped"
}

function Install-Rainmeter {
    if ($SkipRainmeter) { Write-Warn2 'Skipping Rainmeter (requested)'; return }
    $exe = 'C:\Program Files\Rainmeter\Rainmeter.exe'
    if (-not (Test-Path $exe)) {
        Write-Warn2 'Rainmeter is not installed - skipping the desktop HUD.'
        Write-Warn2 'Install it with:  winget install Rainmeter.Rainmeter'
        return
    }
    Write-Step 'Planning and deploying the Rainmeter HUD for this screen'
    # relayout.ps1 measures the display, sizes every panel to fit it, builds
    # the dock and Desktop grid, deploys and (re)starts Rainmeter.
    & (Join-Path $PSScriptRoot 'tools\relayout.ps1') | ForEach-Object { Write-Ok $_ }
}


function Mix-Hex([string]$hex, [string]$toward, [double]$t) {
    # blend $hex toward $toward by $t (0..1); both '#RRGGBB'
    $a = $hex.TrimStart('#'); $b = $toward.TrimStart('#')
    $out = foreach ($i in 0, 2, 4) {
        $x = [Convert]::ToInt32($a.Substring($i, 2), 16)
        $y = [Convert]::ToInt32($b.Substring($i, 2), 16)
        '{0:X2}' -f [int][Math]::Round($x + ($y - $x) * $t)
    }
    '#' + ($out -join '')
}

function Convert-Palette([string]$text) {
    # The Terminal and VS Code themes are authored in the tron palette. Map
    # those exact colours onto the current theme.json accent/background, so
    # alpha suffixes such as #AACFD155 carry through untouched.
    $bg = $BackgroundHex.TrimStart('#').ToUpper()
    $map = [ordered]@{
        'AACFD1' = $AccentHex.TrimStart('#').ToUpper()
        'C8E6E7' = (Mix-Hex $AccentHex '#ffffff' 0.40).TrimStart('#')
        'CFE4E5' = (Mix-Hex $AccentHex '#ffffff' 0.55).TrimStart('#')
        'F0F7F7' = (Mix-Hex $AccentHex '#ffffff' 0.85).TrimStart('#')
        '05080D' = $bg
    }
    foreach ($k in $map.Keys) { $text = [regex]::Replace($text, $k, $map[$k], 'IgnoreCase') }
    $text
}

function Install-AppThemes {
    Write-Step 'Applying app colour schemes'

    # ---- Windows Terminal
    $wtDirs = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState"
    ) | Where-Object { Test-Path $_ }

    foreach ($dir in $wtDirs) {
        $settings = Join-Path $dir 'settings.json'
        if (-not (Test-Path $settings)) { continue }
        Copy-Item $settings "$settings.edex-backup" -Force -ErrorAction SilentlyContinue
        try {
            $json = Get-Content $settings -Raw | ConvertFrom-Json
            $scheme = Convert-Palette (Get-Content (Join-Path $Root 'themes\terminal\edex-tron.json') -Raw) | ConvertFrom-Json

            $schemes = @($json.schemes | Where-Object { $_.name -ne 'eDEX Tron' })
            $json.schemes = @($schemes + $scheme)
            if (-not $json.profiles.defaults) {
                $json.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            # the app's own chrome (tabs, title bar), not just the text colours
            $json | Add-Member -NotePropertyName theme -NotePropertyValue 'dark' -Force
            $json.profiles.defaults | Add-Member -NotePropertyName colorScheme -NotePropertyValue 'eDEX Tron' -Force
            # Keep the window title we pass on the command line; without this the
            # shell overwrites it and launch_terminal.ps1 can no longer find the
            # window to re-snap it into the Terminal panel.
            $json.profiles.defaults | Add-Member -NotePropertyName suppressApplicationTitle -NotePropertyValue $true -Force
            $json.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{ face = 'Fira Mono'; size = 11 }) -Force
            $json.profiles.defaults | Add-Member -NotePropertyName opacity -NotePropertyValue 85 -Force
            $json.profiles.defaults | Add-Member -NotePropertyName useAcrylic -NotePropertyValue $true -Force

            $json | ConvertTo-Json -Depth 32 | Set-Content $settings -Encoding utf8
            Write-Ok "Windows Terminal scheme applied ($(Split-Path $dir -Leaf))"
        } catch {
            Write-Warn2 "Could not patch Windows Terminal settings: $($_.Exception.Message)"
        }
    }
    if (-not $wtDirs) { Write-Warn2 'Windows Terminal not found, skipped' }

    # ---- Office: Black, rather than whatever it was left on
    $office = 'HKCU:\Software\Microsoft\Office\16.0\Common'
    if (Test-Path $office) {
        # installs made before this was tracked: record the original now
        if (Test-Path $BackupFile) {
            $bk = Get-Content $BackupFile -Raw | ConvertFrom-Json
            if (-not $bk.PSObject.Properties['OfficeUITheme']) {
                $bk | Add-Member -NotePropertyName OfficeUITheme -NotePropertyValue (Get-RegValue $office 'UI Theme')
                $bk | ConvertTo-Json -Depth 6 | Set-Content $BackupFile -Encoding utf8
            }
        }
        Set-ItemProperty $office 'UI Theme' 4 -Type DWord      # 4 = Black
        Write-Ok 'Office set to the Black theme (restart Office apps to see it)'
    }

    # ---- VS Code
    $vscodeExt = "$env:USERPROFILE\.vscode\extensions"
    if (Test-Path $vscodeExt) {
        $dest = Join-Path $vscodeExt 'edex-tron-theme-1.0.0'
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        Copy-Item (Join-Path $Root 'themes\vscode') $dest -Recurse -Force
        $vsTheme = Join-Path $dest 'themes\edex-tron-color-theme.json'
        Set-Content $vsTheme (Convert-Palette (Get-Content $vsTheme -Raw)) -Encoding utf8
        Write-Ok 'VS Code theme installed'

        # Select it, rather than leaving it installed but unused.
        $vsSettings = "$env:APPDATA\Code\User\settings.json"
        if (Test-Path $vsSettings) {
            if (-not (Test-Path "$vsSettings.edex-backup")) { Copy-Item $vsSettings "$vsSettings.edex-backup" }
            try {
                $vj = Get-Content $vsSettings -Raw | ConvertFrom-Json
                $vj | Add-Member -NotePropertyName 'workbench.colorTheme' -NotePropertyValue 'eDEX Tron' -Force
                # no BOM: VS Code's settings file is plain UTF-8
                [IO.File]::WriteAllText($vsSettings, ($vj | ConvertTo-Json -Depth 32),
                                        (New-Object Text.UTF8Encoding $false))
                Write-Ok 'VS Code switched to the eDEX Tron theme'
            } catch {
                # settings.json may contain comments, which ConvertFrom-Json rejects
                Write-Warn2 'Could not edit VS Code settings; pick "eDEX Tron" in the theme picker'
            }
        }
    } else {
        Write-Warn2 'VS Code not found, skipped'
    }
}

function Restart-Explorer {
    if ($NoRestartExplorer) {
        Write-Warn2 'Explorer not restarted - accent applies at next sign-in'
        return
    }
    Write-Step 'Restarting Explorer so the accent takes effect'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Write-Ok 'Explorer restarted'
}

# ------------------------------------------------------------------------- Main
Write-Host ''
Write-Host '  eDEX-Tron  ::  Windows theme installer' -ForegroundColor Cyan
Write-Host '  ---------------------------------------' -ForegroundColor DarkCyan

Save-Backup
Install-Fonts
Install-Assets
Set-Appearance
Install-Sounds
Install-AppThemes
Broadcast-SettingChange
Restart-Explorer

# Both of these must follow the Explorer restart: relaunching Explorer re-reads
# the active theme (which would put the old wallpaper straight back) and kills
# any running Rainmeter along with the shell.
Set-Background
Install-ThemeFile
Install-Rainmeter

# Assert the accent last: a restarted Explorer re-applies the active theme
# asynchronously, so an earlier write loses the race. With our own theme now
# active this is belt-and-braces rather than the mechanism.
Start-Sleep -Seconds 5
Set-Appearance
Broadcast-SettingChange

Write-Host ''
Write-Host '  Done. Run uninstall.ps1 to revert everything.' -ForegroundColor Cyan
Write-Host ''
