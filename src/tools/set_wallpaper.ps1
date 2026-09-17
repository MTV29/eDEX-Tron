<#
.SYNOPSIS
    Set the desktop wallpaper reliably on Windows 11.

.DESCRIPTION
    SystemParametersInfo(SPI_SETDESKWALLPAPER) writes the registry and returns
    success even when the shell never picks the change up -- the transcode
    cache is simply never rebuilt and the desktop stays blank. This script
    prefers the IDesktopWallpaper COM interface, which talks to the shell
    directly, and falls back to SystemParametersInfo.

    It also forces BackgroundType to 0 (picture): a slideshow or Spotlight
    background silently overrides any single wallpaper.
#>
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [ValidateSet('Center','Tile','Stretch','Fit','Fill','Span')][string]$Style = 'Fill'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Path)) { throw "Wallpaper not found: $Path" }
$Path = (Resolve-Path $Path).Path

# --- background type must be "picture" or the wallpaper is ignored
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers'
New-Item -Path $key -Force | Out-Null
Set-ItemProperty $key 'BackgroundType' 0 -Type DWord

Add-Type @'
using System;
using System.Runtime.InteropServices;

// Only the vtable slots up to SetPosition are declared; order matters.
[ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDesktopWallpaper {
    void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID,
                      [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
    void GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID,
                      [Out, MarshalAs(UnmanagedType.LPWStr)] out string wallpaper);
    void GetMonitorDevicePathAt(uint monitorIndex,
                      [Out, MarshalAs(UnmanagedType.LPWStr)] out string monitorID);
    void GetMonitorDevicePathCount(out uint count);
    void GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID, out RECT rect);
    void SetBackgroundColor(uint color);
    void GetBackgroundColor(out uint color);
    void SetPosition(int position);
}

[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left, Top, Right, Bottom; }

public static class Spi {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SystemParametersInfoW(uint a, uint b, string c, uint d);

    // The whole COM conversation stays in C#: handing the RCW back to
    // PowerShell drops the static type, and late binding can't see the
    // interface's methods.
    public static void SetViaShell(string path, int position) {
        Type t = Type.GetTypeFromCLSID(new Guid("C2CF3110-460E-4FC1-B9D0-8A1C0C9CC4BD"));
        IDesktopWallpaper dw = (IDesktopWallpaper)Activator.CreateInstance(t);
        dw.SetPosition(position);
        dw.SetWallpaper(null, path);        // null = apply to every monitor
        Marshal.ReleaseComObject(dw);
    }
}
'@

# DESKTOP_WALLPAPER_POSITION
$positions = @{ Center = 0; Tile = 1; Stretch = 2; Fit = 3; Fill = 4; Span = 5 }
# legacy WallpaperStyle values, kept in sync for anything that reads the registry
$styles    = @{ Center = '0'; Tile = '0'; Stretch = '2'; Fit = '6'; Fill = '10'; Span = '22' }
Set-ItemProperty 'HKCU:\Control Panel\Desktop' 'WallpaperStyle' $styles[$Style]
Set-ItemProperty 'HKCU:\Control Panel\Desktop' 'TileWallpaper' $(if ($Style -eq 'Tile') { '1' } else { '0' })

$applied = $false
try {
    [Spi]::SetViaShell($Path, $positions[$Style])
    $applied = $true
    Write-Output "IDesktopWallpaper: applied '$Path' ($Style)"
} catch {
    Write-Output "IDesktopWallpaper failed ($($_.Exception.Message)); falling back"
}

if (-not $applied) {
    # SPI_SETDESKWALLPAPER, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
    if ([Spi]::SystemParametersInfoW(0x0014, 0, $Path, 0x03)) {
        Write-Output "SystemParametersInfo: applied '$Path'"
    } else {
        throw "Both methods failed to set the wallpaper (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
    }
}
