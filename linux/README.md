# eDEX-Tron for Linux

The Linux edition of eDEX-Tron, for **Ubuntu 26.04 LTS (GNOME 50)**. It puts
an **[eDEX-UI](https://github.com/GitSquared/edex-ui)**-style HUD with a real
terminal on your desktop, and restyles the rest of the system to match.

> **Credit:** based on **eDEX-UI** by **Gabriel "Squared" Saillard** (GPL-3.0).
> The colour palette, panel design and home-screen layout come from eDEX-UI.
> This is an independent fan project, not affiliated with eDEX-UI.

> **Version 0.8 — pre-release.** Every change is recorded and
> `edex-tron uninstall` puts your previous settings back.

## Compared with the Windows edition

| | Windows | Linux |
|---|---|---|
| HUD panels (clock, CPU, memory, network, processes, dock, Desktop) | ✓ | ✓ |
| Terminal | Command Prompt window snapped into a frame | **Real terminal inside the HUD, up to 5 tabs** |
| File browser | Fixed folder | **Follows the folder you `cd` into**; click a folder to `cd` there |
| Open ports and disk usage panels | – | ✓ |
| Several monitors | Primary only | **HUD on every monitor** (a lighter layout with a live system log on the others) |
| App colours | Accent colour; Terminal, VS Code, Office | **GTK and Qt apps, top bar, menus, Ubuntu Dock, lock screen**, Ptyxis/GNOME Terminal, VS Code |
| Cursor | – | **eDEX-style cursor theme** |
| Command-line tools | – | **Prompt (starship), fetch screen (fastfetch), btop, tmux, Neovim** |
| Screen effects | – | **Focused-window glow, CRT switch-on/off animation, optional scanlines** |
| Hotkeys | – | **Show the HUD, focus its terminal, toggle scanlines** |
| Boot | – | **Optional themed boot menu (GRUB) and boot splash (Plymouth)** |
| Colours change live | Rebuilds | **HUD and top bar recolour without restarting** |

## Install

Download `eDEX-Tron-linux-v0.8.0.tar.gz` from the
[Releases](../../releases) page, then in a terminal:

```bash
tar xf eDEX-Tron-linux-v0.8.0.tar.gz
cd eDEX-Tron-linux-v0.8.0
./install.sh
```

The script installs the package (it asks for your password) and applies the
theme to your account. It then asks whether you also want the boot menu and
splash themed. **Log out and back in once** so GNOME loads the extension;
after that the HUD starts by itself.

Prefer the package alone? Install `edex-tron_0.8.0_all.deb` with
`sudo apt install ./edex-tron_0.8.0_all.deb`, then open **eDEX-Tron Setup** from
the app grid (or run `edex-tron setup`). Each person on the computer runs
setup for their own account.

## Using it

| To… | Do this |
|---|---|
| See the HUD when windows cover it | **Super + Alt + H** (press again to bring the windows back) |
| Type in the HUD terminal | **Super + Alt + T**, or click it |
| New terminal tab / switch tabs | **Ctrl + Shift + T** / **Ctrl + Page Up/Down** |
| Copy / paste in the terminal | **Ctrl + Shift + C / V** |
| Scanlines on/off | **Super + Alt + E** |
| Switch everything off / on | `edex-tron off` / `edex-tron on`, or the **eDEX-Tron** app / **Theme** dock tile |
| Change colours | `edex-tron theme --accent "#ff9f1c"` (also `--background`, `--icon`, `--grid on`) |
| Back to the original colours | `edex-tron theme --reset` |
| Effects | `edex-tron effects glow off`, `edex-tron effects scanlines on`, `edex-tron effects strength 0.3` — or the extension's settings in the **Extensions** app |
| Edit the dock | Click **[ + EDIT ]** on the dock; it rebuilds when you save |
| Boot menu and splash | `edex-tron boot install` (add `--show-menu` to always show the menu); `edex-tron boot remove`; `edex-tron boot preview` renders them to a folder |
| After changing screens | `edex-tron reapply wallpaper` |
| Something's wrong | `edex-tron doctor`, or `edex-tron hud --window` to see errors |

**Dock format** (`~/.config/edex-tron/dock.txt`), one app per line:
`Label | target [| icon]`. The target can be an app (`org.gnome.Nautilus.desktop`;
list several separated by commas and the first installed one is used), a
command (`!btop`), or a folder, file or web address. Apps you don't have are
skipped.

**Settings** (`~/.config/edex-tron/settings.json`): `prompt` (the eDEX
prompt in bash/zsh; set `EDEX_TRON_PROMPT=0` to skip it in one shell),
`secondary_monitors`, `terminal_font`.

## What setup changes

Everything below is recorded in `~/.local/state/edex-tron/manifest.json`
before it is changed.

- **Desktop:** wallpaper (rendered for your screen); dark style and accent
  colour; Yaru dark variant for GTK 3 apps and icons; cursor theme.
- **Apps:** colour overrides imported at the top of your `gtk.css` (GTK 3
  and 4) and a qt6ct colour scheme (Qt apps).
- **Shell:** Ubuntu Dock colours. Ubuntu's own desktop icons are switched off
  while the theme is on; the HUD's Desktop panel replaces them.
- **Terminal:** Ptyxis palette; a marked block in `~/.bashrc` (and
  `~/.zshrc` if you have one); btop's `color_theme`; a `source-file` line in
  your tmux config; a Neovim colour scheme (`init.lua` only if you had none).
- **VS Code:** only if it's installed; just the colour-theme setting is
  changed, and comments in `settings.json` are kept.

## Remove

```bash
edex-tron boot remove    # only if you installed the boot theme
edex-tron uninstall      # restores your settings and files
sudo apt remove edex-tron
```

`uninstall` leaves your `~/.config/edex-tron` (colours and dock) in place, so
reinstalling picks up where you left off; delete that folder if you don't
want it.

## Limitations

- Made and tested for Ubuntu 26.04 / GNOME 50. Other GNOME versions
  won't load the extension. On other desktops, `edex-tron hud --window` still
  runs the HUD as a normal window.
- The login screen isn't themed: that would mean replacing a system file that
  Ubuntu updates overwrite. The lock screen is themed.
- Ubuntu hides the boot menu when only one system is installed; use
  `edex-tron boot install --show-menu`, or hold Shift / press Esc while booting.
- While scanlines are on, full-screen games can't bypass the compositor
  (switch them off with Super + Alt + E when gaming).
- eDEX-UI's United Sans font isn't included (it's commercial); the HUD uses it
  if it's installed, otherwise Ubuntu Sans.

## For developers

```
linux/
  bin/edex-tron          command-line entry point
  edex_tron/             Python package: apply.py (setup/undo), changes.py (undo log),
                         themes.py (generated configs), cursor.py, boot.py, cli.py
  edex_tron/hud/         the HUD: GTK 4 + VTE
  extension/             GNOME Shell extension: desktop layer, hotkeys, effects, shell CSS
  data/                  default dock, app launchers
  build-deb.sh           builds dist/edex-tron_<version>_all.deb
  install.sh             user-facing installer
  tests/                 unit tests and a headless GNOME Shell test harness
```

- **Unit tests:** `python3 -m unittest discover -s linux/tests`.
- **Headless GNOME Shell test:** `linux/tests/run_shell_test.sh OUT scenario.sh`.
  It starts GNOME Shell with a virtual monitor (no display needed, so it works
  in WSL) and gives the scenario `shot`, `windows` and `call` helpers.
- **HUD on its own:** `linux/bin/edex-tron hud --window`.

How the HUD stays on the desktop: the extension launches it as a trusted
Wayland client (`Meta.WaylandClient`). It marks the HUD's windows as desktop
windows, puts them on every workspace and hides them from Alt+Tab, following
the approach of [Desktop Icons NG](https://gitlab.com/rastersoft/desktop-icons-ng)
by Sergio Costas.
