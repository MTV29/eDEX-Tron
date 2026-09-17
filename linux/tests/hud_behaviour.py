"""HUD behaviour checks on a real (headless) Wayland display.

usage: python3 tests/hud_behaviour.py OUT_DIR
Needs WAYLAND_DISPLAY (a headless mutter is enough). Uses a throwaway HOME.
"""
import json
import os
import shutil
import sys
import tempfile

HOME = tempfile.mkdtemp(prefix='edex-hud-home-')
os.makedirs(os.path.join(HOME, 'Desktop'))
os.environ.update(HOME=HOME, XDG_CONFIG_HOME=f'{HOME}/.config', XDG_DATA_HOME=f'{HOME}/.local/share',
                  XDG_STATE_HOME=f'{HOME}/.local/state', SHELL='/bin/bash',
                  XDG_DESKTOP_DIR=f'{HOME}/Desktop')
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import gi  # noqa: E402

gi.require_version('Gtk', '4.0')
from gi.repository import GLib, Gtk  # noqa: E402

from edex_tron import config  # noqa: E402
from edex_tron.hud.app import HudApp  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hud_snapshot import snap  # noqa: E402

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
results = []


def check(name, ok, detail=''):
    results.append((name, bool(ok)))
    print(f'{"PASS" if ok else "FAIL"} {name} {detail}', flush=True)


def tile_names(flow):
    names = []
    child = flow.get_first_child()
    while child:
        btn = child.get_child()
        if isinstance(btn, Gtk.Button):
            box = btn.get_child()
            names.append(box.get_last_child().get_label())
        child = child.get_next_sibling()
    return names


def steps(app):
    win = app.windows[0]
    shell, files = win.shell, win.files
    desk = next(p for p in win.panels if type(p).__name__ == 'Desktop')
    dock = next(p for p in win.panels if type(p).__name__ == 'Dock')

    yield 3000
    check('terminal started', shell.current().pid)
    check('file browser shows home', files.grid.path == HOME, files.grid.path)

    os.makedirs(os.path.join(HOME, 'projects', 'demo'))
    shell.cd(os.path.join(HOME, 'projects'))
    yield 2500
    check('browser follows cd', files.grid.path == os.path.join(HOME, 'projects'), files.grid.path)
    check('browser lists folder', 'demo' in tile_names(files.grid.flow), tile_names(files.grid.flow))

    # clicking a folder tile cds the shell there
    files._activate(os.path.join(HOME, 'projects', 'demo'), True, files)
    yield 2500
    check('click folder -> cd', shell.current().cwd() == os.path.join(HOME, 'projects', 'demo'),
          shell.current().cwd())

    shell.new_tab()
    yield 1500
    check('second tab', len(shell.terms) == 2 and shell.current() is shell.terms[1])
    check('new tab starts in same folder', shell.current().cwd() == os.path.join(HOME, 'projects', 'demo'),
          shell.current().cwd())
    shell.current().feed_child(b'exit\r')
    yield 1500
    check('tab closes on exit', len(shell.terms) == 1)

    with open(os.path.join(HOME, 'Desktop', 'notes.txt'), 'w') as f:
        f.write('hi')
    yield 1500
    check('desktop panel updates', 'notes.txt' in tile_names(desk.grid.flow), tile_names(desk.grid.flow))

    with open(config.DOCK_FILE, 'w') as f:
        f.write('Home | ~\nTmp | /tmp\n')
    yield 1500
    check('dock rebuilds on save', tile_names(dock.flow) == ['HOME', 'TMP'], tile_names(dock.flow))

    snap(win, os.path.join(OUT, 'hud-before-recolour.png'))
    theme = config.load_theme()
    theme['accent'] = '#ff4f9d'
    config.save_theme(theme)
    yield 2000
    check('live recolour', app.palette['accent'] == '#ff4f9d', app.palette['accent'])
    snap(win, os.path.join(OUT, 'hud-after-recolour.png'))

    # crash-proofing: a panel that throws must not stop the others
    clock = next(p for p in win.panels if type(p).__name__ == 'Clock')
    before = clock.time.get_label()
    cpu = next(p for p in win.panels if type(p).__name__ == 'Cpu')
    cpu.tick = lambda: 1 / 0
    yield 1500
    check('ticks survive a failing panel', clock.time.get_label() != before)


def main():
    app = HudApp()
    gen = None

    def advance():
        nonlocal gen
        if gen is None:
            gen = steps(app)
        try:
            delay = next(gen)
        except StopIteration:
            app.quit()
            return False
        except Exception as e:  # noqa: BLE001
            check('no exception', False, repr(e))
            app.quit()
            return False
        GLib.timeout_add(delay, advance)
        return False

    GLib.timeout_add(500, advance)
    app.run(['hud', '--window'])
    shutil.rmtree(HOME, ignore_errors=True)
    failed = [n for n, ok in results if not ok]
    print(f'{len(results) - len(failed)}/{len(results)} passed')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
