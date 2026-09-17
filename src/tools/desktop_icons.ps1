<#
.SYNOPSIS
    Show, hide or report the desktop icons.

.DESCRIPTION
    The icon list lives in a SysListView32 under SHELLDLL_DefView, which hangs
    off Progman on a plain desktop but migrates to a WorkerW once a wallpaper
    host has run -- so both parents have to be searched.

    Toggling is a WM_COMMAND 0x7402 to that DefView. That is the same command
    the desktop context menu sends, so it takes effect immediately and needs no
    Explorer restart.
#>
param([ValidateSet('show', 'hide', 'status')][string]$Action = 'status')

Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class DeskIcons {
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string c, string w);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowExW(IntPtr p, IntPtr a, string c, string w);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageW(IntPtr h, uint m, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    public delegate bool EnumProc(IntPtr h, IntPtr l);

    public static IntPtr Progman;
    public static IntPtr WorkerW;

    public static IntPtr FindDefView() {
        Progman = FindWindowW("Progman", null);
        IntPtr v = FindWindowExW(Progman, IntPtr.Zero, "SHELLDLL_DefView", null);
        if (v != IntPtr.Zero) return v;
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, l) => {
            var cls = new StringBuilder(64);
            GetClassNameW(h, cls, 64);
            if (cls.ToString() == "WorkerW") {
                IntPtr w = FindWindowExW(h, IntPtr.Zero, "SHELLDLL_DefView", null);
                if (w != IntPtr.Zero) { WorkerW = h; found = w; return false; }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static bool Visible() {
        IntPtr v = FindDefView();
        if (v == IntPtr.Zero) return true;
        IntPtr list = FindWindowExW(v, IntPtr.Zero, "SysListView32", null);
        return list != IntPtr.Zero && IsWindowVisible(list);
    }

    public static bool Toggle() {
        IntPtr v = FindDefView();
        if (v == IntPtr.Zero) return false;
        SendMessageW(v, 0x0111, (IntPtr)0x7402, IntPtr.Zero);
        return true;
    }
}
'@

$view = [DeskIcons]::FindDefView()
"DefView handle : $view"
"  under Progman: $([DeskIcons]::Progman)   WorkerW: $([DeskIcons]::WorkerW)"
$visible = [DeskIcons]::Visible()
"icons visible  : $visible"

switch ($Action) {
    'status' { break }
    'hide'   { if ($visible) { "toggling -> hide"; [void][DeskIcons]::Toggle() } else { "already hidden" } }
    'show'   { if (-not $visible) { "toggling -> show"; [void][DeskIcons]::Toggle() } else { "already shown" } }
}

if ($Action -ne 'status') {
    Start-Sleep -Milliseconds 700
    "icons visible now: $([DeskIcons]::Visible())"
}
