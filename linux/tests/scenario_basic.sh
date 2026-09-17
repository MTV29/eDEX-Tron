# Basic: HUD on the desktop layer, a normal window above it, glow, peek.
sleep 8
windows
shot 01-desktop
gnome-text-editor --new-window >/dev/null 2>&1 &
sleep 0.12; shot 02-tv-opening
sleep 3
windows
shot 03-window-open
call peek; sleep 1.5
windows
shot 04-peek
call peek; sleep 1.5
shot 05-restored
overview true; sleep 2; shot 06-overview; overview false; sleep 1
