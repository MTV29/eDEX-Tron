# Emit graphics-card load, memory and temperature as a fixed-width table for
# the Gpu skin's monospace meter.
#
# nvidia-smi is the fast path and the only one that reports a temperature.
# Without it (AMD, Intel, or no driver tools) the load comes from the GPU Engine
# performance counters, which Windows keeps for every vendor, and the memory
# from the adapter's dedicated-usage counter. Those counter names are localised,
# so every lookup is guarded: a missing field prints as "--" rather than
# emptying the panel.
#
# Output is plain ASCII: the skin reads it as ANSI, so no degree sign.

$ErrorActionPreference = 'SilentlyContinue'

function Format-Row([string]$label, [string]$value) { '{0,-6}{1}' -f $label.ToUpper(), $value }

# --- nvidia-smi --------------------------------------------------------------
$smi = @("$env:SystemRoot\System32\nvidia-smi.exe",
         "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe") |
       Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $smi) {
    $cmd = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if ($cmd) { $smi = $cmd.Source }
}

if ($smi) {
    # utilization, memory and temperature of the first card, no units attached
    $line = & $smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu `
                   --format=csv,noheader,nounits 2>$null | Select-Object -First 1
    if ($line) {
        $f = $line -split '\s*,\s*'
        if ($f.Count -ge 4) {
            Format-Row 'load' ('{0}%' -f $f[0])
            Format-Row 'vram' ('{0:N1}/{1:N1}G' -f ([double]$f[1] / 1024), ([double]$f[2] / 1024))
            Format-Row 'temp' ('{0}C' -f $f[3])
            return
        }
    }
}

# --- performance counters ----------------------------------------------------
function Get-CounterSum([string]$path) {
    $s = (Get-Counter -Counter $path -ErrorAction SilentlyContinue).CounterSamples
    if (-not $s) { return $null }
    ($s | Measure-Object -Property CookedValue -Sum).Sum
}

$load = Get-CounterSum '\GPU Engine(*engtype_3D)\Utilization Percentage'
if ($null -eq $load) { $load = Get-CounterSum '\GPU Engine(*)\Utilization Percentage' }
Format-Row 'load' $(if ($null -ne $load) { '{0:N0}%' -f [Math]::Min($load, 100) } else { '--' })

$used = Get-CounterSum '\GPU Adapter Memory(*)\Dedicated Usage'
if ($null -ne $used) {
    # AdapterRAM caps at 4 GiB in WMI, so only the used figure is trustworthy.
    Format-Row 'vram' ('{0:N1}G used' -f ($used / 1GB))
} else {
    Format-Row 'vram' '--'
}

Format-Row 'temp' '--'
