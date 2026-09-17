# Emit the heaviest processes by CPU, formatted as a fixed-width table for the
# TopList skin's monospace meter.
#
# Rainmeter's UsageMonitor plugin access-violates on the Process category on
# Windows 11 25H2, and AdvancedCPU's TopProcess returns raw counter values
# rather than names, so the list is sampled here instead: two Get-Process
# snapshots a short interval apart, differenced on total CPU seconds. That is
# far cheaper than Get-Counter '\Process(*)\% Processor Time' and accurate
# enough at this refresh rate.

$ErrorActionPreference = 'SilentlyContinue'
$rows     = 6
$interval = 0.5
$cores    = [Environment]::ProcessorCount

function Snapshot {
    Get-Process | Where-Object { $_.Id -ne 0 } | ForEach-Object {
        [pscustomobject]@{ Id = $_.Id; Name = $_.ProcessName; Cpu = $_.CPU; Mem = $_.WorkingSet64 }
    }
}

$before = @{}
foreach ($p in Snapshot) { $before[$p.Id] = $p.Cpu }
Start-Sleep -Seconds $interval
$after = Snapshot

$used = foreach ($p in $after) {
    $prev = $before[$p.Id]
    if ($null -eq $prev -or $null -eq $p.Cpu) { continue }
    $pct = (($p.Cpu - $prev) / $interval / $cores) * 100
    if ($pct -lt 0) { continue }
    [pscustomobject]@{ Name = $p.Name; Pct = $pct; Mem = $p.Mem }
}

function Format-Mem([double]$bytes) {
    if ($bytes -ge 1GB) { return ('{0,5:N1}G' -f ($bytes / 1GB)) }
    return ('{0,5:N0}M' -f ($bytes / 1MB))
}

$top = $used | Sort-Object Pct -Descending | Select-Object -First $rows
foreach ($p in $top) {
    $name = $p.Name
    if ($name.Length -gt 15) { $name = $name.Substring(0, 15) }
    '{0,-15}{1,5:N1}% {2}' -f $name, $p.Pct, (Format-Mem $p.Mem)
}
