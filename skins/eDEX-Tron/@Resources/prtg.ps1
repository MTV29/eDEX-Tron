# Sensors that are down in PRTG, oldest "last up" first.
#
# Reads runtime\prtg.json for where the server is and how to authenticate:
#
#   {
#     "server":   "https://prtg.example.com:8443",
#     "apitoken": "",          // PRTG: Setup > Account Settings > API Keys
#     "rows":     10,
#     "insecure": false        // true only for a self-signed certificate
#   }
#
# The token stays in that file. It is never printed, never logged and never
# passed on a command line where another process could read it off the process
# list -- the query goes in the request body style, as a URI the script builds
# and uses once.
#
# runtime\ is outside the repository, so the file never leaves this machine.
#
# Output is a fixed-width table for the panel's monospace meter, plain ASCII.

# The deployed skins live under Documents\Rainmeter\Skins, not in the project,
# so the config path cannot be derived from where this script sits -- walking up
# from there lands in Documents\runtime. gen_skins.py bakes the real path into
# the skin's Parameter line, the same way the launcher has its paths baked in at
# build time.
param([string]$Config = '')

$ErrorActionPreference = 'SilentlyContinue'

function Row([string]$a, [string]$b) { '{0,-35}{1}' -f $a, $b }

$cfgPath = $Config
if (-not $cfgPath) {
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $cfgPath = Join-Path $root 'runtime\prtg.json'
}

if (-not (Test-Path $cfgPath)) {
    Row 'no config' ''
    'runtime\prtg.json'
    return
}

try { $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { Row 'bad config' ''; return }

if (-not $cfg.server)   { Row 'no server' ''; return }
if (-not $cfg.apitoken) { Row 'no token' 'see prtg.json'; return }

$rows = if ($cfg.rows -and [int]$cfg.rows -gt 0) { [int]$cfg.rows } else { 10 }

# A self-signed certificate is normal on an internal PRTG, but trusting one is
# the person's decision to make, not this script's default.
if ($cfg.insecure -eq $true) {
    try {
        Add-Type @'
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class PrtgCertPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate c, WebRequest r, int p) { return true; }
}
'@ -ErrorAction SilentlyContinue
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object PrtgCertPolicy
    } catch { }
}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# status 5 is Down, 13 Down (Acknowledged), 14 Down (Partial). Sorted by
# lastup descending -- PRTG's "-" prefix -- so the most recently up is at the
# top: the smallest time since it was last seen, which is what has just gone
# down and is worth looking at. Something down for three years is not news.
$uri = ('{0}/api/table.json?content=sensors&output=json&columns=device,sensor,lastup,status' +
        '&filter_status=5&filter_status=13&filter_status=14&sortby=-lastup&count={1}&apitoken={2}') -f
       $cfg.server.TrimEnd('/'), $rows, [uri]::EscapeDataString([string]$cfg.apitoken)

try {
    $resp = Invoke-RestMethod -Uri $uri -TimeoutSec 20 -ErrorAction Stop
} catch {
    # Never echo the exception verbatim: it quotes the URL, token and all.
    $code = ''
    try { $code = [int]$_.Exception.Response.StatusCode } catch { }
    Row 'unreachable' $(if ($code) { "http $code" } else { 'no answer' })
    return
}

$list = @($resp.sensors)
if ($list.Count -eq 0) {
    Row 'all up' ''
    return
}

foreach ($s in $list | Select-Object -First $rows) {
    # PRTG's "lastup" is display HTML, not a date: it comes back as
    #   9/1/2023 2:59:31 AM <span class="percent">[1132 d ago]</span>
    # which no date parser will take. Every column also has a _raw twin, and
    # for a datetime that is an OLE automation date -- a plain number of days
    # since 1899-12-30. Use that and do the arithmetic here.
    $when = 'never'
    $stamp = [datetime]::MinValue
    $ole = 0.0
    if ($s.lastup_raw -ne $null -and
        [double]::TryParse([string]$s.lastup_raw, [ref]$ole) -and $ole -gt 0) {
        try { $stamp = [datetime]::FromOADate($ole) } catch { }
    }
    if ($stamp -eq [datetime]::MinValue) {
        # No usable raw value: fall back to the text with the markup stripped.
        $text = ([string]$s.lastup) -replace '<[^>]+>', ''
        $text = ($text -replace '\[.*?\]', '').Trim()
        $parsed = [datetime]::MinValue
        if ($text -and [datetime]::TryParse($text, [ref]$parsed)) { $stamp = $parsed }
    }
    if ($stamp -ne [datetime]::MinValue) {
        $ago = (Get-Date) - $stamp
        $when = if ($ago.TotalDays -ge 1) { '{0:0}d {1:00}h' -f $ago.Days, $ago.Hours }
                elseif ($ago.TotalHours -ge 1) { '{0:0}h {1:00}m' -f $ago.Hours, $ago.Minutes }
                else { '{0:0}m' -f $ago.TotalMinutes }
    }
    $name = [string]$s.sensor
    $dev = [string]$s.device
    $label = if ($dev) { "$dev/$name" } else { $name }
    if ($label.Length -gt 34) { $label = $label.Substring(0, 33) + '.' }
    Row $label $when
}

$total = 0
try { $total = [int]$resp.treesize } catch { }
if ($total -gt $rows) { Row '' ('+{0} more' -f ($total - $rows)) }
