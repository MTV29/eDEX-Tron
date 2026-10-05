# Changelog

## 0.9.0 — 2026-10-05 (Windows)

### Added

- **Settings window.** `Win+Alt+S`, or `eDEX-Tron.exe settings`. Colours with a
  picker, which panels you want, the folder panel and every switch, without
  editing a file. It is a front end for `src\tools\settings.ps1` and holds no
  logic of its own, so the window and the command line cannot disagree about
  what a setting means.
- **Three optional panels.** **GPU** (load, memory and temperature — `nvidia-smi`
  where it exists, performance counters otherwise), **DISK** (free space per
  fixed drive) and **PORTS** (listening ports and the program holding each one,
  with Windows' own service hosts pushed to the bottom).
- **Hotkeys.** `Win+Alt+H` hide or show the HUD, `T` the shell, `E` the theme
  on or off, `S` settings. Switchable off.
- **Boot screen.** eDEX's startup log when the theme comes up, reporting the
  machine it is actually running on: the real processor, memory, drives,
  display adapter, network links, the services Windows has running and the real
  uptime. It is shown while the HUD genuinely starts behind it, so the closing
  line is true rather than timed to look true. Any key skips it.
- **Audible key clicks**, off by default. The click is rendered by
  `src\tools\gen_sounds.py` rather than taken from eDEX-UI, whose sound set
  cannot be redistributed — and whose `keyboard.wav` is a 1.2-second run of
  typing rather than one keystroke. The hook asks only whether a key went down
  and never looks at which one.
- **A folder of your choosing as clickable icons** (your games by default),
  replacing the old FILESYSTEM text list. It follows changes to that folder.
- `src\dev\test_plan.py`: 13824 layouts asserted free of overlaps and
  off-screen panels. `src\dev\capture_window.ps1`: a picture of one window by
  title, rather than of the whole screen.

### Changed

- **The layout is planned from the bottom up** — dock and grids first, system
  panels into what is left. Panels that cannot fit are switched off rather than
  drawn over each other, and `theme.json` `"off"` switches any standard panel
  off and gives its space back to the rest.
- **The shell stays in its frame.** It is a real console window moved into
  place, so anything that moved or resized it used to leave the frame empty. It
  is now put back, and kept out of Alt-Tab as part of the HUD.
- The launcher's C# moved out of a PowerShell here-string into `launcher.cs`,
  `SettingsForm.cs` and `BootScreen.cs`.

### Fixed

- On a short screen (a 1366x768 laptop at 125%) the right-hand column ran off
  the bottom, leaving the process list half off the screen.
- A long dock wrapped to enough rows to climb into the CPU panel and the shell.
  It now widens before it stacks.
- Rebuilding the layout could bring the old one back: Rainmeter rewrites its own
  `Rainmeter.ini` as it shuts down, over the top of the one just written. The
  rebuild now waits for the process to actually exit.
- Game tiles showed a shortcut arrow over the artwork, or a generic icon, for
  `.lnk` and `.url` shortcuts that keep their icon in a separate file.
- Removing an item from a panel's folder left its icon behind.
- A broken path in the README, written through a shell that ate its backslashes.

## 0.8.0 — 2026-09-17

First public release: the live HUD, the shell frame, the dock and Desktop
panels, the matching colour scheme across Windows, Windows Terminal, VS Code
and Office, and a setup that backs up everything it changes.

A separate Linux edition for Ubuntu 26.04 / GNOME 50 was released alongside it
as `v0.8.0-linux`, with a real terminal in the HUD, whole-system theming,
multi-monitor support, screen effects and an optional boot theme. See
[linux/README.md](linux/README.md).
