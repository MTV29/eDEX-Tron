"""Apply, switch and remove the theme for the current user.

Everything here goes through `changes`, so `edex-tron uninstall` can put back
exactly what was there before.
"""
import contextlib
import glob
import io
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import uuid

from . import EXTENSION_UUID, VERSION, changes, cursor, shared_path, themes
from .config import (CONFIG_HOME, DATA_HOME, GEN_DIR, HOME, THEME_FILE, convert_tron,
                     ensure_dirs, load_settings, load_theme, palette, seed_user_files)

DING_UUID = 'ding@rastersoft.com'
EXT_SCHEMA = 'org.gnome.shell.extensions.edex-tron'
IFACE = 'org.gnome.desktop.interface'
DOCK = 'org.gnome.shell.extensions.dash-to-dock'


def say(msg):
    print(msg, flush=True)


def have(cmd):
    return shutil.which(cmd) is not None


def run(*args, check=False):
    return subprocess.run(args, capture_output=True, text=True, check=check)


def gen(*parts):
    return os.path.join(GEN_DIR, *parts)


def _load_shared(name, relpath):
    spec = importlib.util.spec_from_file_location(name, shared_path(*relpath))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# --- screen size (for the wallpaper) ------------------------------------------

def screen_pixels():
    """Largest monitor in physical pixels; 1920x1080 when unknown."""
    try:
        import gi
        gi.require_version('Gdk', '4.0')
        from gi.repository import Gdk
        display = Gdk.Display.get_default()
        best = (0, 0)
        if display:
            mons = display.get_monitors()
            for i in range(mons.get_n_items()):
                m = mons.get_item(i)
                g, s = m.get_geometry(), m.get_scale()
                w, h = round(g.width * s), round(g.height * s)
                if w * h > best[0] * best[1]:
                    best = (w, h)
        if best[0]:
            return best
    except (ImportError, ValueError):
        pass
    return 1920, 1080


# --- individual components ---------------------------------------------------------

def apply_wallpaper(p, theme):
    w, h = screen_pixels()
    mw = _load_shared('edex_wallpaper', ('src', 'tools', 'make_wallpaper.py'))
    shell = os.path.basename(os.environ.get('SHELL', 'bash')).upper()
    tag = theme['accent'].lstrip('#') + theme['background'].lstrip('#')
    out = gen('wallpaper', f'edex-tron-{w}x{h}-{tag}.png')
    if not os.path.exists(out):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_png = os.path.join(tmp, 'wall.png')
            with contextlib.redirect_stdout(io.StringIO()):
                mw.build(w, h, shared_path('themes', 'edex', 'tron.json'), tmp_png, config=theme,
                         footer=f'SHELL: {shell}   ·   THEME: TRON   ·   RENDER: OK')
            os.makedirs(gen('wallpaper'), exist_ok=True)
            # keep only the current render
            for old in glob.glob(gen('wallpaper', 'edex-tron-*')):
                os.remove(old)
            shutil.copyfile(tmp_png, out)
    uri = 'file://' + out
    changes.gset('org.gnome.desktop.background', 'picture-uri', f"'{uri}'")
    changes.gset('org.gnome.desktop.background', 'picture-uri-dark', f"'{uri}'")
    changes.gset('org.gnome.desktop.background', 'picture-options', "'zoom'")
    changes.gset('org.gnome.desktop.background', 'primary-color', f"'{p['bg']}'")
    changes.gset('org.gnome.desktop.screensaver', 'picture-uri', f"'{uri}'")
    return f'wallpaper {w}x{h}'


def apply_icon(theme):
    dest = os.path.join(DATA_HOME, 'icons', 'hicolor', '512x512', 'apps', 'edex-tron.png')
    with tempfile.TemporaryDirectory() as tmp:
        cfg = os.path.join(tmp, 'theme.json')
        with open(cfg, 'w') as f:
            json.dump(theme, f)
        r = run(sys.executable, shared_path('src', 'tools', 'gen_icon.py'),
                '--out', tmp, '--config', cfg, '--size', '768')
        if r.returncode:
            return 'icon skipped (' + (r.stderr.strip().splitlines() or ['error'])[-1] + ')'
        with open(os.path.join(tmp, 'edex-tron.png'), 'rb') as f:
            changes.write_file(dest, f.read())
    hicolor = os.path.join(DATA_HOME, 'icons', 'hicolor')
    changes.track_dir(os.path.join(hicolor, 'icon-theme.cache'))
    run('gtk4-update-icon-cache', '-q', '-t', '-f', hicolor)
    return 'icon'


def apply_gtk(p):
    changes.write_file(gen('gtk4.css'), themes.gtk4_css(p))
    changes.write_file(gen('gtk3.css'), themes.gtk3_css(p))
    for ver, name in (('gtk-4.0', 'gtk4.css'), ('gtk-3.0', 'gtk3.css')):
        changes.add_block(os.path.join(CONFIG_HOME, ver, 'gtk.css'),
                          f'@import url("file://{gen(name)}");', '/*', ' */', top=True)
    yaru = themes.yaru_dark(p)
    changes.gset(IFACE, 'color-scheme', "'prefer-dark'")
    changes.gset(IFACE, 'accent-color', f"'{themes.gnome_accent(p)}'")
    if os.path.isdir(f'/usr/share/themes/{yaru}'):
        changes.gset(IFACE, 'gtk-theme', f"'{yaru}'")
    if os.path.isdir(f'/usr/share/icons/{yaru}'):
        changes.gset(IFACE, 'icon-theme', f"'{yaru}'")
    changes.gset('org.gnome.shell.ubuntu', 'color-scheme', "'prefer-dark'")
    return f'GTK apps ({yaru})'


def apply_shell(p):
    changes.write_file(gen('gnome-shell.css'), themes.shell_css(p))
    changes.gset(EXT_SCHEMA, 'shell-stylesheet', f"'{gen('gnome-shell.css')}'")
    changes.gset(EXT_SCHEMA, 'accent', f"'{p['accent']}'")
    # Ubuntu Dock
    if changes.schema_exists(DOCK):
        changes.gset(DOCK, 'apply-custom-theme', 'false')
        changes.gset(DOCK, 'custom-background-color', 'true')
        changes.gset(DOCK, 'background-color', f"'{p['bg']}'")
        changes.gset(DOCK, 'transparency-mode', "'FIXED'")
        changes.gset(DOCK, 'background-opacity', '0.85')
        changes.gset(DOCK, 'running-indicator-style', "'DASHES'")
        changes.gset(DOCK, 'custom-theme-customize-running-dots', 'true')
        changes.gset(DOCK, 'custom-theme-running-dots-color', f"'{p['accent']}'")
        changes.gset(DOCK, 'custom-theme-running-dots-border-color', f"'{p['accent']}'")
    return 'GNOME Shell, dock and lock screen'


def apply_qt(p):
    done = []
    for ver in (6, 5):
        tool = f'qt{ver}ct'
        plugin = glob.glob(f'/usr/lib/*/qt{ver}/plugins/platformthemes/lib{tool}.so')
        if not plugin:
            continue
        base = os.path.join(CONFIG_HOME, tool)
        scheme = os.path.join(base, 'colors', 'edex-tron.conf')
        changes.write_file(scheme, themes.qt_colors(p))
        changes.write_file(os.path.join(base, f'{tool}.conf'), themes.qtct_conf(scheme))
        done.append(tool)
    if not done:
        return 'Qt skipped (install qt6ct to theme Qt apps)'
    # Qt 6 apps read qt6ct; Qt 5 apps can't load it and fall back quietly.
    changes.write_file(os.path.join(CONFIG_HOME, 'environment.d', '90-edex-tron.conf'),
                       f'QT_QPA_PLATFORMTHEME={done[0]}\n')
    return 'Qt apps (' + ', '.join(done) + '; after next login)'


def apply_cursor(p):
    dest = os.path.join(DATA_HOME, 'icons', 'eDEX-Tron')
    with tempfile.TemporaryDirectory() as tmp:
        build = os.path.join(tmp, 'eDEX-Tron')
        cursor.build_theme(build, p['accent'], p['bg'])
        changes.copy_tree(build, dest)
    changes.gset(IFACE, 'cursor-theme', "'eDEX-Tron'")
    return 'cursor'


def _ptyxis(p):
    if not changes.schema_exists('org.gnome.Ptyxis'):
        return None
    pal_dir = os.path.join(DATA_HOME, 'org.gnome.Ptyxis', 'palettes')
    changes.write_file(os.path.join(pal_dir, 'edex-tron.palette'), themes.ptyxis_palette(p))
    profile = (changes.gget('org.gnome.Ptyxis', 'default-profile-uuid') or '').strip("'")
    if not profile:
        profile = uuid.uuid4().hex
        changes.gset('org.gnome.Ptyxis', 'profile-uuids', f"['{profile}']")
        changes.gset('org.gnome.Ptyxis', 'default-profile-uuid', f"'{profile}'")
    schema = f'org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/{profile}/'
    changes.gset(schema, 'palette', "'edex-tron'")
    changes.gset('org.gnome.Ptyxis', 'interface-style', "'dark'")
    return 'Ptyxis'


def _gnome_terminal(p):
    base = 'org.gnome.Terminal.ProfilesList'
    if not changes.schema_exists(base):
        return None
    profile = (changes.gget(base, 'default') or '').strip("'")
    if not profile:
        return None
    schema = f'org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:{profile}/'
    changes.gset(schema, 'use-theme-colors', 'false')
    changes.gset(schema, 'foreground-color', f"'{p['accent']}'")
    changes.gset(schema, 'background-color', f"'{p['bg']}'")
    changes.gset(schema, 'palette', themes.gnome_terminal_palette(p))
    return 'GNOME Terminal'


def apply_terminal(p, settings):
    done = [x for x in (_ptyxis(p), _gnome_terminal(p)) if x]

    changes.write_file(gen('starship.toml'), themes.starship_toml(p))
    changes.write_file(gen('fastfetch-logo.txt'), themes.fastfetch_logo())
    changes.write_file(gen('fastfetch.jsonc'), themes.fastfetch_jsonc(p, gen('fastfetch-logo.txt')))
    if settings.get('prompt', True):
        changes.add_block(os.path.join(HOME, '.bashrc'), themes.shell_block(GEN_DIR, 'bash'))
        if os.path.exists(os.path.join(HOME, '.zshrc')):
            changes.add_block(os.path.join(HOME, '.zshrc'), themes.shell_block(GEN_DIR, 'zsh'))
        done.append('prompt' + ('' if have('starship') else ' (install starship to see it)'))

    changes.write_file(os.path.join(CONFIG_HOME, 'btop', 'themes', 'edex-tron.theme'), themes.btop_theme(p))
    changes.set_line(os.path.join(CONFIG_HOME, 'btop', 'btop.conf'), 'color_theme',
                     'color_theme = "edex-tron"')
    done.append('btop')

    changes.write_file(gen('tmux.conf'), themes.tmux_conf(p))
    tmux_conf = os.path.join(CONFIG_HOME, 'tmux', 'tmux.conf')
    if not os.path.exists(tmux_conf):
        tmux_conf = os.path.join(HOME, '.tmux.conf')
    changes.add_block(tmux_conf, f'source-file "{gen("tmux.conf")}"')
    done.append('tmux')

    nvim = os.path.join(CONFIG_HOME, 'nvim')
    changes.write_file(os.path.join(nvim, 'colors', 'edex-tron.lua'), themes.nvim_colors(p))
    init_lua = os.path.join(nvim, 'init.lua')
    if changes.created_by_us(init_lua) or not any(
            os.path.exists(os.path.join(nvim, f)) for f in ('init.lua', 'init.vim')):
        changes.write_file(init_lua,
                           '-- created by eDEX-Tron; removed by `edex-tron uninstall`\n'
                           "vim.cmd.colorscheme('edex-tron')\n")
        done.append('Neovim')
    else:
        done.append('Neovim (add `colorscheme edex-tron` to your init)')

    vscode = _vscode(p)
    if vscode:
        done.append(vscode)
    return 'terminal & tools: ' + ', '.join(done)


def _vscode(p):
    user_dirs = [d for d in (os.path.join(CONFIG_HOME, 'Code', 'User'),
                             os.path.join(CONFIG_HOME, 'VSCodium', 'User')) if os.path.isdir(os.path.dirname(d))]
    if not user_dirs:
        return None
    src = shared_path('themes', 'vscode')
    ext_root = os.path.join(HOME, '.vscode', 'extensions')
    dest = os.path.join(ext_root, f'local.edex-tron-theme-{VERSION}')
    with tempfile.TemporaryDirectory() as tmp:
        staged = os.path.join(tmp, 'ext')
        shutil.copytree(src, staged)
        path = os.path.join(staged, 'themes', 'edex-tron-color-theme.json')
        with open(path, encoding='utf-8') as f:
            text = convert_tron(f.read(), p)
        with open(path, 'w', encoding='utf-8') as f:
            f.write(text)
        changes.copy_tree(staged, dest)
    ok = all(changes.set_json_key(os.path.join(d, 'settings.json'), 'workbench.colorTheme', 'eDEX Tron')
             for d in user_dirs)
    return 'VS Code' if ok else 'VS Code theme installed (pick "eDEX Tron" yourself; settings.json could not be read)'


# --- extension and desktop icons ---------------------------------------------------

def extension_state():
    r = run('gnome-extensions', 'info', EXTENSION_UUID)
    if r.returncode:
        return 'missing'
    for line in r.stdout.splitlines():
        if line.strip().lower().startswith('state:'):
            return line.split(':', 1)[1].strip().lower()
    return 'unknown'


def _shell_list(key):
    raw = changes.gget('org.gnome.shell', key) or '@as []'
    return json.loads(raw.replace('@as ', '').replace("'", '"'))


def _write_list(key, items):
    if items != _shell_list(key):
        changes.gset('org.gnome.shell', key, json.dumps(items))


def set_extension(on):
    """Enable/disable ours and switch Ubuntu's desktop icons the other way.

    Changing DING makes GNOME briefly disable and re-enable the extensions
    after it (ours included), and if ours changes in the same moment GNOME
    can leave it marked inactive without calling disable(). So the two are
    switched one after the other, with DING never changing while ours runs."""
    import time

    def lists():
        return _shell_list('enabled-extensions'), _shell_list('disabled-extensions')

    if changes.gget('org.gnome.shell', 'disable-user-extensions') == 'true':
        changes.gset('org.gnome.shell', 'disable-user-extensions', 'false')
    if on:
        enabled, disabled = lists()
        _write_list('enabled-extensions', [u for u in enabled if u != DING_UUID])
        _write_list('disabled-extensions', [u for u in disabled if u != DING_UUID] + [DING_UUID])
        time.sleep(0.6)
        enabled, disabled = lists()
        _write_list('disabled-extensions', [u for u in disabled if u != EXTENSION_UUID])
        _write_list('enabled-extensions', [u for u in enabled if u != EXTENSION_UUID] + [EXTENSION_UUID])
    else:
        enabled, disabled = lists()
        _write_list('enabled-extensions', [u for u in enabled if u != EXTENSION_UUID])
        _write_list('disabled-extensions', [u for u in disabled if u != EXTENSION_UUID] + [EXTENSION_UUID])
        time.sleep(0.6)
        _, disabled = lists()
        _write_list('disabled-extensions', [u for u in disabled if u != DING_UUID])


def set_hud(on):
    changes.gset(EXT_SCHEMA, 'hud-enabled', 'true' if on else 'false')


# --- public commands ----------------------------------------------------------------------

COMPONENTS = ('wallpaper', 'icon', 'gtk', 'shell', 'qt', 'cursor', 'terminal')


def apply_theme(only=None):
    ensure_dirs()
    changes.track_dir(GEN_DIR)
    theme = load_theme()
    p = palette(theme)
    settings = load_settings()
    steps = {
        'wallpaper': lambda: apply_wallpaper(p, theme),
        'icon': lambda: apply_icon(theme),
        'gtk': lambda: apply_gtk(p),
        'shell': lambda: apply_shell(p),
        'qt': lambda: apply_qt(p),
        'cursor': lambda: apply_cursor(p),
        'terminal': lambda: apply_terminal(p, settings),
    }
    failures = []
    for name in (only or COMPONENTS):
        try:
            say(f'  ✓ {steps[name]()}')
        except Exception as e:  # noqa: BLE001 - report and carry on
            failures.append(name)
            say(f'  ✗ {name}: {e}')
    return failures


def setup(boot=None):
    say(f'eDEX-Tron {VERSION} for Linux: based on eDEX-UI by Gabriel "Squared" Saillard\n')
    problems = preflight()
    for level, msg in problems:
        say(f'  {level}: {msg}')
    if any(level == 'error' for level, _ in problems):
        return 1
    seed_user_files()
    say('Applying the theme:')
    failures = apply_theme()
    set_extension(True)
    set_hud(True)
    state = extension_state()
    say('')
    if state in ('active', 'enabled'):
        say('The HUD is starting now.')
    else:
        say('Log out and back in once to start the HUD (GNOME only loads new\n'
            'extensions at login). After that it starts by itself.')
    say('\nTurn it off/on:   edex-tron off | edex-tron on'
        '\nChange colours:   edex-tron theme --accent "#ff9f1c"'
        '\nBoot menu/splash: edex-tron boot install     (asks for your password)'
        '\nRemove it all:    edex-tron uninstall')
    return 1 if failures else 0


def preflight():
    out = []
    desktop = os.environ.get('XDG_CURRENT_DESKTOP', '')
    if 'GNOME' not in desktop.upper():
        out.append(('warning', f'this desktop is "{desktop or "unknown"}"; the HUD needs GNOME '
                               '(elsewhere run `edex-tron hud --window`)'))
    r = run('gnome-shell', '--version') if have('gnome-shell') else None
    if r and r.returncode == 0:
        try:
            major = int(r.stdout.split()[-1].split('.')[0])
        except ValueError:
            major = 0
        if major and major != 50:
            out.append(('warning', f'GNOME Shell {major} found; this release is built for GNOME 50 '
                                   '(Ubuntu 26.04)'))
    if os.environ.get('XDG_SESSION_TYPE') not in (None, '', 'wayland'):
        out.append(('warning', 'not a Wayland session; the HUD runs as a normal window'))
    try:
        import gi
        gi.require_version('Vte', '3.91')
        from gi.repository import Vte  # noqa: F401
    except (ImportError, ValueError):
        out.append(('error', 'VTE for GTK 4 is missing: sudo apt install gir1.2-vte-3.91'))
    try:
        import psutil  # noqa: F401
        import PIL  # noqa: F401
    except ImportError:
        out.append(('error', 'Python packages missing: sudo apt install python3-psutil python3-pil python3-numpy'))
    return out


def turn_on():
    set_extension(True)
    set_hud(True)
    state = extension_state()
    if state not in ('active', 'enabled'):
        say('Enabled. Log out and back in to start it (GNOME loads new extensions at login).')
    else:
        say('eDEX-Tron is on.')


def turn_off():
    set_extension(False)
    say('eDEX-Tron is off: HUD, effects and hotkeys stopped; desktop icons are back.\n'
        'App colours stay until `edex-tron uninstall`.')


def status():
    theme = load_theme()
    enabled = EXTENSION_UUID in (changes.gget('org.gnome.shell', 'enabled-extensions') or '')
    say(f'eDEX-Tron {VERSION}')
    say(f'  extension : {"on" if enabled else "off"} ({extension_state()})')
    say(f'  HUD       : {changes.gget(EXT_SCHEMA, "hud-enabled") or "?"}')
    for key in ('scanlines', 'glow', 'tv-animation'):
        say(f'  {key:<10}: {changes.gget(EXT_SCHEMA, key) or "?"}')
    say(f'  colours   : accent {theme["accent"]}, background {theme["background"]}, icon {theme["icon"]}')
    say(f'  settings  : {THEME_FILE}')
    return 0 if enabled else 3


def toggle():
    enabled = EXTENSION_UUID in (changes.gget('org.gnome.shell', 'enabled-extensions') or '')
    (turn_off if enabled else turn_on)()


def uninstall():
    say('Removing eDEX-Tron for this user...')
    set_extension(False)
    changes.restore_all(say)
    say('Done. Your previous settings are back. The package itself stays installed;\n'
        'remove it with: sudo apt remove edex-tron')
    say('(Boot theme, if you installed it: edex-tron boot remove)')
    return 0


def doctor():
    say(f'eDEX-Tron {VERSION} diagnostics')
    for level, msg in preflight() or [('ok', 'environment looks right')]:
        say(f'  {level}: {msg}')
    say(f'  extension state: {extension_state()}')
    say(f'  HUD command: {changes.gget(EXT_SCHEMA, "hud-command")}')
    say(f'  edex-tron on PATH: {shutil.which("edex-tron")}')
    say('\nTo see HUD errors directly, run:  edex-tron hud --window')
    say('Shell log:  journalctl --user -b -g "eDEX-Tron" --no-pager | tail -n 40')
    return 0
