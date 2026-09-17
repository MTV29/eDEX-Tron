# Report where Rainmeter actually placed each skin, in true physical pixels.
# Rainmeter is DPI-aware, so a DPI-unaware caller sees virtualised coordinates
# and cannot tell whether a panel really fits on screen.
Add-Type @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class SkinRects {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static List<string> Go() {
    SetProcessDPIAware();
    var res = new List<string>();
    res.Add(string.Format("physical desktop: {0}x{1}", GetSystemMetrics(0), GetSystemMetrics(1)));
    int w = GetSystemMetrics(0);
    EnumWindows((h, l) => {
      var cn = new StringBuilder(256); GetClassName(h, cn, 256);
      if (cn.ToString() == "RainmeterMeterWindow" && IsWindowVisible(h)) {
        RECT r; GetWindowRect(h, out r);
        res.Add(string.Format("x={0,5} y={1,5}  {2,4}x{3,-4}  right={4,5} {5}",
          r.L, r.T, r.R - r.L, r.B - r.T, r.R, r.R > w ? "<-- OFF SCREEN" : ""));
      }
      return true;
    }, IntPtr.Zero);
    return res;
  }
}
'@
[SkinRects]::Go() | ForEach-Object { $_ }
