"""Building blocks: eDEX-style panel frames, graphs, bars and dot maps."""
import gi

gi.require_version('Gtk', '4.0')
gi.require_version('Gdk', '4.0')
gi.require_version('Graphene', '1.0')
from gi.repository import Gdk, Graphene, Gtk  # noqa: E402


try:
    gi.require_version('GioUnix', '2.0')
    from gi.repository import GioUnix  # noqa: E402
    DesktopAppInfo = GioUnix.DesktopAppInfo
except (ValueError, ImportError):
    from gi.repository import Gio  # noqa: E402
    DesktopAppInfo = Gio.DesktopAppInfo


def rgba(hex_colour, alpha=1.0):
    c = Gdk.RGBA()
    c.parse(hex_colour)
    c.alpha = alpha
    return c


class Theme:
    """Colours the drawing code needs; set once by the app."""
    accent = rgba('#aacfd1')
    dim = rgba('#aacfd1', 0.35)
    faint = rgba('#aacfd1', 0.12)
    bg = rgba('#05080d')

    @classmethod
    def set(cls, palette):
        cls.accent = rgba(palette['accent'])
        cls.dim = rgba(palette['accent'], 0.35)
        cls.faint = rgba(palette['accent'], 0.12)
        cls.bg = rgba(palette['bg'])


def label(text='', css=None, xalign=0.0, ellipsize=True, **kw):
    w = Gtk.Label(label=text, xalign=xalign, **kw)
    if ellipsize:
        from gi.repository import Pango
        w.set_ellipsize(Pango.EllipsizeMode.END)
    for c in (css or '').split():
        w.add_css_class(c)
    return w


class Panel(Gtk.Box):
    """A module: caption row (NAME ........ right) over a body, with the
    little corner ticks eDEX draws on its frames."""

    def __init__(self, title, right='', right_action=None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.add_css_class('panel')
        head = Gtk.Box(spacing=6)
        head.add_css_class('panel-head')
        self.title = label(title.upper(), 'panel-title', hexpand=True)
        head.append(self.title)
        if right_action:
            self.right = Gtk.Button(label=right)
            self.right.add_css_class('panel-action')
            self.right.connect('clicked', lambda *_: right_action())
        else:
            self.right = label(right, 'panel-right', xalign=1.0)
        head.append(self.right)
        self.append(head)
        self.body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.body.set_vexpand(True)
        self.append(self.body)
        # panels keep their natural height unless a layout asks otherwise
        self.set_vexpand(False)

    def set_right(self, text):
        self.right.set_label(text)

    def add(self, widget):
        self.body.append(widget)
        return widget

    def do_snapshot(self, snapshot):
        Gtk.Box.do_snapshot(self, snapshot)
        w, h = self.get_width(), self.get_height()
        if w < 8 or h < 8:
            return
        c, arm = Theme.accent, 6
        # top edge: full hairline, heavier ticks at both ends
        snapshot.append_color(Theme.dim, Graphene.Rect().init(0, 0, w, 1))
        for x in (0, w - arm):
            snapshot.append_color(c, Graphene.Rect().init(x, 0, arm, 2))
        snapshot.append_color(c, Graphene.Rect().init(0, 0, 1, arm))
        snapshot.append_color(c, Graphene.Rect().init(w - 1, 0, 1, arm))
        # bottom corners only
        snapshot.append_color(c, Graphene.Rect().init(0, h - 1, arm, 1))
        snapshot.append_color(c, Graphene.Rect().init(w - arm, h - 1, arm, 1))


class Graph(Gtk.DrawingArea):
    """Scrolling line graph. series: list of (history deque-like list, alpha)."""

    def __init__(self, length=60, height=60, maximum=100.0, autoscale=False):
        super().__init__()
        self.set_content_height(height)
        self.set_hexpand(True)
        self.length = length
        self.maximum = maximum
        self.autoscale = autoscale
        self.series = []
        self.set_draw_func(self._draw)

    def set_series(self, series):
        self.series = series
        self.queue_draw()

    def _draw(self, _area, cr, w, h):
        a = Theme.accent
        # grid
        cr.set_line_width(1)
        cr.set_source_rgba(a.red, a.green, a.blue, 0.10)
        for i in range(1, 4):
            y = int(h * i / 4) + 0.5
            cr.move_to(0, y)
            cr.line_to(w, y)
        for i in range(1, 6):
            x = int(w * i / 6) + 0.5
            cr.move_to(x, 0)
            cr.line_to(x, h)
        cr.stroke()
        peak = self.maximum
        if self.autoscale:
            peak = max([max(s, default=0) for s, _ in self.series] + [1e-9]) * 1.15
        step = w / max(1, self.length - 1)
        for values, alpha in self.series:
            vals = list(values)[-self.length:]
            if len(vals) < 2:
                continue
            x0 = w - step * (len(vals) - 1)
            cr.set_source_rgba(a.red, a.green, a.blue, alpha)
            cr.set_line_width(1.2)
            for i, v in enumerate(vals):
                y = h - 1 - (min(v, peak) / peak) * (h - 2)
                (cr.move_to if i == 0 else cr.line_to)(x0 + i * step, y)
            cr.stroke_preserve()
            cr.line_to(w, h)
            cr.line_to(x0, h)
            cr.close_path()
            cr.set_source_rgba(a.red, a.green, a.blue, alpha * 0.12)
            cr.fill()


class Bar(Gtk.DrawingArea):
    """Thin segmented usage bar, like eDEX's disk and swap meters."""

    def __init__(self, height=6):
        super().__init__()
        self.set_content_height(height)
        self.set_hexpand(True)
        self.value = 0.0
        self.set_draw_func(self._draw)

    def set_value(self, fraction):
        self.value = max(0.0, min(1.0, fraction))
        self.queue_draw()

    def _draw(self, _area, cr, w, h):
        a = Theme.accent
        seg, gap = 4, 2
        n = max(1, int((w + gap) // (seg + gap)))
        lit = round(n * self.value)
        for i in range(n):
            cr.set_source_rgba(a.red, a.green, a.blue, 0.9 if i < lit else 0.15)
            cr.rectangle(i * (seg + gap), 0, seg, h)
            cr.fill()


class DotMap(Gtk.DrawingArea):
    """eDEX's memory map: a field of dots, bright = active, dim = cached/free."""

    def __init__(self, rows=6):
        super().__init__()
        self.rows = rows
        self.set_content_height(rows * 9)
        self.set_hexpand(True)
        self.parts = (0.0, 0.0)  # (used, cached) fractions
        self.set_draw_func(self._draw)

    def set_parts(self, used, cached):
        self.parts = (used, cached)
        self.queue_draw()

    def _draw(self, _area, cr, w, h):
        a = Theme.accent
        pitch = h / self.rows
        cols = max(1, int(w // pitch))
        total = cols * self.rows
        used = round(total * self.parts[0])
        cached = round(total * self.parts[1])
        r = pitch * 0.22
        for i in range(total):
            col, row = i % cols, i // cols
            if i < used:
                alpha = 1.0
            elif i < used + cached:
                alpha = 0.45
            else:
                alpha = 0.12
            cr.set_source_rgba(a.red, a.green, a.blue, alpha)
            cr.arc(col * pitch + pitch / 2, row * pitch + pitch / 2, r, 0, 6.2832)
            cr.fill()


class KeyValue(Gtk.Grid):
    """Rows of small caption over value, eDEX's "TYPE / linux" style."""

    def __init__(self, keys):
        super().__init__(column_spacing=14, row_spacing=0)
        self.values = {}
        for i, k in enumerate(keys):
            self.attach(label(k.upper(), 'kv-key', ellipsize=False), i, 0, 1, 1)
            v = label('--', 'kv-value')
            v.set_hexpand(True)
            self.attach(v, i, 1, 1, 1)
            self.values[k] = v

    def set(self, key, text):
        self.values[key].set_label(str(text))

