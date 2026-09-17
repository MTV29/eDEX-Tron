#!/bin/bash
# Build the Linux release into dist/linux/ from what is committed.
#   linux/build-release.sh
# Produces edex-tron_<v>_all.deb, eDEX-Tron-linux-v<v>.tar.gz, SHA256SUMS-linux.txt
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(tr -d '[:space:]' < "$REPO/linux/VERSION")
OUT=$REPO/dist/linux
if [ -n "$(git -C "$REPO" status --porcelain)" ] && [ "${ALLOW_DIRTY:-0}" != 1 ]; then
  echo "Uncommitted changes; commit first (or ALLOW_DIRTY=1)." >&2
  exit 1
fi
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# build from exactly what is committed
git -C "$REPO" archive --format=tar HEAD | tar -xf - -C "$WORK"
rm -rf "$OUT" && mkdir -p "$OUT"
bash "$WORK/linux/build-deb.sh" "$OUT"

NAME=eDEX-Tron-linux-v$VERSION
PKG=$WORK/$NAME
mkdir -p "$PKG"
cp "$OUT/edex-tron_${VERSION}_all.deb" "$WORK/linux/install.sh" "$WORK/linux/README.md" \
   "$WORK/linux/TESTING.md" "$WORK/LICENSE" "$WORK/THIRD-PARTY-NOTICES.md" "$PKG/"
chmod 0755 "$PKG/install.sh"
tar -C "$WORK" --owner=0 --group=0 -czf "$OUT/$NAME.tar.gz" "$NAME"
(cd "$OUT" && sha256sum edex-tron_*.deb "$NAME.tar.gz" > SHA256SUMS-linux.txt)
cat "$OUT/SHA256SUMS-linux.txt"
