# eDEX-Tron

A Windows 11 desktop theme inspired by **[eDEX-UI](https://github.com/GitSquared/edex-ui)**
— the sci-fi terminal interface by **Gabriel "Squared" Saillard**. It brings
eDEX-UI's look to your whole desktop while you keep using Windows normally:
live system panels, a built-in shell, a shortcut dock, and a matching colour
scheme across Windows, the taskbar, Windows Terminal, VS Code and Office.

> **Version 0.8 — pre-release.** It works day to day, but it is still changing.
> Everything it changes is backed up and can be undone.

## Credit

This project would not exist without **eDEX-UI** by Gabriel "Squared" Saillard
(GPL-3.0). Its colour palette, panel design and home-screen layout are the
basis of everything here. eDEX-Tron is an independent fan project and is not
affiliated with or endorsed by eDEX-UI. See
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

---

## What you get

- **Live HUD** on the desktop, behind your windows: clock, uptime and machine
  info; per-core CPU graphs; memory map; network status (with a refresh
  button); network usage graph; top processes; a file browser.
- **Main shell** — a real Command Prompt that sits inside an eDEX-style frame.
- **Dock** of your apps, and a **Desktop** panel that mirrors your Desktop
  folder and updates itself. Real desktop icons are hidden while the theme is on.
- **Dark everywhere** — Windows, Windows Terminal, VS Code and Office — in one
  accent colour you can change with a single command.
- **Fits your screen** — the layout is worked out from your resolution and
  scaling, not hard-coded.
- **One switch** — `eDEX-Tron.exe` turns it all on or off.

## Requirements

- Windows 10 or 11 with **winget** (the "App Installer" from the Microsoft Store)
- An internet connection during setup
- Optional: **eDEX-UI** installed, for its original typeface and sounds

Setup installs what else it needs: Rainmeter, TranslucentTB, Python and a few
Python packages.

## Install

1. Download **`eDEX-Tron-Setup-v0.8.0.exe`** from the
   [Releases](../../releases) page.
2. Run it. Windows SmartScreen may warn that the app is unrecognised, because
   the installer isn't code-signed: choose **More info → Run anyway**.
3. Confirm the install location (`Documents\eDEX-Tron`). A PowerShell window
   shows progress; Windows may ask for permission while the helper apps
   install, and Explorer restarts once.

That's it — the theme switches on when setup finishes.

Prefer the source? Clone into `Documents\eDEX-Tron` (the scripts expect that
folder) and run:

```bash
powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\Documents\eDEX-Tron\src\setup.ps1"
```

## Using it

**Turn it on or off** — double-click **eDEX-Tron Theme** on the Desktop or in
the Start menu, or the **Theme** tile in the dock. `eDEX-Tron.exe` also takes
`start`, `stop` and `status`. Switching off stops the HUD, the taskbar
transparency and the Desktop watcher and brings your desktop icons back; your
colours stay until you uninstall.

**Shell** — click the MAIN SHELL panel to open or re-snap it.

**Dock** — right-click it, or click **+ EDIT**, to edit `dock.txt` in Notepad.
One app per line: `Label | target [| icon source]`. Targets can be programs,
shortcuts, folders, documents, `ms-settings:` links or Store apps
(`shell:AppsFolder\<id>!App`). Save and close, and the layout rebuilds. The dock
wraps to a second row when it gets long.

**Desktop panel** — shows what's in your Desktop folder and refreshes a moment
after anything changes. Right-click to rescan by hand.

**Colours** — all colours live in `theme.json`. Change them with:

```bash
powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\Documents\eDEX-Tron\src\retheme.ps1" -Accent "#ff9f1c"
```

Options: `-Accent`, `-Background`, `-IconColor` (each `#RRGGBB`) and
`-Grid on|off`. The theme is dark-only, so light backgrounds are refused.

**Changed resolution or scaling?** Run `src\tools\relayout.ps1`.

**Taskbar styling (optional)** — Windhawk mods can add accent lines to the
taskbar; see [windhawk/taskbar-styler.md](windhawk/taskbar-styler.md).

## Uninstall

```bash
powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\Documents\eDEX-Tron\src\uninstall.ps1"
```

Restores everything setup backed up — accent, dark mode, wallpaper, Office and
VS Code settings, sounds — brings back desktop icons, and removes the fonts,
panels and shortcuts. Rainmeter, TranslucentTB and Python stay installed;
remove them with `winget uninstall` if you like.

## Known limitations

- Primary display only.
- The Windhawk taskbar styling is manual.
- The installer is not code-signed yet.
- Without eDEX-UI installed, text uses Windows' Bahnschrift rather than
  eDEX-UI's United Sans (which can't be redistributed).

## Licence

GPL-3.0 — see [LICENSE](LICENSE). Third-party components are listed in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

---

## For developers

```
dock.default.txt / theme.default.json   starting settings (setup copies them)
themes/edex/tron.json   eDEX-UI's palette
themes/terminal, vscode app colour schemes
skins/eDEX-Tron/@Resources  scripts the panels run
src/setup.ps1           first-time setup
src/install.ps1         applies the theme (and backs up first)
src/retheme.ps1         colours
src/uninstall.ps1       reverts
src/tools/              generators and helpers
src/dev/                verification scripts used while developing
windhawk/               optional taskbar styles
```

| Tool | Purpose |
|---|---|
| `relayout.ps1` | Measures the screen, plans the layout, regenerates and deploys every panel |
| `gen_rainmeter_ini.py` | The layout planner (logical, DPI-scaled pixels) |
| `gen_skins.py` | Generates the Rainmeter panels |
| `gen_dock.ps1` | Builds the dock (from `dock.txt`) or the Desktop grid (from a folder), extracting real icons |
| `make_wallpaper.py`, `gen_icon.py` | Render the wallpaper and launcher icon from `theme.json` |
| `build_launcher.ps1` | Compiles `eDEX-Tron.exe` with the C# compiler built into Windows |
| `bootstrap_assets.ps1` | Copies fonts and sounds out of a local eDEX-UI install |
| `build_release.ps1` | Builds the setup exe and source zip into `dist/` |
| `run_outside.ps1` | Runs a script outside an app container (see below) |

**Building a release:** commit, then run `src\tools\build_release.ps1`.

**Don't run the scripts from inside a packaged (MSIX) app** such as the Claude
desktop app or the Store build of Windows Terminal: those redirect writes to
`%APPDATA%`/`%LOCALAPPDATA%` into a private container that nothing else can
see. `run_outside.ps1` works around it by going through Task Scheduler.

### Things that fail silently (and cost real time)

- Rainmeter positions skins in logical (DPI-scaled) pixels.
- Rainmeter merges same-named sections without an error — `gen_skins.py`
  refuses to write duplicates.
- `ClipString=1` clips to `H`; 12pt text needs `H` of about 22.
- `AutoScale` is a meter option, not a measure option.
- `RunCommand` only runs when sent `[!CommandMeasure ... "Run"]`.
- FileView has no parent/child measures and no icon type: every measure needs
  its own `Path`, or it lists your drives.
- `UsageMonitor`'s Process category crashes Rainmeter on Windows 11 25H2.
- `BackgroundType` 2/3 (slideshow/Spotlight) overrides any wallpaper;
  `AutoColorization` recomputes the accent from it.
- `DWM\AccentColor` is re-derived from the active theme — check
  `AccentColorMenu` or the `UISettings` API instead.
- P/Invoke `FindWindow`/`GetClassName` need `CharSet.Unicode`.
- Task Scheduler kills its process tree; long-lived processes are started with
  `Win32_Process.Create`.
- PowerShell 5.1 turns native stderr into terminating errors under `Stop`, and
  writes a BOM with `-Encoding utf8`.
