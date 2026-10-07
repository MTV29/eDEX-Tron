<#
.SYNOPSIS
    Prove that uninstalling really does put everything back.

.DESCRIPTION
    The theme changes your wallpaper, accent colour, dark mode, sounds, Windows
    Terminal, VS Code and Office. It claims to back all of that up and revert
    it. This is how that claim gets checked rather than believed.

    Take a snapshot before installing, another after uninstalling, and compare:

        .\src\dev\verify_uninstall.ps1 -Snapshot before.json
        # ... install, use it, uninstall ...
        .\src\dev\verify_uninstall.ps1 -Snapshot after.json
        .\src\dev\verify_uninstall.ps1 -Before before.json -After after.json

    The comparison lists every registry value, file and shortcut that did not
    come back the way it was. An empty report is the result you want.

    It reads the same places install.ps1 writes, plus the ones it only reads --
    so a value the backup forgot to capture still shows up here as a difference.
    That is the point: it is deliberately not written from the backup's list.

    Run it outside any app container (see run_outside.ps1), or it will snapshot
    the container's private copy of the registry and files instead of yours.
#>
param(
    [string]$Snapshot,
    [string]$Before,
    [string]$After
)

$ErrorActionPreference = 'Stop'

# Everything the theme is known to touch, and a few neighbours it should not.
$RegistryValues = @(
    @('HKCU:\Control Panel\Desktop', 'Wallpaper'),
    @('HKCU:\Control Panel\Desktop', 'WallpaperStyle'),
    @('HKCU:\Control Panel\Desktop', 'TileWallpaper'),
    @('HKCU:\Control Panel\Desktop', 'AutoColorization'),
    # Not ours to change -- tracked precisely so that if anything ever does,
    # it shows up here rather than as "my fonts look pixelated" a reboot later.
    @('HKCU:\Control Panel\Desktop', 'FontSmoothing'),
    @('HKCU:\Control Panel\Desktop', 'FontSmoothingType'),
    @('HKCU:\Control Panel\Desktop', 'UserPreferencesMask'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers', 'BackgroundType'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes', 'CurrentTheme'),
    @('HKCU:\Software\Microsoft\Windows\DWM', 'AccentColor'),
    @('HKCU:\Software\Microsoft\Windows\DWM', 'AccentColorInactive'),
    @('HKCU:\Software\Microsoft\Windows\DWM', 'ColorizationColor'),
    @('HKCU:\Software\Microsoft\Windows\DWM', 'ColorizationAfterglow'),
    @('HKCU:\Software\Microsoft\Windows\DWM', 'ColorPrevalence'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'AppsUseLightTheme'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'SystemUsesLightTheme'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'EnableTransparency'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent', 'AccentColorMenu'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent', 'StartColorMenu'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent', 'AccentPalette'),
    @('HKCU:\Software\Microsoft\Office\16.0\Common', 'UI Theme'),
    @('HKCU:\AppEvents\Schemes', '(default)'),
    # The Apps & features entry install.ps1 adds, which uninstall must remove.
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\eDEX-Tron', 'DisplayName'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\eDEX-Tron', 'UninstallString'),
    # Explorer's own setting for hidden desktop icons: the launcher toggles the
    # icons through a window message, which must not leave this changed.
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'HideIcons')
)

# Every sound event install.ps1 can repoint.
$SoundEvents = @('.Default', 'SystemAsterisk', 'SystemExclamation', 'SystemHand',
                 'SystemNotification', 'Notification.Default', 'WindowsLogon',
                 'WindowsLogoff', 'DeviceConnect', 'DeviceDisconnect',
                 'DeviceFail', 'Open', 'Close', 'Maximize', 'Minimize',
                 'MenuCommand', 'RestoreDown', 'RestoreUp')

function Get-RegValue($path, $name) {
    try {
        $item = Get-ItemProperty -Path $path -Name $name -ErrorAction Stop
        $v = $item.$name
        if ($v -is [byte[]]) { return 'bytes:' + [Convert]::ToBase64String($v) }
        return [string]$v
    } catch { return $null }
}

function Get-FileState($path) {
    if (-not (Test-Path $path)) { return $null }
    $item = Get-Item $path -Force
    if ($item.PSIsContainer) { return 'directory' }
    return '{0} bytes, sha256 {1}' -f $item.Length,
           (Get-FileHash $path -Algorithm SHA256).Hash.ToLower()
}

function New-Snapshot {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $local = $env:LOCALAPPDATA
    $roaming = $env:APPDATA

    $state = [ordered]@{}

    foreach ($pair in $RegistryValues) {
        $state["reg: $($pair[0])\$($pair[1])"] = Get-RegValue $pair[0] $pair[1]
    }
    foreach ($evt in $SoundEvents) {
        $state["sound: $evt"] = Get-RegValue "HKCU:\AppEvents\Schemes\Apps\.Default\$evt\.Current" '(default)'
    }

    # Files and folders the theme creates, replaces or copies.
    $files = @(
        "$docs\Rainmeter\Skins\eDEX-Tron",
        "$docs\Rainmeter\Skins\eDEX-Tron-2",
        "$roaming\Rainmeter\Rainmeter.ini",
        "$local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$roaming\Code\User\settings.json",
        "$local\Programs\Microsoft VS Code\resources\app\extensions\edex-tron",
        "$roaming\Microsoft\Windows\Start Menu\Programs\eDEX-Tron Theme.lnk",
        "$([Environment]::GetFolderPath('Desktop'))\eDEX-Tron Theme.lnk",
        "$([Environment]::GetFolderPath('Startup'))\eDEX-Tron Theme.lnk",
        # The Startup shortcut is "eDEX-Tron.lnk"; the line above checks a
        # name setup_autostart.ps1 does not create, so it could never fail.
        "$([Environment]::GetFolderPath('Startup'))\eDEX-Tron.lnk",
        # Installed assets, including a wallpaper per monitor.
        "$local\eDEX-Tron",
        "$roaming\Microsoft\Windows\Fonts"
    )

    # TranslucentTB: the theme rewrites its settings and keeps the original
    # beside it, so both the file and the backup have to come back right.
    $ttb = Get-AppxPackage -Name '*TranslucentTB*' -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if ($ttb) {
        $files += "$local\Packages\$($ttb.PackageFamilyName)\RoamingState\settings.json"
        $files += "$local\Packages\$($ttb.PackageFamilyName)\RoamingState\settings.json.edex-backup"
    }
    foreach ($f in $files) { $state["file: $f"] = Get-FileState $f }

    # Fonts the theme may install, by name rather than by folder listing.
    $fontKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    $fonts = @()
    if (Test-Path $fontKey) {
        $fonts = @((Get-ItemProperty $fontKey).PSObject.Properties |
                   Where-Object { $_.Name -notlike 'PS*' } |
                   ForEach-Object { $_.Name } | Sort-Object)
    }
    $state['fonts: user-installed'] = ($fonts -join '; ')

    # Leftover backup markers that uninstall should have consumed.
    foreach ($marker in @(
        "$local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json.edex-backup",
        "$roaming\Code\User\settings.json.edex-backup")) {
        $state["marker: $marker"] = Get-FileState $marker
    }

    $state
}

if ($Snapshot) {
    $state = New-Snapshot
    $dir = Split-Path $Snapshot -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $state | ConvertTo-Json -Depth 4 | Set-Content $Snapshot -Encoding utf8
    "snapshot written: $Snapshot ($($state.Count) values)"
    return
}

if ($Before -or $After) {
    if (-not ($Before -and $After)) { throw 'Pass both: -Before before.json -After after.json' }
    $a = Get-Content $Before -Raw | ConvertFrom-Json
    $b = Get-Content $After -Raw | ConvertFrom-Json

    $keys = @($a.PSObject.Properties.Name) + @($b.PSObject.Properties.Name) |
            Sort-Object -Unique
    $differences = 0
    foreach ($k in $keys) {
        $before = $a.$k
        $after = $b.$k
        if ([string]$before -eq [string]$after) { continue }
        $differences++
        Write-Host "DIFFERS  $k" -ForegroundColor Yellow
        Write-Host "   before: $(if ($null -eq $before) { '(absent)' } else { $before })"
        Write-Host "   after : $(if ($null -eq $after) { '(absent)' } else { $after })"
    }
    Write-Host ''
    if ($differences -eq 0) {
        Write-Host "$($keys.Count) values checked, everything came back as it was." -ForegroundColor Green
    } else {
        Write-Host "$($keys.Count) values checked, $differences did not come back." -ForegroundColor Red
    }
    if ($differences -gt 0) { exit 1 }
    exit 0
}

throw 'Pass -Snapshot <file>, or -Before <file> -After <file>. See the top of this script.'
