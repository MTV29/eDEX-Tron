"""edex-tron: set up, switch on/off, recolour and remove the theme."""
import argparse
import sys

from . import VERSION

EFFECT_KEYS = {'scanlines': 'scanlines', 'glow': 'glow', 'tv': 'tv-animation'}


def _effects(args):
    from . import changes
    from .apply import EXT_SCHEMA
    if not args.name:
        for name, key in EFFECT_KEYS.items():
            print(f'{name:<10} {changes.gget(EXT_SCHEMA, key)}')
        print(f'strength   {changes.gget(EXT_SCHEMA, "scanline-strength")}')
        return 0
    if args.name == 'strength':
        value = max(0.0, min(0.6, float(args.state)))
        changes.gset(EXT_SCHEMA, 'scanline-strength', str(value))
        return 0
    if args.state not in ('on', 'off'):
        print('use: edex-tron effects <scanlines|glow|tv> on|off', file=sys.stderr)
        return 2
    changes.gset(EXT_SCHEMA, EFFECT_KEYS[args.name], 'true' if args.state == 'on' else 'false')
    print(f'{args.name} {args.state}')
    return 0


def _theme(args):
    from .apply import apply_theme
    from .config import load_theme, luma, normalise_hex, save_theme, seed_user_files
    seed_user_files()
    t = load_theme()
    if args.reset:
        from .config import DEFAULT_THEME
        t = dict(DEFAULT_THEME)
    changed = False
    for key in ('accent', 'background', 'icon'):
        v = getattr(args, key)
        if v:
            t[key] = normalise_hex(v)
            changed = True
    if args.accent and not args.icon and not args.reset:
        t['icon'] = t['accent']
    if args.grid:
        t['grid'] = args.grid == 'on'
        changed = True
    if luma(t['background']) > 0.25:
        print('That background is too light: eDEX-Tron is a dark theme.', file=sys.stderr)
        return 2
    if not (changed or args.reset):
        print(f'accent {t["accent"]}  background {t["background"]}  icon {t["icon"]}  '
              f'grid {"on" if t.get("grid") else "off"}')
        print('change with: edex-tron theme --accent "#RRGGBB" [--background ...] [--icon ...]')
        return 0
    save_theme(t)
    print(f'Recolouring: accent {t["accent"]}, background {t["background"]}')
    failures = apply_theme()
    print('The HUD and shell update by themselves; open apps pick it up when restarted.')
    return 1 if failures else 0


def _boot(args):
    from .boot import request
    from .config import load_theme
    t = load_theme()
    if args.action == 'preview':
        from .boot import main_root
        return main_root(['render', '--accent', t['accent'], '--background', t['background'],
                          '--out', args.out])
    return request(args.action, t['accent'], t['background'], args.show_menu)


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == ['hud']:
        # GTK parses the HUD's own options (--window, --primary=X,Y, ...)
        from .hud.app import main as hud_main
        return hud_main(['edex-tron-hud'] + argv[1:])
    if argv[:1] == ['boot-root']:
        from .boot import main_root
        return main_root(argv[1:])

    ap = argparse.ArgumentParser(
        prog='edex-tron',
        description='eDEX-Tron: an eDEX-UI style desktop for Ubuntu (GNOME). '
                    'Based on eDEX-UI by Gabriel "Squared" Saillard.')
    ap.add_argument('--version', action='version', version=f'eDEX-Tron {VERSION}')
    sub = ap.add_subparsers(dest='cmd', metavar='COMMAND')

    su = sub.add_parser('setup', help='apply the theme for this user (run once after installing)')
    su.add_argument('--pause', action='store_true', help='wait for Enter at the end (used by the launcher)')
    sub.add_parser('on', help='switch the HUD, effects and hotkeys on')
    sub.add_parser('off', help='switch them off (colours stay)')
    sub.add_parser('toggle', help='switch on if off, off if on')
    sub.add_parser('status', help='show what is on')

    t = sub.add_parser('theme', help='show or change the colours')
    t.add_argument('--accent')
    t.add_argument('--background')
    t.add_argument('--icon', help='launcher icon colour (defaults to the accent)')
    t.add_argument('--grid', choices=('on', 'off'), help="eDEX-UI's grid in the wallpaper")
    t.add_argument('--reset', action='store_true', help='back to the original tron colours')

    e = sub.add_parser('effects', help='screen effects: scanlines, glow, tv')
    e.add_argument('name', nargs='?', choices=(*EFFECT_KEYS, 'strength'))
    e.add_argument('state', nargs='?', help='on/off (or 0.0-0.6 for strength)')

    b = sub.add_parser('boot', help='boot menu and splash (needs your password)')
    b.add_argument('action', choices=('install', 'remove', 'preview'))
    b.add_argument('--show-menu', action='store_true',
                   help='always show the boot menu for 5 seconds')
    b.add_argument('--out', default='edex-tron-boot-preview', help='preview: output folder')

    r = sub.add_parser('reapply', help='regenerate everything (e.g. after changing screens)')
    r.add_argument('parts', nargs='*', help='only these: wallpaper icon gtk shell qt cursor terminal')

    sub.add_parser('doctor', help='check the installation')
    sub.add_parser('uninstall', help='remove the theme for this user and restore your settings')

    args = ap.parse_args(argv)
    if not args.cmd:
        ap.print_help()
        return 0

    from . import apply
    if args.cmd == 'setup':
        import os
        if os.geteuid() == 0:
            print('Run setup as yourself, not with sudo: it themes the account that runs it.',
                  file=sys.stderr)
            return 2
        code = apply.setup()
        if args.pause:
            input('\nPress Enter to close this window.')
        return code
    if args.cmd == 'on':
        apply.turn_on()
        return 0
    if args.cmd == 'off':
        apply.turn_off()
        return 0
    if args.cmd == 'toggle':
        apply.toggle()
        return 0
    if args.cmd == 'status':
        return apply.status()
    if args.cmd == 'theme':
        return _theme(args)
    if args.cmd == 'effects':
        return _effects(args)
    if args.cmd == 'boot':
        return _boot(args)
    if args.cmd == 'reapply':
        bad = [x for x in args.parts if x not in apply.COMPONENTS]
        if bad:
            print(f'unknown part(s): {" ".join(bad)}', file=sys.stderr)
            return 2
        return 1 if apply.apply_theme(args.parts or None) else 0
    if args.cmd == 'doctor':
        return apply.doctor()
    if args.cmd == 'uninstall':
        return apply.uninstall()
    return 0
