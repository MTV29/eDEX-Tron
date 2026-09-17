"""Unit tests that need no desktop: python3 -m unittest discover -s linux/tests"""
import json
import os
import shutil
import struct
import sys
import tempfile
import unittest

HOME = tempfile.mkdtemp(prefix='edex-home-')
os.environ.update(HOME=HOME, XDG_CONFIG_HOME=f'{HOME}/.config',
                  XDG_DATA_HOME=f'{HOME}/.local/share', XDG_STATE_HOME=f'{HOME}/.local/state')
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from edex_tron import changes, config, cursor, themes  # noqa: E402


def tearDownModule():
    shutil.rmtree(HOME, ignore_errors=True)


class Palette(unittest.TestCase):
    def test_defaults_are_tron(self):
        p = config.palette(config.DEFAULT_THEME)
        self.assertEqual(p['accent'], '#aacfd1')
        self.assertEqual(p['bg'], '#05080d')
        self.assertEqual(len(config.ansi16(p)), 16)

    def test_hex_validation(self):
        self.assertEqual(config.normalise_hex('ABC'), '#aabbcc')
        with self.assertRaises(ValueError):
            config.normalise_hex('#12345g')

    def test_convert_tron_keeps_alpha_suffix(self):
        p = config.palette({'accent': '#ff9f1c', 'background': '#000000', 'icon': '#ff9f1c'})
        self.assertEqual(config.convert_tron('"#AACFD155"', p), '"#ff9f1c55"')

    def test_accent_names(self):
        for colour, gnome in (('#ff9f1c', 'orange'), ('#4f9dff', 'blue'), ('#888888', 'slate')):
            p = config.palette({'accent': colour, 'background': '#05080d', 'icon': colour})
            self.assertEqual(themes.gnome_accent(p), gnome)
            self.assertTrue(themes.yaru_dark(p).endswith('-dark'))


class Renderers(unittest.TestCase):
    p = config.palette(config.DEFAULT_THEME)

    def test_css_is_balanced(self):
        for css in (themes.gtk4_css(self.p), themes.gtk3_css(self.p), themes.shell_css(self.p)):
            self.assertEqual(css.count('{'), css.count('}'))
            self.assertNotIn('None', css)

    def test_ptyxis_palette_has_both_variants(self):
        text = themes.ptyxis_palette(self.p)
        for group in ('[Palette]', '[Light]', '[Dark]'):
            self.assertIn(group, text)
        self.assertEqual(text.count('Color15='), 2)

    def test_qt_scheme_has_21_roles(self):
        for line in themes.qt_colors(self.p).splitlines()[1:]:
            self.assertEqual(len(line.split('=', 1)[1].split(',')), 21)

    def test_fastfetch_is_json(self):
        body = themes.fastfetch_jsonc(self.p, '/logo').split('\n', 1)[1]
        self.assertEqual(json.loads(body)['logo']['source'], '/logo')

    def test_btop_and_tmux_mention_accent(self):
        self.assertIn('#aacfd1', themes.btop_theme(self.p))
        self.assertIn('#aacfd1', themes.tmux_conf(self.p))

    def test_nvim_sets_colors_name(self):
        self.assertIn("vim.g.colors_name = 'edex-tron'", themes.nvim_colors(self.p))


class Changes(unittest.TestCase):
    def setUp(self):
        shutil.rmtree(config.STATE_DIR, ignore_errors=True)
        self.dir = tempfile.mkdtemp(dir=HOME)

    def test_created_file_is_removed(self):
        path = os.path.join(self.dir, 'new', 'file.txt')
        changes.write_file(path, 'hi')
        changes.write_file(path, 'again')   # second write must not "back up" ours
        changes.restore_all(lambda *_: None)
        self.assertFalse(os.path.exists(path))

    def test_replaced_file_is_restored(self):
        path = os.path.join(self.dir, 'conf')
        with open(path, 'w') as f:
            f.write('mine')
        changes.write_file(path, 'ours')
        changes.write_file(path, 'ours v2')
        changes.restore_all(lambda *_: None)
        with open(path) as f:
            self.assertEqual(f.read(), 'mine')

    def test_block_top_and_bottom(self):
        path = os.path.join(self.dir, 'gtk.css')
        with open(path, 'w') as f:
            f.write('label { color: red; }\n')
        changes.add_block(path, '@import url("a");', '/*', ' */', top=True)
        changes.add_block(path, '@import url("b");', '/*', ' */', top=True)
        with open(path) as f:
            text = f.read()
        self.assertTrue(text.startswith('/* >>> edex-tron >>> */'))
        self.assertEqual(text.count('@import'), 1)
        changes.restore_all(lambda *_: None)
        with open(path) as f:
            self.assertEqual(f.read(), 'label { color: red; }\n')

    def test_block_in_new_file_removes_file(self):
        path = os.path.join(self.dir, '.tmux.conf')
        changes.add_block(path, 'source-file x')
        changes.restore_all(lambda *_: None)
        self.assertFalse(os.path.exists(path))

    def test_set_line(self):
        path = os.path.join(self.dir, 'btop.conf')
        with open(path, 'w') as f:
            f.write('a = 1\ncolor_theme = "Default"\nb = 2\n')
        changes.set_line(path, 'color_theme', 'color_theme = "edex-tron"')
        # btop rewrites its file; our line must still be found and restored
        with open(path, 'w') as f:
            f.write('b = 3\ncolor_theme = "edex-tron"\n')
        changes.restore_all(lambda *_: None)
        with open(path) as f:
            self.assertEqual(f.read(), 'b = 3\ncolor_theme = "Default"\n')

    def test_json_key_keeps_comments(self):
        path = os.path.join(self.dir, 'settings.json')
        original = '{\n    // my font\n    "editor.fontSize": 14,\n    "workbench.colorTheme": "Default Dark+",\n}\n'
        with open(path, 'w') as f:
            f.write(original)
        self.assertTrue(changes.set_json_key(path, 'workbench.colorTheme', 'eDEX Tron'))
        with open(path) as f:
            text = f.read()
        self.assertIn('// my font', text)
        self.assertEqual(changes._read_jsonc(path)['workbench.colorTheme'], 'eDEX Tron')
        changes.restore_all(lambda *_: None)
        with open(path) as f:
            self.assertEqual(f.read(), original)

    def test_json_key_added_then_removed(self):
        path = os.path.join(self.dir, 'empty.json')
        with open(path, 'w') as f:
            f.write('{\n    "a": "b"\n}\n')
        changes.set_json_key(path, 'workbench.colorTheme', 'eDEX Tron')
        self.assertEqual(changes._read_jsonc(path), {'a': 'b', 'workbench.colorTheme': 'eDEX Tron'})
        changes.restore_all(lambda *_: None)
        self.assertEqual(changes._read_jsonc(path), {'a': 'b'})

    def test_unparseable_json_is_left_alone(self):
        path = os.path.join(self.dir, 'broken.json')
        with open(path, 'w') as f:
            f.write('{ nope')
        self.assertFalse(changes.set_json_key(path, 'k', 'v'))
        with open(path) as f:
            self.assertEqual(f.read(), '{ nope')


class Cursors(unittest.TestCase):
    def test_xcursor_header_and_toc(self):
        img, xh, yh = cursor.draw('default', 24, '#aacfd1', '#05080d')
        data = cursor.xcursor_bytes([(24, img, xh, yh, 0), (24, img, xh, yh, 0)])
        magic, header, version, ntoc = struct.unpack('<4sIII', data[:16])
        self.assertEqual((magic, header, ntoc), (b'Xcur', 16, 2))
        _type, subtype, pos = struct.unpack('<III', data[16:28])
        self.assertEqual((_type, subtype), (cursor.IMAGE_TYPE, 24))
        chunk = struct.unpack('<IIIIIIIII', data[pos:pos + 36])
        self.assertEqual(chunk[4:6], (24, 24))
        self.assertEqual(pos, 16 + 2 * 12)
        self.assertEqual(len(data), 16 + 2 * 12 + 2 * (36 + 24 * 24 * 4))

    def test_every_shape_draws(self):
        for shape in cursor.ALIASES:
            img, xh, yh = cursor.draw(shape, 32, '#aacfd1', '#05080d', 3, 12)
            self.assertEqual(img.size, (32, 32))
            self.assertTrue(0 <= xh < 32 and 0 <= yh < 32)
            self.assertIsNotNone(img.getbbox(), shape)

    def test_theme_links(self):
        dest = os.path.join(HOME, 'cursor-theme')
        cursor.build_theme(dest, '#aacfd1', '#05080d')
        self.assertTrue(os.path.islink(os.path.join(dest, 'cursors', 'left_ptr')))
        self.assertEqual(os.readlink(os.path.join(dest, 'cursors', 'hand2')), 'pointer')


class Dock(unittest.TestCase):
    def test_parse_skips_missing_and_comments(self):
        try:
            from edex_tron.hud import dock
        except (ImportError, ValueError) as e:
            self.skipTest(f'GTK not available: {e}')
        path = os.path.join(HOME, 'dock.txt')
        with open(path, 'w') as f:
            f.write('# comment\n\nHome | ~ \nNope | not-installed.desktop\n'
                    'Bad line\nShell | !sh -c true | utilities-terminal\nWeb | https://example.org\n')
        names = [e['name'] for e in dock.parse(path)]
        self.assertEqual(names, ['Home', 'Shell', 'Web'])


if __name__ == '__main__':
    unittest.main()
