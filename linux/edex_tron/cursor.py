"""eDEX-Tron cursor theme: drawn with Pillow, written as Xcursor files.

Xcursor format (libXcursor): a "Xcur" header, a table of contents, then one
image chunk per size/frame holding premultiplied ARGB pixels.
"""
import math
import os
import struct

from PIL import Image, ImageDraw, ImageFilter

from .config import rgb

SIZES = (24, 32, 48, 64)
SS = 4                      # supersampling factor
IMAGE_TYPE = 0xfffd0002

# shape -> every name apps may ask for (CSS names, X11 names, legacy hashes)
ALIASES = {
    'default': ['default', 'left_ptr', 'arrow', 'top_left_arrow', 'left_arrow', 'right_ptr'],
    'pointer': ['pointer', 'hand', 'hand1', 'hand2', 'pointing_hand',
                'e29285e634086352946a0e7090d73106', '9d800788f1b08800ae810202380a0822'],
    'text': ['text', 'xterm', 'ibeam', 'vertical-text'],
    'wait': ['wait', 'watch'],
    'progress': ['progress', 'left_ptr_watch', 'half-busy',
                 '00000000000000020006000e7e9ffc3f', '08e8e1c95fe2fc01f976f1e063a24ccd',
                 '3ecb610c1bf2410f44200f48c40d3599'],
    'crosshair': ['crosshair', 'cross', 'tcross', 'cross_reverse', 'diamond_cross', 'cell', 'plus'],
    'move': ['move', 'fleur', 'all-scroll', 'size_all'],
    'ns': ['ns-resize', 'n-resize', 's-resize', 'size_ver', 'sb_v_double_arrow',
           'v_double_arrow', 'row-resize', 'top_side', 'bottom_side',
           '00008160000006810000408080010102'],
    'ew': ['ew-resize', 'e-resize', 'w-resize', 'size_hor', 'sb_h_double_arrow',
           'h_double_arrow', 'col-resize', 'left_side', 'right_side',
           '028006030e0e7ebffc7f7070c0600140'],
    'nwse': ['nwse-resize', 'nw-resize', 'se-resize', 'size_fdiag', 'bd_double_arrow',
             'top_left_corner', 'bottom_right_corner', 'c7088f0f3e6c8088236ef8e1e3e70000'],
    'nesw': ['nesw-resize', 'ne-resize', 'sw-resize', 'size_bdiag', 'fd_double_arrow',
             'top_right_corner', 'bottom_left_corner', 'fcf1c3c7cd4491d801f1e1c78f100000'],
    'not-allowed': ['not-allowed', 'no-drop', 'crossed_circle', 'forbidden', 'circle',
                    'dnd-no-drop', 'dnd-none', '03b6e0fcb3499374a867c041f52298f0'],
    'grab': ['grab', 'openhand', '5aca4d189052212118709018842178c0',
             '9141b49c8149039304290b508d208c40'],
    'grabbing': ['grabbing', 'closedhand', 'dnd-move', '208530c400c041818281048008011002',
                 '4498f0e0c1937ffe01fd06f973665830'],
    'help': ['help', 'question_arrow', 'whats_this', 'left_ptr_help', 'dnd-ask',
             '5c6cd98b3f3ebcb1f9c7f1c204630408', 'd9ce0ab605698f320427677b458ad60b'],
    'copy': ['copy', 'dnd-copy', '1081e37283d90000800003c07f3ef6bf',
             '6407b0e94181790501fd1e167b474872'],
    'alias': ['alias', 'dnd-link', 'link', '3085a0e285430894940527032f8b26df',
              '640fb0e74195791501fd1ed57b41487f'],
    'context-menu': ['context-menu'],
    'zoom-in': ['zoom-in'],
    'zoom-out': ['zoom-out'],
}

ARROW = [(0, 0), (0, 17), (4.2, 13.2), (7.2, 20), (10, 18.8), (7.1, 12.2), (12.6, 12.2)]


class Pen:
    """Draws in a 32-unit design grid at any output size."""

    def __init__(self, size, accent, bg):
        self.size = size
        self.px = size * SS
        self.unit = self.px / 32
        self.accent = rgb(accent)
        self.bg = rgb(bg)
        self.img = Image.new('RGBA', (self.px, self.px), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def pt(self, x, y):
        return (x * self.unit, y * self.unit)

    def w(self, v):
        return max(1, round(v * self.unit))

    def poly(self, points, fill=True, width=1.4):
        pts = [self.pt(*p) for p in points]
        if fill:
            self.d.polygon(pts, fill=self.bg + (235,))
        self.d.line(pts + [pts[0]], fill=self.accent + (255,), width=self.w(width), joint='curve')

    def line(self, a, b, width=1.6, alpha=255):
        self.d.line([self.pt(*a), self.pt(*b)], fill=self.accent + (alpha,), width=self.w(width))

    def circle(self, c, r, width=1.6, fill=False, alpha=255):
        x, y = self.pt(*c)
        rr = r * self.unit
        box = [x - rr, y - rr, x + rr, y + rr]
        if fill:
            self.d.ellipse(box, fill=self.accent + (alpha,))
        else:
            self.d.ellipse(box, fill=self.bg + (200,), outline=self.accent + (alpha,), width=self.w(width))

    def arc(self, c, r, start, end, width=2.2):
        x, y = self.pt(*c)
        rr = r * self.unit
        self.d.arc([x - rr, y - rr, x + rr, y + rr], start, end,
                   fill=self.accent + (255,), width=self.w(width))

    def arrowhead(self, tip, angle, length=4.2, spread=0.62, width=1.6):
        for s in (-spread, spread):
            self.line(tip, (tip[0] - length * math.cos(angle + s), tip[1] - length * math.sin(angle + s)), width)

    def double_arrow(self, a, b):
        ang = math.atan2(b[1] - a[1], b[0] - a[0])
        self.line(a, b, 1.8)
        self.arrowhead(b, ang)
        self.arrowhead(a, ang + math.pi)

    def finish(self):
        """Glow, downsample, return (PIL image, scale)."""
        glow = self.img.split()[3].filter(ImageFilter.GaussianBlur(self.unit * 1.2))
        halo = Image.new('RGBA', self.img.size, self.accent + (0,))
        halo.putalpha(glow.point(lambda v: int(v * 0.45)))
        out = Image.alpha_composite(halo, self.img)
        return out.resize((self.size, self.size), Image.LANCZOS)


def _pointer_arrow(p, dx=0.0, dy=0.0):
    p.poly([(x + 2 + dx, y + 2 + dy) for x, y in ARROW])


def draw(shape, size, accent, bg, frame=0, frames=1):
    """-> (image, hot_x, hot_y) in output pixels."""
    p = Pen(size, accent, bg)
    hot = (2, 2)
    c = (16, 16)
    if shape == 'default':
        _pointer_arrow(p)
    elif shape == 'pointer':
        # targeting reticle: ring, ticks and a centre dot
        p.circle(c, 7.5, 1.6)
        for ang in (0, 90, 180, 270):
            r = math.radians(ang)
            p.line((16 + 5 * math.cos(r), 16 + 5 * math.sin(r)),
                   (16 + 11 * math.cos(r), 16 + 11 * math.sin(r)), 1.6)
        p.circle(c, 1.8, fill=True)
        hot = c
    elif shape == 'text':
        p.line((16, 7), (16, 25), 1.8)
        for y in (7, 25):
            p.line((12.5, y), (19.5, y), 1.6)
        hot = c
    elif shape in ('wait', 'progress'):
        centre = (16, 16) if shape == 'wait' else (22, 22)
        radius = 8 if shape == 'wait' else 5.5
        if shape == 'progress':
            _pointer_arrow(p)
        p.circle(centre, radius, 1.0, alpha=90)
        start = (frame / frames) * 360
        p.arc(centre, radius, start, start + 110, 2.4 if shape == 'wait' else 2.0)
        hot = c if shape == 'wait' else (2, 2)
    elif shape == 'crosshair':
        for a, b in (((16, 5), (16, 13)), ((16, 19), (16, 27)), ((5, 16), (13, 16)), ((19, 16), (27, 16))):
            p.line(a, b, 1.6)
        p.circle(c, 1.2, fill=True)
        hot = c
    elif shape == 'move':
        p.double_arrow((16, 5), (16, 27))
        p.double_arrow((5, 16), (27, 16))
        hot = c
    elif shape == 'ns':
        p.double_arrow((16, 5), (16, 27))
        hot = c
    elif shape == 'ew':
        p.double_arrow((5, 16), (27, 16))
        hot = c
    elif shape == 'nwse':
        p.double_arrow((8, 8), (24, 24))
        hot = c
    elif shape == 'nesw':
        p.double_arrow((24, 8), (8, 24))
        hot = c
    elif shape == 'not-allowed':
        p.circle(c, 9, 2.0)
        p.line((9.8, 22.2), (22.2, 9.8), 2.0)
        hot = c
    elif shape in ('grab', 'grabbing'):
        # corner brackets that close in when grabbing
        k = 4 if shape == 'grab' else 7
        for sx, sy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            x0, y0 = 16 - sx * (12 - k), 16 - sy * (12 - k)
            p.line((x0, y0), (x0 + sx * 5, y0), 1.8)
            p.line((x0, y0), (x0, y0 + sy * 5), 1.8)
        p.circle(c, 2.2 if shape == 'grab' else 3.2, fill=True)
        hot = c
    elif shape == 'help':
        _pointer_arrow(p)
        p.arc((23, 20), 3.2, 180, 90, 1.6)
        p.line((23, 23.2), (23, 25), 1.6)
        p.circle((23, 28), 0.9, fill=True)
    elif shape in ('copy', 'alias', 'context-menu'):
        _pointer_arrow(p)
        if shape == 'copy':
            p.line((20, 25), (28, 25), 1.8)
            p.line((24, 21), (24, 29), 1.8)
        elif shape == 'alias':
            p.arc((23, 26), 4, 180, 360, 1.6)
            p.arrowhead((27, 26), math.pi / 2, 2.4)
        else:
            for i in range(3):
                p.line((19, 20 + i * 3), (28, 20 + i * 3), 1.4)
    elif shape in ('zoom-in', 'zoom-out'):
        p.circle((13, 13), 7, 1.8)
        p.line((18, 18), (26, 26), 2.4)
        p.line((10, 13), (16, 13), 1.6)
        if shape == 'zoom-in':
            p.line((13, 10), (13, 16), 1.6)
        hot = (13, 13)
    else:
        raise ValueError(shape)
    img = p.finish()
    scale = size / 32
    return img, round(hot[0] * scale), round(hot[1] * scale)


def xcursor_bytes(images):
    """images: list of (nominal_size, PIL RGBA image, xhot, yhot, delay_ms)."""
    header = struct.pack('<4sIII', b'Xcur', 16, 0x10000, len(images))
    toc_size = 12 * len(images)
    pos = 16 + toc_size
    toc, chunks = b'', b''
    for nominal, img, xh, yh, delay in images:
        w, h = img.size
        # premultiplied ARGB as little-endian uint32 = bytes B, G, R, A
        raw = img.convert('RGBA').tobytes()
        px = bytearray(len(raw))
        for i in range(0, len(raw), 4):
            r, g, b, a = raw[i:i + 4]
            px[i] = b * a // 255
            px[i + 1] = g * a // 255
            px[i + 2] = r * a // 255
            px[i + 3] = a
        chunk = struct.pack('<IIIIIIIII', 36, IMAGE_TYPE, nominal, 1, w, h, xh, yh, delay) + bytes(px)
        toc += struct.pack('<III', IMAGE_TYPE, nominal, pos)
        chunks += chunk
        pos += len(chunk)
    return header + toc + chunks


def build_theme(dest, accent, bg):
    """Write an Xcursor theme to dest (…/icons/eDEX-Tron)."""
    cursors = os.path.join(dest, 'cursors')
    os.makedirs(cursors, exist_ok=True)
    for shape, names in ALIASES.items():
        animated = shape in ('wait', 'progress')
        frames = 12 if animated else 1
        images = []
        for size in SIZES:
            for f in range(frames):
                img, xh, yh = draw(shape, size, accent, bg, f, frames)
                images.append((size, img, xh, yh, 60 if animated else 0))
        data = xcursor_bytes(images)
        primary = os.path.join(cursors, names[0])
        with open(primary, 'wb') as fh:
            fh.write(data)
        for alias in names[1:]:
            link = os.path.join(cursors, alias)
            if os.path.lexists(link):
                os.remove(link)
            os.symlink(names[0], link)
    with open(os.path.join(dest, 'index.theme'), 'w') as fh:
        fh.write('[Icon Theme]\nName=eDEX-Tron\nComment=eDEX-Tron cursors (generated)\n'
                 'Inherits=Yaru,Adwaita\n')
    with open(os.path.join(dest, 'cursor.theme'), 'w') as fh:
        fh.write('[Icon Theme]\nInherits=eDEX-Tron\n')


def preview(accent, bg, path):
    """Contact sheet of every shape, for the README and tests."""
    shapes = list(ALIASES)
    cell = 72
    sheet = Image.new('RGBA', (cell * len(shapes), cell), rgb(bg) + (255,))
    for i, s in enumerate(shapes):
        img, _, _ = draw(s, 48, accent, bg, 2, 12)
        sheet.alpha_composite(img, (i * cell + 12, 12))
    sheet.save(path)
