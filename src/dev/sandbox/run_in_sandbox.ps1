# What runs *inside* Windows Sandbox: install eDEX-Tron on a machine that has
# never had Rainmeter, Python, the fonts or anything else it depends on, and
# write down everything that happened.
#
# Started by clean_install_test.wsb; not meant to be run on your own machine.
#
# Sandbox ships without winget, where a real Windows 11 has it, so the first
# job is to put winget there -- otherwise the test only ever proves that setup
# notices winget is missing, which it already does.

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$out = 'C:\out'
$log = Join-Path $out ('sandbox-{0}.log' -f (Get-Date -Format 'HHmmss'))

function Say($msg) {
    $line = '{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path $log -Value $line
}

function Step($name, [scriptblock]$body) {
    Say "=== $name"
    try {
        & $body | ForEach-Object { Say "    $_" }
        Say "--- $name OK"
    } catch {
        Say "!!! $name FAILED: $($_.Exception.Message)"
    }
}

New-Item -ItemType Directory -Force -Path $out | Out-Null
Say "Windows: $((Get-CimInstance Win32_OperatingSystem).Caption) build $((Get-CimInstance Win32_OperatingSystem).BuildNumber)"
Say "This machine starts with nothing: no winget, Rainmeter, Python or fonts."

# --- what a clean machine genuinely lacks -----------------------------------
foreach ($probe in @(
    @{ n = 'winget';        t = { [bool](Get-Command winget -EA SilentlyContinue) } },
    @{ n = 'python';        t = { & python -c 'import sys' 2>$null; $LASTEXITCODE -eq 0 } },
    @{ n = 'Rainmeter';     t = { Test-Path "$env:ProgramFiles\Rainmeter\Rainmeter.exe" } },
    @{ n = 'TranslucentTB'; t = { [bool](Get-AppxPackage -Name '*TranslucentTB*' -EA SilentlyContinue) } },
    @{ n = 'eDEX-UI';       t = { Test-Path "$env:LOCALAPPDATA\Programs\eDEX-UI" } },
    @{ n = 'csc.exe';       t = { Test-Path "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe" } })) {
    Say ("  before: {0,-14} {1}" -f $probe.n, (& $probe.t))
}

# --- give it winget, the way a real Windows 11 already has it ---------------
function Test-Winget { [bool](Get-Command winget.exe -EA SilentlyContinue) }

Step 'installing winget (App Installer)' {
    $env:Path += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"

    # The supported route first: Microsoft's own module knows the dependency
    # set for this build and fixes up the app execution alias.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Install-Module -Name Microsoft.WinGet.Client -Force -Scope CurrentUser -Repository PSGallery
        Repair-WinGetPackageManager -Force
        'Repair-WinGetPackageManager finished'
    } catch {
        "module route failed: $($_.Exception.Message)"
    }

    if (-not (Test-Winget)) {
        'falling back to installing the packages by hand'
        $tmp = 'C:\winget'
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $files = @(
            @{ u = 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx'; f = 'vclibs.appx' },
            @{ u = 'https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx'; f = 'xaml.appx' },
            @{ u = 'https://aka.ms/getwinget'; f = 'winget.msixbundle' }
        )
        foreach ($d in $files) {
            $dest = Join-Path $tmp $d.f
            if (-not (Test-Path $dest)) { Invoke-WebRequest -Uri $d.u -OutFile $dest -UseBasicParsing }
            "have $($d.f) ({0:N0} bytes)" -f (Get-Item $dest).Length
        }
        # Dependencies passed in the same call, rather than installed separately:
        # that is what the deployment stack actually wants, and it reports why
        # when it refuses.
        try {
            Add-AppxPackage -Path (Join-Path $tmp 'winget.msixbundle') `
                -DependencyPath @((Join-Path $tmp 'vclibs.appx'), (Join-Path $tmp 'xaml.appx')) `
                -ErrorAction Stop
            'Add-AppxPackage succeeded'
        } catch {
            "Add-AppxPackage failed: $($_.Exception.Message)"
        }
    }

    $env:Path += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
    "winget now present: $(Test-Winget)"
    if (Test-Winget) { "winget at: $((Get-Command winget.exe).Source)" }
}

Step 'winget version' { winget --version 2>&1 }
Step 'accepting the winget source agreements' {
    winget list --accept-source-agreements --count 1 2>&1 | Select-Object -First 2
}

# A winget installed moments ago has no package index yet, and every install
# then fails with the same source-level error. A real Windows 11 has had its
# sources since first boot, so this is the sandbox catching up rather than
# anything the installer should have to do.
Step 'making winget fetch its package index' {
    winget source reset --force 2>&1 | Select-Object -Last 2
    winget source update 2>&1 | Select-Object -Last 4
    'can winget find Rainmeter now?'
    winget show --id Rainmeter.Rainmeter --exact --accept-source-agreements 2>&1 | Select-Object -First 3
}

# --- the actual test --------------------------------------------------------
$setup = Get-ChildItem 'C:\installer\eDEX-Tron-Setup-*.exe' | Select-Object -First 1
Say "=== running $($setup.Name) /S  (this is the slow part)"
$sw = [Diagnostics.Stopwatch]::StartNew()
$p = Start-Process $setup.FullName -ArgumentList '/S' -PassThru
$finished = $p.WaitForExit(1500000)
$sw.Stop()
Say ("installer exit code : {0}" -f $(if ($finished) { $p.ExitCode } else { 'STILL RUNNING' }))
Say ("installer took      : {0}s" -f [int]$sw.Elapsed.TotalSeconds)

Start-Sleep -Seconds 20

# --- did it actually work? --------------------------------------------------
$docs = [Environment]::GetFolderPath('MyDocuments')
foreach ($check in @(
    @{ n = 'project folder';   t = { Test-Path "$docs\eDEX-Tron" } },
    @{ n = 'launcher built';   t = { Test-Path "$docs\eDEX-Tron\eDEX-Tron.exe" } },
    @{ n = 'Rainmeter';        t = { Test-Path "$env:ProgramFiles\Rainmeter\Rainmeter.exe" } },
    @{ n = 'python';           t = { & python -c 'import sys' 2>$null; $LASTEXITCODE -eq 0 } },
    @{ n = 'skins deployed';   t = { Test-Path "$docs\Rainmeter\Skins\eDEX-Tron\Clock\Clock.ini" } },
    @{ n = 'Rainmeter.ini';    t = { Test-Path "$env:APPDATA\Rainmeter\Rainmeter.ini" } },
    @{ n = 'wallpaper made';   t = { (Get-ChildItem "$docs\eDEX-Tron\runtime\wallpaper\*.jpg" -EA SilentlyContinue | Measure-Object).Count -gt 0 } },
    @{ n = 'backup.json';      t = { Test-Path "$docs\eDEX-Tron\runtime\backup.json" } },
    @{ n = 'layout planned';   t = { Test-Path "$docs\eDEX-Tron\runtime\layout.json" } },
    @{ n = 'Apps+features';    t = { Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\eDEX-Tron' } },
    @{ n = 'Rainmeter running';t = { [bool](Get-Process Rainmeter -EA SilentlyContinue) } },
    @{ n = 'watcher running';  t = { [bool](Get-Process eDEX-Tron -EA SilentlyContinue) } },
    @{ n = 'desktop shortcut'; t = { Test-Path ([Environment]::GetFolderPath('Desktop') + '\eDEX-Tron Theme.lnk') } })) {
    Say ("  after:  {0,-18} {1}" -f $check.n, (& $check.t))
}

Step 'skins Rainmeter loaded' {
    $rl = "$env:APPDATA\Rainmeter\Rainmeter.log"
    if (Test-Path $rl) {
        (Select-String -Path $rl -Pattern 'Refreshing skin').Line -replace '.*eDEX-Tron.', '' -replace '\.ini.*', ''
        $errs = Select-String -Path $rl -Pattern 'ERROR' | Select-Object -First 10
        if ($errs) { 'RAINMETER ERRORS:'; $errs.Line } else { 'no Rainmeter errors' }
    } else { 'no Rainmeter log' }
}

Step 'setup transcript (last 40 lines)' {
    $t = "$docs\eDEX-Tron\runtime\setup.log"
    if (Test-Path $t) { Get-Content $t -Tail 60 }
    else { 'no setup.log - setup did not get far enough to start one' }
}

Step 'uninstall on a clean machine' {
    & "$docs\eDEX-Tron\src\uninstall.ps1" 2>&1 | Select-Object -Last 25
}

Say 'DONE'
Copy-Item $log (Join-Path $out 'latest.log') -Force

# Shut the sandbox down from the inside, cleanly.
#
# The alternative -- killing WindowsSandbox.exe from the host between runs --
# force-kills a running Hyper-V virtual machine, and doing that repeatedly is
# the most likely explanation for the host freezing solid partway through a
# test session. Never do that. If the log needs reading live, pass -KeepOpen.
if (-not ($args -contains '-KeepOpen')) {
    Say 'shutting the sandbox down cleanly in 10s (its log is already saved)'
    Start-Sleep -Seconds 10
    Stop-Computer -Force
}
