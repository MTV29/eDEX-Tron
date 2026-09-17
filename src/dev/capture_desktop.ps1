# Capture the desktop (briefly minimising windows) so the HUD can be inspected.
param([string]$Out = "$env:TEMP\edex-desktop.png", [switch]$NoMinimize)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace Cap -Name Keys -MemberDefinition @'
[DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
'@

# Without this the process sees a virtualised 1536x864 desktop while GDI still
# copies physical pixels, so the capture silently crops to the top-left ~80%
# of the screen instead of covering it.
[void][Cap.Keys]::SetProcessDPIAware()

# Shell.Application rather than a synthetic Win+D: the key toggle is swallowed
# when another app holds focus, and it silently no-ops or double-toggles.
$shell = New-Object -ComObject Shell.Application
if (-not $NoMinimize) { $shell.MinimizeAll(); Start-Sleep -Milliseconds 1400 }

$w = [Cap.Keys]::GetSystemMetrics(0)   # SM_CXSCREEN, physical
$h = [Cap.Keys]::GetSystemMetrics(1)   # SM_CYSCREEN, physical
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

if (-not $NoMinimize) { Start-Sleep -Milliseconds 300; $shell.UndoMinimizeALL() }
Write-Output $Out
