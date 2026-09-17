# End to end: setup -> features -> recolour -> off/on -> uninstall.
# Runs inside run_shell_test.sh with EXT_MODE=system (package installed).
set -u
dump() { dconf dump / | grep -v -E '^(welcome-dialog|enabled-extensions|disable-user-extensions)' ; }
sleep 6
mkdir -p "$OUT/state"
dump > "$OUT/state/dconf-before.txt"
find ~ -xdev -type f -not -path '*/.cache/*' -not -path '*/.local/state/*' \
  -not -path '*/.local/share/gnome-shell/*' -not -path '*/.config/dconf/*' \
  -not -path '*/.local/share/gvfs-metadata/*' -not -path '*/.local/share/recently-used*' \
  -not -path '*/.local/share/localsearch*' -not -path '*/.local/share/tracker*' -not -path '*/.local/bin/*' \
  -printf '%p %s\n' | sort > "$OUT/state/files-before.txt"
md5sum ~/.bashrc > "$OUT/state/bashrc-before.md5"

echo "=== setup"
edex-tron setup 2>&1
sleep 6
edex-tron status
windows
shot 10-setup-desktop

echo "=== apps"
gnome-text-editor --new-window >/dev/null 2>&1 &
nautilus --new-window >/dev/null 2>&1 &
sleep 5
shot 11-apps
call quick; sleep 1.2; shot 12-quick-settings; call close
call calendar; sleep 1.2; shot 13-calendar; call close
overview true; sleep 2; shot 14-overview; overview false; sleep 1
call peek; sleep 1.5; shot 15-peek; call peek; sleep 1

echo "=== window animation"
gnome-text-editor --new-window >/dev/null 2>&1 &
for i in 1 2 3 4 5 6 7 8; do sleep 0.08; shot "15-tv-$i" >/dev/null; done
sleep 1

echo "=== prefs"
gnome-extensions prefs edex-tron@mtv29.github.io >/dev/null 2>&1 &
sleep 4; shot 15-prefs
pkill -f org.gnome.Shell.Extensions || true; sleep 1

echo "=== boot"
edex-tron boot preview --out "$OUT/boot" | tail -1
sudo -n true && sudo -n "$(command -v edex-tron)" boot-root install --accent "#aacfd1" --background "#05080d" | tail -6
update-alternatives --query default.plymouth | sed -n 3,5p
sudo -n "$(command -v edex-tron)" boot-root remove | tail -3
update-alternatives --query default.plymouth | sed -n 3,5p
ls /usr/share/plymouth/themes | grep -c edex || true

echo "=== effects"
edex-tron effects scanlines on; sleep 1.5; windows | head -1; shot 16-scanlines
edex-tron effects scanlines off

echo "=== recolour"
edex-tron theme --accent "#ff9f1c" 2>&1 | tail -12
sleep 4
shot 17-orange

echo "=== lock"
if call lock | grep -q ok; then sleep 3; shot 18-lock; call unlock; sleep 2; else echo "(no lock screen in this session)"; fi

echo "=== off/on"
edex-tron off; sleep 3; windows | grep -c "eDEX-Tron HUD" ; shot 19-off
edex-tron on; sleep 5; windows | grep -c "eDEX-Tron HUD"

echo "=== uninstall"
pkill -f gnome-text-editor; pkill -f nautilus
edex-tron uninstall 2>&1 | tail -8
sleep 3
dump > "$OUT/state/dconf-after.txt"
find ~ -xdev -type f -not -path '*/.cache/*' -not -path '*/.local/state/*' \
  -not -path '*/.local/share/gnome-shell/*' -not -path '*/.config/dconf/*' \
  -not -path '*/.local/share/gvfs-metadata/*' -not -path '*/.local/share/recently-used*' \
  -not -path '*/.local/share/localsearch*' -not -path '*/.local/share/tracker*' -not -path '*/.local/bin/*' \
  -printf '%p %s\n' | sort > "$OUT/state/files-after.txt"
echo "--- dconf differences (before vs after uninstall):"
diff "$OUT/state/dconf-before.txt" "$OUT/state/dconf-after.txt"
echo "--- file differences:"
diff "$OUT/state/files-before.txt" "$OUT/state/files-after.txt"
md5sum -c "$OUT/state/bashrc-before.md5"
shot 20-after-uninstall
