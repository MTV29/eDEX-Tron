// eDEX-Tron.exe -- the theme's switch, settings window and boot screen.
//
// build_launcher.ps1 compiles this with the C# compiler that ships with
// Windows, substituting the double-percent placeholders below with the paths
// it resolves on this machine. Keep them inside verbatim strings: Windows
// paths are full of backslashes and nothing here should have to escape them.
//
//     eDEX-Tron.exe                 toggle the theme
//     eDEX-Tron.exe start|stop      ... explicitly
//     eDEX-Tron.exe status          what is running, and why a panel is missing
//     eDEX-Tron.exe settings        the settings window
//     eDEX-Tron.exe boot            replay the boot screen
//     eDEX-Tron.exe watch           the background half (hotkeys, sound,
//                                   folder watchers, shell snapping)
//     eDEX-Tron.exe restart-watcher reload the toggles from theme.json
//
// It deliberately does NOT touch the wallpaper, accent colour or fonts: those
// are the persistent theme, and src\uninstall.ps1 reverts them.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.ServiceProcess;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

static class EdexTron
{
    const string RainmeterPath  = @"%%RAINMETER%%";
    const string TtbArg         = @"%%TTBARG%%";
    const string TermScript     = @"%%TERMSCRIPT%%";
    const string RefreshScript  = @"%%REFRESHSCRIPT%%";
    const string SettingsScript = @"%%SETTINGSSCRIPT%%";
    const string RelayoutScript = @"%%RELAYOUTSCRIPT%%";
    internal const string ProjectRoot = @"%%PROJECTROOT%%";
    const string KeySound       = @"%%KEYSOUND%%";
    const string Version        = @"%%VERSION%%";
    const string WatcherMutex   = @"Local\eDEX-Tron-DesktopWatcher";
    const string ShellTitle     = "eDEX Shell";

    // Every skin in the suite, in the order gen_rainmeter_ini.py loads them.
    static readonly string[] Configs = {
        "Clock", "CpuInfo", "NetStat", "RamWatcher", "ConnInfo", "TopList",
        "Disk", "Ports", "Gpu", "Power", "Terminal", "Folder", "Dock", "Desktop",
    };

    // ---------------------------------------------------------------- win32 ---
    // CharSet.Unicode is required on every one of these: the default is Ansi,
    // which marshals the class names as narrow strings into the wide-char
    // entry points, so the lookups silently never match.
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowW(string cls, string win);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowExW(IntPtr parent, IntPtr after, string cls, string win);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("kernel32.dll")] static extern bool AttachConsole(int pid);
    const int ATTACH_PARENT_PROCESS = -1;
    [DllImport("user32.dll")] static extern IntPtr SendMessageW(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int index);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h, int index, int value);
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetWindowsHookEx(int id, HookProc cb, IntPtr mod, uint tid);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern uint GetDpiForSystem();
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] static extern bool SystemParametersInfoW(uint action, uint param, ref RECT r, uint winIni);
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)] static extern bool PlaySoundW(string snd, IntPtr mod, uint flags);
    [DllImport("winmm.dll", EntryPoint = "PlaySoundW")] static extern bool PlaySoundMem(IntPtr snd, IntPtr mod, uint flags);
    [DllImport("kernel32.dll")] static extern ulong GetTickCount64();
    [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX s);

    delegate bool EnumProc(IntPtr h, IntPtr l);
    delegate IntPtr HookProc(int code, IntPtr wp, IntPtr lp);

    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    struct MEMORYSTATUSEX
    {
        public uint Length, MemoryLoad;
        public ulong TotalPhys, AvailPhys, TotalPageFile, AvailPageFile,
                     TotalVirtual, AvailVirtual, AvailExtendedVirtual;
    }

    const uint WM_COMMAND = 0x0111;
    const int WM_HOTKEY = 0x0312;
    const int WM_DISPLAYCHANGE = 0x007E;
    const int WM_SETTINGCHANGE = 0x001A;
    const int SPI_SETWORKAREA = 0x002F;
    const uint SPI_GETWORKAREA = 0x0030;
    const int SM_CXSCREEN = 0, SM_CYSCREEN = 1, SM_CMONITORS = 80;
    const int SM_CXVIRTUALSCREEN = 78, SM_CYVIRTUALSCREEN = 79;
    const int TOGGLE_DESKTOP_ICONS = 0x7402;
    const int GWL_EXSTYLE = -20;
    const int WS_EX_TOOLWINDOW = 0x00000080;
    const int WS_EX_APPWINDOW = 0x00040000;
    const int SW_HIDE = 0, SW_SHOW = 5, SW_RESTORE = 9;
    const uint MOD_ALT = 0x0001, MOD_WIN = 0x0008, MOD_NOREPEAT = 0x4000;
    const int WH_KEYBOARD_LL = 13;
    const int WM_KEYDOWN = 0x0100, WM_SYSKEYDOWN = 0x0104;
    const int WM_KEYUP = 0x0101, WM_SYSKEYUP = 0x0105;
    const uint SND_ASYNC = 0x0001, SND_NODEFAULT = 0x0002, SND_MEMORY = 0x0004,
               SND_FILENAME = 0x00020000;

    // --------------------------------------------------------- theme.json ----
    // Flat JSON, read with a regex rather than a serializer: csc has no JSON
    // reader in the framework assemblies, and settings.ps1 owns every write.
    static string ThemeText()
    {
        try { return File.ReadAllText(Path.Combine(ProjectRoot, "theme.json")); }
        catch { return ""; }
    }

    static bool Flag(string key, bool fallback)
    {
        var m = Regex.Match(ThemeText(), "\"" + key + "\"\\s*:\\s*(true|false)",
                            RegexOptions.IgnoreCase);
        return m.Success ? m.Groups[1].Value.ToLowerInvariant() == "true" : fallback;
    }

    internal static string Str(string key, string fallback)
    {
        var m = Regex.Match(ThemeText(), "\"" + key + "\"\\s*:\\s*\"([^\"]*)\"");
        return m.Success ? m.Groups[1].Value : fallback;
    }

    // A number out of theme.json, which Str cannot read: it only matches
    // quoted values, and these are written bare.
    internal static double Number(string key, double fallback)
    {
        var m = Regex.Match(ThemeText(), "\"" + key + "\"\\s*:\\s*(-?[0-9.]+)");
        double v;
        if (m.Success && double.TryParse(m.Groups[1].Value, NumberStyles.Float,
                                         CultureInfo.InvariantCulture, out v)) return v;
        return fallback;
    }

    static Color Accent()
    {
        try
        {
            string hex = Str("accent", "#aacfd1").TrimStart('#');
            return Color.FromArgb(
                int.Parse(hex.Substring(0, 2), NumberStyles.HexNumber),
                int.Parse(hex.Substring(2, 2), NumberStyles.HexNumber),
                int.Parse(hex.Substring(4, 2), NumberStyles.HexNumber));
        }
        catch { return Color.FromArgb(170, 207, 209); }
    }

    static Color Background()
    {
        try
        {
            string hex = Str("background", "#05080d").TrimStart('#');
            return Color.FromArgb(
                int.Parse(hex.Substring(0, 2), NumberStyles.HexNumber),
                int.Parse(hex.Substring(2, 2), NumberStyles.HexNumber),
                int.Parse(hex.Substring(4, 2), NumberStyles.HexNumber));
        }
        catch { return Color.FromArgb(5, 8, 13); }
    }

    // ------------------------------------------------------- desktop icons ---
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

    // -------------------------------------------------------------- process ---
    static bool Running(string name) { return Process.GetProcessesByName(name).Length > 0; }

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

    // StartQuiet asks for a hidden window, and a WinForms process started that
    // way honours it: its first form comes up invisible. Anything meant to be
    // seen has to be started without that.
    static void StartVisible(string file, string args)
    {
        try
        {
            var psi = new ProcessStartInfo(file, args);
            psi.UseShellExecute = true;
            Process.Start(psi);
        }
        catch { }
    }

    static string RunCaptured(string file, string args, int timeoutMs)
    {
        try
        {
            var psi = new ProcessStartInfo(file, args);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            using (var p = Process.Start(psi))
            {
                string stdout = p.StandardOutput.ReadToEnd();
                string stderr = p.StandardError.ReadToEnd();
                p.WaitForExit(timeoutMs);
                return stdout + (stderr.Trim().Length > 0 ? "\n" + stderr : "");
            }
        }
        catch (Exception ex) { return "error: " + ex.Message; }
    }

    static string PowerShellArgs(string script, string rest)
    {
        return "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \""
               + script + "\"" + (rest.Length > 0 ? " " + rest : "");
    }

    static bool IsOn() { return Running("Rainmeter"); }

    static void Bang(string bang, string config)
    {
        if (RainmeterPath.Length == 0 || !File.Exists(RainmeterPath)) return;
        try
        {
            var psi = new ProcessStartInfo(RainmeterPath,
                bang + (config.Length > 0 ? " \"eDEX-Tron\\" + config + "\"" : ""));
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            Process.Start(psi);
        }
        catch { }
    }

    // The Folder panel's folder, as relayout.ps1 recorded it from theme.json.
    static string FolderPanelPath()
    {
        try
        {
            string file = Path.Combine(ProjectRoot, "runtime", "folder-path.txt");
            if (File.Exists(file))
            {
                string path = Environment.ExpandEnvironmentVariables(File.ReadAllText(file).Trim());
                if (path.Length > 0) return path;
            }
        }
        catch { }
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Games");
    }

    static void RunRefresh(string panel)
    {
        if (!File.Exists(RefreshScript)) return;
        try
        {
            var psi = new ProcessStartInfo("powershell.exe",
                PowerShellArgs(RefreshScript, "-Panel " + panel));
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            using (var p = Process.Start(psi)) p.WaitForExit(120000);
        }
        catch { }
    }

    // ---------------------------------------------------------- shell frame ---
    // Rainmeter cannot host a PTY, so the MAIN SHELL panel is only chrome and a
    // real console window is moved into it. Left alone it drifts: anything that
    // moves or resizes it leaves the frame empty with a terminal floating next
    // to it. The watcher keeps it in place.
    static IntPtr FindShell()
    {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, l) =>
        {
            if (!IsWindowVisible(h)) return true;
            var t = new StringBuilder(512); GetWindowTextW(h, t, 512);
            if (t.ToString().IndexOf(ShellTitle, StringComparison.Ordinal) < 0) return true;
            var c = new StringBuilder(256); GetClassNameW(h, c, 256);
            string cls = c.ToString();
            if (cls == "CASCADIA_HOSTING_WINDOW_CLASS" || cls == "ConsoleWindowClass")
            {
                found = h; return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    // terminal-pos.txt is written by gen_rainmeter_ini.py in logical pixels, so
    // the window and the chrome stay in sync from one source.
    static bool ShellTarget(out Rectangle rect)
    {
        rect = Rectangle.Empty;
        try
        {
            string file = Path.Combine(Path.GetDirectoryName(TermScript), "terminal-pos.txt");
            string[] parts = File.ReadAllText(file).Trim().Split(',');
            if (parts.Length != 4) return false;
            double scale = GetDpiForSystem() / 96.0;
            rect = new Rectangle(
                (int)(int.Parse(parts[0]) * scale), (int)(int.Parse(parts[1]) * scale),
                (int)(int.Parse(parts[2]) * scale), (int)(int.Parse(parts[3]) * scale));
            return rect.Width > 0 && rect.Height > 0;
        }
        catch { return false; }
    }

    static readonly HashSet<IntPtr> altTabHidden = new HashSet<IntPtr>();

    static void HideFromAltTab(IntPtr hwnd)
    {
        if (altTabHidden.Contains(hwnd)) return;
        altTabHidden.Add(hwnd);
        // The style only takes on a hidden window, so blink it.
        int ex = GetWindowLong(hwnd, GWL_EXSTYLE);
        ShowWindow(hwnd, SW_HIDE);
        SetWindowLong(hwnd, GWL_EXSTYLE, (ex | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW);
        ShowWindow(hwnd, SW_SHOW);
    }

    static void KeepShellInFrame()
    {
        if (!IsOn()) return;
        IntPtr hwnd = FindShell();
        if (hwnd == IntPtr.Zero) { altTabHidden.Clear(); return; }

        if (!Flag("shellalttab", false)) HideFromAltTab(hwnd);

        Rectangle want;
        if (!ShellTarget(out want)) return;
        // Don't fight someone who is dragging the window right now.
        if ((GetAsyncKeyState(0x01) & 0x8000) != 0) return;
        if (IsIconic(hwnd)) return;          // minimised on purpose; leave it

        RECT got;
        if (!GetWindowRect(hwnd, out got)) return;
        if (Math.Abs(got.Left - want.X) <= 8 && Math.Abs(got.Top - want.Y) <= 8 &&
            Math.Abs((got.Right - got.Left) - want.Width) <= 8 &&
            Math.Abs((got.Bottom - got.Top) - want.Height) <= 8) return;
        MoveWindow(hwnd, want.X, want.Y, want.Width, want.Height, true);
    }

    static void FocusShell()
    {
        IntPtr hwnd = FindShell();
        if (hwnd == IntPtr.Zero)
        {
            if (TermScript.Length > 0)
                StartQuiet("powershell.exe", PowerShellArgs(TermScript, ""));
            return;
        }
        if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
        SetForegroundWindow(hwnd);
    }

    // ---------------------------------------------------------- key clicks ---
    // A keyboard sound, the way eDEX-UI has one. The hook is only ever asked
    // *whether* a key went down: it never looks at lParam, so no key identity
    // is read, stored or passed on. Switched off unless theme.json says
    // "keyclick": true.
    static IntPtr keyHook = IntPtr.Zero;
    static HookProc keyHookProc;             // a field, or the GC collects it
    static string keySoundFile;
    static AutoResetEvent keyRang;
    static Thread keyPlayer;
    static int keyLastTick;

    // Which keys are physically down, so that holding one is one keystroke.
    //
    // This is the only place the theme looks at *which* key was pressed, and
    // it does so to answer one question: is this a new press, or Windows
    // repeating a key the person is still holding? Auto-repeat runs at about
    // thirty a second, so without this, leaning on Shift or an arrow key is a
    // machine gun. The code is used as an index and nothing more -- no key is
    // recorded, counted, written down or passed on.
    static readonly bool[] keyIsDown = new bool[256];

    // A low-level keyboard hook has to return promptly: take longer than
    // LowLevelHooksTimeout (300ms by default) and Windows quietly unhooks you,
    // and the clicks stop until something re-installs them. So this does no
    // work at all -- no disk, no audio call -- it just nudges a thread that
    // does. That is what the "sometimes it works" came down to.
    static IntPtr OnKey(int code, IntPtr wp, IntPtr lp)
    {
        if (code >= 0)
        {
            int msg = (int)wp;
            int vk = Marshal.ReadInt32(lp) & 0xFF;      // KBDLLHOOKSTRUCT.vkCode
            if (msg == WM_KEYUP || msg == WM_SYSKEYUP)
            {
                keyIsDown[vk] = false;
            }
            else if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
            {
                if (!keyIsDown[vk])
                {
                    keyIsDown[vk] = true;
                    // A floor on the rate as well, for the typist who really
                    // is hitting two hundred keys a minute on purpose.
                    int now = Environment.TickCount;
                    if (now - keyLastTick >= 20)
                    {
                        keyLastTick = now;
                        keyRang.Set();
                    }
                }
            }
        }
        return CallNextHookEx(keyHook, code, wp, lp);
    }

    static int keyPlays;

    static void PlayClicks()
    {
        while (true)
        {
            keyRang.WaitOne();
            if (keyHook == IntPtr.Zero) return;
            try
            {
                if (KeyAudio.Ready) KeyAudio.Play();
                else PlaySoundW(keySoundFile, IntPtr.Zero, SND_FILENAME | SND_NODEFAULT);
                if (++keyPlays <= 3) Log("key click " + keyPlays + " played");
            }
            catch (Exception ex)
            {
                if (++keyPlays <= 3) Log("key click failed: " + ex.Message);
            }
        }
    }

    static void StartKeyClicks()
    {
        if (keyHook != IntPtr.Zero) return;
        if (KeySound.Length == 0 || !File.Exists(KeySound))
        {
            Log("key clicks wanted, but no sound file at: "
                + (KeySound.Length == 0 ? "(none built in)" : KeySound));
            return;
        }
        keySoundFile = KeySound;
        // The proper player: device opened once, several variants, overlapping
        // voices. PlaySound stays as the fallback for a wav it cannot read.
        string problem;
        if (!KeyAudio.Start(KeySound, out problem))
            Log("key clicks: falling back to PlaySound (" + problem + ")");
        keyRang = new AutoResetEvent(false);
        keyHookProc = OnKey;
        keyHook = SetWindowsHookEx(WH_KEYBOARD_LL, keyHookProc, IntPtr.Zero, 0);
        if (keyHook == IntPtr.Zero)
        {
            Log("key clicks wanted, but the keyboard hook was refused (error "
                + Marshal.GetLastWin32Error() + ")");
            return;
        }
        keyPlayer = new Thread(PlayClicks);
        keyPlayer.IsBackground = true;
        keyPlayer.Start();
        Log("key clicks on, playing " + KeySound
            + (KeyAudio.Ready ? " (waveOut, 6 variants)" : " (PlaySound)"));
    }

    static void StopKeyClicks()
    {
        if (keyHook == IntPtr.Zero) return;
        UnhookWindowsHookEx(keyHook);
        keyHook = IntPtr.Zero;
        if (keyRang != null) keyRang.Set();      // let the player thread end
        KeyAudio.Stop();
    }

    // ------------------------------------------------------------------- log ---
    // The background half has no window to report into, so the few things worth
    // knowing about go to runtime\watcher.log: when it noticed the screen
    // change, when it rebuilt, and anything it could not do. Trimmed when it
    // gets long, so it can be left alone forever.
    static readonly object logLock = new object();

    internal static void Log(string message)
    {
        try
        {
            string dir = Path.Combine(ProjectRoot, "runtime");
            Directory.CreateDirectory(dir);
            string file = Path.Combine(dir, "watcher.log");
            lock (logLock)
            {
                var info = new FileInfo(file);
                if (info.Exists && info.Length > 64 * 1024)
                {
                    var lines = new List<string>(File.ReadAllLines(file));
                    if (lines.Count > 200) lines.RemoveRange(0, lines.Count - 200);
                    File.WriteAllLines(file, lines.ToArray());
                }
                File.AppendAllText(file,
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + message
                    + Environment.NewLine);
            }
        }
        catch { }
    }

    // ------------------------------------------------------- display changes ---
    // The layout is worked out for one screen size. Change the resolution, the
    // scaling, or plug in a monitor, and it is wrong until relayout.ps1 runs --
    // which used to mean knowing to run it. The watcher notices instead.
    static string lastGeometry = "";

    // Asked of Windows every time, never of Screen.AllScreens: that caches, and
    // its cache is only invalidated by a resolution change -- so moving or
    // resizing the taskbar, which changes the work area the layout is fitted
    // to, leaves it reporting the old figures and nothing rebuilds.
    static string Geometry()
    {
        var work = new RECT();
        SystemParametersInfoW(SPI_GETWORKAREA, 0, ref work, 0);
        return string.Join("x", new[] {
            GetDpiForSystem().ToString(),
            GetSystemMetrics(SM_CXSCREEN).ToString(),
            GetSystemMetrics(SM_CYSCREEN).ToString(),
            GetSystemMetrics(SM_CMONITORS).ToString(),
            GetSystemMetrics(SM_CXVIRTUALSCREEN).ToString(),
            GetSystemMetrics(SM_CYVIRTUALSCREEN).ToString(),
            work.Left.ToString(), work.Top.ToString(),
            work.Right.ToString(), work.Bottom.ToString(),
        });
    }

    static void Relayout(bool force)
    {
        if (!force && !IsOn()) return;            // nothing on screen to fix
        if (RelayoutScript.Length == 0 || !File.Exists(RelayoutScript)) return;
        string now = Geometry();
        if (!force && now == lastGeometry)
        {
            Log("screen change seen, but the geometry is the same (" + now + ") - nothing to do");
            return;
        }
        Log("rebuilding layout: " + (force ? "asked to" : lastGeometry + " -> " + now));
        lastGeometry = now;
        try
        {
            var psi = new ProcessStartInfo("powershell.exe", PowerShellArgs(RelayoutScript, ""));
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            using (var p = Process.Start(psi)) p.WaitForExit(300000);
        }
        catch { }
        KeepShellInFrame();                       // the frame moved; the shell follows
    }

    // --------------------------------------------------------------- watcher ---
    // The background half of the theme, held single by a mutex and ended by
    // Stop() killing the process. It owns:
    //   * the folder watchers that rebuild the Desktop and Folder panels
    //   * the global hotkeys
    //   * the shell-window keeper
    //   * the keyboard sound
    // All of which need a message loop, so it runs a hidden form.
    class WatcherForm : Form
    {
        bool hudHidden;

        public WatcherForm()
        {
            // Never shown: it exists to own the hotkeys and the hook.
            ShowInTaskbar = false;
            FormBorderStyle = FormBorderStyle.FixedToolWindow;
            StartPosition = FormStartPosition.Manual;
            Location = new Point(-32000, -32000);
            Size = new Size(1, 1);
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            if (Flag("hotkeys", true))
            {
                // Win+Alt, which Windows itself leaves alone, and NOREPEAT so
                // holding the combination fires once.
                RegisterHotKey(Handle, 1, MOD_WIN | MOD_ALT | MOD_NOREPEAT, 0x48); // H
                RegisterHotKey(Handle, 2, MOD_WIN | MOD_ALT | MOD_NOREPEAT, 0x54); // T
                RegisterHotKey(Handle, 3, MOD_WIN | MOD_ALT | MOD_NOREPEAT, 0x45); // E
                RegisterHotKey(Handle, 4, MOD_WIN | MOD_ALT | MOD_NOREPEAT, 0x53); // S
            }
            if (Flag("keyclick", false)) StartKeyClicks();

            var shell = new System.Windows.Forms.Timer();
            shell.Interval = 1200;
            shell.Tick += (s, a) => { if (Flag("snapshell", true)) KeepShellInFrame(); };
            shell.Start();

            // A display change arrives as a burst of messages, and Windows is
            // still settling when the first one lands, so rebuild once things
            // have stopped moving rather than on every message.
            lastGeometry = Geometry();
            replan = new System.Windows.Forms.Timer();
            replan.Interval = 4000;
            replan.Tick += (s, a) => { replan.Stop(); Relayout(false); };
            Log("background tasks started; screen is " + lastGeometry);
        }

        System.Windows.Forms.Timer replan;

        void DisplayChanged(string why)
        {
            if (replan == null) return;
            Log("screen change (" + why + "); checking in 4s");
            replan.Stop();
            replan.Start();
        }

        protected override void WndProc(ref Message m)
        {
            // Resolution or monitor count changed, or the taskbar moved or
            // resized (which changes the work area the layout is fitted to).
            if (m.Msg == WM_DISPLAYCHANGE)
                DisplayChanged("resolution or monitors");
            else if (m.Msg == WM_SETTINGCHANGE && m.WParam.ToInt32() == SPI_SETWORKAREA)
                DisplayChanged("work area");

            if (m.Msg == WM_HOTKEY)
            {
                switch (m.WParam.ToInt32())
                {
                    case 1:                                  // Win+Alt+H
                        hudHidden = !hudHidden;
                        foreach (string c in Configs)
                            Bang(hudHidden ? "!HideFade" : "!ShowFade", c);
                        break;
                    case 2: FocusShell(); break;             // Win+Alt+T
                    case 3:                                  // Win+Alt+E
                        new Thread(() => { if (IsOn()) Stop(); else Start(); }).Start();
                        break;
                    case 4:                                  // Win+Alt+S
                        StartVisible(Application.ExecutablePath, "settings");
                        break;
                }
            }
            base.WndProc(ref m);
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            for (int i = 1; i <= 4; i++) UnregisterHotKey(Handle, i);
            StopKeyClicks();
            base.OnFormClosed(e);
        }
    }

    static bool WatcherRunning()
    {
        try { using (Mutex.OpenExisting(WatcherMutex)) return true; }
        catch { return false; }
    }

    static void Watch()
    {
        bool created;
        using (var mutex = new Mutex(true, WatcherMutex, out created))
        {
            if (!created) return;               // one watcher is enough

            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            RunRefresh("Both");                 // catch changes made while the theme was off

            // The Desktop and Folder panels are generated (icons come from the
            // shell), so they have to be rebuilt when their folder changes. A
            // FileSystemWatcher is event-driven -- nothing polls, and it catches
            // renames that an item count would miss. Debounced, because a copy
            // or an unzip fires many events.
            var watchers = new List<FileSystemWatcher>();
            foreach (var pair in new[] { Tuple.Create("Desktop", desktop),
                                         Tuple.Create("Folder", FolderPanelPath()) })
            {
                string panel = pair.Item1, dir = pair.Item2;
                if (dir == null || !Directory.Exists(dir)) continue;
                var timer = new System.Threading.Timer(_ => RunRefresh(panel), null,
                    Timeout.Infinite, Timeout.Infinite);
                FileSystemEventHandler changed = (s, e) => timer.Change(1500, Timeout.Infinite);
                var fsw = new FileSystemWatcher(dir);
                fsw.IncludeSubdirectories = false;
                fsw.NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName;
                fsw.Created += changed;
                fsw.Deleted += changed;
                fsw.Renamed += (s, e) => timer.Change(1500, Timeout.Infinite);
                fsw.EnableRaisingEvents = true;
                watchers.Add(fsw);
            }

            Application.Run(new WatcherForm());
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

    static void StartWatcher()
    {
        if (!WatcherRunning())
            StartQuiet(Process.GetCurrentProcess().MainModule.FileName, "watch");
    }

    // ------------------------------------------------------------ start/stop ---
    static void StartCore()
    {
        if (RainmeterPath.Length > 0 && !Running("Rainmeter"))
            StartQuiet(RainmeterPath, "");

        if (TtbArg.Length > 0 && !Running("TranslucentTB"))
            StartQuiet("explorer.exe", TtbArg);

        SetDesktopIcons(false);

        if (TermScript.Length > 0)
            StartQuiet("powershell.exe", PowerShellArgs(TermScript, ""));

        StartWatcher();
    }

    static void Start()
    {
        if (Flag("bootscreen", true) && !IsOn())
        {
            // Bring the theme up behind the boot screen, so the log is showing
            // while the work it describes is actually happening.
            var worker = new Thread(StartCore);
            worker.IsBackground = true;
            worker.Start();
            BootScreen.Run(worker, Accent(), Background(), Version);
        }
        else
        {
            StartCore();
        }
    }

    static void Stop()
    {
        Kill("Rainmeter");
        Kill("TranslucentTB");
        StopWatcher();
        SetDesktopIcons(true);
    }

    // ---------------------------------------------------------------- repair ---
    // Everything that can be put right without reinstalling, in the order that
    // fixes the most: rebuild the layout for whatever the screen is now, bring
    // back anything that has died, and put the shell and the icons back.
    /// <summary>Skins deployed, but nothing telling Rainmeter to load them.
    ///
    /// Rainmeter owns Rainmeter.ini and rewrites it as it pleases: reinstalling
    /// or repairing it resets that file to its defaults, which leaves every
    /// skin sitting in the Skins folder with no entry referring to it. The HUD
    /// then does not appear and nothing anywhere reports an error -- the skins
    /// are present, Rainmeter is running, and it has simply never been told.
    ///
    /// Returns a description when that is the case, null otherwise.
    /// </summary>
    static string OrphanedSkins()
    {
        try
        {
            string skins = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                @"Rainmeter\Skins\eDEX-Tron");
            if (!Directory.Exists(skins)) return null;      // nothing deployed yet
            int onDisk = 0;
            foreach (string d in Directory.GetDirectories(skins))
                if (!Path.GetFileName(d).StartsWith("@")) onDisk++;
            if (onDisk == 0) return null;

            string ini = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                @"Rainmeter\Rainmeter.ini");
            int listed = 0;
            if (File.Exists(ini))
            {
                // ReadAllLines detects the BOM: Rainmeter rewrites this file as
                // UTF-16LE, and reading it as bytes would find no matches at all.
                foreach (string line in File.ReadAllLines(ini))
                    if (line.TrimStart().StartsWith("[eDEX-Tron",
                            StringComparison.OrdinalIgnoreCase)) listed++;
            }
            if (listed > 0) return null;
            return onDisk + " skin(s) deployed, none listed in Rainmeter.ini";
        }
        catch { return null; }
    }

    static string Repair()
    {
        var log = new StringBuilder();
        bool wasOn = IsOn();

        if (!wasOn)
        {
            log.AppendLine("HUD was not running - starting it");
            StartCore();
            Thread.Sleep(2000);
        }

        string orphaned = OrphanedSkins();
        if (orphaned != null)
        {
            log.AppendLine("Rainmeter's config does not mention the HUD (" + orphaned + ").");
            log.AppendLine("Its settings were most likely reset by reinstalling or");
            log.AppendLine("repairing Rainmeter. Putting the config back.");
        }

        log.AppendLine("Rebuilding the layout for this screen...");
        Relayout(true);

        if (!Running("Rainmeter") && RainmeterPath.Length > 0)
        {
            StartQuiet(RainmeterPath, "");
            log.AppendLine("Restarted the HUD");
        }
        if (TtbArg.Length > 0 && !Running("TranslucentTB"))
        {
            StartQuiet("explorer.exe", TtbArg);
            log.AppendLine("Restarted the taskbar transparency");
        }
        if (!WatcherRunning())
        {
            StartWatcher();
            log.AppendLine("Restarted the background tasks");
        }
        if (FindShell() == IntPtr.Zero && TermScript.Length > 0)
        {
            StartQuiet("powershell.exe", PowerShellArgs(TermScript, ""));
            log.AppendLine("Reopened the shell");
        }
        else
        {
            KeepShellInFrame();
        }
        SetDesktopIcons(false);

        log.AppendLine();
        log.Append(StatusText());
        return log.ToString();
    }

    // ---------------------------------------------------------------- status ---
    static string StatusText()
    {
        var sb = new StringBuilder();
        sb.AppendLine("eDEX-Tron " + Version + " is currently " + (IsOn() ? "ON" : "OFF") + ".");
        sb.AppendLine();
        // A message box draws in a proportional font, so padded columns do not
        // line up; separate the value with a colon instead.
        sb.AppendLine("HUD (Rainmeter): " + (Running("Rainmeter") ? "running" : "stopped"));
        sb.AppendLine("Taskbar (TranslucentTB): " + (Running("TranslucentTB") ? "running" : "stopped"));
        sb.AppendLine("Background tasks: " + (WatcherRunning() ? "running" : "stopped"));
        sb.AppendLine("Shell window: " + (FindShell() != IntPtr.Zero ? "in frame" : "closed"));

        string orphaned = OrphanedSkins();
        if (orphaned != null)
        {
            sb.AppendLine();
            sb.AppendLine("PROBLEM: " + orphaned + ".");
            sb.AppendLine("Rainmeter's settings were reset; run `eDEX-Tron.exe repair`.");
        }

        string noRoom = PlanList("no_room");
        if (noRoom.Length > 0)
        {
            sb.AppendLine();
            sb.AppendLine("No room on this screen for: " + noRoom);
            sb.AppendLine("Switch another panel off in Settings to make space.");
        }
        return sb.ToString();
    }

    // One list out of runtime\layout.json, without a JSON reader.
    static string PlanList(string key)
    {
        try
        {
            string text = File.ReadAllText(Path.Combine(ProjectRoot, "runtime", "layout.json"));
            var m = Regex.Match(text, "\"" + key + "\"\\s*:\\s*\\[([^\\]]*)\\]");
            if (!m.Success) return "";
            var names = new List<string>();
            foreach (Match q in Regex.Matches(m.Groups[1].Value, "\"([^\"]+)\""))
                names.Add(q.Groups[1].Value);
            return string.Join(", ", names.ToArray());
        }
        catch { return ""; }
    }

    // --------------------------------------------------------------- output ---
    // True once we have borrowed the console of whoever launched us.
    static bool haveConsole;

    /// <summary>Borrow the calling terminal's console, if we were started from
    /// one.
    ///
    /// The launcher is built /target:winexe so that double-clicking it does not
    /// flash a console window. The cost is that a run from a terminal has no
    /// console at all, which is why every command reported through a MessageBox
    /// -- fine from the dock tile or a hotkey, useless from a shell, where the
    /// dialog is often behind other windows and the command looks like it hung
    /// until someone finds it and clicks OK.
    /// </summary>
    static void TryAttachConsole()
    {
        try
        {
            if (!AttachConsole(ATTACH_PARENT_PROCESS)) return;
            // The runtime bound Console.Out to a null stream at startup, when
            // there was no console; rebind it to the one we just attached to.
            var stdout = new StreamWriter(Console.OpenStandardOutput());
            stdout.AutoFlush = true;
            Console.SetOut(stdout);
            haveConsole = true;
        }
        catch { haveConsole = false; }
    }

    /// <summary>Say something, wherever the person can actually see it.</summary>
    static void Report(string text, string title)
    {
        if (haveConsole) Console.WriteLine(text);
        else MessageBox.Show(text, title, MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    // ------------------------------------------------------------------ main ---
    [STAThread]
    static int Main(string[] argv)
    {
        TryAttachConsole();
        SetProcessDPIAware();
        Application.EnableVisualStyles();
        string cmd = argv.Length > 0 ? argv[0].ToLowerInvariant().TrimStart('-', '/') : "toggle";
        switch (cmd)
        {
            case "start":  Start(); break;
            case "stop":   Stop();  break;
            case "watch":  Watch(); break;
            case "toggle": if (IsOn()) Stop(); else Start(); break;
            case "boot":
                // "boot demo" substitutes a generic user, host and address,
                // so the screen can be recorded without showing whose it is.
                BootScreen.Demo = argv.Length > 1 &&
                                  argv[1].Trim().ToLowerInvariant() == "demo";
                BootScreen.Run(null, Accent(), Background(), Version);
                break;
            case "settings":
                Application.Run(new SettingsForm(SettingsScript, ProjectRoot,
                                                 Accent(), Background(), Version));
                break;
            case "restart-watcher":
                StopWatcher();
                Thread.Sleep(400);
                StartWatcher();
                break;
            case "status":
                Report(StatusText(), "eDEX-Tron");
                break;
            case "repair":
                Report(Repair(), "eDEX-Tron repair");
                break;
            case "relayout":
                Relayout(true);
                break;
            case "dumpclicks":
            {
                // Write the key-click variants out so they can be heard on
                // their own, which is the only way to tell a time stretch that
                // worked from one that quietly wrecked the sound.
                string where = argv.Length > 1
                    ? argv[1]
                    : Path.Combine(ProjectRoot, "runtime", "clicks");
                string why;
                if (!KeyAudio.Start(KeySound, out why))
                {
                    Report("Could not prepare the clicks: " + why, "eDEX-Tron");
                    return 1;
                }
                int n = KeyAudio.Dump(where);
                KeyAudio.Stop();
                Report(n + " variants written to:" + Environment.NewLine + where,
                       "eDEX-Tron");
                break;
            }
            default:
                Report("Usage: eDEX-Tron.exe "
                       + "[start|stop|toggle|status|repair|settings|boot|relayout|watch|dumpclicks]",
                       "eDEX-Tron");
                return 1;
        }
        return 0;
    }
}
