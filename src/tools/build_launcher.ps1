<#
.SYNOPSIS
    Compile eDEX-Tron.exe, the theme's on/off switch.

.DESCRIPTION
    Produces a small GUI executable (no console flash) that starts or stops the
    live parts of the theme: the Rainmeter HUD, TranslucentTB's taskbar
    transparency, the shell window, and the desktop icons -- which the dock
    replaces, so they are hidden while the theme is on and restored when it is
    off.

        eDEX-Tron.exe            toggle
        eDEX-Tron.exe start
        eDEX-Tron.exe stop
        eDEX-Tron.exe status     shows a message box

    It deliberately does NOT touch the wallpaper, accent colour or fonts --
    those are the persistent theme; src\uninstall.ps1 reverts them.

    Uses the .NET compiler that ships with Windows, so nothing extra is needed.
    Machine-specific paths are baked in at build time.
#>
param(
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $OutFile) { $OutFile = Join-Path $root 'eDEX-Tron.exe' }

# --- resolve what this machine actually has
$rainmeter = Join-Path ${env:ProgramFiles} 'Rainmeter\Rainmeter.exe'
if (-not (Test-Path $rainmeter)) { Write-Warning "Rainmeter not found at $rainmeter" }

$ttbArg = ''
$pkg = Get-AppxPackage -Name '*TranslucentTB*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pkg) { $ttbArg = "shell:AppsFolder\$($pkg.PackageFamilyName)!TranslucentTB" }
else { Write-Warning 'TranslucentTB not installed; the launcher will skip it' }

$termScript = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins\eDEX-Tron\@Resources\launch_terminal.ps1'
$refreshScript = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins\eDEX-Tron\@Resources\refresh_desktop.ps1'

function Esc($s) { $s -replace '\\', '\\' -replace '"', '\"' }

$source = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Text;
using System.Windows.Forms;

static class EdexTron
{
    const string RainmeterPath = "$(Esc $rainmeter)";
    const string TtbArg        = "$(Esc $ttbArg)";
    const string TermScript    = "$(Esc $termScript)";
    const string RefreshScript = "$(Esc $refreshScript)";
    const string WatcherMutex  = @"Local\eDEX-Tron-DesktopWatcher";

    // CharSet.Unicode is required on every one of these: the default is Ansi,
    // which marshals the class names as narrow strings into the wide-char
    // entry points, so the lookups silently never match.
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowW(string cls, string win);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowExW(IntPtr parent, IntPtr after, string cls, string win);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr SendMessageW(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    delegate bool EnumProc(IntPtr h, IntPtr l);

    const uint WM_COMMAND = 0x0111;
    const int TOGGLE_DESKTOP_ICONS = 0x7402;

    // The icon list lives under SHELLDLL_DefView, which hangs off Progman on a
    // plain desktop but moves to a WorkerW once a wallpaper host has run.
    static IntPtr FindDefView()
    {
        IntPtr progman = FindWindowW("Progman", null);
        IntPtr view = FindWindowExW(progman, IntPtr.Zero, "SHELLDLL_DefView", null);
        if (view != IntPtr.Zero) return view;

        IntPtr found = IntPtr.Zero;
        EnumWindows((h, l) =>
        {
            var cls = new StringBuilder(64);
            GetClassNameW(h, cls, 64);
            if (cls.ToString() == "WorkerW")
            {
                IntPtr v = FindWindowExW(h, IntPtr.Zero, "SHELLDLL_DefView", null);
                if (v != IntPtr.Zero) { found = v; return false; }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    static bool DesktopIconsVisible()
    {
        IntPtr view = FindDefView();
        if (view == IntPtr.Zero) return true;
        IntPtr list = FindWindowExW(view, IntPtr.Zero, "SysListView32", null);
        return list != IntPtr.Zero && IsWindowVisible(list);
    }

    static void SetDesktopIcons(bool show)
    {
        if (DesktopIconsVisible() == show) return;
        IntPtr view = FindDefView();
        if (view != IntPtr.Zero)
            SendMessageW(view, WM_COMMAND, (IntPtr)TOGGLE_DESKTOP_ICONS, IntPtr.Zero);
    }

    static bool Running(string name)
    {
        return Process.GetProcessesByName(name).Length > 0;
    }

    static void Kill(string name)
    {
        foreach (var p in Process.GetProcessesByName(name))
        {
            try { p.Kill(); p.WaitForExit(4000); } catch { }
        }
    }

    static void StartQuiet(string file, string args)
    {
        try
        {
            var psi = new ProcessStartInfo(file, args);
            psi.UseShellExecute = true;
            psi.WindowStyle = ProcessWindowStyle.Hidden;
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            MessageBox.Show("Could not start:\n" + file + "\n\n" + ex.Message,
                "eDEX-Tron", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    static bool IsOn() { return Running("Rainmeter"); }

    // ---- Desktop watcher ------------------------------------------------
    // The Desktop panel is generated (icons come from the shell), so it has to
    // be rebuilt when the folder changes. A FileSystemWatcher is event-driven:
    // nothing polls, and it catches renames that an item count would miss.
    // It runs as a second copy of this exe ("watch"), held single by a mutex.

    static bool WatcherRunning()
    {
        try { using (Mutex.OpenExisting(WatcherMutex)) return true; }
        catch { return false; }
    }

    static void RunRefresh()
    {
        if (!File.Exists(RefreshScript)) return;
        try
        {
            var psi = new ProcessStartInfo("powershell.exe",
                "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + RefreshScript + "\"");
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            using (var p = Process.Start(psi)) p.WaitForExit(120000);
        }
        catch { }
    }

    static void Watch()
    {
        bool created;
        using (var mutex = new Mutex(true, WatcherMutex, out created))
        {
            if (!created) return;               // one watcher is enough

            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            RunRefresh();                       // catch changes made while the theme was off

            // Debounce: a copy or unzip fires many events; rebuild once they settle.
            var timer = new System.Threading.Timer(_ => RunRefresh(), null, Timeout.Infinite, Timeout.Infinite);
            FileSystemEventHandler changed = (s, e) => timer.Change(1500, Timeout.Infinite);

            var fsw = new FileSystemWatcher(desktop);
            fsw.IncludeSubdirectories = false;
            fsw.NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName;
            fsw.Created += changed;
            fsw.Deleted += changed;
            fsw.Renamed += (s, e) => timer.Change(1500, Timeout.Infinite);
            fsw.EnableRaisingEvents = true;

            Thread.Sleep(Timeout.Infinite);     // ended by Stop() killing this process
        }
    }

    static void StopWatcher()
    {
        int self = Process.GetCurrentProcess().Id;
        foreach (var p in Process.GetProcessesByName(Process.GetCurrentProcess().ProcessName))
        {
            if (p.Id == self) continue;
            try { p.Kill(); p.WaitForExit(4000); } catch { }
        }
    }

    static void Start()
    {
        if (RainmeterPath.Length > 0 && !Running("Rainmeter"))
            StartQuiet(RainmeterPath, "");

        if (TtbArg.Length > 0 && !Running("TranslucentTB"))
            StartQuiet("explorer.exe", TtbArg);

        SetDesktopIcons(false);

        if (TermScript.Length > 0)
            StartQuiet("powershell.exe",
                "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + TermScript + "\"");

        if (!WatcherRunning())
            StartQuiet(Process.GetCurrentProcess().MainModule.FileName, "watch");
    }

    static void Stop()
    {
        Kill("Rainmeter");
        Kill("TranslucentTB");
        StopWatcher();
        SetDesktopIcons(true);
    }

    [STAThread]
    static int Main(string[] argv)
    {
        string cmd = argv.Length > 0 ? argv[0].ToLowerInvariant().TrimStart('-', '/') : "toggle";
        switch (cmd)
        {
            case "start":  Start(); break;
            case "stop":   Stop();  break;
            case "watch":  Watch(); break;
            case "status":
                MessageBox.Show("eDEX-Tron is currently " + (IsOn() ? "ON" : "OFF") + ".",
                    "eDEX-Tron", MessageBoxButtons.OK, MessageBoxIcon.Information);
                break;
            case "toggle": if (IsOn()) Stop(); else Start(); break;
            default:
                MessageBox.Show("Usage: eDEX-Tron.exe [start|stop|toggle|status|watch]",
                    "eDEX-Tron", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return 1;
        }
        return 0;
    }
}
"@

# Compile with csc.exe rather than Add-Type: only csc can attach a Win32 icon
# resource (/win32icon), and Add-Type exposes no equivalent. csc ships with the
# .NET Framework that is present on every Windows install.
$icon = Join-Path $root 'assets\icon\edex-tron.ico'
$csc = @("$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
         "$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319\csc.exe") |
       Where-Object { Test-Path $_ } | Select-Object -First 1

$watcherWasUp = [bool](Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($OutFile)) -ErrorAction SilentlyContinue)
Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($OutFile)) -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 300

if ($csc -and (Test-Path $icon)) {
    $cs = Join-Path ([IO.Path]::GetTempPath()) ("edex-tron-{0}.cs" -f [guid]::NewGuid().ToString('N'))
    $source | Set-Content $cs -Encoding UTF8
    try {
        $args = @('/nologo', '/target:winexe', '/optimize+',
                  "/win32icon:$icon", "/out:$OutFile",
                  '/reference:System.dll',
                  '/reference:System.Windows.Forms.dll',
                  '/reference:System.Drawing.dll', $cs)
        $out = & $csc @args 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($out | Out-String) }
        "built $OutFile ({0:N0} bytes) with embedded icon" -f (Get-Item $OutFile).Length
    } finally {
        Remove-Item $cs -Force -ErrorAction SilentlyContinue
    }
} else {
    if (-not $icon -or -not (Test-Path $icon)) {
        Write-Warning "No icon at $icon - run src\tools\gen_icon.py first"
    }
    Add-Type -TypeDefinition $source `
             -OutputAssembly $OutFile `
             -OutputType WindowsApplication `
             -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing'
    "built $OutFile ({0:N0} bytes) without icon" -f (Get-Item $OutFile).Length
}
"  Rainmeter : $rainmeter"
"  TranslucentTB : $(if ($ttbArg) { $ttbArg } else { '(not installed)' })"
"  shell script  : $termScript"

if ($watcherWasUp -and (Get-Process Rainmeter -ErrorAction SilentlyContinue)) {
    # Win32_Process.Create: survive this script ending, even under Task Scheduler
    [void](Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = "`"$OutFile`" watch" })
    "  desktop watcher restarted"
}
