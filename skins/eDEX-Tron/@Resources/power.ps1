# Emit power draw -- and, on a laptop, the battery -- as a fixed-width table
# for the Power skin's monospace meter.
#
# Windows will tell you the wattage without any driver or elevation, if you
# know where to look:
#
#   \Power Meter(*)\Power            the ACPI power meter: whole-machine draw.
#                                    Laptops have one; most desktops do not.
#   \Energy Meter(RAPL_Package0_PKG) Intel RAPL, the processor package. Present
#                                    on Intel desktops as well as laptops, and
#                                    the closest thing to a system figure when
#                                    there is no power meter.
#   nvidia-smi power.draw            the card, where the NVIDIA tools exist.
#
# Both counter sets report milliwatts. Neither is guaranteed: AMD exposes RAPL
# differently, a desktop may have no meter at all, and a machine with neither
# prints "--" rather than emptying the panel.
#
# Output is plain ASCII: the skin reads it as ANSI, so no degree sign.

$ErrorActionPreference = 'SilentlyContinue'

function Format-Row([string]$label, [string]$value) { '{0,-5}{1}' -f $label.ToUpper(), $value }

# Every counter in one call. Get-Counter costs about a second to set the
# performance-counter subsystem up and almost nothing per extra path, so three
# calls cost three seconds and one call costs one. (The raw .NET
# PerformanceCounter class is faster still, but RAPL's Power is a rate counter
# and returns zero from a single NextValue; Get-Counter samples it properly.)
$wanted = @('\Power Meter(*)\Power',
            '\Energy Meter(RAPL_Package0_PKG)\Power',
            '\Energy Meter(RAPL_Package0_PP1)\Power')
$samples = @()
try { $samples = (Get-Counter -Counter $wanted -ErrorAction SilentlyContinue).CounterSamples } catch { }

function Get-Milliwatts([string]$match) {
    $hit = $samples | Where-Object { $_.Path -like "*$match*" }
    if (-not $hit) { return $null }
    $v = ($hit | Measure-Object -Property CookedValue -Sum).Sum
    # A meter that is present but idle reports 0, which is not a reading.
    if ($v -le 0) { return $null }
    $v
}

function Format-Watts($milliwatts) {
    if ($null -eq $milliwatts) { return '--' }
    '{0:N1}W' -f ($milliwatts / 1000)
}

# --- battery -----------------------------------------------------------------
# Win32_Battery for the percentage and state; root\WMI BatteryStatus for the
# rate, which is the only place the milliwatts in or out are exposed.
$battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
$rate = $null
if ($battery) {
    $status = Get-CimInstance -Namespace root\WMI -ClassName BatteryStatus -ErrorAction SilentlyContinue |
              Select-Object -First 1
    $percent = $battery.EstimatedChargeRemaining

    $state = 'on battery'
    if ($status) {
        if ($status.ChargeRate -gt 0) { $state = 'charging'; $rate = $status.ChargeRate }
        elseif ($status.DischargeRate -gt 0) { $rate = $status.DischargeRate }
        else { $state = 'full' }
    }
    # BatteryStatus 2 is "on mains"; it does not distinguish charging from full.
    if (-not $status -and $battery.BatteryStatus -eq 2) { $state = 'on mains' }

    Format-Row 'batt' ('{0}% {1}' -f $percent, $state)

    # Minutes left, when Windows is willing to estimate.
    $mins = $battery.EstimatedRunTime
    if ($mins -and $mins -gt 0 -and $mins -lt 71582788) {
        Format-Row 'left' ('{0}h {1:00}m' -f [int]($mins / 60), ($mins % 60))
    }
}

# --- whole machine -----------------------------------------------------------
# The ACPI meter is the real system figure. Where there is none, the battery's
# own discharge rate is the same number by another route; on a desktop with
# neither, say so rather than inventing one.
$system = Get-Milliwatts 'power meter'
if ($null -eq $system -and $null -ne $rate) { $system = $rate }
if ($null -ne $system) { Format-Row 'sys' (Format-Watts $system) }

# --- processor ---------------------------------------------------------------
$cpu = Get-Milliwatts 'pkg'
Format-Row 'cpu' (Format-Watts $cpu)

# --- graphics ----------------------------------------------------------------
$smi = @("$env:SystemRoot\System32\nvidia-smi.exe",
         "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe") |
       Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $smi) {
    $cmd = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if ($cmd) { $smi = $cmd.Source }
}

$gpu = $null
if ($smi) {
    $line = & $smi --query-gpu=power.draw --format=csv,noheader,nounits 2>$null | Select-Object -First 1
    $parsed = 0.0
    if ($line -and [double]::TryParse(($line -replace '[^0-9.]', ''), [ref]$parsed) -and $parsed -gt 0) {
        $gpu = $parsed * 1000
    }
}
# RAPL PP1 is the integrated graphics, which is the right answer on a machine
# with no discrete card.
if ($null -eq $gpu) { $gpu = Get-Milliwatts 'pp1' }
Format-Row 'gpu' (Format-Watts $gpu)
