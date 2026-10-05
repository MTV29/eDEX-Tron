# Emit the listening TCP ports and the process holding each one, formatted as a
# fixed-width table for the Ports skin's monospace meter.
#
# Rainmeter has no port measure, so this samples it directly. Get-NetTCPConnection
# is the fast path; netstat is parsed instead on a machine where the NetTCPIP
# module is missing or blocked.
#
# A port is usually bound twice (IPv4 and IPv6), so rows are collapsed on
# port + owner. Ports held by Windows' own service hosts are pushed to the
# bottom: they are the same on every machine, and the interesting entry is the
# dev server or game you just started.

param([int]$Rows = 5)

$ErrorActionPreference = 'SilentlyContinue'

# Processes whose listeners are part of stock Windows and never change.
$plumbing = @('system', 'idle', 'svchost', 'lsass', 'services', 'wininit',
              'spoolsv', 'searchindexer', 'dashost', 'msmpeng')

function Get-Listeners {
    $conns = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
    if ($conns) {
        return $conns | ForEach-Object {
            [pscustomobject]@{ Port = [int]$_.LocalPort; Pid = [int]$_.OwningProcess }
        }
    }
    # Fallback: netstat -ano, "  TCP    0.0.0.0:135   0.0.0.0:0   LISTENING   1234"
    netstat -ano | Select-String '^\s+TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)' |
        ForEach-Object {
            [pscustomobject]@{ Port = [int]$_.Matches[0].Groups[1].Value
                               Pid  = [int]$_.Matches[0].Groups[2].Value }
        }
}

$names = @{}
foreach ($p in Get-Process) { $names[$p.Id] = $p.ProcessName }

$seen = @{}
$list = foreach ($l in Get-Listeners) {
    $name = $names[$l.Pid]
    if (-not $name) { $name = if ($l.Pid -eq 4) { 'System' } else { "pid $($l.Pid)" } }
    $key = "$($l.Port)/$name"
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    [pscustomobject]@{
        Port = $l.Port
        Name = $name
        Rank = if ($plumbing -contains $name.ToLower()) { 1 } else { 0 }
    }
}

$top = $list | Sort-Object Rank, Port | Select-Object -First $Rows
foreach ($r in $top) {
    $name = $r.Name
    if ($name.Length -gt 17) { $name = $name.Substring(0, 17) }
    '{0,-7}{1}' -f $r.Port, $name
}
if (-not $top) { 'none listening' }
