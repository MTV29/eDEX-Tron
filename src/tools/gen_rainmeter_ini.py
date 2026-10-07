"""Plan the eDEX-Tron layout for the actual screen and emit Rainmeter.ini.

The arrangement follows eDEX-UI's home screen: a column of system panels down
each side, the shell in the middle, and a bottom band holding the folder
browser, the shortcut dock and the Desktop grid. Nothing is positioned by hand
any more -- `plan()` stacks the panels from their known heights so the layout
fits whatever screen it is given.

The pieces depend on each other, which is why they are planned together:
the dock's width (and so how many rows it wraps to) decides where the Desktop
grid starts; the dock's height decides how much room is left for the
folder grid and therefore how tall the shell can be.

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
    'ConnInfo': 76,
    'Ports': 121,
    'Gpu': 74,
    # Disk grows with the drive count; see DISK_BASE / DISK_ROW.
    # Power grows with how many readings the machine can answer; see
    # POWER_BASE / POWER_ROW.
}
GRID_CELL = 66               # gen_dock: icon 40 + gap 26
GRID_ROW = 68                # gen_dock: icon 40 + label 28
GRID_BASE = 111              # gen_dock: height of a one-row grid
TERM_FRAME_TOP = 25          # Terminal skin: caption + rule above the frame
TERM_CHROME = 29             # Terminal skin height = frame height + this
MIN_TERM_H = 120 + TERM_CHROME   # the shell never gets squeezed below this

# Optional panels, in the order they claim space: the last one listed is the
# first to go when the screen cannot hold them all. Which ones are *wanted* is
# theme.json "panels"; this decides which of those actually fit.
OPTIONAL = ('Gpu', 'Power', 'Disk', 'Ports')
# The two fixed columns, top to bottom. Any of these can be switched off
# (theme.json "off"), and the space it was using is given back to the rest.
LEFT_STACK = ('Clock', 'CpuInfo')
RIGHT_STACK = ('NetStat', 'RamWatcher', 'ConnInfo', 'TopList')
DISK_BASE = 22               # gen_skins disk(): caption block
DISK_ROW = 26                # gen_skins disk(): one drive's row
# Power rows are the same mono lines the Gpu and Ports panels use, so these
# two reproduce those exactly: 3 rows is 74 like Gpu, 5 rows is 121 like
# Ports. A laptop answers five (battery, time left, system, cpu, gpu); a
# desktop with no meter answers two or three, and should not reserve the
# difference as blank space.
POWER_BASE = 4
POWER_ROW = 23.5

INTERACTIVE = {'Terminal', 'Dock', 'Desktop', 'Folder', 'NetStat'}
DOCK_SHARE = 0.60            # the dock may take this much of the bottom band


def grid_w(cols):
    return cols * GRID_CELL + 2


def grid_h(rows):
    return GRID_BASE + (rows - 1) * GRID_ROW


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def plan(screen_w, work_h, dock_n, desk_n, folder_n=0, panels=(), drives=1,
         off=(), power_rows=5):
    """Work out where every panel goes on a screen of this size.

    Planned from the bottom up, because the bottom is where your own content
    is: the dock holds apps you chose and the grids hold your files, so they
    get their space first and the system panels fit into what is left. On a
    screen too short for all of them, panels are dropped from the end of each
    column (the process list before the memory map, the CPU panel before the
    clock) rather than drawn on top of each other.
    """
    left_x = MARGIN
    right_x = screen_w - PANEL_W - MARGIN
    band_l = left_x + PANEL_W + GUTTER
    band_r = right_x - GUTTER
    pos = {}
    hidden = []
    no_room = []

    heights = dict(H)
    heights['Disk'] = DISK_BASE + DISK_ROW * max(1, drives)
    heights['Power'] = int(POWER_BASE + POWER_ROW * max(1, power_rows))
    off = set(off)

    def stack_h(names):
        """Height of a column of panels, including the gaps between them."""
        return sum(heights[n] for n in names) + GAP * max(0, len(names) - 1)

    # --- dock, at the bottom. It wraps to more rows as it gets longer, but a
    # tall dock would climb into the shell, so it is widened first: a wide
    # single row beats a square block in the middle of the screen. Only once
    # it spans the whole band does it start stacking.
    bottom_w = band_r - left_x
    dock_n = max(1, dock_n)
    cols_pref = max(1, (int(bottom_w * DOCK_SHARE) - 2) // GRID_CELL)
    cols_max = max(1, (bottom_w - 2) // GRID_CELL)
    dock_budget = work_h - BOTTOM_PAD - (TOP + MIN_TERM_H + GAP)
    dock_cols = min(cols_pref, dock_n)
    dock_rows = math.ceil(dock_n / dock_cols)
    while grid_h(dock_rows) > dock_budget and dock_cols < cols_max:
        dock_cols = min(cols_max, dock_cols + 1)
        dock_rows = math.ceil(dock_n / dock_cols)
    dock_w, dock_h = grid_w(dock_cols), grid_h(dock_rows)
    dock_y = work_h - dock_h - BOTTOM_PAD
    pos['Dock'] = (left_x, dock_y)

    # --- the band above the dock, holding the folder panel (an icon grid of
    # one folder, e.g. your games) on the left and the Desktop grid beside it
    lb_w = max(dock_w, 380)
    folder_cols = max(1, (lb_w - 2) // GRID_CELL)
    folder_want = math.ceil(max(1, folder_n) / folder_cols)
    band_top = max(TOP + MIN_TERM_H + GAP,
                   min(dock_y, dock_y - GAP - grid_h(min(folder_want, 3))))
    # On a short screen the grid may not fit between the shell and the dock;
    # drop the panel rather than let it overlap.
    folder_fit = (dock_y - GAP - band_top - GRID_BASE) // GRID_ROW + 1
    if folder_fit < 1:
        hidden.append('Folder')
    folder_rows = clamp(min(folder_want, folder_fit), 1, 6)
    pos['Folder'] = (left_x, band_top)

    # --- left column, into the height above the band. The dock can be taller
    # than the band, so the column has to clear whichever starts higher.
    left_cap = min(band_top, dock_y) - GAP - TOP
    left_req = [n for n in LEFT_STACK if n not in off]
    while left_req and stack_h(left_req) > left_cap:
        no_room.append(left_req.pop())
    y = TOP
    for name in left_req:
        pos[name] = (left_x, y)
        y += heights[name] + GAP
    left_bottom = max(TOP, y - GAP)

    # --- right column. Nothing sits below or beside it, so it has the full
    # height; everything in it is a fixed size now.
    avail = work_h - TOP - BOTTOM_PAD
    right_req = [n for n in RIGHT_STACK if n not in off]
    while right_req and stack_h(right_req) > avail:
        no_room.append(right_req.pop())

    # --- fit the optional panels into whatever the two columns have spare
    left_room = left_cap - stack_h(left_req) - (GAP if left_req else 0)
    right_room = avail - stack_h(right_req) - (GAP if right_req else 0)

    col = {'left': [], 'right': []}
    for name in [n for n in OPTIONAL if n in panels and n not in off]:
        need = heights[name] + GAP
        # Prefer the roomier column, so one tall panel cannot strand the rest.
        order = ['left', 'right'] if left_room >= right_room else ['right', 'left']
        for side in order:
            if (left_room if side == 'left' else right_room) >= need:
                col[side].append(name)
                if side == 'left':
                    left_room -= need
                else:
                    right_room -= need
                break
        else:
            no_room.append(name)

    # Belt and braces: give up the lowest-priority extra rather than letting
    # the column run off the bottom of the screen.
    while col['right'] and stack_h(right_req + col['right']) > avail:
        no_room.append(col['right'].pop())

    y = TOP
    for name in right_req + col['right']:
        pos[name] = (right_x, y)
        y += heights[name] + GAP

    y = left_bottom + GAP
    for name in col['left']:
        pos[name] = (left_x, y)
        y += heights[name] + GAP

    # Panels that are off still need a position, in case they are switched on
    # by hand from Rainmeter's own menu.
    for name in OPTIONAL + RIGHT_STACK:
        pos.setdefault(name, (right_x, TOP))
    for name in LEFT_STACK:
        pos.setdefault(name, (left_x, TOP))

    # --- Desktop grid fills the rest of the band
    grid_x = left_x + lb_w + GUTTER
    desk_cols = max(1, (band_r - grid_x - 2) // GRID_CELL)
    desk_rows = max(1, (work_h - BOTTOM_PAD - band_top - GRID_BASE) // GRID_ROW + 1)
    pos['Desktop'] = (grid_x, band_top)

    # --- shell fills the gap between the columns, down to the band
    term_w = band_r - band_l
    term_h = max(MIN_TERM_H - TERM_CHROME, band_top - GAP - TOP - TERM_CHROME)
    pos['Terminal'] = (band_l, TOP)

    return {
        'screen_w': screen_w, 'work_h': work_h,
        'positions': pos,
        'term_w': term_w, 'term_h': term_h,
        'term_rect': [band_l + 1, TOP + TERM_FRAME_TOP + 1, term_w - 2, term_h - 2],
        'folder_cols': folder_cols, 'folder_rows': folder_rows,
        'dock_cols': dock_cols, 'dock_rows': dock_rows,
        'desk_cols': desk_cols, 'desk_rows': desk_rows,
        # Everything switched off: the ones you did not ask for, the ones you
        # switched off by hand, and the ones that did not fit. 'no_room' is
        # that last group on its own, so settings.ps1 can say why.
        'hidden': sorted(set(hidden) | off | set(no_room)
                         | {n for n in OPTIONAL if n not in panels}),
        'no_room': no_room,
        'shown': [n for n in OPTIONAL
                  if n in panels and n not in no_room and n not in off],
    }


# Every skin the config lists. A panel the planner positions but that is
# missing here is simply never written out: it has a place on screen and no
# entry telling Rainmeter to load it, and the only symptom is that it does
# not appear. Keep this in step with OPTIONAL.
ORDER = ['Clock', 'CpuInfo', 'NetStat', 'RamWatcher', 'ConnInfo', 'TopList',
         'Disk', 'Ports', 'Gpu', 'Power',
         'Terminal', 'Folder', 'Dock', 'Desktop']

# Catch the next one at import rather than on someone's desktop.
assert not set(OPTIONAL) - set(ORDER), ('optional panels missing from ORDER: ' + ', '.join(sorted(set(OPTIONAL) - set(ORDER))))


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
    ap.add_argument('--folder-count', type=int, default=10,
                    help='items in the folder panel (theme.json "folder")')
    ap.add_argument('--panels', default='',
                    help='optional panels to switch on, comma separated: '
                         + ', '.join(n.lower() for n in OPTIONAL))
    ap.add_argument('--drive-count', type=int, default=1,
                    help='fixed drives the Disk panel lists')
    ap.add_argument('--power-rows', type=int, default=5,
                    help='readings the Power panel can fill: 5 on a laptop, '
                         'fewer on a desktop with no battery')
    ap.add_argument('--off', default='',
                    help='side panels to switch off and reclaim the space of: '
                         + ', '.join(n.lower() for n in LEFT_STACK + RIGHT_STACK))
    ap.add_argument('--root', default='eDEX-Tron')
    ap.add_argument('--disable', default='')
    a = ap.parse_args()

    # accept any capitalisation: theme.json says "disk", the skin is "Disk"
    def names(arg, allowed):
        by_lower = {n.lower(): n for n in allowed}
        return [by_lower[s] for s in
                (t.strip().lower() for t in arg.split(',') if t.strip())
                if s in by_lower]

    p = plan(a.screen_w, a.work_h, a.dock_count, a.desk_count, a.folder_count,
             names(a.panels, OPTIONAL), a.drive_count,
             names(a.off, LEFT_STACK + RIGHT_STACK), a.power_rows)

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
          f"folder {p['folder_cols']}x{p['folder_rows']}, "
          f"dock {p['dock_cols']}x{p['dock_rows']}, desktop {p['desk_cols']}x{p['desk_rows']}"
          f"{'  extras: ' + ', '.join(p['shown']) if p['shown'] else ''}"
          f"{'  NO ROOM: ' + ', '.join(p['no_room']) if p['no_room'] else ''}")
