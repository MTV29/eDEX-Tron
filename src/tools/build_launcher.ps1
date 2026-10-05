<#
.SYNOPSIS
    Compile eDEX-Tron.exe -- the theme's switch, settings window and boot screen.

.DESCRIPTION
    The C# lives in launcher.cs, BootScreen.cs and SettingsForm.cs next to this
    script. Paths that differ per machine (where Rainmeter installed itself,
    which package TranslucentTB is) are resolved here and substituted into the
    %%TOKENS%% in launcher.cs, so the compiled exe needs no config file.

        eDEX-Tron.exe                 toggle
        eDEX-Tron.exe start|stop
        eDEX-Tron.exe status          what is running
        eDEX-Tron.exe settings        the settings window
        eDEX-Tron.exe boot            replay the boot screen
        eDEX-Tron.exe watch           hotkeys, key clicks, folder watchers,
                                      and keeping the shell in its frame

    Uses the C# compiler that ships with the .NET Framework, which is present
    on every Windows install, so there is nothing extra to download.
#>
param(
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $OutFile) { $OutFile = Join-Path $root 'eDEX-Tron.exe' }
$docs = [Environment]::GetFolderPath('MyDocuments')

# --- resolve what this machine actually has ---------------------------------
$rainmeter = Join-Path ${env:ProgramFiles} 'Rainmeter\Rainmeter.exe'
if (-not (Test-Path $rainmeter)) { Write-Warning "Rainmeter not found at $rainmeter" }

$ttbArg = ''
$pkg = Get-AppxPackage -Name '*TranslucentTB*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pkg) { $ttbArg = "shell:AppsFolder\$($pkg.PackageFamilyName)!TranslucentTB" }
else { Write-Warning 'TranslucentTB not installed; the launcher will skip it' }

$liveRes      = Join-Path $docs 'Rainmeter\Skins\eDEX-Tron\@Resources'
$termScript   = Join-Path $liveRes 'launch_terminal.ps1'
$refreshScript= Join-Path $liveRes 'refresh_desktop.ps1'
$settingsScript = Join-Path $PSScriptRoot 'settings.ps1'

# The key click we render ourselves, deliberately in preference to eDEX-UI's
# keyboard.wav even when that has been copied out of a local install: theirs is
# a 1.2-second run of typing, not one keystroke, so restarting it on every key
# would be a rattle rather than a click.
$keySound = Join-Path $root 'assets\sounds\gen\key.wav'
if (-not (Test-Path $keySound)) {
    try { & python (Join-Path $PSScriptRoot 'gen_sounds.py') | Out-Null } catch { }
}
if (-not (Test-Path $keySound)) {
    Write-Warning 'No key click sound; run src\tools\gen_sounds.py'
    $keySound = ''
}

$version = '0.9.0'
$versionFile = Join-Path $root 'VERSION'
if (Test-Path $versionFile) { $version = (Get-Content $versionFile -Raw).Trim() }

# --- substitute the per-machine paths ---------------------------------------
# Every token sits inside a C# verbatim string, so a Windows path needs no
# escaping at all -- only a double quote would, and none of these can contain one.
$tokens = @{
    '%%RAINMETER%%'      = $rainmeter
    '%%TTBARG%%'         = $ttbArg
    '%%TERMSCRIPT%%'     = $termScript
    '%%REFRESHSCRIPT%%'  = $refreshScript
    '%%SETTINGSSCRIPT%%' = $settingsScript
    '%%RELAYOUTSCRIPT%%' = (Join-Path $PSScriptRoot 'relayout.ps1')
    '%%PROJECTROOT%%'    = $root
    '%%KEYSOUND%%'       = $keySound
    '%%VERSION%%'        = $version
}

$sources = @('launcher.cs', 'BootScreen.cs', 'SettingsForm.cs') |
           ForEach-Object { Join-Path $PSScriptRoot $_ }
foreach ($s in $sources) {
    if (-not (Test-Path $s)) { throw "missing source file: $s" }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("edex-tron-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$compile = @()
try {
    foreach ($s in $sources) {
        $text = Get-Content $s -Raw
        foreach ($k in $tokens.Keys) {
            if ($tokens[$k] -like '*"*') { throw "path contains a quote: $($tokens[$k])" }
            $text = $text.Replace($k, $tokens[$k])
        }
        $left = [regex]::Matches($text, '%%\w+%%') | ForEach-Object { $_.Value } | Select-Object -Unique
        if ($left) { throw "unreplaced token(s) in $(Split-Path $s -Leaf): $($left -join ', ')" }
        $dest = Join-Path $work (Split-Path $s -Leaf)
        # No BOM: csc copes, but it shows up in error messages as a stray glyph.
        [IO.File]::WriteAllText($dest, $text, (New-Object Text.UTF8Encoding $false))
        $compile += $dest
    }

    # Compile with csc.exe rather than Add-Type: only csc can attach a Win32
    # icon resource (/win32icon), and Add-Type exposes no equivalent.
    $icon = Join-Path $root 'assets\icon\edex-tron.ico'
    $csc = @("$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
             "$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319\csc.exe") |
           Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $csc) { throw 'csc.exe not found; is the .NET Framework present?' }

    $name = [IO.Path]::GetFileNameWithoutExtension($OutFile)
    $watcherWasUp = [bool](Get-Process -Name $name -ErrorAction SilentlyContinue)
    Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 300

    $cscArgs = @('/nologo', '/target:winexe', '/optimize+', "/out:$OutFile",
                 '/reference:System.dll',
                 '/reference:System.Windows.Forms.dll',
                 '/reference:System.Drawing.dll',
                 '/reference:System.ServiceProcess.dll')
    # MediaPlayer, for the boot sound: it reads mp3 as well as wav and can
    # play faster than recorded. These two live in a WPF subfolder that csc
    # does not search, so they go in by full path.
    $wpf = Join-Path (Split-Path $csc -Parent) 'WPF'
    foreach ($dll in 'PresentationCore.dll', 'WindowsBase.dll') {
        $path = Join-Path $wpf $dll
        if (Test-Path $path) { $cscArgs += "/reference:$path" }
        else { Write-Warning "$dll not found; the boot screen will be silent" }
    }

    if (Test-Path $icon) { $cscArgs += "/win32icon:$icon" }
    else { Write-Warning "No icon at $icon - run src\tools\gen_icon.py first" }

    $ErrorActionPreference = 'Continue'
    $out = & $csc @cscArgs @compile 2>&1
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw ($out | Out-String) }

    "built $OutFile ({0:N0} bytes)" -f (Get-Item $OutFile).Length
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

"  version       : $version"
"  Rainmeter     : $rainmeter"
"  TranslucentTB : $(if ($ttbArg) { $ttbArg } else { '(not installed)' })"
"  shell script  : $termScript"
"  settings      : $settingsScript"
"  key click     : $(if ($keySound) { $keySound } else { '(none)' })"

if ($watcherWasUp -and (Get-Process Rainmeter -ErrorAction SilentlyContinue)) {
    # Win32_Process.Create: survive this script ending, even under Task Scheduler
    [void](Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = "`"$OutFile`" watch" })
    '  background tasks restarted'
}
