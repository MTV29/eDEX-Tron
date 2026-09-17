"""Plan the eDEX-Tron layout for the actual screen and emit Rainmeter.ini.

The arrangement follows eDEX-UI's home screen: a column of system panels down
each side, the shell in the middle, and a bottom band holding the filesystem
browser, the shortcut dock and the Desktop grid. Nothing is positioned by hand
any more -- `plan()` stacks the panels from their known heights so the layout
fits whatever screen it is given.

The pieces depend on each other, which is why they are planned together:
the dock's width (and so how many rows it wraps to) decides where the Desktop
grid starts; the dock's height decides how much room is left for the
filesystem list and therefore how tall the shell can be.

Two things worth knowing:

* Rainmeter places skins in *logical* (DPI-scaled) pixels. Every number here
  is logical; pass the logical screen width and work-area height.

* Read-only panels are AlwaysOnTop=-2 ("On Desktop") with ClickThrough=1, so
  the HUD sits at desktop level and never covers or steals focus from apps.
  The panels you click keep their clicks.

Outputs: Rainmeter.ini, @Resources/terminal-pos.txt (for launch_terminal.ps1)
and, with --plan-out, a JSON plan the other generators read their sizes from.
"""
import argparse, json, math, os

PANEL_W = 250
MARGIN = 14
GUTTER = 20
GAP = 10
TOP = 16
BOTTOM_PAD = 6

# Rendered heights in logical px, measured with src/dev/skin_rects.ps1. Panels
# auto-size to their content, so these must track gen_skins / gen_dock.
H = {
    'Clock': 187,
    'CpuInfo': 213,
    'NetStat': 191,
    'RamWatcher': 152,
    'TopList': 135,
}
CONNINFO_FIXED = 72          # ConnInfo height = 72 + 2 * graph height
FS_FIXED, FS_ROW = 54, 16    # FileSystem height = 54 + 16 * rows
GRID_CELL = 66               # gen_dock: icon 40 + gap 26
GRID_ROW = 68                # gen_dock: icon 40 + label 28
GRID_BASE = 111              # gen_dock: height of a one-row grid
TERM_FRAME_TOP = 25          # Terminal skin: caption + rule above the frame
TERM_CHROME = 29             # Terminal skin height = frame height + this

INTERACTIVE = {'Terminal', 'Dock', 'Desktop', 'FileSystem', 'NetStat'}
DOCK_SHARE = 0.60            # the dock may take this much of the bottom band


def grid_w(cols):
    return cols * GRID_CELL + 2


def grid_h(rows):
    return GRID_BASE + (rows - 1) * GRID_ROW


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def plan(screen_w, work_h, dock_n, desk_n):
    left_x = MARGIN
    right_x = screen_w - PANEL_W - MARGIN
    band_l = left_x + PANEL_W + GUTTER
    band_r = right_x - GUTTER
    pos = {}

    # --- left column
    pos['Clock'] = (left_x, TOP)
    pos['CpuInfo'] = (left_x, TOP + H['Clock'] + GAP)
    left_bottom = pos['CpuInfo'][1] + H['CpuInfo']

    # --- right column: the traffic graph absorbs whatever height is spare
    avail = work_h - TOP - BOTTOM_PAD
    fixed = H['NetStat'] + H['RamWatcher'] + H['TopList'] + 3 * GAP + CONNINFO_FIXED
    graph_h = clamp((avail - fixed) // 2, 30, 95)
    y = TOP
    for name, h in (('NetStat', H['NetStat']), ('RamWatcher', H['RamWatcher']),
                    ('ConnInfo', CONNINFO_FIXED + 2 * graph_h), ('TopList', H['TopList'])):
        pos[name] = (right_x, y)
        y += h + GAP

    # --- dock: one row until it would crowd the Desktop grid, then wrap
    bottom_w = band_r - left_x
    dock_n = max(1, dock_n)
    max_cols = max(1, (int(bottom_w * DOCK_SHARE) - 2) // GRID_CELL)
    dock_cols = min(max_cols, dock_n)
    dock_rows = math.ceil(dock_n / dock_cols)
    dock_w, dock_h = grid_w(dock_cols), grid_h(dock_rows)
    dock_y = work_h - dock_h - BOTTOM_PAD
    pos['Dock'] = (left_x, dock_y)

    # --- the band everything below the shell starts at
    lb_w = max(dock_w, 380)
    fs_full = FS_FIXED + 9 * FS_ROW
    band_top = max(left_bottom + GAP, dock_y - GAP - fs_full)
    # On a short screen the list may not fit between the shell and the dock;
    # drop the panel rather than let it overlap.
    fs_fit = (dock_y - GAP - band_top - FS_FIXED) // FS_ROW
    hidden = [] if fs_fit >= 3 else ['FileSystem']
    fs_rows = clamp(fs_fit, 3, 12)
    pos['FileSystem'] = (left_x, band_top)

    # --- Desktop grid fills the rest of the band
    grid_x = left_x + lb_w + GUTTER
    desk_cols = max(1, (band_r - grid_x - 2) // GRID_CELL)
    desk_rows = max(1, (work_h - BOTTOM_PAD - band_top - GRID_BASE) // GRID_ROW + 1)
    pos['Desktop'] = (grid_x, band_top)

    # --- shell fills the gap between the columns, down to the band
    term_w = band_r - band_l
    term_h = max(120, band_top - GAP - TOP - TERM_CHROME)
    pos['Terminal'] = (band_l, TOP)

    return {
        'screen_w': screen_w, 'work_h': work_h,
        'positions': pos,
        'term_w': term_w, 'term_h': term_h,
        'term_rect': [band_l + 1, TOP + TERM_FRAME_TOP + 1, term_w - 2, term_h - 2],
        'fs_w': lb_w, 'fs_rows': fs_rows,
        'graph_h': graph_h,
        'dock_cols': dock_cols, 'dock_rows': dock_rows,
        'desk_cols': desk_cols, 'desk_rows': desk_rows,
        'hidden': hidden,
    }


ORDER = ['Clock', 'CpuInfo', 'NetStat', 'RamWatcher', 'ConnInfo', 'TopList',
         'Terminal', 'FileSystem', 'Dock', 'Desktop']


def build_ini(p, skin_path, root, disable=()):
    out = [f"[Rainmeter]\nSkinPath={skin_path}\nLanguage=1033\nLogging=1\n"
           f"TrayExecuteM=[!About]\nDisableDragging=0\n"]
    for order, name in enumerate(ORDER):
        x, y = p['positions'][name]
        out.append(rf"[{root}\{name}]" "\n"
                   f"Active={0 if name in disable else 1}\n"
                   f"WindowX={x}\n"
                   f"WindowY={y}\n"
                   f"AlwaysOnTop=-2\n"
                   f"Draggable=1\n"
                   f"SnapEdges=1\n"
                   f"ClickThrough={0 if name in INTERACTIVE else 1}\n"
                   f"KeepOnScreen=1\n"
                   f"LoadOrder={order}\n")
    return '\n'.join(out)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--skin-path', required=True)
    ap.add_argument('--out', help='Rainmeter.ini to write (omit to only plan)')
    ap.add_argument('--plan-out', help='write the computed plan as JSON')
    ap.add_argument('--screen-w', type=int, default=1536, help='logical width')
    ap.add_argument('--work-h', type=int, default=825,
                    help='logical height of the work area (screen minus taskbar)')
    ap.add_argument('--dock-count', type=int, default=10)
    ap.add_argument('--desk-count', type=int, default=10)
    ap.add_argument('--root', default='eDEX-Tron')
    ap.add_argument('--disable', default='')
    a = ap.parse_args()

    p = plan(a.screen_w, a.work_h, a.dock_count, a.desk_count)

    if a.plan_out:
        os.makedirs(os.path.dirname(os.path.abspath(a.plan_out)), exist_ok=True)
        with open(a.plan_out, 'w') as f:
            json.dump(p, f, indent=2)

    if a.out:
        disable = {s.strip() for s in a.disable.split(',') if s.strip()}
        disable |= set(p['hidden'])
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        with open(a.out, 'w') as f:
            f.write(build_ini(p, a.skin_path, a.root, disable))
        res = os.path.join(a.skin_path, a.root, '@Resources')
        if os.path.isdir(res):
            with open(os.path.join(res, 'terminal-pos.txt'), 'w') as f:
                f.write(','.join(str(v) for v in p['term_rect']))

    print(f"plan {a.screen_w}x{a.work_h}: terminal {p['term_w']}x{p['term_h']}, "
          f"fs {p['fs_rows']} rows, graph {p['graph_h']}, "
          f"dock {p['dock_cols']}x{p['dock_rows']}, desktop {p['desk_cols']}x{p['desk_rows']}"
          f"{'  hidden: ' + ', '.join(p['hidden']) if p['hidden'] else ''}")
