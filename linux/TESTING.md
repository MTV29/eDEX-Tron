# eDEX-Tron for Linux 0.8.0 — tester checklist

Thanks for testing! This needs **Ubuntu 26.04 with the normal (GNOME) desktop**.
It takes about 15 minutes. Everything can be undone at the end.

Most of this has already been tested automatically in a headless GNOME 50
session. What's left can only be checked on a real machine: the login/logout
cycle, real graphics, the lock screen, the keyboard shortcuts and the boot
splash.

When something looks wrong, a photo or screenshot plus the output of these
two commands helps most:

```bash
edex-tron doctor
journalctl --user -b -g "eDEX-Tron" --no-pager | tail -n 60
```

## 1. Install

- [ ] `tar xf eDEX-Tron-linux-v0.8.0.tar.gz && cd eDEX-Tron-linux-v0.8.0 && ./install.sh`
- [ ] It asks for your password once, finishes, and asks about the boot theme.
      Answer **n** for now (that's step 6).
- [ ] Log out and back in.

## 2. The HUD

- [ ] After logging in, the HUD fills the desktop: clock, system, CPU, memory
      and processes on the left; the terminal in the middle; network, ports,
      disks and dock on the right.
- [ ] Opening an app puts it **above** the HUD, and the HUD never covers it.
- [ ] The HUD is not in Alt+Tab or the dock, and it stays when you switch workspaces.
- [ ] Click the terminal and type `ls`: it works. Run `cd /usr/share` and
      the FILESYSTEM panel follows it.
- [ ] Click a folder in FILESYSTEM: the terminal `cd`s there.
- [ ] Ctrl+Shift+T opens a second tab; typing `exit` closes it.
- [ ] Put a file on the Desktop (e.g. `touch ~/Desktop/test.txt`): it
      appears in the DESKTOP panel within a second or two.
- [ ] Click a dock tile: the app opens. **[ + EDIT ]** opens the dock file;
      delete a line, save, and the tile disappears.
- [ ] NETWORK STATUS → **[ REFRESH ]** fills in "Gateway ping".
- [ ] With a second monitor: that screen shows the smaller HUD with SYSTEM LOG.

## 3. Hotkeys

- [ ] **Super+Alt+H**: windows minimise and the HUD is in front; press again and they come back.
- [ ] **Super+Alt+T**: the same, with the cursor in the HUD terminal.
- [ ] **Super+Alt+E**: fine scanlines over the screen; press again to remove them.

## 4. The rest of the desktop

- [ ] Top bar, quick settings (top-right menu), calendar and notifications are dark with the cyan accent.
- [ ] The Ubuntu Dock is dark; open apps are marked with small dashes.
- [ ] Files, Settings and Text Editor are dark.
- [ ] Any Qt app (e.g. VLC, if installed) is dark; this may need one more logout first.
- [ ] The mouse pointer is the thin cyan arrow; over links it's a round target.
- [ ] Newly opened windows get a quick "CRT switch-on" flash and a soft cyan glow while focused.
- [ ] Open **Terminal** (Ptyxis): cyan-on-black colours and the `┌─user@host ─ path` prompt.
- [ ] **Lock the screen (Super+L)**: the clock and password box are in the theme colours.
      Unlock, and the HUD terminal still has what you typed before.
- [ ] Run `btop`, `tmux` and `nvim` (if installed): they use the theme colours.

## 5. Switching and colours

- [ ] Run `edex-tron off`: the HUD disappears and Ubuntu's desktop icons come back.
- [ ] Run `edex-tron on`: the HUD comes back (no logout needed).
- [ ] Run `edex-tron theme --accent "#ff9f1c"`: the HUD, top bar and window glow turn orange within a few seconds.
- [ ] Run `edex-tron theme --reset`: everything goes back to cyan.
- [ ] Open **Extensions** → eDEX-Tron → settings: the switches work.

## 6. Boot menu and splash (optional; needs your password)

- [ ] Run `edex-tron boot install --show-menu` and reboot.
- [ ] The boot menu is dark, with "SELECT OPERATING SYSTEM" and a cyan selection bar.
- [ ] The boot splash shows the blue globe with a spinning ring and a progress line.
- [ ] If the disk is encrypted: the password box appears and accepts the password.
- [ ] Run `edex-tron boot remove` and reboot: the normal Ubuntu menu and splash are back.

## 7. Remove

- [ ] Run `edex-tron uninstall`, then log out and in: the wallpaper, dark/light
      style, cursor, terminal colours and `~/.bashrc` are as they were before.
- [ ] Run `sudo apt remove edex-tron`.
