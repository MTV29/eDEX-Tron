"""File browser (follows the shell) and the Desktop panel (mirrors ~/Desktop)."""
import os

from gi.repository import Gio, GLib, Gtk, Pango

from .panels import human_bytes
from .widgets import Bar, DesktopAppInfo, Panel, label

MAX_ITEMS = 200


def open_path(path, widget=None):
    uri = Gio.File.new_for_path(path).get_uri()
    launcher = Gtk.FileLauncher.new(Gio.File.new_for_path(path))
    try:
        launcher.launch(widget.get_root() if widget else None, None, None, None)
    except (TypeError, GLib.Error):
        Gio.AppInfo.launch_default_for_uri(uri, None)


class FileGrid(Gtk.ScrolledWindow):
    """Icon grid of one folder, refreshed when the folder changes."""

    def __init__(self, on_activate, icon_size=32, show_parent=False):
        super().__init__(vexpand=True, hexpand=True)
        self.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE,
                                homogeneous=True, max_children_per_line=30,
                                min_children_per_line=3, row_spacing=2, column_spacing=2)
        self.flow.set_valign(Gtk.Align.START)
        self.set_child(self.flow)
        self.on_activate = on_activate
        self.icon_size = icon_size
        self.show_parent = show_parent
        self.show_hidden = False
        self.path = None
        self.monitor = None
        self._pending = 0

    def load(self, path):
        if path != self.path:
            self.path = path
            if self.monitor:
                self.monitor.cancel()
            try:
                self.monitor = Gio.File.new_for_path(path).monitor_directory(
                    Gio.FileMonitorFlags.WATCH_MOVES, None)
                self.monitor.connect('changed', self._changed)
            except GLib.Error:
                self.monitor = None
        self._fill()

    def _changed(self, *_):
        # debounce bursts (a download writes many events)
        if self._pending:
            GLib.source_remove(self._pending)
        self._pending = GLib.timeout_add(400, self._refill)

    def _refill(self):
        self._pending = 0
        self._fill()
        return False

    def _fill(self):
        child = self.flow.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self.flow.remove(child)
            child = nxt
        entries = []
        try:
            d = Gio.File.new_for_path(self.path)
            en = d.enumerate_children(
                'standard::name,standard::display-name,standard::icon,'
                'standard::type,standard::is-hidden,standard::is-backup,'
                'thumbnail::path', Gio.FileQueryInfoFlags.NONE, None)
            for info in en:
                if not self.show_hidden and (info.get_is_hidden() or info.get_is_backup()):
                    continue
                entries.append(info)
        except GLib.Error as e:
            self.flow.append(label(f'CANNOT READ: {e.message}', 'dim'))
            return
        entries.sort(key=lambda i: (i.get_file_type() != Gio.FileType.DIRECTORY,
                                    i.get_display_name().lower()))
        if self.show_parent and self.path != '/':
            self._tile('..', Gio.ThemedIcon.new('go-up-symbolic'),
                       os.path.dirname(self.path.rstrip('/')) or '/', True, None)
        for info in entries[:MAX_ITEMS]:
            full = os.path.join(self.path, info.get_name())
            is_dir = info.get_file_type() == Gio.FileType.DIRECTORY
            thumb = info.get_attribute_byte_string('thumbnail::path')
            self._tile(info.get_display_name(), info.get_icon(), full, is_dir, thumb)
        if len(entries) > MAX_ITEMS:
            self.flow.append(label(f'+{len(entries) - MAX_ITEMS} MORE', 'dim'))

    def _tile(self, name, icon, full, is_dir, thumb):
        btn = Gtk.Button()
        btn.add_css_class('tile')
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        if thumb and os.path.exists(thumb):
            img = Gtk.Image.new_from_file(thumb)
        else:
            img = Gtk.Image.new_from_gicon(icon) if icon else Gtk.Image.new_from_icon_name('text-x-generic')
        img.set_pixel_size(self.icon_size)
        lab = Gtk.Label(label=name)
        lab.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        lab.set_max_width_chars(10)
        lab.set_width_chars(8)
        box.append(img)
        box.append(lab)
        btn.set_child(box)
        btn.set_tooltip_text(full)
        btn.connect('clicked', lambda *_: self.on_activate(full, is_dir, btn))
        self.flow.append(btn)


class Filesystem(Panel):
    """eDEX's filesystem display: the shell's current folder."""

    def __init__(self, shell):
        super().__init__('Filesystem', '[ HIDDEN ]', right_action=self.toggle_hidden)
        self.shell = shell
        self.path_label = self.add(label('~', 'kv-value'))
        self.path_label.set_ellipsize(Pango.EllipsizeMode.START)
        self.grid = self.add(FileGrid(self._activate, icon_size=28, show_parent=True))
        row = Gtk.Box(spacing=8)
        self.usage = Bar()
        self.usage.set_valign(Gtk.Align.CENTER)
        self.usage_text = label('', 'kv-key', xalign=1.0, ellipsize=False)
        row.append(label('MOUNT', 'kv-key', ellipsize=False))
        row.append(self.usage)
        row.append(self.usage_text)
        self.add(row)
        self.show(os.path.expanduser('~'))

    def show(self, path):
        self.path_label.set_label(path.replace(os.path.expanduser('~'), '~', 1))
        self.grid.load(path)
        try:
            st = os.statvfs(path)
            total = st.f_blocks * st.f_frsize
            free = st.f_bavail * st.f_frsize
            self.usage.set_value(1 - free / total if total else 0)
            self.usage_text.set_label(f'{human_bytes(free)} FREE')
        except OSError:
            self.usage.set_value(0)

    def toggle_hidden(self):
        self.grid.show_hidden = not self.grid.show_hidden
        self.set_right('[ HIDE ]' if self.grid.show_hidden else '[ HIDDEN ]')
        self.grid.load(self.grid.path)

    def _activate(self, path, is_dir, widget):
        if is_dir:
            self.shell.cd(path)          # the browser follows via the cwd poll
        else:
            open_path(path, widget)

    def tick(self):
        pass


def desktop_dir():
    d = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DESKTOP)
    return d or os.path.expanduser('~/Desktop')


def _trusted_launcher(path):
    """Same rule as Ubuntu's desktop icons: a .desktop file only runs once
    it is executable and marked "Allow Launching" (metadata::trusted), so a
    downloaded launcher can't run something just because it was clicked."""
    if not os.access(path, os.X_OK):
        return False
    try:
        info = Gio.File.new_for_path(path).query_info(
            'metadata::trusted', Gio.FileQueryInfoFlags.NONE, None)
    except GLib.Error:
        return False
    return info.get_attribute_as_string('metadata::trusted') == 'true'


class Desktop(Panel):
    """Everything in the Desktop folder; the real desktop icons are hidden
    while the theme is on."""

    def __init__(self):
        super().__init__('Desktop', '[ OPEN ]', right_action=lambda: open_path(desktop_dir(), self))
        self.grid = self.add(FileGrid(self._activate, icon_size=36))
        path = desktop_dir()
        os.makedirs(path, exist_ok=True)
        self.grid.load(path)

    def _activate(self, path, is_dir, widget):
        if path.endswith('.desktop') and not is_dir and _trusted_launcher(path):
            try:
                app = DesktopAppInfo.new_from_filename(path)
            except (TypeError, GLib.Error):
                app = None
            if app:
                app.launch([], None)
                return
        open_path(path, widget)

    def tick(self):
        pass
