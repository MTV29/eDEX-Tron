// The boot sequence eDEX-UI opens with: a log scrolling up the left of a black
// screen while the system comes up.
//
// eDEX-UI's version is a scripted animation with invented messages. This one
// reports what is actually on the machine -- the real CPU, the real drives and
// their real free space, the services Windows really has running, the real
// network link and the real uptime -- because a fake log that says the same
// thing every boot stops being interesting the second you read it twice.
//
// It is shown while the HUD is genuinely starting behind it (Start() hands the
// thread in), so the last line is true when it appears rather than timed to
// look true. Any key or click skips it.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.ServiceProcess;
using System.Threading;
using System.Windows.Forms;

static class BootScreen
{
    [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX s);
    [DllImport("kernel32.dll")] static extern ulong GetTickCount64();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplayDevicesW(string device, uint index,
                                           ref DISPLAY_DEVICE info, uint flags);

    [StructLayout(LayoutKind.Sequential)]
    struct MEMORYSTATUSEX
    {
        public uint Length, MemoryLoad;
        public ulong TotalPhys, AvailPhys, TotalPageFile, AvailPageFile,
                     TotalVirtual, AvailVirtual, AvailExtendedVirtual;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DISPLAY_DEVICE
    {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    const int MaxLines = 40;
    // How long the screen stays up when there is a sound to go with it.
    const double MinSeconds = 5.0;

    class Line
    {
        public string Tag, Text;
        public Line(string tag, string text) { Tag = tag; Text = text; }
    }

    // ------------------------------------------------------------ real data ---
    static string Gib(ulong bytes) { return (bytes / 1073741824.0).ToString("0.0") + "G"; }

    static string CpuName()
    {
        try
        {
            using (var k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(
                       @"HARDWARE\DESCRIPTION\System\CentralProcessor\0"))
            {
                if (k != null)
                {
                    string s = (string)k.GetValue("ProcessorNameString", "");
                    if (s != null && s.Trim().Length > 0) return s.Trim();
                }
            }
        }
        catch { }
        return "unknown processor";
    }

    static string OsName()
    {
        try
        {
            using (var k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(
                       @"SOFTWARE\Microsoft\Windows NT\CurrentVersion"))
            {
                if (k != null)
                {
                    string name = Convert.ToString(k.GetValue("ProductName", "Windows"));
                    string build = Convert.ToString(k.GetValue("CurrentBuild", ""));
                    // ProductName still says "Windows 10" on Windows 11: Microsoft
                    // never updated the value, and plenty of software reads it.
                    int n;
                    if (int.TryParse(build, out n) && n >= 22000)
                        name = name.Replace("Windows 10", "Windows 11");
                    return string.Format("{0} {1} (build {2})",
                        name, k.GetValue("DisplayVersion", ""), build);
                }
            }
        }
        catch { }
        return "Windows " + Environment.OSVersion.Version;
    }

    static string Gpu()
    {
        // Index 0 is whichever adapter drives the primary display, which on a
        // laptop is the integrated one even when a discrete card is fitted.
        // Prefer the discrete card, since that is the one worth reporting.
        string first = "";
        try
        {
            for (uint i = 0; i < 8; i++)
            {
                var d = new DISPLAY_DEVICE();
                d.cb = Marshal.SizeOf(d);
                if (!EnumDisplayDevicesW(null, i, ref d, 0)) break;
                string name = d.DeviceString.Trim();
                if (name.Length == 0) continue;
                if (first.Length == 0) first = name;
                if (name.IndexOf("NVIDIA", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    name.IndexOf("GeForce", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    name.IndexOf("Radeon", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    name.IndexOf("Arc", StringComparison.OrdinalIgnoreCase) >= 0)
                    return name;
            }
        }
        catch { }
        return first;
    }

    static string Uptime()
    {
        var up = TimeSpan.FromMilliseconds(GetTickCount64());
        string since = DateTime.Now.Subtract(up).ToString("yyyy-MM-dd HH:mm");
        if (up.TotalDays >= 1)
            return string.Format("up {0}d {1}h since {2}", (int)up.TotalDays, up.Hours, since);
        return string.Format("up {0}h {1}m since {2}", (int)up.TotalHours, up.Minutes, since);
    }

    static int StartupItems()
    {
        int n = 0;
        try
        {
            foreach (var root in new[] { Microsoft.Win32.Registry.CurrentUser,
                                         Microsoft.Win32.Registry.LocalMachine })
                using (var k = root.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run"))
                    if (k != null) n += k.GetValueNames().Length;
        }
        catch { }
        return n;
    }

    // Collected on a worker thread: ServiceController and DriveInfo both hit
    // the disk, and the screen should already be up by then.
    static void Collect(Action<Line> emit)
    {
        emit(new Line("INFO", OsName()));
        emit(new Line("INFO", Environment.UserName + "@" + Environment.MachineName));

        emit(new Line("OK", "cpu: " + CpuName() + " (" +
                            Environment.ProcessorCount + " threads)"));

        var mem = new MEMORYSTATUSEX();
        mem.Length = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        if (GlobalMemoryStatusEx(ref mem))
            emit(new Line("OK", "memory: " + Gib(mem.AvailPhys) + " free of " +
                                Gib(mem.TotalPhys) + " (" + mem.MemoryLoad + "% in use)"));

        string gpu = Gpu();
        if (gpu.Length > 0) emit(new Line("OK", "display adapter: " + gpu));

        foreach (var d in DriveInfo.GetDrives())
        {
            try
            {
                if (!d.IsReady || d.DriveType != DriveType.Fixed) continue;
                emit(new Line("OK", "mounted " + d.Name.TrimEnd('\\') + " " +
                    d.DriveFormat + ", " + Gib((ulong)d.TotalSize) + ", " +
                    Gib((ulong)d.AvailableFreeSpace) + " free"));
            }
            catch { }
        }

        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            try
            {
                if (nic.OperationalStatus != OperationalStatus.Up) continue;
                if (nic.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                string ip = "";
                foreach (var a in nic.GetIPProperties().UnicastAddresses)
                    if (a.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                        ip = a.Address.ToString();
                if (ip.Length == 0) continue;
                emit(new Line("OK", "link up: " + nic.Name + " " + ip +
                    (nic.Speed > 0 ? " at " + (nic.Speed / 1000000) + " Mb/s" : "")));
            }
            catch { }
        }

        // The part that reads like a boot log, because it is one: the services
        // Windows has actually started, in its own order.
        int shown = 0;
        try
        {
            foreach (var svc in ServiceController.GetServices())
            {
                try
                {
                    if (svc.Status != ServiceControllerStatus.Running) continue;
                    string name = svc.DisplayName;
                    if (name.Length > 46) name = name.Substring(0, 46);
                    emit(new Line("OK", "started " + name));
                    if (++shown >= 26) break;
                }
                catch { }
            }
        }
        catch { }

        emit(new Line("INFO", Process.GetProcesses().Length + " processes, " +
                              StartupItems() + " startup entries"));
        emit(new Line("INFO", Uptime()));
    }

    // --------------------------------------------------------------- screen ---
    class Screen : Form
    {
        readonly List<Line> lines = new List<Line>();
        readonly Queue<Line> pending = new Queue<Line>();
        readonly Color accent, back;
        readonly string version;
        readonly Thread worker;
        readonly Font logFont, titleFont, smallFont;
        bool collected, finished;
        int readyTicks;
        readonly DateTime opened = DateTime.UtcNow;
        System.Windows.Media.MediaPlayer sound;
        double soundVolume;

        public Screen(Thread worker, Color accent, Color back, string version)
        {
            this.worker = worker;
            this.accent = accent;
            this.back = back;
            this.version = version;

            // Borderless, so the title is never drawn -- but it is what the
            // window is found by, from the taskbar and from capture_window.ps1.
            Text = "eDEX-Tron boot";
            FormBorderStyle = FormBorderStyle.None;
            WindowState = FormWindowState.Maximized;
            TopMost = true;
            ShowInTaskbar = false;
            BackColor = back;
            KeyPreview = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                     | ControlStyles.OptimizedDoubleBuffer, true);

            logFont = new Font("Consolas", 10f);
            titleFont = Installed("Bahnschrift") ? new Font("Bahnschrift", 34f)
                                                 : new Font("Segoe UI", 32f);
            smallFont = new Font("Consolas", 9f);

            // Collect on a worker so the screen is up immediately; the queue is
            // drained by the timer, which is what paces the log.
            var gather = new Thread(() =>
            {
                Collect(l => { lock (pending) pending.Enqueue(l); });
                collected = true;
            });
            gather.IsBackground = true;
            gather.Start();

            var tick = new System.Windows.Forms.Timer();
            tick.Interval = 45;
            tick.Tick += (s, a) => Step();
            tick.Start();

            Cursor.Hide();
            StartSound();
            KeyDown += (s, a) => Close();
            MouseDown += (s, a) => Close();
        }

        // The boot sound, if there is one. MediaPlayer rather than PlaySound
        // because it reads mp3 as happily as wav and can play it faster than
        // recorded, which a boot animation written for a film-length intro
        // badly needs.
        void StartSound()
        {
            string file = BootSoundFile();
            if (file == null) return;
            try
            {
                sound = new System.Windows.Media.MediaPlayer();
                sound.Open(new Uri(file));
                sound.SpeedRatio = BootSoundSpeed();
                soundVolume = 0.85;
                sound.Volume = soundVolume;
                sound.Play();
            }
            catch { sound = null; }
        }

        // Fade rather than cut: stopping a 40-second track four seconds in
        // sounds like a fault, and a fade sounds like an ending.
        void FadeAndStop()
        {
            if (sound == null) return;
            try
            {
                var player = sound;
                sound = null;
                var fade = new System.Windows.Forms.Timer();
                fade.Interval = 40;
                fade.Tick += (s, a) =>
                {
                    soundVolume -= 0.12;
                    if (soundVolume <= 0)
                    {
                        fade.Stop();
                        try { player.Stop(); player.Close(); } catch { }
                        return;
                    }
                    try { player.Volume = soundVolume; } catch { }
                };
                fade.Start();
            }
            catch { }
        }

        // Your own recording if you have one, otherwise the one we render.
        // A boot animation ripped from a game is not ours to ship, so it is
        // only ever read from assets\sounds\ -- which the repository ignores,
        // the same arrangement as eDEX-UI's own typeface.
        static string BootSoundFile()
        {
            var tried = new List<string>();
            string custom = EdexTron.Str("bootsound", "");
            if (custom.Length > 0) tried.Add(Environment.ExpandEnvironmentVariables(custom));
            string sounds = Path.Combine(EdexTron.ProjectRoot, "assets", "sounds");
            foreach (string name in new[] { "boot.mp3", "boot.wav", "boot.wma", "boot.m4a" })
                tried.Add(Path.Combine(sounds, name));
            tried.Add(Path.Combine(sounds, "gen", "boot.wav"));
            foreach (string f in tried)
            {
                try { if (File.Exists(f)) return f; } catch { }
            }
            return null;
        }

        static double BootSoundSpeed()
        {
            double v = EdexTron.Number("bootsoundspeed", 1.6);
            return (v >= 0.25 && v <= 4.0) ? v : 1.6;
        }

        static bool Installed(string family)
        {
            try
            {
                using (var f = new Font(family, 10f))
                    return f.Name.Equals(family, StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
        }

        void Step()
        {
            Line next = null;
            lock (pending) if (pending.Count > 0) next = pending.Dequeue();

            if (next != null)
            {
                lines.Add(next);
                while (lines.Count > MaxLines) lines.RemoveAt(0);
                Invalidate();
                return;
            }

            // Everything gathered and shown. Wait for the HUD thread to finish
            // so the last line is the truth, then hold the title for a beat.
            if (!collected) return;
            if (worker != null && worker.IsAlive) return;
            if (!finished)
            {
                finished = true;
                lines.Add(new Line("OK", "eDEX-Tron HUD online"));
                while (lines.Count > MaxLines) lines.RemoveAt(0);
                Invalidate();
                return;
            }
            // Hold the READY frame, but also give the boot sound long enough to
            // be a boot sound. On a fast machine everything is collected and the
            // HUD is up inside two seconds, which is not an entrance.
            double shown = (DateTime.UtcNow - opened).TotalSeconds;
            if (++readyTicks > 16 && (sound == null || shown >= MinSeconds)) Close();
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            FadeAndStop();
            base.OnFormClosing(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(back);
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;

            int w = ClientSize.Width, h = ClientSize.Height;
            int split = (int)(w * 0.62);
            using (var dim = new SolidBrush(Color.FromArgb(110, accent)))
            using (var mid = new SolidBrush(Color.FromArgb(190, accent)))
            using (var full = new SolidBrush(accent))
            using (var rule = new Pen(Color.FromArgb(90, accent)))
            {
                // the log, left
                int lh = logFont.Height + 3;
                int y = 46;
                foreach (var line in lines)
                {
                    string tag = "[ " + line.Tag.PadRight(4) + " ]";
                    g.DrawString(tag, logFont, line.Tag == "OK" ? mid : dim, 46, y);
                    g.DrawString(line.Text, logFont, full, 46 + 78, y);
                    y += lh;
                    if (y > h - 60) break;
                }

                // the title block, right
                g.DrawLine(rule, split, 40, split, h - 40);
                int tx = split + 48;
                g.DrawString("eDEX-TRON", titleFont, full, tx, h / 2 - 90);
                g.DrawString(version, smallFont, mid, tx + 4, h / 2 - 34);
                g.DrawString(finished ? "READY" : "STARTING", smallFont, full, tx + 4, h / 2 + 4);
                g.DrawString("any key to skip", smallFont, dim, tx + 4, h - 70);
            }
        }
    }

    public static void Run(Thread worker, Color accent, Color back, string version)
    {
        try { Application.Run(new Screen(worker, accent, back, version)); }
        catch { }
        try { Cursor.Show(); } catch { }
        // Whatever happened on screen, the theme still has to come up.
        if (worker != null && worker.IsAlive) worker.Join(60000);
    }
}
