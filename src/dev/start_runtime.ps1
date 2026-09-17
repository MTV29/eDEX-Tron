# Start (or stop) the theme's live parts through eDEX-Tron.exe, detached.
#
# Win32_Process.Create parents the launcher to the WMI host instead of to us,
# so it survives Task Scheduler tearing down the task's process tree -- which
# is what happens when this is invoked through run_outside.ps1.
param([ValidateSet('start', 'stop', 'toggle')][string]$Action = 'start')

$exe = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'eDEX-Tron\eDEX-Tron.exe'
if (-not (Test-Path $exe)) { throw "Launcher not built: $exe" }

$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create `
                      -Arguments @{ CommandLine = "`"$exe`" $Action" }
"Win32_Process.Create -> ReturnValue=$($r.ReturnValue) ProcessId=$($r.ProcessId)"

Start-Sleep -Seconds 6
foreach ($n in 'Rainmeter', 'TranslucentTB', 'WindowsTerminal') {
    "{0,-16} {1}" -f $n, [bool](Get-Process -Name $n -ErrorAction SilentlyContinue)
}
