"""Generate the eDEX-tron desktop wallpaper.

Reproduces eDEX-UI's backdrop geometry from its own CSS: a grid of
`light_black` squares (1.85vh) on a `grey` field in 2.04vh cells, then layers
the HUD furniture -- corner ticks, column guides, radar rings, scanlines.
Everything is expressed in vh so it rescales to any resolution.
"""
import argparse, json, math, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
def _font(name, fallback):
    # eDEX-UI's fonts when setup extracted them; otherwise Windows' own.
    p = os.path.join(ROOT, 'build', 'ttf', name)
    return p if os.path.exists(p) else os.path.join(
        os.environ.get('SystemRoot', r'C:\Windows'), 'Fonts', fallback)


FONT_MED   = _font('united_sans_medium.ttf', 'bahnschrift.ttf')
FONT_LIGHT = _font('united_sans_light.ttf', 'bahnschrift.ttf')
FONT_MONO  = _font('fira_mono.ttf', 'consola.ttf')


def hex2rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def load_theme(path):
    with open(path) as f:
        t = json.load(f)
    c = t['colors']
    return {
        'accent': (c['r'], c['g'], c['b']),
        'black': hex2rgb(c['black']),
        'light_black': hex2rgb(c['light_black']),
        'grey': hex2rgb(c['grey']),
    }


def draw_grid(img, th, vh):
    """eDEX main.css: light_black squares on a grey field, 2.04vh cells."""
    cell = 2.04 * vh
    square = 1.85 * vh
    gap = cell - square                      # the visible grey rule (~2px @1080p)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, img.width, img.height], fill=th['grey'])
    y = 0.0
    while y < img.height + cell:
        x = 0.0
        while x < img.width + cell:
            d.rectangle([x + gap, y + gap, x + gap + square, y + gap + square],
                        fill=th['light_black'])
            x += cell
        y += cell


def draw_radar(img, th, vh, scale):
    """Faint concentric rings + graticule, echoing eDEX's globe module."""
    ov = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    cx, cy = img.width / 2, img.height * 0.52
    r_max = img.height * 0.42
    a = th['accent']

    for i in range(1, 8):
        r = r_max * i / 7
        alpha = int(58 - i * 4.0)
        d.ellipse([cx - r, cy - r, cx + r, cy + r],
                  outline=a + (max(alpha, 16),), width=max(1, int(0.09 * vh)))
    # graticule spokes
    for deg in range(0, 360, 15):
        rad = math.radians(deg)
        major = deg % 45 == 0
        r0 = r_max * (0.12 if major else 0.55)
        d.line([cx + r0 * math.cos(rad), cy + r0 * math.sin(rad),
                cx + r_max * math.cos(rad), cy + r_max * math.sin(rad)],
               fill=a + (34 if major else 18,), width=max(1, int(0.09 * vh)))
    # ranging ticks around the outer ring
    for deg in range(0, 360, 5):
        rad = math.radians(deg)
        r0, r1 = r_max, r_max + 0.9 * vh
        d.line([cx + r0 * math.cos(rad), cy + r0 * math.sin(rad),
                cx + r1 * math.cos(rad), cy + r1 * math.sin(rad)],
               fill=a + (46,), width=max(1, int(0.09 * vh)))
    img.alpha_composite(ov)


def tick_frame(d, box, th, vh, alpha=70, arm=2.2):
    """eDEX's signature corner ticks: an L of two short rules at each corner."""
    x0, y0, x1, y1 = box
    a = th['accent'] + (alpha,)
    w = max(1, int(0.13 * vh))
    L = arm * vh
    for (cx, cy, sx, sy) in ((x0, y0, 1, 1), (x1, y0, -1, 1),
                             (x0, y1, 1, -1), (x1, y1, -1, -1)):
        d.line([cx, cy, cx + sx * L, cy], fill=a, width=w)
        d.line([cx, cy, cx, cy + sy * L], fill=a, width=w)


def draw_hud(img, th, vh):
    ov = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    a = th['accent']
    W, H = img.size
    m = 3.2 * vh                                   # outer margin

    tick_frame(d, (m, m, W - m, H - m), th, vh, alpha=140, arm=3.0)

    # eDEX column guides: side panels occupy the outer 17% of the width
    for x in (W * 0.17, W * (1 - 0.17)):
        d.line([x, m + 5 * vh, x, H - m - 5 * vh], fill=a + (30,),
               width=max(1, int(0.09 * vh)))

    # header / footer rules with inboard ticks, as in section > h3.title
    for y in (m + 4.2 * vh, H - m - 4.2 * vh):
        d.line([W * 0.17, y, W * (1 - 0.17), y], fill=a + (72,),
               width=max(1, int(0.09 * vh)))
        for x in (W * 0.17, W * (1 - 0.17)):
            d.line([x, y - 0.8 * vh, x, y + 0.8 * vh], fill=a + (95,),
                   width=max(1, int(0.09 * vh)))

    try:
        f_title = ImageFont.truetype(FONT_MED, int(2.6 * vh))
        f_small = ImageFont.truetype(FONT_LIGHT, int(1.25 * vh))
        f_mono = ImageFont.truetype(FONT_MONO, int(1.15 * vh))
    except OSError:
        f_title = f_small = f_mono = ImageFont.load_default()

    # Centred rather than tucked into the top-left corner: the side columns and
    # the desktop icons both live there, so anything in that corner ends up
    # hidden behind them. Alphas are lifted to read clearly against the grid.
    cx = W / 2
    d.text((cx, m + 0.9 * vh), "eDEX  //  SYSTEM ACTIVE",
           font=f_title, fill=a + (225,), anchor='mt')
    d.text((cx, m + 4.9 * vh), "TRON  ·  DESKTOP ENVIRONMENT",
           font=f_small, fill=a + (140,), anchor='mt')

    footer = "SHELL: CMD   ·   THEME: TRON   ·   RENDER: OK"
    d.text((cx, H - m - 3.4 * vh), footer, font=f_mono, fill=a + (130,), anchor='mt')

    img.alpha_composite(ov)


def draw_scanlines(img, vh):
    ov = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    step = max(2, int(0.28 * vh))
    for y in range(0, img.height, step):
        d.line([0, y, img.width, y], fill=(0, 0, 0, 26), width=1)
    img.alpha_composite(ov)


def draw_vignette(img, th):
    W, H = img.size
    # build small and upscale -- a cheap, perfectly smooth radial falloff
    small = Image.new('L', (64, 36), 0)
    sd = ImageDraw.Draw(small)
    sd.ellipse([-14, -8, 78, 44], fill=255)
    mask = small.resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(W / 40))
    shade = Image.new('RGBA', (W, H), th['black'] + (100,))
    inv = Image.eval(mask, lambda v: 255 - v)
    shade.putalpha(inv)
    img.alpha_composite(shade)


def load_config(path):
    """theme.json in the project root: the one place colours are chosen."""
    try:
        with open(path, encoding='utf-8-sig') as f:
            return json.load(f)
    except OSError:
        return {}


def build(width, height, theme, out, ss=2, config=None):
    th = load_theme(theme)
    cfg = config or {}
    if cfg.get('accent'):
        th['accent'] = hex2rgb(cfg['accent'])
    if cfg.get('background'):
        th['light_black'] = hex2rgb(cfg['background'])
    W, H = width * ss, height * ss
    vh = H / 100.0
    img = Image.new('RGBA', (W, H), th['light_black'] + (255,))
    if cfg.get('grid', False):
        draw_grid(img, th, vh)
    draw_radar(img, th, vh, ss)
    draw_vignette(img, th)
    draw_hud(img, th, vh)
    draw_scanlines(img, vh)
    img = img.convert('RGB').resize((width, height), Image.LANCZOS)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out, 'PNG')
    # Windows transcodes JPEG desktop backgrounds more reliably than PNG, so
    # ship both and let the installer prefer the JPEG.
    jpg = os.path.splitext(out)[0] + '.jpg'
    img.save(jpg, 'JPEG', quality=95, subsampling=0)
    print(f'wallpaper {width}x{height} -> {out}\n                    -> {jpg}')


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--width', type=int, default=1920)
    p.add_argument('--height', type=int, default=1080)
    p.add_argument('--theme', default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
        'themes', 'edex', 'tron.json'))  # bundled; no eDEX-UI install needed
    p.add_argument('--out', default=os.path.join(ROOT, 'assets', 'wallpaper', 'edex-tron-1920x1080.png'))
    p.add_argument('--config', default=os.path.join(ROOT, 'theme.json'))
    a = p.parse_args()
    build(a.width, a.height, a.theme, a.out, config=load_config(a.config))
