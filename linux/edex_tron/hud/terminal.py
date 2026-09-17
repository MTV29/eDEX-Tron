"""The main shell: real terminals (VTE) in eDEX-style tabs.

The file browser follows the active tab's working directory. That is read
from /proc/<shell pid>/cwd, so it works for bash, zsh and fish alike without
any shell integration.
"""
import os
import pwd

import gi

gi.require_version('Vte', '3.91')
from gi.repository import Gdk, GLib, Gtk, Pango, Vte  # noqa: E402

from ..config import ansi16  # noqa: E402
from .widgets import Panel, rgba  # noqa: E402

MAX_TABS = 5


def user_shell():
    shell = os.environ.get('SHELL')
    if not shell:
        try:
            shell = pwd.getpwuid(os.getuid()).pw_shell
        except KeyError:
            shell = '/bin/bash'
    return shell if os.path.exists(shell) else '/bin/sh'


class Term(Vte.Terminal):
    def __init__(self, palette, font, first=False, on_exit=None, cwd=None):
        super().__init__()
        self.pid = None
        self.first = first
        self.on_exit = on_exit
        self.set_hexpand(True)
        self.set_vexpand(True)
        self.set_scrollback_lines(10000)
        self.set_mouse_autohide(True)
        self.set_cursor_blink_mode(Vte.CursorBlinkMode.ON)
        self.set_cursor_shape(Vte.CursorShape.BLOCK)
        self.set_font(Pango.FontDescription.from_string(font))
        self.set_clear_background(False)
        self.apply_palette(palette)
        self.connect('child-exited', self._exited)
        self._shortcuts()
        self.spawn(cwd)

    def apply_palette(self, p):
        self.set_colors(rgba(p['accent']), rgba(p['bg'], 0.0),
                        [rgba(c) for c in ansi16(p)])
        self.set_color_cursor(rgba(p['accent']))
        self.set_color_cursor_foreground(rgba(p['bg']))
        self.set_color_highlight(rgba(p['accent'], 0.35))
        self.set_color_highlight_foreground(rgba(p['accent_white']))

    def spawn(self, cwd=None):
        env = [f'{k}={v}' for k, v in os.environ.items()
               if k not in ('EDEX_TRON_HUD', 'COLUMNS', 'LINES')]
        env.append('TERM_PROGRAM=edex-tron')
        if self.first:
            # the shell block setup adds shows the fetch screen once, here
            env.append('EDEX_TRON_HUD=1')
        shell = user_shell()
        self.spawn_async(
            Vte.PtyFlags.DEFAULT, cwd or os.path.expanduser('~'),
            [shell], env, GLib.SpawnFlags.DEFAULT,
            None, None, -1, None, self._spawned)

    def _spawned(self, _term, pid, error, *_):
        if error is not None:
            self.feed(f'\r\n[eDEX-Tron] could not start the shell: {error.message}\r\n'.encode())
            return
        self.pid = pid

    def _exited(self, *_):
        self.pid = None
        if self.on_exit:
            self.on_exit(self)

    def cwd(self):
        uri = self.get_current_directory_uri()
        if uri:
            path = GLib.filename_from_uri(uri)[0]
            if path and os.path.isdir(path):
                return path
        if self.pid:
            try:
                return os.readlink(f'/proc/{self.pid}/cwd')
            except OSError:
                pass
        return None

    def cd(self, path):
        quoted = GLib.shell_quote(path)
        # Ctrl+E Ctrl+U clears whatever was half-typed first
        self.feed_child(f'\x05\x15cd -- {quoted}\r'.encode())
        self.grab_focus()

    def _shortcuts(self):
        ctl = Gtk.ShortcutController()
        mods = Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK

        def add(key, fn):
            ctl.add_shortcut(Gtk.Shortcut.new(
                Gtk.KeyvalTrigger.new(key, mods),
                Gtk.CallbackAction.new(lambda *_: fn() or True)))

        add(Gdk.KEY_C, lambda: self.copy_clipboard_format(Vte.Format.TEXT))
        add(Gdk.KEY_V, self.paste_clipboard)
        add(Gdk.KEY_plus, lambda: self.set_font_scale(self.get_font_scale() * 1.1))
        add(Gdk.KEY_underscore, lambda: self.set_font_scale(self.get_font_scale() / 1.1))
        self.add_controller(ctl)


class Shell(Panel):
    """MAIN SHELL with up to five tabs, like eDEX-UI."""

    def __init__(self, palette, font, on_cwd):
        super().__init__('Terminal', 'MAIN SHELL')
        self.palette, self.font, self.on_cwd = palette, font, on_cwd
        self.tabs_box = Gtk.Box(spacing=0)
        self.tabs_box.add_css_class('tabs')
        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        frame.add_css_class('term-frame')
        frame.set_vexpand(True)
        frame.append(self.stack)
        self.add(self.tabs_box)
        self.add(frame)
        self.buttons = []
        self.terms = []
        self.add_btn = Gtk.Button(label='+')
        self.add_btn.set_tooltip_text('New shell (Ctrl+Shift+T)')
        self.add_btn.connect('clicked', lambda *_: self.new_tab())
        self.tabs_box.append(self.add_btn)
        self.last_cwd = None
        self.new_tab(first=True)
        GLib.timeout_add(700, self._poll_cwd)

        ctl = Gtk.ShortcutController()
        ctl.set_scope(Gtk.ShortcutScope.MANAGED)
        mods = Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK
        ctl.add_shortcut(Gtk.Shortcut.new(Gtk.KeyvalTrigger.new(Gdk.KEY_T, mods),
                                          Gtk.CallbackAction.new(lambda *_: self.new_tab() or True)))
        ctl.add_shortcut(Gtk.Shortcut.new(Gtk.KeyvalTrigger.new(Gdk.KEY_Page_Down, Gdk.ModifierType.CONTROL_MASK),
                                          Gtk.CallbackAction.new(lambda *_: self.cycle(1) or True)))
        ctl.add_shortcut(Gtk.Shortcut.new(Gtk.KeyvalTrigger.new(Gdk.KEY_Page_Up, Gdk.ModifierType.CONTROL_MASK),
                                          Gtk.CallbackAction.new(lambda *_: self.cycle(-1) or True)))
        self.add_controller(ctl)

    # --- tabs ---------------------------------------------------------------
    def new_tab(self, first=False):
        if len(self.terms) >= MAX_TABS:
            return
        cwd = None if first else (self.current().cwd() if self.terms else None)
        term = Term(self.palette, self.font, first=first, on_exit=self._closed, cwd=cwd)
        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw.set_child(term)
        self.stack.add_child(sw)
        group = self.buttons[0] if self.buttons else None
        btn = Gtk.ToggleButton(label='MAIN SHELL' if first else f'#{len(self.terms) + 1}')
        if group:
            btn.set_group(group)
        btn.connect('toggled', self._tab_toggled, sw, term)
        self.tabs_box.insert_child_after(btn, self.buttons[-1] if self.buttons else None)
        self.buttons.append(btn)
        self.terms.append(term)
        btn.set_active(True)
        self.add_btn.set_sensitive(len(self.terms) < MAX_TABS)

    def _tab_toggled(self, btn, sw, term):
        if btn.get_active():
            self.stack.set_visible_child(sw)
            self.set_right(btn.get_label())
            term.grab_focus()
            self._poll_cwd()

    def current(self):
        for btn, term in zip(self.buttons, self.terms):
            if btn.get_active():
                return term
        return self.terms[0]

    def cycle(self, step):
        i = self.terms.index(self.current())
        self.buttons[(i + step) % len(self.buttons)].set_active(True)

    def _closed(self, term):
        i = self.terms.index(term)
        if i == 0:
            # the main shell always comes back, as in eDEX-UI
            term.reset(True, True)
            term.spawn()
            return
        btn = self.buttons.pop(i)
        self.terms.pop(i)
        self.tabs_box.remove(btn)
        self.stack.remove(term.get_parent())
        self.buttons[max(0, i - 1)].set_active(True)
        for n, b in enumerate(self.buttons[1:], start=2):
            b.set_label(f'#{n}')
        self.add_btn.set_sensitive(True)

    def _poll_cwd(self):
        path = self.current().cwd()
        if path and path != self.last_cwd:
            self.last_cwd = path
            self.on_cwd(path)
        return True

    def tick(self):
        pass

    def cd(self, path):
        self.current().cd(path)

    def focus(self):
        self.current().grab_focus()

    def apply_palette(self, p):
        self.palette = p
        for t in self.terms:
            t.apply_palette(p)
