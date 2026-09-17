<#
.SYNOPSIS
    Run a PowerShell script outside the current MSIX app container.

.DESCRIPTION
    When this toolchain is driven from a packaged host (the Claude desktop app,
    Windows Terminal from the Store, etc.), every write to %APPDATA% /
    %LOCALAPPDATA% is silently redirected into that package's private
    LocalCache. Test-Path still succeeds, but no other process on the machine
    sees the files -- so per-user fonts never register, Rainmeter never finds
    its config, and the wallpaper renders black.

    Task Scheduler launches processes outside any package container, so
    registering a one-shot task is a reliable way to touch the real user
    profile. The task is unregistered again on the way out.

.PARAMETER Script
    Path to the .ps1 to execute outside the container.

.PARAMETER Arguments
    Extra arguments appended to the script invocation.
#>
param(
    [Parameter(Mandatory = $true)][string]$Script,
    [string]$Arguments = '',
    [string]$LogPath = '',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$Script = (Resolve-Path $Script).Path
# The target must live somewhere the *real* profile can read: a script left in
# a redirected AppData path is invisible to the task and it silently fails.
if ($Script -like "$env:APPDATA\*" -or $Script -like "$env:LOCALAPPDATA\*") {
    Write-Warning "$Script is under AppData; a task outside the container may not see it."
}
$taskName = "eDEXTron-Deploy-$([guid]::NewGuid().ToString('N').Substring(0,8))"

$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not $LogPath) {
    $LogPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'eDEX-Tron\outside-run.log'
}
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
# -Command (not -File) so every stream can be redirected into the log; the task
# has no console of its own to report back through.
# Single quotes only inside: this string is nested in the task's own quoted
# argument, and embedded double quotes do not survive that round trip.
$inner = "& { try { & '$Script' $Arguments } catch { 'FATAL: ' + `$_.Exception.Message; `$_.ScriptStackTrace } } *>&1 | Out-File -FilePath '$LogPath' -Encoding utf8"
$argLine = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"$inner`""

$action    = New-ScheduledTaskAction -Execute $psExe -Argument $argLine
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 700
        $info = Get-ScheduledTaskInfo -TaskName $taskName
        $state = (Get-ScheduledTask -TaskName $taskName).State
    } while ($state -eq 'Running' -and (Get-Date) -lt $deadline)

    if ($state -eq 'Running') { Write-Warning "Task still running after ${TimeoutSeconds}s" }
    Write-Output "outside-container exit code: $($info.LastTaskResult)"
} finally {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}
