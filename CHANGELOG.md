# Changelog

## 1.0.0 — 2026-10-07 (Windows)

The release the "primary display only" line was waiting on. A second screen
now gets the HUD too, the project ships its own sounds and typeface, and the
install has been run from scratch on a clean machine rather than assumed.

### Added

- **A second display gets a duplicate of the HUD**, laid out for its own size
  rather than the primary's coordinates repeated — the screens are rarely the
  same shape. Drawn larger (the panels scale as a set: width, padding, type
  sizes and row metrics together), inset from the left edge, and removed again
  when the display goes away. The shell stays on the primary, being one real
  console window that cannot be in two places.
- **A wallpaper per monitor**, rendered at each one's exact pixel size.
  Windows takes a single image and a single fit mode, which stretches a 16:9
  picture onto a 21:9 screen; spanning assumes the displays tile into a
  rectangle, which they often do not.
- **The boot screen comes up on every display.** One window does the work and
  the others mirror it, so there is one log, one timer and one sound however
  many screens there are. Its text scales with each screen, with `bootscale`
  deciding how much of the difference to apply.
- **A POWER panel** — watts drawn, and the battery where there is one. Windows
  exposes the wattage through plain performance counters with no driver and no
  elevation: the ACPI power meter, and Intel RAPL, which Intel desktops have
  too. Only the lines a machine can answer are printed; there is no honest
  whole-system figure on a desktop without a kernel driver, so none is shown.
- **Layout profiles** — a named set of panels, switched in one go. They hold
  the panel choice and nothing else, so switching one is not a bigger surprise
  than the name suggests.
- **A PRTG panel** for sensors that are down, on a second display only, off
  until you switch it on. Reads `runtime\prtg.json` for the server and an API
  token, which never leaves that file.
- **A speed test button** on Network Usage. It moves about 33MB, so it is on a
  button and never on a timer.
- **Audible key clicks**, off by default: the device is opened once and kept
  open, presses layer over each other rather than cutting each other off, six
  variants keep it from sounding like one sample on repeat, and a held key is
  one keystroke rather than thirty a second. `keyclickms` and `keyclickvolume`
  tune it.
- **Sound over the boot screen**, with `boot demo` substituting a generic user,
  host, address and service list so it can be recorded.
- **A choice of typeface** — automatic, eDEX-UI's United Sans, Fira, or
  Windows' own. Fira Mono and Fira Code now ship with the project (OFL 1.1), so
  there is a non-Windows option without eDEX-UI installed.
- **eDEX-UI's sound effects ship**, composed by IceWolf and redistributed under
  eDEX-UI's GPL-3.0 with the credit that licence asks for.
- **The taskbar is part of the theme.** Setup installed TranslucentTB and never
  said what it should look like; it is now tinted from `theme.json`.
- **A preview in the README** — the HUD and the boot screen, composited from
  the theme's own windows rather than photographed off a desktop.
- **`eDEX-Tron.exe dumpclicks`**, and `src\dev` tooling to capture the HUD,
  the boot screen and build a GIF without picturing anyone's desktop.

### Changed

- **Network Usage** is two readouts rather than a pair of mirrored histograms,
  which took 200 pixels of a column three other panels were queuing for.
- **The project installs from wherever it is cloned**, not only from
  `Documents\eDEX-Tron`.
- **`status` and `repair` print to the terminal** when run from one, and still
  show a dialog when launched from the dock. They reported through a dialog
  only, which from a shell looked like the command had hung.

### Fixed

- Font smoothing could end up **absent** rather than off, leaving text
  unsmoothed. Windows re-applies the active theme, and a theme whose
  `[Control Panel\Desktop]` section does not mention those values clears
  them; install now asserts them back at the very end.
- `gen_icon.py` wrote to a path relative to the working directory, so setup
  tried to write the icon into `C:\Windows\System32\assets`, failed, and
  carried on with the bundled icon.
- Uninstall left the second display's skins behind entirely — the folder on
  disk and twelve entries in `Rainmeter.ini`, which `[eDEX-Tron\` did not match.
- Uninstall could not remove the fonts if `build\ttf` was gone, and the font
  family names it registered were guessed: three of four were wrong, so the
  HUD silently rendered in Microsoft Sans Serif.
- A panel the planner placed but that was missing from `ORDER` was never
  written to the config: a place on screen, no entry telling Rainmeter to load
  it, and no symptom beyond not appearing. There is now an assertion at import.
- `ConvertTo-Json` defaults to depth 2, which flattened the nested `profiles`
  into space-joined strings with no error anywhere.
- The settings window wrote every setting on Apply, so one left open would
  undo a change made elsewhere. It now writes only what was changed in it.

## 0.9.1 — 2026-10-05 (Windows)

### Added

- **The layout rebuilds itself when the screen changes.** Change the resolution
  or the scaling, plug in a monitor, or move the taskbar, and the HUD is
  re-planned a few seconds later instead of waiting to be told.
- **`eDEX-Tron.exe repair`** — rebuild the layout for this screen, restart
  anything that has died, put the shell back in its frame, hide the desktop
  icons again, then report. Also `relayout` to force a rebuild on its own.
- **The background tasks keep a log** at `runtime\watcher.log`: what they
  noticed, what they rebuilt, and anything they could not do.
- **Silent install.** `eDEX-Tron-Setup.exe /S` (or `/silent`, `/quiet`,
  `/VERYSILENT`) installs without a prompt, waits for setup to finish and
  returns its exit code, so winget and scripted rollouts can use it.
  `setup.ps1 -Unattended` does the same from source.
- **`src\dev\verify_uninstall.ps1`** — snapshots the 50 registry values, files,
  fonts and shortcuts the theme touches, so the claim that uninstalling puts
  everything back can be checked rather than believed.

### Fixed

- `CurrentTheme` was captured in the backup and never restored, so anyone who
  had applied the generated `.theme` file was left with Personalization
  pointing at a file the uninstall had just deleted.
- Setup now says so when Documents is inside OneDrive, since the whole theme
  would be synced.

### Verified

An install, uninstall, reinstall and uninstall cycle on a real machine leaves
all 50 tracked values exactly as they were — the Windows counterpart of the
empty dconf diff the Linux edition was held to.

## 0.9.0-linux — 2026-10-05 (Linux)

### Fixed

- The HUD did not fit a short screen: the side columns were cut off rather than
  scrolled, and `--window` opened larger than the work area on a laptop display.
  The columns scroll when they have to, and the window now opens at a size that
  fits the screen it is on.

Everything else is unchanged from `v0.8.0-linux`. Version numbers are kept in
step with the Windows edition, so this release carries no other changes.

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
