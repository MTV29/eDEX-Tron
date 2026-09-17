"""The app dock, read from ~/.config/edex-tron/dock.txt.

One entry per line:   Label | target [| icon]

target is one of
  some-app.desktop[,other.desktop]  first installed one wins
  !command args                     run directly (no shell)
  a path or URL                     opened with its default app
icon is an icon name or an image path (optional).
Entries whose app is not installed are skipped.
"""
import os
import shlex

import gi

gi.require_version('Gtk', '4.0')
from gi.repository import Gio, GLib, Gtk, Pango  # noqa: E402

from ..config import DOCK_FILE  # noqa: E402
from .files import open_path  # noqa: E402
from .widgets import DesktopAppInfo, Panel  # noqa: E402


def parse(path=DOCK_FILE):
    entries = []
    try:
        with open(path) as f:
            lines = f.readlines()
    except OSError:
        return entries
    for line in lines:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = [p.strip() for p in line.split('|')]
        if len(parts) < 2 or not parts[0] or not parts[1]:
            continue
        entry = resolve(parts[0], parts[1], parts[2] if len(parts) > 2 else '')
        if entry:
            entries.append(entry)
    return entries


def resolve(name, target, icon):
    """-> dict(name, icon (Gio.Icon), launch callable) or None if missing."""
    gicon = _icon(icon) if icon else None
    if target.startswith('!'):
        argv = shlex.split(target[1:])
        if not argv or not GLib.find_program_in_path(os.path.expanduser(argv[0])):
            return None
        return {'name': name, 'icon': gicon or Gio.ThemedIcon.new('application-x-executable'),
                'launch': lambda _w: GLib.spawn_async(argv, flags=GLib.SpawnFlags.SEARCH_PATH)}
    if target.endswith('.desktop') or ',' in target:
        for desktop_id in (t.strip() for t in target.split(',')):
            try:
                app = DesktopAppInfo.new(desktop_id)
            except TypeError:
                app = None
            if app:
                return {'name': name, 'icon': gicon or app.get_icon(),
                        'launch': lambda _w, a=app: a.launch([], None)}
        return None
    expanded = os.path.expandvars(os.path.expanduser(target))
    if '://' in target or target.startswith(('mailto:', 'settings:')):
        return {'name': name, 'icon': gicon or Gio.ThemedIcon.new('web-browser'),
                'launch': lambda _w: Gio.AppInfo.launch_default_for_uri(target, None)}
    if os.path.exists(expanded):
        if not gicon:
            try:
                gicon = Gio.File.new_for_path(expanded).query_info(
                    'standard::icon', Gio.FileQueryInfoFlags.NONE, None).get_icon()
            except GLib.Error:
                gicon = Gio.ThemedIcon.new('folder')
        return {'name': name, 'icon': gicon,
                'launch': lambda w: open_path(expanded, w)}
    return None


def _icon(spec):
    p = os.path.expanduser(spec)
    if os.path.isabs(p):
        return Gio.FileIcon.new(Gio.File.new_for_path(p)) if os.path.exists(p) else None
    return Gio.ThemedIcon.new(spec)


class Dock(Panel):
    def __init__(self, on_edit):
        super().__init__('Dock', '[ + EDIT ]', right_action=on_edit)
        self.flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, homogeneous=True,
                                max_children_per_line=12, min_children_per_line=4,
                                row_spacing=2, column_spacing=2)
        self.flow.set_valign(Gtk.Align.START)
        self.add(self.flow)
        self.body.set_vexpand(False)
        self.monitor = Gio.File.new_for_path(DOCK_FILE).monitor_file(Gio.FileMonitorFlags.NONE, None)
        self.monitor.connect('changed', self._changed)
        self._pending = 0
        self.reload()

    def _changed(self, *_):
        # editors save in several steps; rebuild once they are done
        if self._pending:
            GLib.source_remove(self._pending)
        self._pending = GLib.timeout_add(300, self._reload_once)

    def _reload_once(self):
        self._pending = 0
        self.reload()
        return False

    def reload(self):
        child = self.flow.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self.flow.remove(child)
            child = nxt
        for e in parse():
            btn = Gtk.Button()
            btn.add_css_class('tile')
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            img = Gtk.Image.new_from_gicon(e['icon'])
            img.set_pixel_size(36)
            lab = Gtk.Label(label=e['name'].upper())
            lab.set_max_width_chars(9)
            lab.set_ellipsize(Pango.EllipsizeMode.END)
            box.append(img)
            box.append(lab)
            btn.set_child(box)
            btn.set_tooltip_text(e['name'])
            btn.connect('clicked', lambda b, f=e['launch']: _safe(f, b))
            self.flow.append(btn)

    def tick(self):
        pass


def _safe(fn, widget):
    try:
        fn(widget)
    except GLib.Error as e:
        print(f'dock: {e.message}', flush=True)
