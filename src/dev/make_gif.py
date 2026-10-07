"""Assemble captured frames into an animated GIF.

Pillow is already a dependency (make_wallpaper.py uses it), and it is the only
thing here that can write a real animated GIF -- System.Drawing's encoder
writes the first frame and stops.

GIF is 256 colours, and the HUD is almost entirely one accent on a near-black
background, so an adaptive palette costs nothing and dithering only adds noise
to flat panels. Both are set deliberately rather than left to the default.

    python src/dev/make_gif.py runtime/frames-*.png --out docs/hud.gif
"""
import argparse
import glob
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit('Pillow is needed: pip install --user Pillow')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('frames', nargs='+', help='frame images, or a glob')
    ap.add_argument('--out', default='runtime/demo.gif')
    ap.add_argument('--ms', type=int, default=450, help='milliseconds per frame')
    ap.add_argument('--width', type=int, default=0,
                    help='scale down to this width (0 keeps the original)')
    ap.add_argument('--colors', type=int, default=128,
                    help='palette size; fewer makes a much smaller file')
    ap.add_argument('--bounce', action='store_true',
                    help='play forwards then backwards, so the loop has no jump')
    a = ap.parse_args()

    paths = []
    for pattern in a.frames:
        hits = sorted(glob.glob(pattern))
        paths.extend(hits if hits else [pattern])
    if not paths:
        sys.exit('no frames matched')

    frames = []
    for p in paths:
        im = Image.open(p).convert('RGB')
        if a.width and im.width != a.width:
            h = round(im.height * a.width / im.width)
            im = im.resize((a.width, h), Image.LANCZOS)
        # One adaptive palette per frame keeps the accent clean; without it the
        # default web palette turns the faint grid into banding.
        frames.append(im.quantize(colors=a.colors, method=Image.MEDIANCUT))

    if a.bounce and len(frames) > 2:
        frames = frames + frames[-2:0:-1]

    out = a.out
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=a.ms, loop=0, optimize=True, disposal=2)

    size = os.path.getsize(out)
    print('%s  %d frames  %dx%d  %.1f MB'
          % (out, len(frames), frames[0].width, frames[0].height, size / 1048576))
    if size > 10 * 1048576:
        print('  (GitHub will not inline a GIF much over 10MB -- try --width or --colors)')


if __name__ == '__main__':
    main()
