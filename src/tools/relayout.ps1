<#
.SYNOPSIS
    Rebuild and redeploy the Rainmeter HUD sized for this screen.

.DESCRIPTION
    1. Measures the primary display (logical size and work area).
    2. Counts the dock entries and Desktop items.
    3. Plans the layout (gen_rainmeter_ini.py) -- panel positions, shell size,
       how many rows the dock wraps to, how big the Desktop grid is.
    4. Regenerates every skin at those sizes, in the colours from theme.json.
    5. Deploys to the live skin folder, writes Rainmeter.ini, restarts Rainmeter.

    The plan is saved to runtime\layout.json; refresh_desktop.ps1 and
    customize_dock.ps1 read it so their panels keep the planned size.

    Run it after changing resolution or display scaling. install.ps1,
    retheme.ps1 and the dock's Edit button call it for you.

    Primary display only.
#>
$ErrorActionPreference = 'Stop'
$Root     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tools    = $PSScriptRoot
$srcSkins = Join-Path $Root 'skins\eDEX-Tron'
$docs     = [Environment]::GetFolderPath('MyDocuments')
$skinRoot = Join-Path $docs 'Rainmeter\Skins'
$live     = Join-Path $skinRoot 'eDEX-Tron'
$planFile = Join-Path $Root 'runtime\layout.json'
$rmExe    = Join-Path ${env:ProgramFiles} 'Rainmeter\Rainmeter.exe'

function Invoke-Py {
    # PowerShell 5.1 turns native stderr into terminating errors under 'Stop';
    # judge python by its exit code instead.
    $ErrorActionPreference = 'Continue'
    $out = & python @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "python $($args[0]) failed:`n$($out | Out-String)" }
    $out
}

# --- 1. screen, in logical pixels ------------------------------------------
Add-Type -Namespace Relayout -Name Screen -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
[DllImport("user32.dll")] public static extern uint GetDpiForSystem();
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
[DllImport("user32.dll")] public static extern bool SystemParametersInfoW(uint a, uint b, ref RECT r, uint c);
'@
[void][Relayout.Screen]::SetProcessDPIAware()
$scale = [Relayout.Screen]::GetDpiForSystem() / 96.0
$physW = [Relayout.Screen]::GetSystemMetrics(0)
$work  = New-Object Relayout.Screen+RECT
[void][Relayout.Screen]::SystemParametersInfoW(0x0030, 0, [ref]$work, 0)   # SPI_GETWORKAREA
$logW  = [int][Math]::Floor($physW / $scale)
$logWorkH = [int][Math]::Floor(($work.B - $work.T) / $scale)
"screen: ${physW}px wide at $([int]($scale*100))% -> logical ${logW} x ${logWorkH} work area"

# --- 2. what goes in the dock and the Desktop grid --------------------------
$dockCfg = Join-Path $Root 'dock.txt'
$dockLine = & (Join-Path $tools 'gen_dock.ps1') -Config $dockCfg -SkinRoot $srcSkins | Select-Object -First 1
$dockCount = if ("$dockLine" -match ': (\d+) entr') { [int]$Matches[1] } else { 10 }
$desktop = [Environment]::GetFolderPath('Desktop')
$deskCount = @(Get-ChildItem $desktop -Force -ErrorAction SilentlyContinue |
    Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::Hidden) -and $_.Name -ne 'desktop.ini' }).Count

# --- 3. plan ----------------------------------------------------------------
New-Item -ItemType Directory -Force -Path (Split-Path $planFile) | Out-Null
Invoke-Py (Join-Path $tools 'gen_rainmeter_ini.py') --skin-path "$skinRoot\" `
    --plan-out $planFile --screen-w $logW --work-h $logWorkH `
    --dock-count $dockCount --desk-count $deskCount | ForEach-Object { "$_" }
$plan = Get-Content $planFile -Raw | ConvertFrom-Json

# --- 4. regenerate the skins at the planned sizes ---------------------------
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cpuName = if ($cpu.Name -match '(i[3579]-\w+|Ryzen \d+ \w+|Core Ultra \d \w+)') { $Matches[1] } else { $cpu.Name.Trim() }
$drives = (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
           ForEach-Object { $_.DeviceID.TrimEnd(':') }) -join ','

Invoke-Py (Join-Path $tools 'gen_skins.py') --out $srcSkins `
    --cores $cpu.NumberOfLogicalProcessors --cpu-name $cpuName --drives $drives `
    --width 250 --term-width $plan.term_w --term-height $plan.term_h `
    --fs-width $plan.fs_w --fs-rows $plan.fs_rows --graph-height $plan.graph_h | Out-Null

& (Join-Path $tools 'gen_dock.ps1') -Config $dockCfg -SkinRoot $srcSkins -Cols $plan.dock_cols | Out-Null
& (Join-Path $tools 'gen_dock.ps1') -FromFolder $desktop -SkinRoot $srcSkins -SkinName 'Desktop' `
    -Title 'Desktop' -Cols $plan.desk_cols -Rows $plan.desk_rows -NoEdit | Out-Null
"skins generated: dock $($plan.dock_cols)x$($plan.dock_rows), desktop $($plan.desk_cols)x$($plan.desk_rows), shell $($plan.term_w)x$($plan.term_h)"

# --- 5. deploy ---------------------------------------------------------------
$running = [bool](Get-Process Rainmeter -ErrorAction SilentlyContinue)
Get-Process Rainmeter -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600

New-Item -ItemType Directory -Force -Path $skinRoot | Out-Null
if (Test-Path $live) { Remove-Item $live -Recurse -Force }
Copy-Item $srcSkins $skinRoot -Recurse -Force

New-Item -ItemType Directory -Force -Path "$env:APPDATA\Rainmeter" | Out-Null
$ini = Join-Path $Root 'build\Rainmeter.ini'
Invoke-Py (Join-Path $tools 'gen_rainmeter_ini.py') --skin-path "$skinRoot\" --out $ini `
    --screen-w $logW --work-h $logWorkH --dock-count $dockCount --desk-count $deskCount | Out-Null
Copy-Item $ini "$env:APPDATA\Rainmeter\Rainmeter.ini" -Force

if ((Test-Path $rmExe) -and ($running -or -not $env:EDEX_NO_START)) {
    # Win32_Process.Create so Rainmeter outlives this script even when it runs
    # under Task Scheduler, which kills the task's process tree on exit.
    $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = "`"$rmExe`"" }
    if ($r.ReturnValue -ne 0) { Start-Process $rmExe }
}
"deployed -> $live"
