// The settings window: eDEX-Tron.exe settings, or Win+Alt+S.
//
// It is a front end for src\tools\settings.ps1 and holds no logic of its own --
// it reads the current values from "settings.ps1 -Get" and writes changes back
// by invoking the same script with parameters. That script decides what needs
// regenerating, so the two can never disagree about what a setting means.
//
// Applying can take a minute (new colours re-render the wallpaper and every
// panel), so it runs on a worker thread with the script's own output shown in
// the box at the bottom rather than behind a spinner.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using System.Windows.Forms;

class SettingsForm : Form
{
    readonly string script, projectRoot, version;
    readonly Color accent, back;
    Dictionary<string, string> current = new Dictionary<string, string>();

    // colours
    Button accentSwatch, bgSwatch, iconSwatch;
    string accentHex = "#aacfd1", bgHex = "#05080d", iconHex = "#4f9dff";
    CheckBox gridBox;

    // panels
    readonly Dictionary<string, CheckBox> extraBoxes = new Dictionary<string, CheckBox>();
    readonly Dictionary<string, CheckBox> standardBoxes = new Dictionary<string, CheckBox>();

    // folder + behaviour
    TextBox folderBox;
    ComboBox fontBox;
    ComboBox profileBox;
    List<string> profileNames = new List<string>();
    string profileToApply;        // set by the dropdown, read on Apply
    string profileToSave, profileToDelete;
    CheckBox keyClickBox, hotkeysBox, bootBox, snapBox, altTabBox, autostartBox;

    Button applyButton, closeButton, dockButton;
    TextBox outputBox;
    Label statusLabel;

    static readonly string[] Pretty = {
        "gpu|Graphics card load, memory and temperature",
        "power|Watts drawn, and the battery on a laptop",
        "disk|Free space on every fixed drive",
        "ports|Listening ports and what is holding them",
        "clock|Clock, uptime and machine info",
        "cpuinfo|Per-core CPU graphs",
        "netstat|Network status",
        "ramwatcher|Memory map",
        "conninfo|Network usage graph",
        "toplist|Top processes",
    };

    static string Describe(string key)
    {
        foreach (string row in Pretty)
        {
            string[] parts = row.Split('|');
            if (parts[0] == key) return parts[1];
        }
        return key;
    }

    public SettingsForm(string script, string projectRoot, Color accent, Color back,
                        string version)
    {
        this.script = script;
        this.projectRoot = projectRoot;
        this.accent = accent;
        this.back = back;
        this.version = version;

        Text = "eDEX-Tron settings";
        BackColor = back;
        ForeColor = accent;
        Font = new Font("Consolas", 9f);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(620, 660);

        Load += (s, a) => { Reload(); };
        // Opened from the hotkey this is a brand new process, which Windows
        // does not necessarily bring to the front; insist once.
        Shown += (s, a) => { TopMost = true; TopMost = false; Activate(); };
    }

    // ------------------------------------------------------------- plumbing ---
    string Run(string args, int timeoutMs)
    {
        try
        {
            var psi = new ProcessStartInfo("powershell.exe",
                "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" " + args);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            using (var p = Process.Start(psi))
            {
                string outText = p.StandardOutput.ReadToEnd();
                string errText = p.StandardError.ReadToEnd();
                p.WaitForExit(timeoutMs);
                return outText + (errText.Trim().Length > 0 ? "\n" + errText.Trim() : "");
            }
        }
        catch (Exception ex) { return "could not run settings.ps1: " + ex.Message; }
    }

    static Color Parse(string hex, Color fallback)
    {
        try
        {
            hex = hex.TrimStart('#');
            return Color.FromArgb(
                int.Parse(hex.Substring(0, 2), NumberStyles.HexNumber),
                int.Parse(hex.Substring(2, 2), NumberStyles.HexNumber),
                int.Parse(hex.Substring(4, 2), NumberStyles.HexNumber));
        }
        catch { return fallback; }
    }

    static string Hex(Color c)
    {
        return "#" + c.R.ToString("x2") + c.G.ToString("x2") + c.B.ToString("x2");
    }

    static Color Readable(Color on)
    {
        double luma = (0.2126 * on.R + 0.7152 * on.G + 0.0722 * on.B) / 255.0;
        return luma > 0.45 ? Color.Black : Color.White;
    }

    bool On(string key, bool fallback)
    {
        string v;
        if (current.TryGetValue(key, out v)) return v == "on";
        return fallback;
    }

    string Get(string key)
    {
        string v;
        return current.TryGetValue(key, out v) ? v : "";
    }

    List<string> List(string key)
    {
        var items = new List<string>();
        foreach (string s in Get(key).Split(','))
            if (s.Trim().Length > 0) items.Add(s.Trim());
        return items;
    }

    void Reload()
    {
        current = new Dictionary<string, string>();
        touched.Clear();
        foreach (string line in Run("-Get", 30000).Split('\n'))
        {
            int eq = line.IndexOf('=');
            if (eq > 0) current[line.Substring(0, eq).Trim()] = line.Substring(eq + 1).Trim();
        }
        Controls.Clear();
        Build();
    }

    // ----------------------------------------------------------------- look ---
    Label Heading(string text, int y)
    {
        var l = new Label();
        l.Text = text.ToUpperInvariant();
        l.Location = new Point(18, y);
        l.AutoSize = true;
        l.ForeColor = accent;
        l.Font = new Font("Consolas", 9f, FontStyle.Bold);
        Controls.Add(l);

        var rule = new Panel();
        rule.Location = new Point(18, y + 18);
        rule.Size = new Size(ClientSize.Width - 36, 1);
        rule.BackColor = Color.FromArgb(70, accent);
        Controls.Add(rule);
        return l;
    }

    void Say(string text)
    {
        if (statusLabel != null) statusLabel.Text = text;
    }

    /// <summary>Fill the dropdown from what settings.ps1 reported.</summary>
    void LoadProfiles()
    {
        profileNames = List("profiles");
        string active = Get("profile");
        profileBox.Items.Clear();
        // The first row is whatever is on right now. It is the selection
        // whenever the panels do not match a saved profile -- which is what
        // settings.ps1 reports by clearing the name after a hand edit.
        profileBox.Items.Add(active.Length > 0 ? "(current: " + active + ")" : "(unsaved layout)");
        foreach (string n in profileNames) profileBox.Items.Add(n);
        int at = active.Length > 0 ? profileNames.IndexOf(active) : -1;
        profileBox.SelectedIndex = at >= 0 ? at + 1 : 0;
    }

    /// <summary>A name that is not taken yet, for the Save dialog to start on.</summary>
    string SuggestProfileName()
    {
        string active = Get("profile");
        if (active.Length > 0) return active;
        foreach (string candidate in new[] { "work", "gaming", "minimal" })
            if (!profileNames.Contains(candidate)) return candidate;
        return "profile" + (profileNames.Count + 1);
    }

    /// <summary>A one-line prompt. WinForms has no InputBox, and pulling in
    /// Microsoft.VisualBasic for one would be a reference for a text box.</summary>
    string Ask(string prompt, string initial)
    {
        using (var dlg = new Form())
        {
            dlg.Text = "eDEX-Tron";
            dlg.FormBorderStyle = FormBorderStyle.FixedDialog;
            dlg.StartPosition = FormStartPosition.CenterParent;
            dlg.MinimizeBox = false; dlg.MaximizeBox = false;
            dlg.ClientSize = new Size(380, 116);
            dlg.BackColor = back; dlg.ForeColor = accent;

            var lbl = new Label { Text = prompt, Location = new Point(14, 14),
                                  AutoSize = true, ForeColor = accent, BackColor = back };
            var box = new TextBox { Text = initial, Location = new Point(14, 40),
                                    Size = new Size(352, 22),
                                    BackColor = Color.FromArgb(16, 20, 28),
                                    ForeColor = accent, BorderStyle = BorderStyle.FixedSingle };
            var ok = new Button { Text = "OK", DialogResult = DialogResult.OK,
                                  Location = new Point(196, 76), Size = new Size(80, 26),
                                  FlatStyle = FlatStyle.Flat, BackColor = back, ForeColor = accent };
            var no = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel,
                                  Location = new Point(286, 76), Size = new Size(80, 26),
                                  FlatStyle = FlatStyle.Flat, BackColor = back, ForeColor = accent };
            dlg.Controls.AddRange(new Control[] { lbl, box, ok, no });
            dlg.AcceptButton = ok; dlg.CancelButton = no;
            box.SelectAll();
            if (dlg.ShowDialog(this) != DialogResult.OK) return null;

            string name = box.Text.Trim();
            // The name becomes a JSON key and a command-line argument.
            if (name.Length == 0) return null;
            foreach (char c in new[] { '"', '\'', '`', '$', ';', '|', '&' })
                name = name.Replace(c.ToString(), "");
            name = name.Trim();
            return name.Length > 0 ? name : null;
        }
    }

    Label Note(string text, int x, int y)
    {
        var l = new Label();
        l.Text = text;
        l.Location = new Point(x, y);
        l.AutoSize = true;
        l.ForeColor = Color.FromArgb(150, accent);
        Controls.Add(l);
        return l;
    }

    readonly ToolTip tips = new ToolTip();

    // What the person changed in this window, as opposed to what simply
    // differs from the values it loaded. A window left open while something
    // else changes a setting -- the dock's own tile, settings.ps1, another
    // copy of this window -- would otherwise write its stale view back over
    // the newer one the moment Apply was pressed.
    readonly HashSet<string> touched = new HashSet<string>();

    List<string> fontNames = new List<string>();

    /// <summary>What to call each font set in the dropdown.</summary>
    static string FontLabel(string set)
    {
        switch (set)
        {
            case "auto":       return "Automatic (best available)";
            case "unitedsans": return "United Sans - eDEX-UI's own";
            case "fira":       return "Fira - ships with eDEX-Tron";
            case "windows":    return "Bahnschrift - comes with Windows";
            default:           return set;
        }
    }

    CheckBox Check(string text, bool value, int x, int y, string tip = null,
                   string field = null)
    {
        var c = new CheckBox();
        c.Text = text;
        c.Checked = value;
        c.Location = new Point(x, y);
        c.AutoSize = true;
        c.ForeColor = accent;
        c.BackColor = back;
        c.FlatStyle = FlatStyle.Flat;
        Controls.Add(c);
        // The descriptions are long enough to collide with the next column, so
        // they live in a tooltip and the box carries the name alone.
        if (tip != null) tips.SetToolTip(c, tip);
        if (field != null) c.CheckedChanged += (s, a) => touched.Add(field);
        return c;
    }

    Button Flat(string text, int x, int y, int w, EventHandler click)
    {
        var b = new Button();
        b.Text = text;
        b.Location = new Point(x, y);
        b.Size = new Size(w, 26);
        b.FlatStyle = FlatStyle.Flat;
        b.BackColor = back;
        b.ForeColor = accent;
        b.FlatAppearance.BorderColor = Color.FromArgb(120, accent);
        b.FlatAppearance.MouseOverBackColor = Color.FromArgb(40, accent);
        b.Click += click;
        Controls.Add(b);
        return b;
    }

    Button Swatch(string hex, int x, int y, string field, Action<string> set)
    {
        var b = new Button();
        b.Location = new Point(x, y);
        b.Size = new Size(120, 24);
        b.FlatStyle = FlatStyle.Flat;
        b.BackColor = Parse(hex, accent);
        // The background swatch is nearly black, so black-on-black would hide
        // its own label; pick whichever of black or white can be read on it.
        b.ForeColor = Readable(b.BackColor);
        b.Text = hex;
        b.FlatAppearance.BorderColor = Color.FromArgb(120, accent);
        b.Click += (s, a) =>
        {
            using (var dlg = new ColorDialog())
            {
                dlg.Color = b.BackColor;
                dlg.FullOpen = true;
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                b.BackColor = dlg.Color;
                b.ForeColor = Readable(dlg.Color);
                b.Text = Hex(dlg.Color);
                set(Hex(dlg.Color));
                touched.Add(field);
            }
        };
        Controls.Add(b);
        return b;
    }

    // ---------------------------------------------------------------- build ---
    void Build()
    {
        accentHex = Get("accent");
        bgHex = Get("background");
        iconHex = Get("icon");
        var noRoom = List("noroom");
        var panelsOn = List("panels");
        var switchedOff = List("off");

        int y = 14;
        Heading("Colours", y); y += 30;
        Note("Accent", 20, y + 4);
        accentSwatch = Swatch(accentHex, 110, y, "accent", v => accentHex = v);
        Note("Background", 250, y + 4);
        bgSwatch = Swatch(bgHex, 350, y, "background", v => bgHex = v);
        y += 32;
        Note("Icon", 20, y + 4);
        iconSwatch = Swatch(iconHex, 110, y, "icon", v => iconHex = v);
        gridBox = Check("Grid on the wallpaper", On("grid", false), 250, y + 3, null, "grid");
        y += 40;

        Heading("Layout profiles", y); y += 28;
        profileBox = new ComboBox();
        profileBox.DropDownStyle = ComboBoxStyle.DropDownList;
        profileBox.FlatStyle = FlatStyle.Flat;
        profileBox.Location = new Point(20, y);
        profileBox.Size = new Size(240, 22);
        profileBox.BackColor = Color.FromArgb(16, 20, 28);
        profileBox.ForeColor = accent;
        LoadProfiles();
        profileBox.SelectedIndexChanged += (s2, a2) =>
        {
            int i = profileBox.SelectedIndex;
            // Index 0 is the unsaved state, which is not something to apply.
            profileToApply = (i > 0 && i - 1 < profileNames.Count) ? profileNames[i - 1] : null;
            if (profileToApply != null) touched.Add("profile");
        };
        tips.SetToolTip(profileBox, "A named set of panels -- switch the whole layout at once");
        Controls.Add(profileBox);

        Flat("Save as", 270, y - 2, 80, (s2, a2) =>
        {
            string name = Ask("Save the panels that are on now as:", SuggestProfileName());
            if (name == null) return;
            profileToSave = name;
            touched.Add("profile");
            Say("Will save profile \"" + name + "\" when you press Apply.");
        });
        Flat("Delete", 358, y - 2, 80, (s2, a2) =>
        {
            int i = profileBox.SelectedIndex;
            if (i <= 0 || i - 1 >= profileNames.Count)
            {
                Say("Pick a saved profile to delete first.");
                return;
            }
            string name = profileNames[i - 1];
            if (MessageBox.Show("Delete the profile \"" + name + "\"?", "eDEX-Tron",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            profileToDelete = name;
            profileToApply = null;
            touched.Add("profile");
            Say("Will delete profile \"" + name + "\" when you press Apply.");
        });
        y += 30;
        Note("Saving stores the panels below; switching puts them all back at once.",
             20, y); y += 26;

        Heading("Extra panels", y); y += 28;
        var optional = List("optional");
        for (int i = 0; i < optional.Count; i++)
        {
            string key = optional[i];
            bool fits = !noRoom.Contains(key);
            extraBoxes[key] = Check(key.ToUpperInvariant() + (fits ? "" : "  (no room)"),
                                    panelsOn.Contains(key),
                                    20 + (i % 3) * 190, y + (i / 3) * 24,
                                    Describe(key), "panels");
        }
        y += ((optional.Count + 2) / 3) * 24;
        if (noRoom.Count > 0)
            Note("No room: on, but this screen cannot fit it -- turn one below off.",
                 20, y + 2);
        else
            Note("Hover a name for what it shows.", 20, y + 2);
        y += 30;

        Heading("Standard panels", y); y += 28;
        var standard = List("standard");
        for (int i = 0; i < standard.Count; i++)
        {
            string key = standard[i];
            standardBoxes[key] = Check(key.ToUpperInvariant(), !switchedOff.Contains(key),
                                       20 + (i % 3) * 190, y + (i / 3) * 24, Describe(key), "off");
        }
        y += ((standard.Count + 2) / 3) * 24 + 14;

        Heading("Folder panel", y); y += 28;
        folderBox = new TextBox();
        folderBox.Text = Get("folderraw");
        folderBox.Location = new Point(20, y);
        folderBox.Size = new Size(440, 22);
        folderBox.BackColor = Color.FromArgb(16, 20, 28);
        folderBox.ForeColor = accent;
        folderBox.BorderStyle = BorderStyle.FixedSingle;
        folderBox.TextChanged += (s2, a2) => touched.Add("folder");
        Controls.Add(folderBox);
        Flat("Browse", 470, y - 2, 80, (s, a) =>
        {
            using (var dlg = new FolderBrowserDialog())
            {
                dlg.SelectedPath = Environment.ExpandEnvironmentVariables(folderBox.Text);
                if (dlg.ShowDialog(this) == DialogResult.OK) folderBox.Text = dlg.SelectedPath;
            }
        });
        y += 40;

        Heading("Typeface", y); y += 28;
        fontBox = new ComboBox();
        fontBox.DropDownStyle = ComboBoxStyle.DropDownList;
        fontBox.FlatStyle = FlatStyle.Flat;
        fontBox.Location = new Point(20, y);
        fontBox.Size = new Size(240, 22);
        fontBox.BackColor = Color.FromArgb(16, 20, 28);
        fontBox.ForeColor = accent;
        // Only the sets whose files are actually on this machine.
        // Offering eDEX-UI's typeface without eDEX-UI installed is
        // offering a choice that silently does nothing.
        var haveFonts = List("fontavailable");
        if (haveFonts.Count == 0) haveFonts = List("fonts");
        string fontNow = Get("font");
        if (fontNow.Length == 0) fontNow = "auto";
        foreach (string set in haveFonts) fontBox.Items.Add(FontLabel(set));
        fontBox.SelectedIndex = Math.Max(0, haveFonts.IndexOf(fontNow));
        fontBox.SelectedIndexChanged += (s2, a2) => touched.Add("font");
        tips.SetToolTip(fontBox, "Which typeface the panels and the shell use");
        Controls.Add(fontBox);
        fontNames = haveFonts;
        Note(haveFonts.Contains("unitedsans")
             ? "Fira ships; United Sans is yours"
             : "Install eDEX-UI for United Sans",
             276, y + 3);
        y += 36;

        Heading("Behaviour", y); y += 28;
        keyClickBox = Check("Audible key clicks", On("keyclick", false), 20, y,
                            "A click on every keystroke, the way eDEX-UI has one", "keyclick");
        hotkeysBox = Check("Hotkeys", On("hotkeys", true), 300, y,
                           "Win+Alt+H hide the HUD, T the shell, E on/off, S these settings", "hotkeys");
        y += 24;
        bootBox = Check("Boot screen at start", On("bootscreen", true), 20, y,
                        "The eDEX startup log, with this machine's own figures", "bootscreen");
        snapBox = Check("Keep the shell in its frame", On("snapshell", true), 300, y,
                        "Put the shell window back if something moves or resizes it", "snapshell");
        y += 24;
        altTabBox = Check("Shell in Alt-Tab", On("shellalttab", false), 20, y,
                          "Off keeps the shell out of the window switcher, as part of the HUD", "shellalttab");
        autostartBox = Check("Start when I log in", On("autostart", false), 300, y,
                             "A shortcut in your Startup folder", "autostart");
        y += 26;
        Note("Win+Alt+H hide HUD, T shell, E on/off, S settings.", 20, y);
        y += 26;

        outputBox = new TextBox();
        outputBox.Multiline = true;
        outputBox.ReadOnly = true;
        outputBox.ScrollBars = ScrollBars.Vertical;
        outputBox.Location = new Point(20, y);
        outputBox.Size = new Size(ClientSize.Width - 40, 96);
        outputBox.BackColor = Color.FromArgb(10, 13, 19);
        outputBox.ForeColor = Color.FromArgb(200, accent);
        outputBox.BorderStyle = BorderStyle.FixedSingle;
        Controls.Add(outputBox);
        y += 104;

        statusLabel = Note("eDEX-Tron " + version, 20, y + 6);
        dockButton = Flat("Edit dock", 290, y, 100, (s, a) =>
        {
            try { Process.Start("notepad.exe", Path.Combine(projectRoot, "dock.txt")); }
            catch (Exception ex) { outputBox.Text = ex.Message; }
        });
        applyButton = Flat("Apply", 400, y, 100, (s, a) => Apply());
        closeButton = Flat("Close", 510, y, 90, (s, a) => Close());
        ClientSize = new Size(620, y + 44);
    }

    // ---------------------------------------------------------------- apply ---
    static string Switch(string name, bool value) { return " -" + name + (value ? " on" : " off"); }

    void Apply()
    {
        var args = new StringBuilder();

        // Only what was changed here, and only when it still differs from what
        // is on disk now. Anything this window never touched is left alone,
        // however stale its own copy of it has become.
        Func<string, bool> changed = field => touched.Contains(field);

        if (changed("accent") && accentHex != Get("accent")) args.Append(" -Accent " + accentHex);
        if (changed("background") && bgHex != Get("background")) args.Append(" -Background " + bgHex);
        if (changed("icon") && iconHex != Get("icon")) args.Append(" -IconColor " + iconHex);
        if (changed("grid") && gridBox.Checked != On("grid", false)) args.Append(Switch("Grid", gridBox.Checked));

        // A profile switch sets the panels itself; sending the boxes as well
        // would overwrite the profile with whatever the window happened to
        // be showing before the switch.
        bool profileDrivesPanels = profileToApply != null;
        var wanted = new List<string>();
        foreach (var kv in extraBoxes) if (kv.Value.Checked) wanted.Add(kv.Key);
        wanted.Sort();
        var was = List("panels"); was.Sort();
        if (!profileDrivesPanels && changed("panels") && string.Join(",", wanted.ToArray()) != string.Join(",", was.ToArray()))
            args.Append(" -Panels " + (wanted.Count > 0 ? string.Join(",", wanted.ToArray()) : "none"));

        var offNow = new List<string>();
        foreach (var kv in standardBoxes) if (!kv.Value.Checked) offNow.Add(kv.Key);
        offNow.Sort();
        var offWas = List("off"); offWas.Sort();
        if (!profileDrivesPanels && changed("off") && string.Join(",", offNow.ToArray()) != string.Join(",", offWas.ToArray()))
            args.Append(" -Off " + (offNow.Count > 0 ? string.Join(",", offNow.ToArray()) : "none"));

        if (changed("folder") && folderBox.Text.Trim() != Get("folderraw"))
            args.Append(" -Folder \"" + folderBox.Text.Trim() + "\"");

        // Profiles first on the command line: settings.ps1 saves what is on
        // now before any switch, and a -Panels further along still wins, so
        // "save this, then switch to that" works in one press.
        if (profileToSave != null) args.Append(" -SaveProfile \"" + profileToSave + "\"");
        if (profileToDelete != null) args.Append(" -DeleteProfile \"" + profileToDelete + "\"");
        if (profileToApply != null && profileToApply != Get("profile"))
            args.Append(" -Profile \"" + profileToApply + "\"");

        if (changed("font") && fontBox.SelectedIndex >= 0
            && fontBox.SelectedIndex < fontNames.Count
            && fontNames[fontBox.SelectedIndex] != Get("font"))
            args.Append(" -Font " + fontNames[fontBox.SelectedIndex]);

        if (changed("keyclick") && keyClickBox.Checked != On("keyclick", false)) args.Append(Switch("KeyClick", keyClickBox.Checked));
        if (changed("hotkeys") && hotkeysBox.Checked != On("hotkeys", true)) args.Append(Switch("Hotkeys", hotkeysBox.Checked));
        if (changed("bootscreen") && bootBox.Checked != On("bootscreen", true)) args.Append(Switch("BootScreen", bootBox.Checked));
        if (changed("snapshell") && snapBox.Checked != On("snapshell", true)) args.Append(Switch("SnapShell", snapBox.Checked));
        if (changed("shellalttab") && altTabBox.Checked != On("shellalttab", false)) args.Append(Switch("ShellAltTab", altTabBox.Checked));
        if (changed("autostart") && autostartBox.Checked != On("autostart", false)) args.Append(Switch("Autostart", autostartBox.Checked));

        if (args.Length == 0)
        {
            outputBox.Text = touched.Count == 0
                ? "nothing changed"
                : "nothing to do - those values are already set";
            return;
        }

        SetBusy(true);
        outputBox.Text = "applying" + args + Environment.NewLine;
        touched.Clear();
        string argLine = args.ToString();
        var worker = new Thread(() =>
        {
            // Colours re-render the wallpaper and every panel, so give it room.
            string result = Run(argLine, 600000);
            BeginInvoke((MethodInvoker)(() =>
            {
                outputBox.Text = (outputBox.Text + result).Trim();
                SetBusy(false);
                string keep = outputBox.Text;
                Reload();                       // pick the new values back up
                outputBox.Text = keep;
            }));
        });
        worker.IsBackground = true;
        worker.Start();
    }

    void SetBusy(bool busy)
    {
        applyButton.Enabled = !busy;
        applyButton.Text = busy ? "Working..." : "Apply";
        dockButton.Enabled = !busy;
        Cursor = busy ? Cursors.WaitCursor : Cursors.Default;
    }
}
