<#
Edit the dock's shortcut list and rebuild the HUD around it.

Opens dock.txt in Notepad and waits. When you close it, the whole layout is
re-planned (src\tools\relayout.ps1): adding or removing apps can change how
many rows the dock wraps to, which moves the filesystem list and the Desktop
grid, so rebuilding only the dock would leave them overlapping.

Bound to the dock's right-click and to its "+ EDIT" caption.
#>
$ErrorActionPreference = 'Continue'

$docs     = [Environment]::GetFolderPath('MyDocuments')
$project  = Join-Path $docs 'eDEX-Tron'
$config   = Join-Path $project 'dock.txt'
$relayout = Join-Path $project 'src\tools\relayout.ps1'

if (-not (Test-Path $config)) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("Shortcut list not found:`n$config", 'eDEX-Tron') | Out-Null
    return
}

$before = Get-FileHash $config
# Wait for the editor so the rebuild uses the saved file.
Start-Process notepad.exe -ArgumentList "`"$config`"" -Wait
if ((Get-FileHash $config).Hash -eq $before.Hash) { return }   # nothing changed

if (Test-Path $relayout) { & $relayout | Out-Null }
