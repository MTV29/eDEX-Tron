#!/bin/bash
# Headless GNOME Shell test session (used from WSL; no display needed).
#   run_shell_test.sh OUT_DIR SCENARIO_SCRIPT [MODE]
# The scenario runs inside the session with helper functions:
#   shot NAME | windows | call peek|focus | overview true|false
set -u
OUT=$1; SCENARIO=$2; MODE=${3:-ubuntu}
HERE=$(cd "$(dirname "$0")" && pwd)
LINUX=$(dirname "$HERE")
mkdir -p "$OUT"
export XDG_RUNTIME_DIR=/tmp/edex-rt-$UID
rm -rf "$XDG_RUNTIME_DIR"; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
unset DISPLAY WAYLAND_DISPLAY
export XDG_CURRENT_DESKTOP=ubuntu:GNOME XDG_SESSION_TYPE=wayland XDG_SESSION_DESKTOP=ubuntu

EXT=~/.local/share/gnome-shell/extensions
mkdir -p "$EXT" ~/.local/bin
# EXT_MODE=system tests the installed package; otherwise this checkout.
rm -rf "${EXT:?}/edex-tron@mtv29.github.io" "${EXT:?}/shell-harness@edex-tron.test"
cp -r "$HERE/shell-harness@edex-tron.test" "$EXT/"
if [ "${EXT_MODE:-source}" != system ]; then
  cp -r "$LINUX/extension/edex-tron@mtv29.github.io" "$EXT/"
  glib-compile-schemas "$EXT/edex-tron@mtv29.github.io/schemas"
  ln -sf "$LINUX/bin/edex-tron" ~/.local/bin/edex-tron
  export PATH=~/.local/bin:$PATH
  export GSETTINGS_SCHEMA_DIR="$EXT/edex-tron@mtv29.github.io/schemas"
else
  rm -f ~/.local/bin/edex-tron
fi

MONITOR_ARGS=""
for m in ${MONITORS:-1920x1080}; do MONITOR_ARGS="$MONITOR_ARGS --virtual-monitor $m"; done
export OUT SCENARIO MODE EXT_MODE MONITOR_ARGS RELEASE_TGZ
dbus-run-session -- bash -c '
  if [ "${EXT_MODE:-source}" = system ]; then
    gsettings set org.gnome.shell enabled-extensions "[\"shell-harness@edex-tron.test\"]"
  else
    gsettings set org.gnome.shell enabled-extensions "[\"edex-tron@mtv29.github.io\", \"shell-harness@edex-tron.test\"]"
  fi
  gsettings set org.gnome.shell disable-user-extensions false
  gsettings set org.gnome.shell welcome-dialog-last-shown-version "999"
  gnome-shell --headless --wayland --no-x11 $MONITOR_ARGS --mode=$MODE \
      --wayland-display edex-shell > "$OUT/shell.log" 2>&1 &
  SP=$!
  export WAYLAND_DISPLAY=edex-shell
  call_bus() { gdbus call --session --dest io.github.mtv29.EdexTronTest \
      --object-path /io/github/mtv29/EdexTronTest --method io.github.mtv29.EdexTronTest.$1 "${@:2}"; }
  for i in $(seq 60); do call_bus Windows >/dev/null 2>&1 && break; sleep 0.5; done
  shot() { call_bus Shot "$OUT/$1.png" >/dev/null && echo "shot $1"; }
  windows() { call_bus Windows | sed -e "s/^(\x27//" -e "s/\x27,)$//" | python3 -m json.tool --compact | python3 -c "
import json,sys; d=json.load(sys.stdin)
print(\"monitors\", d[\"monitors\"], \"workarea\", d[\"workarea\"], \"ui fx\", d[\"uiGroupEffects\"], \"glow\", d[\"glow\"])
for w in d[\"windows\"]: print(\"  \", w)
print(\"  stack:\", d[\"stack\"])"; }
  call() { call_bus Call "$1"; }
  overview() { call_bus Overview "$1" >/dev/null; }
  export -f call_bus shot windows call overview
  timeout 240 bash "$SCENARIO"
  kill $SP; wait $SP 2>/dev/null
'
grep -E "eDEX|edex|harness|JS ERROR|CRITICAL|Traceback" "$OUT/shell.log" | head -60
