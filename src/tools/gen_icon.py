"""Render the eDEX-Tron launcher icon: a filament globe in the theme's blue.

The look is a dense shell of glowing threads over a dark sphere, with a bright
core and a little HUD furniture -- the same language as the wallpaper and
panels, at icon scale.

Everything accumulates into a float intensity buffer (so overlapping strokes
add, the way light does) and is only mapped to colour at the end. Drawing it
with normal alpha compositing gives flat, muddy overlaps instead.
"""
import argparse, json, math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def load_accent(path):
    with open(path) as f:
        c = json.load(f)['colors']
    return (c['r'], c['g'], c['b'])


def saturated(rgb):
    """Strip the grey out of a colour and scale it back up to full brightness."""
    lo = min(rgb)
    c = [max(0.0, v - 0.75 * lo) for v in rgb]
    top = max(c) or 1.0
    return tuple(int(v / top * 255) for v in c)


def density(x, y, z):
    """Smooth pseudo-random field over the sphere, for continent-like clumps."""
    return (np.sin(3.1 * x + 0.7) * np.cos(2.3 * y - 0.4)
            + np.sin(4.7 * z + 1.9) * np.cos(3.7 * x + 2.2)
            + 0.6 * np.sin(7.3 * y + 0.3) * np.cos(6.1 * z - 1.1)
            + 0.4 * np.sin(11.0 * x - 2.0) * np.cos(9.0 * y + 0.8))


def splat(buf, xs, ys, w):
    """Additive point deposit with bilinear spread, clipped to the buffer."""
    n = buf.shape[0]
    x0 = np.floor(xs).astype(np.int64)
    y0 = np.floor(ys).astype(np.int64)
    fx, fy = xs - x0, ys - y0
    for dx, dy, wt in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)),
                       (0, 1, (1 - fx) * fy),       (1, 1, fx * fy)):
        xi, yi = x0 + dx, y0 + dy
        ok = (xi >= 0) & (xi < n) & (yi >= 0) & (yi < n)
        np.add.at(buf, (yi[ok], xi[ok]), (w * wt)[ok])


def globe(n, seed=7):
    """Accumulate the sphere's filaments into an intensity buffer."""
    rng = np.random.default_rng(seed)
    buf = np.zeros((n, n), dtype=np.float32)
    cx = cy = n / 2.0
    R = n * 0.345

    # --- surface points, clumped by the density field
    m = 900_000
    v = rng.normal(size=(3, m))
    v /= np.linalg.norm(v, axis=0)
    x, y, z = v
    d = density(x, y, z)
    keep = d > np.quantile(d, 0.55)          # only the "land"
    x, y, z, d = x[keep], y[keep], z[keep], d[keep]

    front = z > -0.15                         # a sliver past the limb reads as rim light
    x, y, z, d = x[front], y[front], z[front], d[front]

    depth = np.clip((z + 0.15) / 1.15, 0, 1)
    # limb brightening: light piles up where the surface turns away
    limb = 1.0 + 1.9 * np.clip(1.0 - depth, 0, 1) ** 2
    # np.ptp(d), not d.ptp() -- the ndarray method was removed in NumPy 2.
    w = (0.055 + 0.5 * (d - d.min()) / (np.ptp(d) + 1e-6)) * (0.25 + 0.75 * depth) * limb
    splat(buf, cx + x * R, cy - y * R, w.astype(np.float32))

    # --- threads: short great-circle walks, which give the streaky filaments
    starts = rng.integers(0, x.size, size=2600)
    px, py, pz = x[starts], y[starts], z[starts]
    tx, ty, tz = rng.normal(size=(3, starts.size))
    # project the step direction onto the tangent plane
    dot = px * tx + py * ty + pz * tz
    tx, ty, tz = tx - dot * px, ty - dot * py, tz - dot * pz
    ln = np.sqrt(tx * tx + ty * ty + tz * tz) + 1e-9
    tx, ty, tz = tx / ln, ty / ln, tz / ln
    step = 0.008
    for i in range(70):
        px, py, pz = px + tx * step, py + ty * step, pz + tz * step
        ln = np.sqrt(px * px + py * py + pz * pz)
        px, py, pz = px / ln, py / ln, pz / ln
        vis = pz > -0.1
        if not vis.any():
            break
        fade = (1.0 - i / 70.0) * 0.5
        splat(buf, cx + px[vis] * R, cy - py[vis] * R,
              np.full(vis.sum(), fade, dtype=np.float32))

    # --- core: the bright knot at the centre of the reference
    k = 90_000
    ang = rng.uniform(0, 2 * math.pi, k)
    rad = np.abs(rng.normal(0, 0.16, k)) * R
    splat(buf, cx + np.cos(ang) * rad, cy - np.sin(ang) * rad,
          np.full(k, 0.05, dtype=np.float32))

    # --- radial spokes bursting out of the core
    for _ in range(26):
        a = rng.uniform(0, 2 * math.pi)
        t = np.linspace(0.08, rng.uniform(0.6, 1.02), 300)
        jitter = rng.normal(0, 0.006, t.size)
        splat(buf, cx + np.cos(a + jitter) * t * R, cy - np.sin(a + jitter) * t * R,
              (0.5 * (1 - t / t.max())).astype(np.float32))

    return buf


def colourise(buf, accent, radius_frac=0.345):
    """Map intensity to a blue ramp over a dark sphere body.

    Normalising on a low percentile clips almost everything to the top of the
    ramp and the globe comes out solid white. Normalise on the true peak and
    push midtones *down* (gamma > 1) so only the filaments and core light up,
    the way the reference reads: dark body, bright threads.
    """
    n = buf.shape[0]
    # The buffer spans a huge range: filament pixels sit around 0.5-2.5 while
    # the core reaches ~60. Linear normalisation on a high percentile buries
    # the filaments at ~0.03 and the globe renders as a black disc. Compress
    # logarithmically, anchored so the median filament lands in the mid ramp.
    nz = buf[buf > 0]
    floor = np.percentile(nz, 50) + 1e-9
    ceil = np.percentile(nz, 99.9) + 1e-9
    b = np.clip(np.log1p(buf / floor) / np.log1p(ceil / floor), 0, 1)

    glow = np.asarray(Image.fromarray((b * 255).astype(np.uint8))
                      .filter(ImageFilter.GaussianBlur(n / 70)),
                      dtype=np.float32) / 255.0
    lit = np.clip(b + glow * 0.55, 0, 1)

    ar, ag, ab = accent
    # The dark end of the ramp is a saturated version of the accent, so the
    # icon keeps its depth in any theme colour, not just the tron blue.
    deep = saturated(accent)
    def k(f):
        return tuple(int(c * f) for c in deep)
    white = tuple(int(c + (255 - c) * 0.9) for c in accent)
    stops = [(0.00, (0, 0, 0)),
             (0.10, k(0.05)),                           # near-black body
             (0.30, k(0.30)),
             (0.55, k(0.62)),
             (0.78, tuple((a + b) // 2 for a, b in zip(k(0.95), accent))),
             (0.92, (ar, ag, ab)),                      # theme accent
             (1.00, white)]                             # white-hot core
    xs = np.array([s[0] for s in stops])
    cols = np.array([s[1] for s in stops], dtype=np.float32)
    rgb = np.stack([np.interp(lit, xs, cols[:, i]) for i in range(3)], axis=-1)

    # The globe body is opaque even where it is dark; outside it, only the glow
    # carries alpha, so the icon still sits on any background.
    yy, xx = np.mgrid[0:n, 0:n]
    r = np.sqrt((xx - n / 2.0) ** 2 + (yy - n / 2.0) ** 2) / (n * radius_frac)
    disc = np.clip((1.02 - r) / 0.03, 0, 1)
    alpha = np.clip(np.maximum(disc, np.clip(lit * 2.2, 0, 1)), 0, 1)

    rgb = np.maximum(rgb, disc[..., None] * np.array(k(0.07), dtype=np.float32))
    out = np.concatenate([rgb, (alpha * 255)[..., None]], axis=-1)
    return Image.fromarray(out.astype(np.uint8), 'RGBA')


def furniture(img, accent):
    """Corner brackets and a ranging ring -- the HUD frame around the globe."""
    n = img.size[0]
    ov = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    a = accent
    m = int(n * 0.055)
    arm, wdt = int(n * 0.17), max(2, n // 150)

    for (px, py, sx, sy) in ((m, m, 1, 1), (n - m, m, -1, 1),
                             (m, n - m, 1, -1), (n - m, n - m, -1, -1)):
        d.line([px, py, px + sx * arm, py], fill=a + (200,), width=wdt)
        d.line([px, py, px, py + sy * arm], fill=a + (200,), width=wdt)

    # segmented bar, top left
    bx, by = m + int(n * 0.02), m - int(n * 0.022)
    for i in range(5):
        x0 = bx + i * int(n * 0.045)
        d.rectangle([x0, by, x0 + int(n * 0.032), by + max(2, n // 190)],
                    fill=a + (150 - i * 22,))

    # ranging ring, bottom right
    rr = int(n * 0.052)
    rc = (n - m - rr - int(n * 0.01), n - m - rr - int(n * 0.01))
    d.ellipse([rc[0] - rr, rc[1] - rr, rc[0] + rr, rc[1] + rr],
              outline=a + (170,), width=max(2, n // 200))
    for deg in range(0, 360, 30):
        t = math.radians(deg)
        d.line([rc[0] + rr * 0.62 * math.cos(t), rc[1] + rr * 0.62 * math.sin(t),
                rc[0] + rr * 0.96 * math.cos(t), rc[1] + rr * 0.96 * math.sin(t)],
               fill=a + (140,), width=max(1, n // 260))

    img.alpha_composite(ov)


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--out', default='assets/icon')
    p.add_argument('--theme', default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
        'themes', 'edex', 'tron.json'))  # bundled; no eDEX-UI install needed
    p.add_argument('--size', type=int, default=1024, help='render size before downsampling')
    p.add_argument('--config', default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'theme.json'))
    a = p.parse_args()

    accent = load_accent(a.theme)
    try:
        with open(a.config, encoding='utf-8-sig') as f:
            cfg = json.load(f)
        # 'icon' lets the launcher keep its own colour; it falls back to accent
        h = (cfg.get('icon') or cfg.get('accent') or '').lstrip('#')
        if len(h) == 6:
            accent = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    except OSError:
        pass
    img = colourise(globe(a.size), accent)
    furniture(img, accent)

    os.makedirs(a.out, exist_ok=True)
    png = os.path.join(a.out, 'edex-tron.png')
    img.resize((512, 512), Image.LANCZOS).save(png)

    ico = os.path.join(a.out, 'edex-tron.ico')
    sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
    img.resize((256, 256), Image.LANCZOS).save(ico, format='ICO', sizes=sizes)
    print(f'icon -> {png}\n     -> {ico} ({len(sizes)} sizes)')
