"""Check the layout planner over a spread of screens and panel combinations.

Layout bugs are the ones that cost the most time on this project, because
Rainmeter reports nothing when two skins land on top of each other -- you just
get panels drawn over panels. This asserts the two properties that matter:

  * no two panels that are switched on overlap
  * every panel that is switched on is inside the work area

Run it after touching gen_rainmeter_ini.py:

    python src\\dev\\test_plan.py
"""
import itertools
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                os.pardir, 'tools'))

import gen_rainmeter_ini as g               # noqa: E402

# Screens to try: the 16:9 and 16:10 sizes people actually run, as *logical*
# pixels after DPI scaling, with a taskbar's worth taken off the height.
SCREENS = [
    (1280, 625), (1366, 713), (1440, 765), (1536, 825), (1600, 850),
    (1680, 900), (1920, 1032), (2048, 1080), (2560, 1392), (3440, 1392),
    # deliberately cramped, to exercise the drop paths
    (1024, 500), (1280, 480),
]


def rects(p, drives=1):
    """Every switched-on panel as (name, x, y, w, h) in logical pixels."""
    heights = dict(g.H)
    heights['Disk'] = g.DISK_BASE + g.DISK_ROW * max(1, drives)
    hidden = set(p['hidden'])
    out = []
    for name, (x, y) in p['positions'].items():
        if name in hidden:
            continue
        if name == 'Terminal':
            w, h = p['term_w'], p['term_h'] + g.TERM_CHROME
        elif name == 'Dock':
            w, h = g.grid_w(p['dock_cols']), g.grid_h(p['dock_rows'])
        elif name == 'Folder':
            w, h = g.grid_w(p['folder_cols']), g.grid_h(p['folder_rows'])
        elif name == 'Desktop':
            w, h = g.grid_w(p['desk_cols']), g.grid_h(p['desk_rows'])
        else:
            w, h = g.PANEL_W, heights[name]
        out.append((name, x, y, w, h))
    return out


def overlaps(a, b):
    _, ax, ay, aw, ah = a
    _, bx, by, bw, bh = b
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah


def main():
    combos = []
    for n in range(len(g.OPTIONAL) + 1):
        combos += list(itertools.combinations(g.OPTIONAL, n))
    offs = [(), ('TopList',), ('ConnInfo',), ('Clock',),
            ('Clock', 'CpuInfo'), g.RIGHT_STACK]

    checked = failures = 0
    for (w, h), panels, off, dock_n, desk_n, folder_n, drives in itertools.product(
            SCREENS, combos, offs, (1, 12, 30), (0, 40), (0, 13), (1, 4)):
        p = g.plan(w, h, dock_n, desk_n, folder_n, panels, drives, off)
        r = rects(p, drives)
        where = (f'{w}x{h} panels={",".join(panels) or "-"} '
                 f'off={",".join(off) or "-"} dock={dock_n} desk={desk_n} '
                 f'folder={folder_n} drives={drives}')
        checked += 1

        for a, b in itertools.combinations(r, 2):
            if overlaps(a, b):
                print(f'OVERLAP  {a[0]} x {b[0]}  {where}\n'
                      f'         {a}\n         {b}')
                failures += 1

        for name, x, y, pw, ph in r:
            # The icon grids are sized in whole cells, so the last column can
            # reach a few pixels past the panel's own right edge; allow for it.
            slack = 4 if name in ('Dock', 'Folder', 'Desktop') else 0
            if x < 0 or y < 0 or x + pw > w + slack or y + ph > h + slack:
                print(f'OFFSCREEN {name} at {x},{y} {pw}x{ph}  {where}')
                failures += 1

    print(f'{checked} layouts checked, {failures} problem(s)')
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
