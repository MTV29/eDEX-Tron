sleep 6
edex-tron setup >/dev/null 2>&1
sleep 5
echo "after setup:"; pgrep -af "edex-tron hud"
windows | grep -E "HUD @" | cut -c1-120
gnome-text-editor --new-window >/dev/null 2>&1 &
sleep 3
edex-tron off; sleep 3; echo "after off:"; pgrep -af "edex-tron hud"
edex-tron on; sleep 5; echo "after on:"; pgrep -af "edex-tron hud"
windows | grep -E "HUD @" | cut -c1-120
edex-tron uninstall >/dev/null
sleep 2; echo "after uninstall:"; pgrep -af "edex-tron hud"
