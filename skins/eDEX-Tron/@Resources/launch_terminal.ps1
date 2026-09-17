<#
Open the eDEX shell and snap it into the Terminal panel's frame.

Rainmeter cannot host a PTY, so the panel only draws the chrome; this launches
a real Windows Terminal (falling back to PowerShell's console) and moves it to
match. The frame's geometry is written by gen_rainmeter_ini.py into
terminal-pos.txt, so the window and the chrome stay in sync from one source.

Coordinates in that file are logical (DPI-scaled) pixels, matching Rainmeter.
MoveWindow wants physical ones, hence the scale factor.
#>
$ErrorActionPreference = 'SilentlyContinue'

Add-Type @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class TermWin {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern uint GetDpiForSystem();

    public static IntPtr FindByTitle(string needle) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, l) => {
            if (!IsWindowVisible(h)) return true;
            var t = new StringBuilder(512); GetWindowTextW(h, t, 512);
            var c = new StringBuilder(256); GetClassName(h, c, 256);
            string cls = c.ToString();
            if (t.ToString().Contains(needle) &&
                (cls == "CASCADIA_HOSTING_WINDOW_CLASS" || cls == "ConsoleWindowClass")) {
                found = h; return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
'@

[void][TermWin]::SetProcessDPIAware()

$title = 'eDEX Shell'
$res   = $PSScriptRoot
$posFile = Join-Path $res 'terminal-pos.txt'

# defaults if the layout has not been generated yet
$x, $y, $w, $h = 286, 60, 700, 560
if (Test-Path $posFile) {
    $parts = (Get-Content $posFile -Raw).Trim() -split ','
    if ($parts.Count -eq 4) { $x, $y, $w, $h = [int]$parts[0], [int]$parts[1], [int]$parts[2], [int]$parts[3] }
}

$scale = [TermWin]::GetDpiForSystem() / 96.0
$px = [int]($x * $scale); $py = [int]($y * $scale)
$pw = [int]($w * $scale); $ph = [int]($h * $scale)

# already open? bring it back and re-snap it
$hwnd = [TermWin]::FindByTitle($title)
if ($hwnd -ne [IntPtr]::Zero) {
    # MoveWindow on a minimised window repositions it while it stays minimised,
    # so restore first (SW_RESTORE = 9) or the panel just looks empty.
    if ([TermWin]::IsIconic($hwnd)) {
        [void][TermWin]::ShowWindow($hwnd, 9)
        Start-Sleep -Milliseconds 250
    }
    [void][TermWin]::MoveWindow($hwnd, $px, $py, $pw, $ph, $true)
    [void][TermWin]::SetForegroundWindow($hwnd)
    return
}

# Command Prompt, not PowerShell. Passing cmd.exe as the command line rather
# than naming a profile means this does not break if the "Command Prompt"
# profile has been renamed or removed; it still picks up the default profile's
# eDEX Tron colours.
$wt = Get-Command wt.exe -ErrorAction SilentlyContinue
if ($wt) {
    Start-Process wt.exe -ArgumentList @('--title', "`"$title`"", '-d', "`"$env:USERPROFILE`"", 'cmd.exe')
} else {
    # no Windows Terminal: fall back to a bare console, titled to match
    Start-Process cmd.exe -ArgumentList @('/K', "title $title")
}

# the window takes a moment to exist; poll rather than guess a sleep
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 150
    $hwnd = [TermWin]::FindByTitle($title)
    if ($hwnd -ne [IntPtr]::Zero) {
        Start-Sleep -Milliseconds 250        # let it finish its own initial layout
        [void][TermWin]::MoveWindow($hwnd, $px, $py, $pw, $ph, $true)
        break
    }
}
