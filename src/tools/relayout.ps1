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

# --- 1b. a second display, if there is one ----------------------------------
# The planner solves one screen. Anything it cannot fit there goes onto the
# largest other display, stacked in a column -- see plan_second.
#
# The coordinates have to be in the same units Rainmeter writes: it multiplies
# WindowX/WindowY by the display scale, so what it wants is physical pixels
# divided by that scale. System.Windows.Forms.Screen reports the other monitor
# in a virtualised space that does not survive that round trip -- a panel asked
# for ended up 164px left and 342px above the monitor it was meant to be on,
# i.e. nowhere. EnumDisplayMonitors gives the true physical rectangle.
Add-Type -Namespace Relayout -Name Mon -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonEnum cb, IntPtr data);
[DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern bool GetMonitorInfo(IntPtr mon, ref MONITORINFO mi);
public delegate bool MonEnum(IntPtr mon, IntPtr dc, IntPtr rect, IntPtr data);
[StructLayout(LayoutKind.Sequential)] public struct RECT2 { public int L, T, R, B; }
[StructLayout(LayoutKind.Sequential)] public struct MONITORINFO {
    public int cbSize; public RECT2 rcMonitor; public RECT2 rcWork; public uint dwFlags; }
'@

$monitors = New-Object System.Collections.ArrayList
$monCb = [Relayout.Mon+MonEnum] {
    param($mon, $dc, $rect, $data)
    $mi = New-Object Relayout.Mon+MONITORINFO
    $mi.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($mi)
    if ([Relayout.Mon]::GetMonitorInfo($mon, [ref]$mi)) {
        [void]$monitors.Add([pscustomobject]@{
            X = $mi.rcWork.L; Y = $mi.rcWork.T
            W = $mi.rcWork.R - $mi.rcWork.L
            H = $mi.rcWork.B - $mi.rcWork.T
            Primary = [bool]($mi.dwFlags -band 1)   # MONITORINFOF_PRIMARY
        })
    }
    $true
}
[void][Relayout.Mon]::EnumDisplayMonitors([IntPtr]::Zero, [IntPtr]::Zero, $monCb, [IntPtr]::Zero)

# The duplicate is drawn 27% larger -- a second screen is usually further
# away -- and inset from the left edge, because a second monitor is rarely
# flush with the primary and a panel hard against the edge reads as falling
# off it.
# How many sensors the PRTG panel lists, so the layout reserves the right
# height. It is set in runtime\prtg.json, which the panel reads at run time;
# the planner has to be told the same number or it reserves space for the
# default and the panel grows past it.
$prtgRows = 10
try {
    $prtgCfg = Join-Path $Root 'runtime\prtg.json'
    if (Test-Path $prtgCfg) {
        $pj = Get-Content $prtgCfg -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($pj.rows -and [int]$pj.rows -gt 0) { $prtgRows = [int]$pj.rows }
    }
} catch { }

$secondScale = 1.27
$secondPad = 35
$secondW = 0; $secondH = 0; $secondX = 0; $secondY = 0
if ($monitors.Count -gt 1) {
    $primaryMon = $monitors | Where-Object { $_.Primary } | Select-Object -First 1
    if (-not $primaryMon) { $primaryMon = $monitors[0] }
    # Largest working area: with three screens, the biggest is the one most
    # likely to have room for whatever did not fit.
    $other = $monitors | Where-Object { -not $_.Primary } |
             Sort-Object { $_.W * $_.H } -Descending | Select-Object -First 1
    if ($other) {
        $secondW = [int][Math]::Floor($other.W / $scale)
        $secondH = [int][Math]::Floor($other.H / $scale)
        $secondX = [int][Math]::Floor(($other.X - $primaryMon.X) / $scale)
        $secondY = [int][Math]::Floor(($other.Y - $primaryMon.Y) / $scale)
        "second display: $($other.W)x$($other.H) at $($other.X),$($other.Y) physical" +
        " -> ${secondW}x${secondH} at ${secondX},${secondY} logical"
    }
}


# --- 2. what goes in the dock and the Desktop grid --------------------------
$dockCfg = Join-Path $Root 'dock.txt'
$dockLine = & (Join-Path $tools 'gen_dock.ps1') -Config $dockCfg -SkinRoot $srcSkins | Select-Object -First 1
$dockCount = if ("$dockLine" -match ': (\d+) entr') { [int]$Matches[1] } else { 10 }
$desktop = [Environment]::GetFolderPath('Desktop')
function Get-VisibleCount([string]$path) {
    @(Get-ChildItem $path -Force -ErrorAction SilentlyContinue |
        Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::Hidden) -and $_.Name -ne 'desktop.ini' }).Count
}
$deskCount = Get-VisibleCount $desktop

# The Folder panel mirrors one folder of your choosing (theme.json "folder").
$folder = Join-Path $desktop 'Games'
try {
    $cfg = Get-Content (Join-Path $Root 'theme.json') -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($cfg.folder) { $folder = [Environment]::ExpandEnvironmentVariables($cfg.folder) }
} catch { }
if (-not (Test-Path $folder)) {
    # Not the Desktop: that would make this panel a copy of the Desktop one.
    Write-Warning "theme.json folder not found: $folder -- using Documents instead"
    $folder = [Environment]::GetFolderPath('MyDocuments')
}
$folderCount = Get-VisibleCount $folder
# remember it for the watcher and the panel's rescan action
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'runtime') | Out-Null
Set-Content (Join-Path $Root 'runtime\folder-path.txt') $folder -Encoding UTF8

# --- which optional panels are wanted, and what they need to know -----------
# theme.json "panels" lists the extras to switch on; "off" switches any of the
# standard side panels off and gives their space back to the rest. The planner
# decides what actually fits.
$panels = @('gpu', 'disk', 'ports')
$offPanels = @()
if ($cfg) {
    if ($null -ne $cfg.panels) { $panels = @($cfg.panels) }
    if ($null -ne $cfg.off)    { $offPanels = @($cfg.off) }
}
$drives = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
            Sort-Object DeviceID | ForEach-Object { $_.DeviceID.TrimEnd(':') })
if (-not $drives) { $drives = @('C') }

# Short card name for the GPU panel's caption, the way $cpuName is shortened.
$gpuName = ''
$video = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
         Sort-Object { $_.Name -notmatch 'NVIDIA|AMD|Radeon' } | Select-Object -First 1
if ($video) {
    $gpuName = if ($video.Name -match '(RTX \w+|GTX \w+|RX \w+|Arc \w+|Iris \w+|UHD Graphics)') {
        $Matches[1]
    } else { $video.Name.Trim() }
}
if (-not $gpuName) { $gpuName = 'gpu' }
# Empty strings get dropped on their way to a native command in PowerShell 5.1,
# which argparse then reports as a missing value -- so only pass what is set.
# How many lines the Power panel can actually fill here. A laptop answers
# five (battery, time left, system, processor, card); a desktop has no
# battery and usually no ACPI power meter, so it answers two or three and
# should not reserve the rest as blank space.
$powerRows = 3
if (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) { $powerRows = 5 }

$planArgs = @('--drive-count', $drives.Count, '--power-rows', $powerRows)
if ($secondW -gt 0 -and $secondH -gt 0) {
    $planArgs += @('--second-w', $secondW, '--second-h', $secondH,
                   '--second-x', $secondX, '--second-y', $secondY,
                   '--second-scale', $secondScale, '--second-pad', $secondPad,
                   '--prtg-rows', $prtgRows)
}
if ($panels)    { $planArgs += @('--panels', ($panels -join ',')) }
if ($offPanels) { $planArgs += @('--off', ($offPanels -join ',')) }

# --- 3. plan ----------------------------------------------------------------
New-Item -ItemType Directory -Force -Path (Split-Path $planFile) | Out-Null
Invoke-Py (Join-Path $tools 'gen_rainmeter_ini.py') --skin-path "$skinRoot\" `
    --plan-out $planFile --screen-w $logW --work-h $logWorkH `
    --dock-count $dockCount --desk-count $deskCount --folder-count $folderCount `
    @planArgs | ForEach-Object { "$_" }
$plan = Get-Content $planFile -Raw | ConvertFrom-Json

# --- 4. regenerate the skins at the planned sizes ---------------------------
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cpuName = if ($cpu.Name -match '(i[3579]-\w+|Ryzen \d+ \w+|Core Ultra \d \w+)') { $Matches[1] } else { $cpu.Name.Trim() }
Invoke-Py (Join-Path $tools 'gen_skins.py') --out $srcSkins `
    --cores $cpu.NumberOfLogicalProcessors --cpu-name $cpuName `
    --width 250 --term-width $plan.term_w --term-height $plan.term_h `
    --desktop $desktop --folder $folder `
    --drives ($drives -join ',') --gpu-name $gpuName | Out-Null

& (Join-Path $tools 'gen_dock.ps1') -Config $dockCfg -SkinRoot $srcSkins -Cols $plan.dock_cols | Out-Null
& (Join-Path $tools 'gen_dock.ps1') -FromFolder $desktop -SkinRoot $srcSkins -SkinName 'Desktop' `
    -Title 'Desktop' -Cols $plan.desk_cols -Rows $plan.desk_rows -NoEdit | Out-Null
& (Join-Path $tools 'gen_dock.ps1') -FromFolder $folder -SkinRoot $srcSkins -SkinName 'Folder' `
    -Title (Split-Path $folder -Leaf) -Cols $plan.folder_cols -Rows $plan.folder_rows -NoEdit | Out-Null
"skins generated: dock $($plan.dock_cols)x$($plan.dock_rows), desktop $($plan.desk_cols)x$($plan.desk_rows), $(Split-Path $folder -Leaf) $($plan.folder_cols)x$($plan.folder_rows), shell $($plan.term_w)x$($plan.term_h)"
if ($plan.no_room) {
    Write-Warning ("no room on this screen for: $($plan.no_room -join ', '). " +
        'Switch another panel off in theme.json "off" to make space.')
}

# --- 5. deploy ---------------------------------------------------------------
$running = [bool](Get-Process Rainmeter -ErrorAction SilentlyContinue)
# Rainmeter writes its own Rainmeter.ini (skin positions) while shutting down.
# Wait for the process to be gone before writing ours, or that save lands on
# top of the new layout and the old one comes back.
Get-Process Rainmeter -ErrorAction SilentlyContinue | Stop-Process -Force
for ($i = 0; $i -lt 40; $i++) {
    if (-not (Get-Process Rainmeter -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 250
}
Start-Sleep -Milliseconds 400

New-Item -ItemType Directory -Force -Path $skinRoot | Out-Null

# Stopping Rainmeter is not enough. Its RunCommand measures spawn PowerShell
# for ports.ps1 and gpu.ps1, and those children outlive the process that
# started them, still holding a handle on the skin folder. The delete below
# then removes the panels it can and leaves the ones it cannot, and the copy
# dies partway through -- so the HUD comes back with half its panels missing
# and the only clue is a FATAL in the log.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*Rainmeter*Skins*eDEX-Tron*" } |
    ForEach-Object {
        Write-Host "  stopping leftover skin script (pid $($_.ProcessId))"
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

# A handle can still be closing, so give the copy a few goes before failing --
# and if it does fail, say so loudly, because a half-deployed skin folder is a
# visibly broken desktop rather than a quiet degradation.
$deployed = $false
for ($attempt = 1; $attempt -le 4; $attempt++) {
    try {
        if (Test-Path $live) { Remove-Item $live -Recurse -Force -ErrorAction Stop }
        Copy-Item $srcSkins $skinRoot -Recurse -Force -ErrorAction Stop
        $deployed = $true
        break
    } catch {
        if ($attempt -eq 4) {
            throw ("could not replace $live after $attempt attempts: $($_.Exception.Message)`n" +
                   'Something still holds the skin folder open. Close Rainmeter and re-run.')
        }
        Write-Host "  skin folder busy, retrying ($attempt/4)"
        Start-Sleep -Milliseconds 600
    }
}
if (-not $deployed) { throw "skins were not deployed to $live" }

# A duplicate for the second display. Rainmeter loads a config once, so the
# copy needs a folder of its own; the skins inside are identical. Removed
# again when there is no second display, or the old copy would sit there
# pointing at a monitor that is gone.
$live2 = Join-Path $skinRoot 'eDEX-Tron-2'
if ($secondW -gt 0 -and $secondH -gt 0) {
    try {
        if (Test-Path $live2) { Remove-Item $live2 -Recurse -Force -ErrorAction Stop }
        Copy-Item $live $live2 -Recurse -Force -ErrorAction Stop
        # The copy above carries the grids and @Resources; the drawn panels
        # are then replaced with a set generated at the larger size. The
        # grids are not regenerated: they are icon bitmaps extracted at a
        # fixed size, so scaling them would blur rather than enlarge.
        $scaled = Join-Path $Root 'build\skins-2'
        if (Test-Path $scaled) { Remove-Item $scaled -Recurse -Force }
        Invoke-Py (Join-Path $tools 'gen_skins.py') --out $scaled `
            --cores $cpu.NumberOfLogicalProcessors --cpu-name $cpuName `
            --width 250 --scale $secondScale `
            --term-width $plan.term_w --term-height $plan.term_h `
            --desktop $desktop --folder $folder `
            --drives ($drives -join ',') --gpu-name $gpuName | Out-Null
        foreach ($d in Get-ChildItem $scaled -Directory) {
            $dest = Join-Path $live2 $d.Name
            if (Test-Path $dest) { Copy-Item (Join-Path $d.FullName '*') $dest -Recurse -Force }
        }
        "duplicate drawn at $([int]($secondScale * 100))%"
        'duplicate deployed -> ' + $live2
    } catch { Write-Warning "could not deploy the duplicate: $($_.Exception.Message)" }
} elseif (Test-Path $live2) {
    try { Remove-Item $live2 -Recurse -Force -ErrorAction Stop; 'duplicate removed (one display)' }
    catch { }
}

New-Item -ItemType Directory -Force -Path "$env:APPDATA\Rainmeter" | Out-Null
$ini = Join-Path $Root 'build\Rainmeter.ini'
Invoke-Py (Join-Path $tools 'gen_rainmeter_ini.py') --skin-path "$skinRoot\" --out $ini `
    --screen-w $logW --work-h $logWorkH --dock-count $dockCount --desk-count $deskCount `
    --folder-count $folderCount @planArgs | Out-Null
Copy-Item $ini "$env:APPDATA\Rainmeter\Rainmeter.ini" -Force

if ((Test-Path $rmExe) -and ($running -or -not $env:EDEX_NO_START)) {
    # Win32_Process.Create so Rainmeter outlives this script even when it runs
    # under Task Scheduler, which kills the task's process tree on exit.
    $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = "`"$rmExe`"" }
    if ($r.ReturnValue -ne 0) { Start-Process $rmExe }
}
# A display change is also when the wallpapers stop matching: relayout runs
# on WM_DISPLAYCHANGE, so this is where a newly plugged-in monitor gets its
# own picture rather than the primary's stretched to fit.
# $monitors comes from EnumDisplayMonitors above -- the same enumeration the
# layout uses, rather than a second opinion from another API.
try {
    if ($monitors.Count -gt 1) {
        & (Join-Path $tools 'set_wallpapers.ps1') | ForEach-Object { "  $_" }
    }
} catch { "  per-monitor wallpaper skipped: $($_.Exception.Message)" }

"deployed -> $live"
