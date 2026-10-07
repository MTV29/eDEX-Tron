# One wallpaper per display, rendered at that display's own resolution.
#
# Windows takes a single wallpaper image and a single fit mode, which is fine
# on one screen and wrong on two of different shapes: "fill" scales the same
# 16:9 image onto a 21:9 monitor and stretches it, and "span" assumes the
# displays tile into a rectangle, which they rarely do.
#
# IDesktopWallpaper (Windows 8 and later) sets a different image per monitor.
# Each one is generated at its exact pixel size, so the grid stays square and
# nothing is scaled at all.
#
# Must run OUTSIDE any app container -- see run_outside.ps1 -- or the wallpaper
# is set inside the container and the real desktop does not change.
param(
    [string]$OutDir = "$env:LOCALAPPDATA\eDEX-Tron\wallpaper",
    [switch]$Report
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# The COM work stays in C#. PowerShell cannot cast a coclass to an interface
# the way C# can -- (IDesktopWallpaper)new DesktopWallpaperClass() is a
# compile-time QueryInterface, and New-Object gives back a __ComObject that
# PowerShell will not convert. So the interface is used from C# and only plain
# values cross back.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IDesktopWallpaper
{
    void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID,
                      [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
    [return: MarshalAs(UnmanagedType.LPWStr)]
    string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
    [return: MarshalAs(UnmanagedType.LPWStr)]
    string GetMonitorDevicePathAt(uint monitorIndex);
    uint GetMonitorDevicePathCount();
    Wall.RECT GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
    void SetBackgroundColor(uint color);
    uint GetBackgroundColor();
    void SetPosition(int position);
    int GetPosition();
}

[ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")]
class DesktopWallpaperClass { }

public static class Wall
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    static IDesktopWallpaper Get()
    {
        return (IDesktopWallpaper)new DesktopWallpaperClass();
    }

    public static int Count() { return (int)Get().GetMonitorDevicePathCount(); }
    public static string PathAt(int i) { return Get().GetMonitorDevicePathAt((uint)i); }

    /// <summary>left,top,width,height -- or all zeroes for a detached path.</summary>
    public static int[] Rect(string id)
    {
        try
        {
            RECT r = Get().GetMonitorRECT(id);
            return new int[] { r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top };
        }
        catch { return new int[] { 0, 0, 0, 0 }; }
    }

    public static void Set(string id, string file) { Get().SetWallpaper(id, file); }
    public static void SetPosition(int pos) { Get().SetPosition(pos); }
}
'@

$count = [Wall]::Count()
"monitors reported by Windows: $count"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$made = 0

for ($i = 0; $i -lt $count; $i++) {
    $id = [Wall]::PathAt($i)
    if ([string]::IsNullOrEmpty($id)) { continue }

    # A path can be listed but detached; its rectangle is then empty.
    $r = [Wall]::Rect($id)
    $w = $r[2]
    $h = $r[3]
    if ($w -le 0 -or $h -le 0) { "  [$i] no rectangle, skipping"; continue }

    "  [$i] ${w}x${h} at $($r[0]),$($r[1])"
    if ($Report) { continue }

    # Named for the size, so two displays of the same resolution share one file
    # rather than rendering it twice.
    $png = Join-Path $OutDir "edex-tron-${w}x${h}.png"
    if (-not (Test-Path $png)) {
        & python (Join-Path $PSScriptRoot 'make_wallpaper.py') `
            --width $w --height $h --out $png --config (Join-Path $Root 'theme.json') | Out-Null
        if ($LASTEXITCODE -ne 0) { "      render failed, leaving this monitor alone"; continue }
        "      rendered $(Split-Path $png -Leaf)"
    } else {
        "      reusing $(Split-Path $png -Leaf)"
    }

    [Wall]::Set($id, $png)
    $made++
}

if (-not $Report) {
    # 4 = DWPOS_FILL. Each image already matches its monitor exactly, so this
    # only decides what happens if a resolution changes before the next run.
    [Wall]::SetPosition(4)
    "set $made wallpaper(s)"
}
