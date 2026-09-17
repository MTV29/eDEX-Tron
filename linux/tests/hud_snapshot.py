"""Render the HUD offscreen and save a PNG per window (used by the test runs).

usage: python3 -m tests.hud_snapshot OUT_DIR [seconds] [--window]
Needs a Wayland display (a headless mutter/gnome-shell is fine).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import gi  # noqa: E402

gi.require_version('Gtk', '4.0')
from gi.repository import GLib, Gtk  # noqa: E402

from edex_tron.hud.app import HudApp  # noqa: E402


def snap(win, path):
    w, h = win.get_width(), win.get_height()
    paintable = Gtk.WidgetPaintable.new(win)
    snapshot = Gtk.Snapshot()
    paintable.snapshot(snapshot, w, h)
    node = snapshot.to_node()
    if node is None:
        print('empty node for', path)
        return
    tex = win.get_renderer().render_texture(node, None)
    tex.save_to_png(path)
    print('saved', path, w, h, flush=True)


def main():
    out = sys.argv[1]
    secs = float(sys.argv[2]) if len(sys.argv) > 2 else 4
    extra = sys.argv[3:]
    os.makedirs(out, exist_ok=True)
    app = HudApp()

    def shoot():
        for i, w in enumerate(app.windows):
            snap(w, os.path.join(out, f'hud-{i}.png'))
        app.quit()
        return False

    GLib.timeout_add(int(secs * 1000), shoot)
    return app.run(['hud'] + extra)


if __name__ == '__main__':
    sys.exit(main())
