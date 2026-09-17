<#
.SYNOPSIS
    Revert the eDEX-Tron Windows theme.

.DESCRIPTION
    Restores every registry value install.ps1 captured in backup.json, removes
    the installed fonts, sounds, wallpaper, Rainmeter skins and app themes, and
    restarts Explorer.

    The helper apps themselves (Rainmeter, TranslucentTB, Windhawk) are left
    installed - remove those with winget if you want them gone:
        winget uninstall Rainmeter.Rainmeter
        winget uninstall CharlesMilette.TranslucentTB
        winget uninstall RamenSoftware.Windhawk

.PARAMETER KeepFonts
    Leave the United Sans / Fira Mono fonts installed.
#>
[CmdletBinding()]
param([switch]$KeepFonts)

$ErrorActionPreference = 'Stop'
$Root       = Split-Path -Parent $PSScriptRoot
# Must match install.ps1 -- see the note there about MSIX AppData redirection.
$InstallTo  = Join-Path $Root 'runtime'
$BackupFile = Join-Path $InstallTo 'backup.json'

function Write-Step($msg) { Write-Host "  [*] $msg" -ForegroundColor Cyan }
function Write-Ok  ($msg) { Write-Host "  [+] $msg" -ForegroundColor DarkCyan }
function Write-Warn2($msg){ Write-Host "  [!] $msg" -ForegroundColor Yellow }

Add-Type -Namespace EdexTheme -Name Restore -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool SystemParametersInfoW(uint uiAction, uint uiParam, string pvParam, uint fWinIni);
'@

function Restore-Value($path, $name, $value, $type) {
    if ($null -eq $value) {
        # the value did not exist before we ran - remove ours
        Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
        return
    }
    New-Item -Path $path -Force | Out-Null
    if ($type -eq 'DWord') {
        # Colour DWORDs exceed Int32.MaxValue once the alpha byte is set, so
        # reinterpret the bits instead of converting the number.
        $signed = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$value), 0)
        Set-ItemProperty -Path $path -Name $name -Value $signed -Type DWord
    } else {
        Set-ItemProperty -Path $path -Name $name -Value $value -Type $type
    }
}

Write-Host ''
Write-Host '  eDEX-Tron  ::  uninstall' -ForegroundColor Cyan
Write-Host '  ------------------------' -ForegroundColor DarkCyan

if (-not (Test-Path $BackupFile)) {
    Write-Warn2 "No backup found at $BackupFile"
    Write-Warn2 'Registry values cannot be restored automatically. Set your'
    Write-Warn2 'accent colour and wallpaper again from Settings > Personalization.'
    $backup = $null
} else {
    $backup = Get-Content $BackupFile -Raw | ConvertFrom-Json
}

# ------------------------------------------------------------------- registry
if ($backup) {
    Write-Step 'Restoring appearance settings'

    $dwm = 'HKCU:\Software\Microsoft\Windows\DWM'
    foreach ($n in 'AccentColor','AccentColorInactive','ColorizationColor','ColorizationAfterglow','ColorPrevalence') {
        Restore-Value $dwm $n $backup.DWM.$n 'DWord'
    }

    $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    foreach ($n in 'AppsUseLightTheme','SystemUsesLightTheme','EnableTransparency') {
        Restore-Value $personalize $n $backup.Personalize.$n 'DWord'
    }

    Restore-Value 'HKCU:\Control Panel\Desktop' 'AutoColorization' $backup.AutoColorization 'DWord'
    if ($backup.PSObject.Properties['OfficeUITheme'] -and (Test-Path 'HKCU:\Software\Microsoft\Office\16.0\Common')) {
        Restore-Value 'HKCU:\Software\Microsoft\Office\16.0\Common' 'UI Theme' $backup.OfficeUITheme 'DWord'
    }

    $accentKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
    Restore-Value $accentKey 'AccentColorMenu' $backup.Accent.AccentColorMenu 'DWord'
    Restore-Value $accentKey 'StartColorMenu'  $backup.Accent.StartColorMenu  'DWord'
    if ($null -ne $backup.Accent.AccentPalette) {
        Set-ItemProperty $accentKey 'AccentPalette' ([byte[]]$backup.Accent.AccentPalette) -Type Binary
    }
    Write-Ok 'Accent and dark-mode settings restored'

    # ---- wallpaper
    Write-Step 'Restoring wallpaper'
    if ($backup.WallpaperStyle) { Set-ItemProperty 'HKCU:\Control Panel\Desktop' 'WallpaperStyle' $backup.WallpaperStyle }
    if ($backup.TileWallpaper)  { Set-ItemProperty 'HKCU:\Control Panel\Desktop' 'TileWallpaper'  $backup.TileWallpaper }
    # put the slideshow / Spotlight background back if that is what was set
    Restore-Value 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' `
                  'BackgroundType' $backup.BackgroundType 'DWord'
    if ($backup.BackgroundType -and $backup.BackgroundType -ne 0) {
        Write-Warn2 "Background type restored to $($backup.BackgroundType) (slideshow/Spotlight)."
        Write-Warn2 'Windows may need a moment, or a visit to Personalization, to resume it.'
    }
    if ($backup.Wallpaper -and (Test-Path $backup.Wallpaper)) {
        [void][EdexTheme.Restore]::SystemParametersInfoW(0x0014, 0, $backup.Wallpaper, 0x03)
        Write-Ok "Wallpaper -> $($backup.Wallpaper)"
    } else {
        Write-Warn2 'Previous wallpaper file is gone; pick one in Personalization.'
    }

    # ---- sounds
    Write-Step 'Restoring sound events'
    foreach ($prop in $backup.Sounds.PSObject.Properties) {
        $k = "HKCU:\AppEvents\Schemes\Apps\.Default\$($prop.Name)\.Current"
        if (Test-Path $k) {
            Set-ItemProperty $k '(default)' ([string]$prop.Value)
        }
    }
    Set-ItemProperty 'HKCU:\AppEvents\Schemes' '(default)' '.Default'
    Remove-Item 'HKCU:\AppEvents\Schemes\Names\eDEX-Tron' -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok 'Sound scheme reverted to Windows Default'
}

# ------------------------------------------------------------------ runtime
Write-Step 'Stopping the theme and restoring desktop icons'
Get-Process TranslucentTB -ErrorAction SilentlyContinue | Stop-Process -Force
# The launcher hides desktop icons while the theme is on; put them back before
# tearing anything else down, or they stay hidden with no obvious way back.
$icons = Join-Path $PSScriptRoot 'tools\desktop_icons.ps1'
if (Test-Path $icons) { & $icons -Action show | ForEach-Object { Write-Ok $_ } }

foreach ($folder in 'Startup', 'Desktop', 'Programs') {
    $dir = [Environment]::GetFolderPath($folder)
    foreach ($stale in 'eDEX-Tron', 'eDEX-Tron Theme',
                       'eDEX-Tron Rainmeter', 'eDEX-Tron TranslucentTB') {
        $p = Join-Path $dir "$stale.lnk"
        if (Test-Path $p) { Remove-Item $p -Force; Write-Ok "removed $folder shortcut: $stale" }
    }
}

# ------------------------------------------------------------------ rainmeter
Write-Step 'Removing the Rainmeter HUD'
Get-Process Rainmeter -ErrorAction SilentlyContinue | Stop-Process -Force
$skinDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins\eDEX-Tron'
if (Test-Path $skinDir) { Remove-Item $skinDir -Recurse -Force; Write-Ok "Removed $skinDir" }
$rmIni = "$env:APPDATA\Rainmeter\Rainmeter.ini"
if (Test-Path $rmIni) {
    # drop only our configs, leave any other skins the user has
    $kept = @(); $skip = $false
    foreach ($line in Get-Content $rmIni) {
        if ($line -match '^\s*\[') { $skip = $line -match '^\s*\[eDEX-Tron\\' }
        if (-not $skip) { $kept += $line }
    }
    $kept | Set-Content $rmIni -Encoding utf8
    Write-Ok 'eDEX-Tron configs removed from Rainmeter.ini'
}

# ---------------------------------------------------------------- app themes
Write-Step 'Reverting app themes'
foreach ($dir in @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState")) {
    $bak = Join-Path $dir 'settings.json.edex-backup'
    if (Test-Path $bak) {
        Move-Item $bak (Join-Path $dir 'settings.json') -Force
        Write-Ok "Windows Terminal settings restored ($(Split-Path $dir -Leaf))"
    }
}
$vsSettings = "$env:APPDATA\Code\User\settings.json"
if (Test-Path "$vsSettings.edex-backup") {
    Move-Item "$vsSettings.edex-backup" $vsSettings -Force
    Write-Ok 'VS Code settings restored'
}
$vscodeTheme = "$env:USERPROFILE\.vscode\extensions\edex-tron-theme-1.0.0"
if (Test-Path $vscodeTheme) {
    Remove-Item $vscodeTheme -Recurse -Force
    Write-Ok 'VS Code theme removed (pick another theme in VS Code)'
}

# --------------------------------------------------------------------- fonts
if (-not $KeepFonts) {
    Write-Step 'Removing fonts'
    $installer = Join-Path $PSScriptRoot 'tools\install_fonts.ps1'
    if (Test-Path $installer) {
        & $installer -SourceDir (Join-Path $Root 'build\ttf') -Uninstall | ForEach-Object { Write-Ok $_ }
    }
}

# ------------------------------------------------------------------- assets
Write-Step 'Removing installed assets'
foreach ($sub in 'wallpaper', 'sounds') {
    $p = Join-Path $InstallTo $sub
    if (Test-Path $p) { Remove-Item $p -Recurse -Force }
}
Write-Ok "Kept $BackupFile in case you need it; delete $InstallTo when done."

# ------------------------------------------------------------------ explorer
Write-Step 'Restarting Explorer'
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }

Write-Host ''
Write-Host '  Reverted.' -ForegroundColor Cyan
Write-Host ''
