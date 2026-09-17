"""Per-user paths, settings and the colour palette."""
import json
import os
import shutil

from . import data_path, shared_path

HOME = os.path.expanduser('~')


def _xdg(var, default):
    return os.environ.get(var) or os.path.join(HOME, default)


CONFIG_HOME = _xdg('XDG_CONFIG_HOME', '.config')
DATA_HOME = _xdg('XDG_DATA_HOME', '.local/share')
STATE_HOME = _xdg('XDG_STATE_HOME', '.local/state')
CACHE_HOME = _xdg('XDG_CACHE_HOME', '.cache')

CONFIG_DIR = os.path.join(CONFIG_HOME, 'edex-tron')     # things you edit
STATE_DIR = os.path.join(STATE_HOME, 'edex-tron')       # backups, manifest
GEN_DIR = os.path.join(DATA_HOME, 'edex-tron')          # generated assets
THEME_FILE = os.path.join(CONFIG_DIR, 'theme.json')
DOCK_FILE = os.path.join(CONFIG_DIR, 'dock.txt')
SETTINGS_FILE = os.path.join(CONFIG_DIR, 'settings.json')

DEFAULT_THEME = {'accent': '#aacfd1', 'background': '#05080d',
                 'icon': '#4f9dff', 'grid': False}
# Effects and hotkeys live in the extension's GSettings (edex-tron effects ...).
DEFAULT_SETTINGS = {
    'prompt': True,               # eDEX prompt + fetch screen in bash/zsh
    'secondary_monitors': True,   # HUD on every monitor, not just the primary
    'terminal_font': 'Ubuntu Sans Mono 11',
}


def ensure_dirs():
    # GEN_DIR is left to the first write, so the undo log records creating it
    for d in (CONFIG_DIR, STATE_DIR):
        os.makedirs(d, exist_ok=True)


def _load(path, default):
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, ValueError):
        return json.loads(json.dumps(default))
    merged = json.loads(json.dumps(default))
    for k, v in data.items():
        if isinstance(v, dict) and isinstance(merged.get(k), dict):
            merged[k].update(v)
        else:
            merged[k] = v
    return merged


def _save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    os.replace(tmp, path)


def load_theme():
    t = _load(THEME_FILE, DEFAULT_THEME)
    for k in ('accent', 'background', 'icon'):
        t[k] = normalise_hex(t[k])
    return t


def save_theme(t):
    _save(THEME_FILE, t)


def load_settings():
    return _load(SETTINGS_FILE, DEFAULT_SETTINGS)


def save_settings(s):
    _save(SETTINGS_FILE, s)


def seed_user_files():
    """First run: copy the defaults so the person has something to edit."""
    ensure_dirs()
    if not os.path.exists(THEME_FILE):
        save_theme(DEFAULT_THEME)
    if not os.path.exists(SETTINGS_FILE):
        save_settings(DEFAULT_SETTINGS)
    if not os.path.exists(DOCK_FILE):
        shutil.copyfile(data_path('dock.default.txt'), DOCK_FILE)


# --- colours -----------------------------------------------------------------

def normalise_hex(h):
    h = str(h).strip().lstrip('#')
    if len(h) == 3:
        h = ''.join(c * 2 for c in h)
    if len(h) != 6 or any(c not in '0123456789abcdefABCDEF' for c in h):
        raise ValueError(f'not a #RRGGBB colour: {h!r}')
    return '#' + h.lower()


def rgb(h):
    h = normalise_hex(h)[1:]
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def to_hex(c):
    return '#%02x%02x%02x' % tuple(max(0, min(255, round(v))) for v in c)


def mix(a, b, t):
    """t=0 -> a, t=1 -> b."""
    ca, cb = rgb(a), rgb(b)
    return to_hex([x + (y - x) * t for x, y in zip(ca, cb)])


def luma(h):
    r, g, b = (v / 255 for v in rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def rgba(h, alpha):
    r, g, b = rgb(h)
    return f'rgba({r},{g},{b},{alpha:g})'


def palette(theme=None):
    """Every colour the generated themes use, derived from accent + background."""
    t = theme or load_theme()
    a, bg = t['accent'], t['background']
    p = {
        'accent': a,
        'accent_bright': mix(a, '#ffffff', 0.40),
        'accent_pale': mix(a, '#ffffff', 0.55),
        'accent_white': mix(a, '#ffffff', 0.85),
        'accent_dim': mix(a, bg, 0.45),
        'accent_faint': mix(a, bg, 0.80),
        'bg': bg,
        'bg_raised': mix(bg, a, 0.06),
        'bg_high': mix(bg, a, 0.12),
        'bg_sunken': mix(bg, '#000000', 0.35),
        'grey': '#262828',
        'icon': t['icon'],
        # accent-shifted status colours, kept from the tron terminal scheme
        'red': '#d1706a', 'green': '#8fd1a8', 'yellow': '#d1c48f',
        'blue': '#7fa8d1', 'purple': '#b08fd1',
        'red_b': '#e88b84', 'green_b': '#a9e4c2', 'yellow_b': '#e4dba9',
        'blue_b': '#99c2e4', 'purple_b': '#c8a9e4',
    }
    p['on_accent'] = '#000000' if luma(a) > 0.45 else '#ffffff'
    return p


def ansi16(p):
    """Terminal colours 0-15 in the order VTE, Ptyxis and friends expect."""
    return [p['bg'], p['red'], p['green'], p['yellow'], p['blue'], p['purple'],
            p['accent'], p['accent_pale'],
            p['grey'], p['red_b'], p['green_b'], p['yellow_b'], p['blue_b'],
            p['purple_b'], p['accent_bright'], p['accent_white']]


def convert_tron(text, p):
    """Map colours authored in the tron palette onto the current theme
    (same rule as the Windows edition's Convert-Palette)."""
    import re
    table = {
        'aacfd1': p['accent'], 'c8e6e7': p['accent_bright'],
        'cfe4e5': p['accent_pale'], 'f0f7f7': p['accent_white'],
        '05080d': p['bg'],
    }
    return re.sub(r'(?i)(aacfd1|c8e6e7|cfe4e5|f0f7f7|05080d)',
                  lambda m: table[m.group(1).lower()][1:], text)


def tron_theme_json():
    return shared_path('themes', 'edex', 'tron.json')
