# A throughput test, on demand, with nothing installed.
#
# speedtest-cli and Ookla's client are both fine and neither is here, so this
# uses Cloudflare's speed endpoints, which exist for exactly this and need no
# key: __down returns as many bytes as you ask for, __up swallows as many as
# you send. The numbers are a little optimistic against a nearby Cloudflare
# edge, which is the usual caveat for any single-endpoint test.
#
# This moves real data -- about 25MB down and 8MB up -- so it runs only when
# the button is pressed, never on a timer.
#
# One line out, for the panel's caption row:
#   "142.3 down  38.6 up Mbps  12ms"

$ErrorActionPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
# The progress bar costs more time than the transfer on a fast link.
$ProgressPreference = 'SilentlyContinue'

$downBytes = 25MB
$upBytes = 8MB

function Mbps([long]$bytes, [double]$seconds) {
    if ($seconds -le 0) { return 0 }
    [math]::Round(($bytes * 8) / $seconds / 1MB, 1)
}

# --- latency -----------------------------------------------------------------
$ping = '--'
try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $null = Invoke-WebRequest -Uri 'https://speed.cloudflare.com/__down?bytes=1' `
                              -UseBasicParsing -TimeoutSec 10
    $sw.Stop()
    $ping = [int]$sw.Elapsed.TotalMilliseconds
} catch { }

# --- download ----------------------------------------------------------------
$down = 0
try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-WebRequest -Uri "https://speed.cloudflare.com/__down?bytes=$downBytes" `
                           -UseBasicParsing -TimeoutSec 60
    $sw.Stop()
    # What arrived, not what was asked for: a truncated response would
    # otherwise read as a fast link rather than a short one.
    $got = if ($r.RawContentLength -gt 0) { [long]$r.RawContentLength }
           elseif ($r.Content) { [long]$r.Content.Length } else { 0 }
    $down = Mbps $got $sw.Elapsed.TotalSeconds
} catch { }

# --- upload ------------------------------------------------------------------
$up = 0
try {
    $payload = New-Object byte[] $upBytes
    (New-Object Random).NextBytes($payload)   # incompressible, so nothing is cheated
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $null = Invoke-WebRequest -Uri 'https://speed.cloudflare.com/__up' -Method Post `
                              -Body $payload -ContentType 'application/octet-stream' `
                              -UseBasicParsing -TimeoutSec 60
    $sw.Stop()
    $up = Mbps $upBytes $sw.Elapsed.TotalSeconds
} catch { }

if ($down -le 0 -and $up -le 0) {
    'speed test failed'
    return
}

'{0} down  {1} up Mbps  {2}ms' -f $down, $up, $ping
