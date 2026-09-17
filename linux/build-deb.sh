#!/bin/bash
# Build dist/edex-tron_<version>_all.deb from this checkout.
#   linux/build-deb.sh [OUT_DIR]
# Needs: dpkg-deb, python3-pil, glib-compile-schemas (all on Ubuntu).
set -euo pipefail
LINUX=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$LINUX")
VERSION=$(tr -d '[:space:]' < "$LINUX/VERSION")
OUT=${1:-$REPO/dist}
UUID=edex-tron@mtv29.github.io
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
R=$STAGE/root
APP=$R/usr/share/edex-tron

install -d "$R/DEBIAN" "$R/usr/bin" "$APP/shared/themes" "$APP/shared/src/tools" \
  "$APP/shared/assets/icon" "$R/usr/share/applications" "$R/usr/share/glib-2.0/schemas" \
  "$R/usr/share/gnome-shell/extensions" "$R/usr/share/doc/edex-tron"

# application
cp -r "$LINUX/edex_tron" "$APP/"
find "$APP" -name '__pycache__' -prune -exec rm -rf {} +
cp -r "$LINUX/data" "$APP/"
cp "$LINUX/VERSION" "$APP/"
install -m 0755 "$LINUX/bin/edex-tron" "$R/usr/bin/edex-tron"

# pieces shared with the Windows edition
cp -r "$REPO/themes/edex" "$REPO/themes/vscode" "$APP/shared/themes/"
cp "$REPO/src/tools/make_wallpaper.py" "$REPO/src/tools/gen_icon.py" "$APP/shared/src/tools/"
cp "$REPO/assets/icon/edex-tron.png" "$APP/shared/assets/icon/"

# GNOME Shell extension (schema compiled in place, and installed system-wide
# so `gsettings` and the extension both find it)
cp -r "$LINUX/extension/$UUID" "$R/usr/share/gnome-shell/extensions/"
sed -i "s/\"version-name\": \"[^\"]*\"/\"version-name\": \"$VERSION\"/" \
  "$R/usr/share/gnome-shell/extensions/$UUID/metadata.json"
glib-compile-schemas --strict "$R/usr/share/gnome-shell/extensions/$UUID/schemas"
cp "$LINUX/extension/$UUID/schemas/"*.gschema.xml "$R/usr/share/glib-2.0/schemas/"

# launchers and icons
cp "$LINUX/data/"*.desktop "$R/usr/share/applications/"
for size in 48 64 128 256 512; do
  d="$R/usr/share/icons/hicolor/${size}x${size}/apps"
  install -d "$d"
  python3 -c "import sys; from PIL import Image; Image.open(sys.argv[1]).resize((int(sys.argv[3]),)*2, Image.LANCZOS).save(sys.argv[2])" \
    "$REPO/assets/icon/edex-tron.png" "$d/edex-tron.png" "$size"
done

# docs
cp "$LINUX/README.md" "$R/usr/share/doc/edex-tron/README.md"
{
  echo 'Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/'
  echo 'Upstream-Name: eDEX-Tron'
  echo 'Source: https://github.com/MTV29/eDEX-Tron'
  echo
  echo 'Files: *'
  echo 'Copyright: 2026 MTV29'
  echo 'License: GPL-3.0'
  echo 'Comment: Based on eDEX-UI by Gabriel "Squared" Saillard (GPL-3.0),'
  echo ' https://github.com/GitSquared/edex-ui. The desktop-window technique in the'
  echo ' GNOME extension follows Desktop Icons NG by Sergio Costas (GPL-3.0).'
  echo
  echo 'License: GPL-3.0'
  echo ' On Debian systems, the full text is in /usr/share/common-licenses/GPL-3.'
} > "$R/usr/share/doc/edex-tron/copyright"
printf 'edex-tron (%s) unstable; urgency=low\n\n  * Linux edition pre-release.\n\n -- MTV29 <163179392+MTV29@users.noreply.github.com>  %s\n' \
  "$VERSION" "$(date -R)" | gzip -9n > "$R/usr/share/doc/edex-tron/changelog.gz"

# package metadata
SIZE=$(du -sk "$R/usr" | cut -f1)
cat > "$R/DEBIAN/control" <<CONTROL
Package: edex-tron
Version: $VERSION
Architecture: all
Maintainer: MTV29 <163179392+MTV29@users.noreply.github.com>
Installed-Size: $SIZE
Depends: python3 (>= 3.12), python3-gi, python3-gi-cairo, gir1.2-gtk-4.0, gir1.2-vte-3.91, gir1.2-adw-1, python3-psutil, python3-pil, python3-numpy, gnome-shell (>= 50), libglib2.0-bin, fontconfig, fonts-dejavu-core, iputils-ping
Recommends: gnome-shell-extension-prefs, fonts-ubuntu, starship, fastfetch, btop, tmux, qt6ct, grub-common, plymouth, plymouth-label
Suggests: neovim
Section: x11
Priority: optional
Homepage: https://github.com/MTV29/eDEX-Tron
Description: eDEX-UI style desktop for Ubuntu (GNOME)
 A desktop HUD with a built-in terminal, live system panels, open ports,
 a file browser that follows your shell and an app dock, kept behind your
 windows by a GNOME Shell extension. Also themes GTK and Qt apps, the top bar,
 dock and lock screen, the cursor, terminals and command-line tools, with
 optional CRT screen effects and a matching boot menu and splash.
 .
 Based on eDEX-UI by Gabriel "Squared" Saillard. After installing, run
 "edex-tron setup" (or open "eDEX-Tron Setup") once per user.
CONTROL

cat > "$R/DEBIAN/prerm" <<'PRERM'
#!/bin/sh
set -e
# Take the boot theme out with the package, so nothing points at missing files.
if [ "$1" = remove ] || [ "$1" = purge ]; then
    if [ -f /var/lib/edex-tron/boot.json ]; then
        /usr/bin/edex-tron boot-root remove || true
    fi
fi
exit 0
PRERM
cat > "$R/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
set -e
if [ "$1" = purge ]; then
    rm -rf /var/lib/edex-tron
fi
exit 0
POSTRM
cat > "$R/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
    echo "eDEX-Tron installed. Each user runs 'edex-tron setup' (or opens"
    echo "'eDEX-Tron Setup' from the app grid) to switch it on."
fi
exit 0
POSTINST
chmod 0755 "$R/DEBIAN/prerm" "$R/DEBIAN/postrm" "$R/DEBIAN/postinst"
find "$R/usr" -type d -exec chmod 0755 {} +
find "$R/usr" -type f -exec chmod 0644 {} +
chmod 0755 "$R/usr/bin/edex-tron"

mkdir -p "$OUT"
DEB="$OUT/edex-tron_${VERSION}_all.deb"
dpkg-deb --root-owner-group -Zxz --build "$R" "$DEB" >/dev/null
echo "built $DEB ($(du -h "$DEB" | cut -f1))"
