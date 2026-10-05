# Capture one window by title, and nothing else on screen.
#
# PrintWindow asks the window to render itself into a bitmap, so this works
# even when the window is behind something -- and, more to the point, it never
# photographs anything the window does not own. Use this rather than
# capture_desktop.ps1 when checking a dialog: a full-screen grab takes whatever
# the person happens to have open with it.
param(
    [Parameter(Mandatory = $true)][string]$Title,
    [string]$Out = "$env:TEMP\edex-window.png"
)

Add-Type -AssemblyName System.Drawing
Add-Type -Namespace Cap -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
public delegate bool EnumProc(IntPtr h, IntPtr l);
public struct RECT { public int Left, Top, Right, Bottom; }
'@

[void][Cap.Win]::SetProcessDPIAware()

$found = [IntPtr]::Zero
$cb = [Cap.Win+EnumProc] {
    param($h, $l)
    if (-not [Cap.Win]::IsWindowVisible($h)) { return $true }
    $sb = New-Object System.Text.StringBuilder 512
    [void][Cap.Win]::GetWindowTextW($h, $sb, 512)
    if ($sb.ToString() -like "*$Title*") { $script:found = $h; return $false }
    return $true
}
[void][Cap.Win]::EnumWindows($cb, [IntPtr]::Zero)

if ($found -eq [IntPtr]::Zero) { throw "no visible window matching '$Title'" }

$r = New-Object Cap.Win+RECT
[void][Cap.Win]::GetWindowRect($found, [ref]$r)
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
if ($w -le 0 -or $h -le 0) { throw "window has no size" }

$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc()
# 2 = PW_RENDERFULLCONTENT, needed for windows that render with the GPU
[void][Cap.Win]::PrintWindow($found, $dc, 2)
$g.ReleaseHdc($dc)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"captured ${w}x${h} -> $Out"
