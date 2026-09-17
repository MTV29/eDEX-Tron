"""eDEX-Tron HUD: one window per monitor, laid out like eDEX-UI's home screen.

Under GNOME the companion Shell extension launches this process and keeps its
windows on the desktop layer, behind everything else. Each window's title
carries its monitor's origin ("eDEX-Tron HUD @x,y") so the extension knows
where to put it. Run with --window to get an ordinary window instead (useful
on other desktops and for testing).
"""
import sys

import gi

gi.require_version('Gtk', '4.0')
gi.require_version('Gdk', '4.0')
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402

from .. import APP_ID  # noqa: E402
from ..config import (DOCK_FILE, THEME_FILE, load_settings, load_theme,  # noqa: E402
                      palette, seed_user_files)
from . import style  # noqa: E402
from .dock import Dock  # noqa: E402
from .files import Desktop, Filesystem  # noqa: E402
from .panels import (Clock, Cpu, Disks, JournalTail, Memory, NetworkGraph,  # noqa: E402
                     NetworkStatus, Ports, Processes, System)
from .terminal import Shell  # noqa: E402
from .widgets import Theme  # noqa: E402

TITLE = 'eDEX-Tron HUD'


def column(width, *panels, spacing=8):
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=spacing)
    for p in panels:
        box.append(p)
    # A Box hands out natural widths before sharing the spare space, so long
    # labels would widen a side column. A non-scrolling ScrolledWindow reports
    # only its minimum width, which pins the column to `width`.
    clamp = Gtk.ScrolledWindow(hexpand=False, vexpand=True)
    clamp.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.NEVER)
    clamp.set_size_request(width, -1)
    clamp.set_child(box)
    return clamp


class HudWindow(Gtk.ApplicationWindow):
    def __init__(self, app, monitor, primary, windowed):
        super().__init__(application=app)
        self.app = app
        self.panels = []
        self.shell = None
        geo = monitor.get_geometry()
        self.monitor = monitor
        self.add_css_class('edex-hud')
        if windowed:
            self.add_css_class('opaque')
            self.set_title('eDEX-Tron')
            w, h = min(geo.width, 1600), min(geo.height - 80, 960)
        else:
            self.set_title(f'{TITLE} @{geo.x},{geo.y}')
            self.set_decorated(False)
            w, h = geo.width, geo.height
        self.set_default_size(w, h)
        self.scale = max(0.8, min(1.5, h / 1080))
        side = int(max(280, min(460, w * 0.21)))
        gap = int(10 * self.scale)

        root = Gtk.Box(spacing=gap)
        for m in ('top', 'bottom', 'start', 'end'):
            getattr(root, f'set_margin_{m}')(gap)
        self.set_child(root)

        if primary:
            self._primary_layout(root, side, h, gap)
        else:
            self._secondary_layout(root, side, gap)

        self.connect('notify::is-active', self._on_active)

    def _add(self, panel):
        self.panels.append(panel)
        return panel

    def _primary_layout(self, root, side, h, gap):
        a = self._add
        procs = a(Processes())
        procs.set_vexpand(True)
        left = column(side,
                      a(Clock()), a(System()), a(Cpu()), a(Memory()), procs,
                      spacing=gap)
        s = self.app.settings
        self.shell = a(Shell(self.app.palette, s['terminal_font'], self._cwd_changed))
        self.shell.set_vexpand(True)
        self.files = a(Filesystem(self.shell))
        desk = a(Desktop())
        bottom = Gtk.Box(spacing=gap, homogeneous=True)
        bottom.set_size_request(-1, int(h * 0.30))
        bottom.append(self.files)
        bottom.append(desk)
        centre = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=gap, hexpand=True)
        centre.append(self.shell)
        centre.append(bottom)
        ports = a(Ports())
        ports.set_vexpand(True)
        right = column(side,
                       a(NetworkStatus()), a(NetworkGraph()), ports, a(Disks()),
                       a(Dock(self.app.edit_dock)),
                       spacing=gap)
        for w in (left, centre, right):
            root.append(w)

    def _secondary_layout(self, root, side, gap):
        a = self._add
        mem = a(Memory())
        left = column(side, a(Clock()), a(Cpu()), mem, spacing=gap)
        log = a(JournalTail())
        log.set_hexpand(True)
        log.set_vexpand(True)
        disks = a(Disks())
        disks.set_vexpand(True)
        right = column(side, a(NetworkGraph()), disks, spacing=gap)
        for w in (left, log, right):
            root.append(w)

    def _cwd_changed(self, path):
        self.files.show(path)

    def _on_active(self, *_):
        if self.is_active() and self.shell:
            self.shell.focus()

    def tick(self):
        for p in self.panels:
            try:
                p.tick()
            except Exception as e:  # noqa: BLE001 - one panel must not stop the rest
                print(f'hud: {type(p).__name__} failed: {e!r}', file=sys.stderr, flush=True)

    def apply_palette(self, p):
        if self.shell:
            self.shell.apply_palette(p)
        self.queue_draw()
        _redraw(self)


def _redraw(widget):
    child = widget.get_first_child()
    while child:
        child.queue_draw()
        _redraw(child)
        child = child.get_next_sibling()


class HudApp(Gtk.Application):
    def __init__(self):
        # NON_UNIQUE: when the extension restarts the HUD, the old process may
        # still be shutting down; a unique app would hand over to it and exit.
        super().__init__(application_id=APP_ID + '.Hud',
                         flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE
                         | Gio.ApplicationFlags.NON_UNIQUE)
        self.add_main_option('window', ord('w'), GLib.OptionFlags.NONE,
                             GLib.OptionArg.NONE, 'Run in an ordinary window', None)
        self.add_main_option('primary-only', ord('p'), GLib.OptionFlags.NONE,
                             GLib.OptionArg.NONE, 'Only use the primary monitor', None)
        self.add_main_option('primary', 0, GLib.OptionFlags.NONE,
                             GLib.OptionArg.STRING, 'Origin of the primary monitor', 'X,Y')
        self.windows = []
        self.primary_origin = None
        self.windowed = False
        self.primary_only = False
        self.provider = None
        self.settings = None
        self.palette = None

    # --- lifecycle ------------------------------------------------------------
    def do_command_line(self, cmdline):
        opts = cmdline.get_options_dict().end().unpack()
        if not self.windows:
            self.windowed = bool(opts.get('window'))
            self.primary_only = bool(opts.get('primary-only'))
            if opts.get('primary'):
                try:
                    self.primary_origin = tuple(int(v) for v in opts['primary'].split(','))
                except ValueError:
                    pass
            self.start()
        else:
            self.focus_terminal()
        return 0

    def do_startup(self):
        Gtk.Application.do_startup(self)
        seed_user_files()
        for name, fn in (('focus-terminal', self.focus_terminal),
                         ('reload-theme', self.reload_theme),
                         ('quit', self.quit)):
            act = Gio.SimpleAction.new(name, None)
            act.connect('activate', lambda *_a, f=fn: f())
            self.add_action(act)
        # stay running with no windows while monitors are being replugged
        self.hold()

    def start(self):
        self.settings = load_settings()
        self.palette = palette(load_theme())
        Theme.set(self.palette)
        self.fonts = style.pick_fonts()
        self.provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), self.provider,
            Gtk.STYLE_PROVIDER_PRIORITY_USER + 10)
        settings = Gtk.Settings.get_default()
        settings.set_property('gtk-application-prefer-dark-theme', True)

        self.build_windows()
        monitors = Gdk.Display.get_default().get_monitors()
        monitors.connect('items-changed', lambda *_: GLib.timeout_add(800, self._rebuild))
        GLib.timeout_add(1000, self.tick)

        self.theme_monitor = Gio.File.new_for_path(THEME_FILE).monitor_file(Gio.FileMonitorFlags.NONE, None)
        self.theme_monitor.connect('changed', lambda *_: GLib.timeout_add(400, self._reload_once))

    def build_windows(self):
        for w in self.windows:
            w.destroy()
        self.windows = []
        display = Gdk.Display.get_default()
        monitors = [display.get_monitors().get_item(i)
                    for i in range(display.get_monitors().get_n_items())]
        if not monitors:
            return
        primary = _primary_monitor(monitors, self.primary_origin)
        wanted = [primary] if (self.windowed or self.primary_only
                               or not self.settings.get('secondary_monitors', True)) else monitors
        scale = 1.0
        for m in wanted:
            win = HudWindow(self, m, m is primary, self.windowed)
            if m is primary:
                scale = win.scale
            self.windows.append(win)
        self.provider.load_from_string(style.css(self.palette, self.fonts, scale))
        for w in self.windows:
            w.present()
        self.tick()

    def _rebuild(self):
        self.build_windows()
        return False

    def tick(self):
        for w in self.windows:
            try:
                w.tick()
            except Exception as e:  # noqa: BLE001 - keep the HUD alive
                print(f'hud: tick failed: {e!r}', file=sys.stderr, flush=True)
        return True

    # --- actions --------------------------------------------------------------
    def focus_terminal(self):
        for w in self.windows:
            if w.shell:
                w.present()
                w.shell.focus()

    def _reload_once(self):
        self.reload_theme()
        return False

    def reload_theme(self):
        self.palette = palette(load_theme())
        Theme.set(self.palette)
        scale = self.windows[0].scale if self.windows else 1.0
        self.provider.load_from_string(style.css(self.palette, self.fonts, scale))
        for w in self.windows:
            w.apply_palette(self.palette)

    def edit_dock(self):
        f = Gio.File.new_for_path(DOCK_FILE)
        app = Gio.AppInfo.get_default_for_type('text/plain', False)
        try:
            if app:
                app.launch([f], None)
            else:
                Gio.AppInfo.launch_default_for_uri(f.get_uri(), None)
        except GLib.Error as e:
            print(f'hud: cannot open dock.txt: {e.message}', file=sys.stderr)


def _primary_monitor(monitors, origin=None):
    # GTK has no "primary" flag on Wayland: the extension passes the primary
    # monitor's origin; without it, a monitor at 0,0 is the best guess.
    for m in monitors:
        g = m.get_geometry()
        if origin and (g.x, g.y) == origin:
            return m
    for m in monitors:
        g = m.get_geometry()
        if g.x == 0 and g.y == 0:
            return m
    return monitors[0]


def main(argv=None):
    app = HudApp()
    return app.run(argv if argv is not None else sys.argv)


if __name__ == '__main__':
    sys.exit(main())
