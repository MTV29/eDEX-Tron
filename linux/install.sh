#!/bin/bash
# eDEX-Tron for Linux: install for the current user.
#
#   ./install.sh            install the package and switch the theme on
#   ./install.sh --boot     ...and theme the boot menu and splash too
#
# Uses the .deb next to this script if there is one, otherwise builds it.
# Based on eDEX-UI by Gabriel "Squared" Saillard.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
BOOT=ask
for arg in "$@"; do
  case "$arg" in
    --boot) BOOT=yes ;;
    --no-boot) BOOT=no ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

say() { printf '\033[38;2;170;207;209m%s\033[0m\n' "$*"; }

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as yourself (it asks for your password when it needs it)." >&2
  exit 1
fi
. /etc/os-release
if [ "${ID:-}" != ubuntu ] && [[ " ${ID_LIKE:-} " != *" ubuntu "* ]]; then
  echo "This release is made for Ubuntu 26.04; found ${PRETTY_NAME:-unknown}." >&2
  read -rp "Continue anyway? [y/N] " a; [[ $a == [yY]* ]] || exit 1
fi
if ! command -v gnome-shell >/dev/null; then
  echo "GNOME Shell was not found. The HUD needs GNOME (Ubuntu's normal desktop)." >&2
  exit 1
fi

say "eDEX-Tron for Linux: based on eDEX-UI by Gabriel \"Squared\" Saillard"

DEB=$(ls -1 "$HERE"/edex-tron_*_all.deb 2>/dev/null | sort -V | tail -n1 || true)
if [ -z "$DEB" ]; then
  if [ ! -f "$HERE/build-deb.sh" ]; then
    echo "No edex-tron_*.deb next to this script. Download the release archive again." >&2
    exit 1
  fi
  say "Building the package..."
  sudo apt-get install -y --no-install-recommends dpkg-dev python3-pil libglib2.0-bin
  bash "$HERE/build-deb.sh" "$HERE/build"
  DEB=$(ls -1 "$HERE"/build/edex-tron_*_all.deb | sort -V | tail -n1)
fi

say "Installing $(basename "$DEB") and what it needs (asks for your password)..."
sudo apt-get update -q
sudo apt-get install -y "$DEB"

say "Applying the theme to your account..."
edex-tron setup

if [ "$BOOT" = ask ] && [ -t 0 ]; then
  echo
  read -rp "Also theme the boot menu and boot splash? (needs admin, can be removed later) [y/N] " a
  [[ $a == [yY]* ]] && BOOT=yes
fi
if [ "$BOOT" = yes ]; then
  edex-tron boot install
fi

echo
say "Done. If the HUD isn't showing yet, log out and back in once."
