# The release archive's install.sh, as a tester runs it.
sleep 6
T=$(mktemp -d)
tar -xzf "$RELEASE_TGZ" -C "$T"
cd "$T"/eDEX-Tron-linux-v* && ./install.sh --no-boot 2>&1 | grep -vE "^(Get|Hit|Reading|Building|Selecting|Preparing|Unpacking|Setting up|Processing|\(Reading)" | tail -25
sleep 6
windows | grep -E "HUD @" | cut -c1-90
shot 40-installed
edex-tron uninstall >/dev/null && echo "uninstalled"
