<#
.SYNOPSIS
    Make the eDEX-Tron HUD and taskbar transparency come back after a reboot.

.DESCRIPTION
    Creates Startup-folder shortcuts for Rainmeter and TranslucentTB. Both are
    per-user and need no admin; deleting the shortcuts (or running this with
    -Remove) undoes it.

    Must run outside any app container -- see run_outside.ps1.
#>
param([switch]$Remove)

$ErrorActionPreference = 'Continue'
$startup = [Environment]::GetFolderPath('Startup')

function Set-Shortcut($folder, $name, $target, $arguments = '') {
    $lnk = Join-Path $folder "$name.lnk"
    if ($Remove) {
        if (Test-Path $lnk) { Remove-Item $lnk -Force; "removed  $name ($(Split-Path $folder -Leaf))" }
        return
    }
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($lnk)
    $sc.TargetPath = $target
    if ($arguments) { $sc.Arguments = $arguments }
    $sc.WorkingDirectory = Split-Path $target -Parent
    $sc.IconLocation = "$target,0"
    $sc.Description = 'Toggle the eDEX-Tron theme on or off'
    $sc.Save()
    "created  $name -> $(Split-Path $folder -Leaf)"
}

# One shortcut to the launcher rather than one per helper: "start" brings up
# Rainmeter, TranslucentTB, the shell and the hidden desktop icons together, so
# the theme comes back in one consistent state.
$launcher = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'eDEX-Tron\eDEX-Tron.exe'
if (Test-Path $launcher) {
    # Startup: bring the theme up at login.
    Set-Shortcut $startup 'eDEX-Tron' $launcher 'start'

    # Desktop: the way back in after switching the theme off. It is hidden
    # exactly when the theme is on (the launcher hides desktop icons, and the
    # dock carries it instead) and visible exactly when it is off -- otherwise
    # turning the theme off leaves no obvious way to turn it back on.
    Set-Shortcut ([Environment]::GetFolderPath('Desktop')) 'eDEX-Tron Theme' $launcher

    # Start menu: searchable in either state.
    Set-Shortcut ([Environment]::GetFolderPath('Programs')) 'eDEX-Tron Theme' $launcher
} else {
    "skipped  launcher not built yet - run src\tools\build_launcher.ps1 first"
}

# tidy up the per-helper shortcuts an earlier version created
foreach ($stale in 'eDEX-Tron Rainmeter', 'eDEX-Tron TranslucentTB') {
    $p = Join-Path $startup "$stale.lnk"
    if (Test-Path $p) { Remove-Item $p -Force; "removed  $stale (superseded)" }
}

"startup folder: $startup"
