"""Every change setup makes is recorded here so uninstall can undo it.

The manifest (~/.local/state/edex-tron/manifest.json) remembers, the first
time each thing is touched:
  files     created by us (deleted on undo) or replaced (original restored)
  blocks    marked sections we added to someone's own config file
  settings  the original value of each GSettings key we change
Re-running setup never overwrites a recorded original, so a second run can't
"back up" our own theme as if it were the person's.
"""
import json
import os
import shutil
import time

from .config import HOME, STATE_DIR

MANIFEST = os.path.join(STATE_DIR, 'manifest.json')
BACKUP_DIR = os.path.join(STATE_DIR, 'backup')
BEGIN = '>>> edex-tron >>>'
END = '<<< edex-tron <<<'


def _load():
    try:
        with open(MANIFEST) as f:
            m = json.load(f)
    except (OSError, ValueError):
        m = {}
    for k in ('files', 'blocks', 'settings'):
        m.setdefault(k, {})
    m.setdefault('dirs', [])
    return m


def _save(m):
    os.makedirs(STATE_DIR, exist_ok=True)
    tmp = MANIFEST + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(m, f, indent=2, sort_keys=True)
    os.replace(tmp, MANIFEST)


def _backup_name(path):
    rel = os.path.relpath(path, HOME) if path.startswith(HOME + os.sep) else path.lstrip('/')
    return os.path.join(BACKUP_DIR, rel)


def _mkparents(path):
    """Create path's parent folders, noting the ones that didn't exist so
    undo can remove them again (only if they are empty by then)."""
    d = os.path.dirname(path)
    missing = []
    while d and d != '/' and not os.path.isdir(d):
        missing.append(d)
        d = os.path.dirname(d)
    if missing:
        m = _load()
        m['dirs'] = sorted(set(m['dirs']) | set(missing))
        _save(m)
    os.makedirs(os.path.dirname(path), exist_ok=True)


def _remember_file(m, path):
    if path in m['files']:
        return
    if os.path.lexists(path):
        dest = _backup_name(path)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.copytree(path, dest, symlinks=True, dirs_exist_ok=True)
        else:
            shutil.copy2(path, dest, follow_symlinks=False)
        m['files'][path] = {'action': 'replaced', 'backup': dest}
    else:
        m['files'][path] = {'action': 'created'}


def write_file(path, content, mode=None):
    """Write a file we own (content: str or bytes)."""
    m = _load()
    _remember_file(m, path)
    _save(m)
    _mkparents(path)
    data = content.encode() if isinstance(content, str) else content
    tmp = path + '.edex-tmp'
    with open(tmp, 'wb') as f:
        f.write(data)
    if mode is not None:
        os.chmod(tmp, mode)
    os.replace(tmp, path)


def copy_tree(src, dest):
    """Copy a directory we own (extension, cursor theme, ...)."""
    m = _load()
    _remember_file(m, dest)
    _save(m)
    if os.path.isdir(dest) and not os.path.islink(dest):
        shutil.rmtree(dest)
    _mkparents(dest)
    shutil.copytree(src, dest, symlinks=True)


def created_by_us(path):
    return _load()['files'].get(path, {}).get('action') == 'created'


def track_dir(dest):
    """Record a directory we are about to create/replace ourselves."""
    m = _load()
    _remember_file(m, dest)
    _save(m)


def add_block(path, body, comment='#', close='', top=False):
    """Insert (or refresh) a marked block in a config file.

    comment/close wrap the marker lines ('/*', ' */' for CSS); top=True puts
    the block first (CSS @import must precede other rules)."""
    begin, end = _markers(comment, close)
    text = ''
    if os.path.exists(path):
        with open(path) as f:
            text = f.read()
    text = _strip_block(text, begin, end)
    note = f'{comment} added by eDEX-Tron; removed by `edex-tron uninstall`{close}'
    block = f'{begin}\n{note}\n{body.rstrip()}\n{end}\n'
    m = _load()
    if path not in m['blocks'] and path not in m['files']:
        m['blocks'][path] = {'comment': comment, 'close': close,
                             'existed': os.path.exists(path)}
        _save(m)
    _mkparents(path)
    if top:
        new = block + text
    else:
        if text and not text.endswith('\n'):
            text += '\n'
        new = text + block
    with open(path, 'w') as f:
        f.write(new)


def _markers(comment, close):
    return f'{comment} {BEGIN}{close}', f'{comment} {END}{close}'


def _strip_block(text, begin, end):
    out, skipping = [], False
    for line in text.splitlines(keepends=True):
        s = line.strip()
        if s == begin:
            skipping = True
            continue
        if skipping and s == end:
            skipping = False
            continue
        if not skipping:
            out.append(line)
    return ''.join(out)


# --- GSettings ----------------------------------------------------------------

# Schemas are written "id" or "id:/relocatable/path/" (as the gsettings tool
# takes them); values are GVariant text such as "'dark'" or "true".

def _settings(schema, key=None):
    """Gio.Settings for schema (and check key), or None if not installed."""
    from gi.repository import Gio
    sid, _, path = schema.partition(':')
    src = Gio.SettingsSchemaSource.get_default()
    found = src.lookup(sid, True) if src else None
    if found is None or (key is not None and not found.has_key(key)):
        return None
    if found.get_path() is None and not path:
        return None
    return Gio.Settings.new_full(found, None, path or None)


def schema_exists(schema):
    return _settings(schema) is not None


def gget(schema, key):
    s = _settings(schema, key)
    return s.get_value(key).print_(True) if s else None


def _gvariant(s, key, text):
    from gi.repository import GLib
    vtype = s.get_value(key).get_type()
    return GLib.Variant.parse(vtype, text, None, None)


def _sync():
    from gi.repository import Gio
    Gio.Settings.sync()


def gset(schema, key, value):
    """Set a key, remembering the original the first time. Keys that were at
    their default are reset on undo rather than pinned to that value.
    Missing schemas are skipped quietly."""
    s = _settings(schema, key)
    if s is None:
        return False
    m = _load()
    ident = f'{schema}\t{key}'
    if ident not in m['settings']:
        user = s.get_user_value(key)
        m['settings'][ident] = {'value': user.print_(True) if user is not None else None}
        _save(m)
    if not s.set_value(key, _gvariant(s, key, value)):
        raise RuntimeError(f'could not set {schema} {key}')
    _sync()
    return True


# --- single lines and JSON keys in files other programs rewrite ----------------

def set_line(path, key, line):
    """Replace (or append) the `key = ...` line of an ini-style file that its
    program rewrites (btop.conf), remembering only the original line."""
    import re
    pat = re.compile(rf'^\s*{re.escape(key)}\s*=')
    lines = []
    if os.path.exists(path):
        with open(path) as f:
            lines = f.read().splitlines()
    old = next((ln for ln in lines if pat.match(ln)), None)
    m = _load()
    m.setdefault('lines', {})
    ident = f'{path}\t{key}'
    if ident not in m['lines']:
        m['lines'][ident] = {'line': old, 'existed': os.path.exists(path)}
        _save(m)
    if old is None:
        lines.append(line)
    else:
        lines = [line if pat.match(ln) else ln for ln in lines]
    _mkparents(path)
    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n')


def _read_jsonc(path):
    """JSON with // and /* */ comments and trailing commas (VS Code style)."""
    import re
    with open(path) as f:
        text = f.read()
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == '\\' else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith('//', i):
            i = text.find('\n', i)
            i = n if i < 0 else i
        elif text.startswith('/*', i):
            i = text.find('*/', i)
            i = n if i < 0 else i + 2
        else:
            out.append(c)
            i += 1
    cleaned = re.sub(r',(\s*[}\]])', r'\1', ''.join(out))
    return json.loads(cleaned) if cleaned.strip() else {}


def _json_string_edit(path, key, value):
    """Set or remove (value=None) a top-level string key by editing the text,
    so the person's comments and formatting survive."""
    import re
    text = ''
    if os.path.exists(path):
        with open(path) as f:
            text = f.read()
    if not text.strip():
        text = '{\n}\n'
    pat = re.compile(r'(\n?[ \t]*)"' + re.escape(key) + r'"\s*:\s*"(?:[^"\\]|\\.)*"(\s*,)?')
    found = pat.search(text)
    if value is None:
        if found:
            text = text[:found.start()] + text[found.end():]
    elif found:
        new = f'"{key}": {json.dumps(value)}'
        text = text[:found.start()] + found.group(1) + new + (found.group(2) or '') + text[found.end():]
    else:
        brace = text.index('{')
        rest = text[brace + 1:]
        comma = ',' if rest.strip() not in ('}', '') and not rest.strip().startswith('}') else ''
        text = text[:brace + 1] + f'\n    "{key}": {json.dumps(value)}{comma}' + rest
    _mkparents(path)
    with open(path, 'w') as f:
        f.write(text)


def set_json_key(path, key, value):
    """Set one top-level string setting in a JSON(C) settings file, remembering
    the old value. Returns False (and changes nothing) if it can't be parsed."""
    data = {}
    if os.path.exists(path):
        try:
            data = _read_jsonc(path)
        except ValueError:
            return False
        if not isinstance(data, dict):
            return False
    m = _load()
    m.setdefault('json', {})
    ident = f'{path}\t{key}'
    if ident not in m['json']:
        old = data.get(key)
        m['json'][ident] = {'present': key in data and isinstance(old, str), 'value': old,
                            'existed': os.path.exists(path)}
        _save(m)
    _json_string_edit(path, key, value)
    return True


# --- undo -----------------------------------------------------------------------

def restore_all(log=print):
    m = _load()
    for ident, info in m['settings'].items():
        schema, key = ident.split('\t')
        s = _settings(schema, key)
        if s is None:
            continue
        if info['value'] is None:
            s.reset(key)
        else:
            s.set_value(key, _gvariant(s, key, info['value']))
        log(f'  restored {schema} {key}')
    _sync()

    for path, info in m['blocks'].items():
        if not os.path.exists(path):
            continue
        begin, end = _markers(info['comment'], info.get('close', ''))
        with open(path) as f:
            text = _strip_block(f.read(), begin, end)
        if not text.strip() and not info.get('existed', True):
            os.remove(path)
        else:
            with open(path, 'w') as f:
                f.write(text)
        log(f'  cleaned {path}')

    for ident, info in m.get('lines', {}).items():
        path, key = ident.split('\t')
        if not os.path.exists(path):
            continue
        if info['line'] is None and not info['existed']:
            os.remove(path)
        else:
            import re
            pat = re.compile(rf'^\s*{re.escape(key)}\s*=')
            with open(path) as f:
                lines = f.read().splitlines()
            if info['line'] is None:
                lines = [ln for ln in lines if not pat.match(ln)]
            else:
                lines = [info['line'] if pat.match(ln) else ln for ln in lines]
            with open(path, 'w') as f:
                f.write('\n'.join(lines) + '\n')
        log(f'  restored {path} ({key})')

    for ident, info in m.get('json', {}).items():
        path, key = ident.split('\t')
        if not os.path.exists(path):
            continue
        _json_string_edit(path, key, info['value'] if info['present'] else None)
        log(f'  restored {path} ({key})')

    # deepest paths first so directories empty out cleanly
    for path in sorted(m['files'], key=len, reverse=True):
        info = m['files'][path]
        _remove(path)
        if info['action'] == 'replaced' and os.path.lexists(info['backup']):
            src = info['backup']
            if os.path.isdir(src) and not os.path.islink(src):
                shutil.copytree(src, path, symlinks=True)
            else:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                shutil.copy2(src, path, follow_symlinks=False)
            log(f'  restored {path}')
        else:
            log(f'  removed  {path}')

    for d in sorted(m['dirs'], key=len, reverse=True):
        try:
            os.rmdir(d)          # only succeeds when nothing else lives there
        except OSError:
            pass

    stamp = time.strftime('%Y%m%d-%H%M%S')
    if os.path.exists(MANIFEST):
        os.replace(MANIFEST, MANIFEST + f'.undone-{stamp}')


def _remove(path):
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path, ignore_errors=True)
    elif os.path.lexists(path):
        os.remove(path)
