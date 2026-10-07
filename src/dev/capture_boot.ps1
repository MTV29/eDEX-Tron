# Capture the boot screen repeatedly from one process.
# Starting a PowerShell per frame costs about a second each, which is most of
# the boot screen, so the P/Invoke is set up once and the loop is tight.
param([int]$Frames = 20, [int]$DelayMs = 200, [string]$OutDir = 'runtime', [int]$BootPid = 0)

$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace Boot -Name Cap -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
public delegate bool EnumProc(IntPtr h, IntPtr l);
public struct RECT { public int Left, Top, Right, Bottom; }
'@
[void][Boot.Cap]::SetProcessDPIAware()

# Find the window by walking the top-level windows and matching the process it
# belongs to. Process.MainWindowHandle returns 0 for this one -- the boot
# screen is borderless and maximised, and .NET's heuristic does not pick it --
# while the window is plainly there, visible and titled.
$script:hwnd = [IntPtr]::Zero
function Find-Boot {
    $script:hwnd = [IntPtr]::Zero
    $target = $BootPid
    $cb = [Boot.Cap+EnumProc] {
        param($h, $l)
        if (-not [Boot.Cap]::IsWindowVisible($h)) { return $true }
        $owner = 0
        [void][Boot.Cap]::GetWindowThreadProcessId($h, [ref]$owner)
        if ($owner -ne $target) { return $true }
        $sb = New-Object System.Text.StringBuilder 256
        [void][Boot.Cap]::GetWindowTextW($h, $sb, $sb.Capacity)
        if ($sb.ToString().Length -eq 0) { return $true }
        $script:hwnd = $h
        $false
    }
    [void][Boot.Cap]::EnumWindows($cb, [IntPtr]::Zero)
    $script:hwnd
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Get-ChildItem (Join-Path $OutDir 'boot-*.png') -ErrorAction SilentlyContinue | Remove-Item -Force

$n = 0
for ($i = 0; $i -lt $Frames; $i++) {
    $h = Find-Boot
    if ($h -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 120; continue }
    $r = New-Object Boot.Cap+RECT
    if (-not [Boot.Cap]::GetWindowRect($h, [ref]$r)) { continue }
    $w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
    if ($w -le 0 -or $hh -le 0) { continue }
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $dc = $g.GetHdc()
    $ok = [Boot.Cap]::PrintWindow($h, $dc, 2)
    $g.ReleaseHdc($dc); $g.Dispose()
    if ($ok) {
        $bmp.Save((Join-Path $OutDir ('boot-{0:d3}.png' -f $n)),
                  [System.Drawing.Imaging.ImageFormat]::Png)
        $n++
    }
    $bmp.Dispose()
    Start-Sleep -Milliseconds $DelayMs
}
"captured $n frame(s)"
