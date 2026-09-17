"""Generated theme files: GTK, GNOME Shell, Qt, terminals and CLI tools.

Every renderer takes the palette from config.palette() and returns text.
"""
import colorsys

from .config import ansi16, rgb, rgba

# --- helpers -----------------------------------------------------------------


def hue_name(hex_colour, hues, grey):
    """Nearest named hue to a colour; `grey` for washed-out colours."""
    r, g, b = (v / 255 for v in rgb(hex_colour))
    h, _l, s = colorsys.rgb_to_hls(r, g, b)
    if s < 0.18:
        return grey
    deg = h * 360
    return min(hues, key=lambda n: abs((deg - hues[n] + 180) % 360 - 180))


GNOME_ACCENTS = {'red': 0, 'orange': 30, 'yellow': 50, 'green': 120, 'teal': 175,
                 'blue': 215, 'purple': 275, 'pink': 325}
YARU_VARIANTS = {'Yaru-red': 0, 'Yaru-wartybrown': 30, 'Yaru-yellow': 50, 'Yaru-olive': 80,
                 'Yaru-sage': 150, 'Yaru-prussiangreen': 185, 'Yaru-blue': 215,
                 'Yaru-purple': 275, 'Yaru-magenta': 320}


def gnome_accent(p):
    return hue_name(p['accent'], GNOME_ACCENTS, 'slate')


def yaru_dark(p):
    return hue_name(p['accent'], YARU_VARIANTS, 'Yaru') + '-dark'


# --- GTK 4 / libadwaita -------------------------------------------------------------

def gtk4_css(p):
    a, bg = p['accent'], p['bg']
    colours = {
        'accent-bg-color': a, 'accent-fg-color': p['on_accent'], 'accent-color': p['accent_bright'],
        'window-bg-color': bg, 'window-fg-color': p['accent_pale'],
        'view-bg-color': p['bg_sunken'], 'view-fg-color': p['accent_pale'],
        'headerbar-bg-color': p['bg_raised'], 'headerbar-fg-color': a,
        'headerbar-backdrop-color': bg, 'headerbar-border-color': p['accent_dim'],
        'headerbar-shade-color': rgba(a, 0.18), 'headerbar-darker-shade-color': rgba(a, 0.30),
        'sidebar-bg-color': p['bg_raised'], 'sidebar-fg-color': p['accent_pale'],
        'sidebar-backdrop-color': bg, 'sidebar-border-color': rgba(a, 0.25),
        'sidebar-shade-color': rgba('#000000', 0.36),
        'secondary-sidebar-bg-color': bg, 'secondary-sidebar-fg-color': p['accent_pale'],
        'secondary-sidebar-backdrop-color': bg, 'secondary-sidebar-border-color': rgba(a, 0.2),
        'card-bg-color': rgba(a, 0.06), 'card-fg-color': p['accent_pale'],
        'card-shade-color': rgba('#000000', 0.36),
        'thumbnail-bg-color': p['bg_high'], 'thumbnail-fg-color': p['accent_pale'],
        'dialog-bg-color': p['bg_raised'], 'dialog-fg-color': p['accent_pale'],
        'popover-bg-color': p['bg_raised'], 'popover-fg-color': p['accent_pale'],
        'popover-shade-color': rgba('#000000', 0.25),
        'shade-color': rgba('#000000', 0.36), 'scrollbar-outline-color': rgba('#000000', 0.5),
        'destructive-bg-color': p['red'], 'destructive-fg-color': '#000000', 'destructive-color': p['red_b'],
        'success-bg-color': p['green'], 'success-fg-color': '#000000', 'success-color': p['green_b'],
        'warning-bg-color': p['yellow'], 'warning-fg-color': '#000000', 'warning-color': p['yellow_b'],
        'error-bg-color': p['red'], 'error-fg-color': '#000000', 'error-color': p['red_b'],
        'border-color': rgba(a, 0.22),
    }
    lines = ['/* eDEX-Tron colours for GTK 4 / libadwaita apps (generated). */', ':root {']
    lines += [f'  --{k}: {v};' for k, v in colours.items()]
    lines.append('}')
    # older libadwaita and plain GTK 4 apps still read named colours
    lines += [f'@define-color {k.replace("-", "_")} {v};' for k, v in colours.items()]
    lines += [
        '',
        'headerbar { box-shadow: inset 0 -1px ' + rgba(a, 0.35) + '; }',
        'window.background, .background { background-color: ' + bg + '; }',
        'textview text, .view { background-color: ' + p['bg_sunken'] + '; }',
        'selection, *:selected { background-color: ' + rgba(a, 0.35) + '; }',
        'switch:checked, checkbutton check:checked, radio:checked { background-color: ' + a + '; }',
        'progressbar progress, scale highlight { background-color: ' + a + '; }',
    ]
    return '\n'.join(lines) + '\n'


# --- GTK 3 (on top of Yaru dark) ---------------------------------------------------

def gtk3_css(p):
    a, bg = p['accent'], p['bg']
    named = {
        'theme_bg_color': bg, 'theme_fg_color': p['accent_pale'],
        'theme_base_color': p['bg_sunken'], 'theme_text_color': p['accent_pale'],
        'theme_selected_bg_color': a, 'theme_selected_fg_color': p['on_accent'],
        'insensitive_bg_color': bg, 'insensitive_fg_color': p['accent_dim'],
        'theme_unfocused_bg_color': bg, 'theme_unfocused_fg_color': p['accent_dim'],
        'borders': rgba(a, 0.25), 'accent_color': a, 'accent_bg_color': a,
        'headerbar_bg_color': p['bg_raised'], 'window_bg_color': bg, 'view_bg_color': p['bg_sunken'],
    }
    lines = ['/* eDEX-Tron colours for GTK 3 apps (generated). */']
    lines += [f'@define-color {k} {v};' for k, v in named.items()]
    lines += [
        'window, .background { background-color: ' + bg + '; color: ' + p['accent_pale'] + '; }',
        'headerbar, .titlebar { background: ' + p['bg_raised'] + '; color: ' + a
        + '; box-shadow: inset 0 -1px ' + rgba(a, 0.35) + '; border-color: ' + rgba(a, 0.3) + '; }',
        '.view, textview text, treeview, iconview { background-color: ' + p['bg_sunken'] + '; }',
        '*:selected, selection { background-color: ' + rgba(a, 0.35) + '; }',
        'switch:checked, check:checked, radio:checked, progressbar progress, scale highlight '
        '{ background-color: ' + a + '; border-color: ' + a + '; }',
    ]
    return '\n'.join(lines) + '\n'


# --- GNOME Shell ----------------------------------------------------------------

def shell_css(p):
    """Loaded by the extension on top of Ubuntu's Yaru shell theme.
    Yaru marks some rules !important, so these do too."""
    a, bg = p['accent'], p['bg']
    panel_bg = rgba(bg, 0.92)
    menu_bg = rgba(p['bg_raised'], 0.97)
    line = rgba(a, 0.45)
    hover = rgba(a, 0.16)
    active = rgba(a, 0.28)
    return f"""/* eDEX-Tron GNOME Shell colours (generated; loaded by the edex-tron extension). */

/* top bar */
#panel {{ background-color: {panel_bg} !important; border-bottom: 1px solid {line}; }}
#panel .panel-button {{ color: {a} !important; border-radius: 0 !important; }}
#panel .panel-button:hover {{ background-color: {hover} !important; }}
#panel .panel-button:active, #panel .panel-button:checked,
#panel .panel-button:focus {{ background-color: {active} !important; box-shadow: none !important; }}
#panel .panel-button.clock-display .clock {{ color: {a} !important; letter-spacing: 1px; }}
#panel .panel-button#panelActivities .workspace-dot {{ background-color: {a} !important; }}
#panel .system-status-icon {{ color: {a} !important; }}

/* menus, quick settings, calendar */
.popup-menu-content, .quick-settings, .datemenu-popover .popup-menu-content {{
  background-color: {menu_bg} !important; color: {p['accent_pale']} !important;
  border: 1px solid {line} !important; border-radius: 4px !important;
  box-shadow: 0 0 18px {rgba(a, 0.18)} !important;
}}
.popup-menu-item {{ color: {p['accent_pale']} !important; }}
.popup-menu-item:hover, .popup-menu-item:focus {{ background-color: {hover} !important; color: {p['accent_white']} !important; }}
.popup-menu-item:active, .popup-menu-item:checked {{ background-color: {active} !important; }}
.popup-separator-menu-item .popup-separator-menu-item-separator {{ background-color: {rgba(a, 0.2)} !important; }}
.quick-toggle, .quick-menu-toggle .quick-toggle, .quick-toggle-arrow, .icon-button,
.quick-settings-system-item .icon-button {{
  background-color: {rgba(a, 0.08)} !important; color: {p['accent_pale']} !important;
}}
.quick-toggle:hover, .icon-button:hover, .quick-toggle-arrow:hover {{ background-color: {hover} !important; }}
.quick-toggle:checked, .quick-menu-toggle .quick-toggle:checked,
.quick-menu-toggle .quick-toggle-arrow:checked {{
  background-color: {a} !important; color: {p['on_accent']} !important;
}}
.quick-toggle-menu {{ background-color: {p['bg_high']} !important; }}
.slider {{
  -barlevel-active-background-color: {a} !important;
  -barlevel-background-color: {rgba(a, 0.18)} !important;
  -slider-handle-border-color: {a} !important;
  color: {p['accent_white']} !important;
}}
.toggle-switch:checked {{ background-color: {a} !important; }}
.calendar {{ background-color: transparent !important; }}
.calendar .calendar-day.calendar-today, .datemenu-today-button:hover {{
  background-color: {a} !important; color: {p['on_accent']} !important;
}}
.calendar .calendar-day:hover {{ background-color: {hover} !important; }}
.calendar .calendar-day-heading, .calendar .calendar-week-number {{ color: {p['accent_dim']} !important; }}
.message, .notification-banner, .message-list .message {{
  background-color: {rgba(p['bg_raised'], 0.97)} !important; color: {p['accent_pale']} !important;
  border: 1px solid {rgba(a, 0.3)} !important;
}}
.message:hover {{ background-color: {p['bg_high']} !important; }}
.message .message-title {{ color: {a} !important; }}

/* dialogs, OSDs, switchers */
.modal-dialog, .end-session-dialog, .run-dialog, .prompt-dialog {{
  background-color: {menu_bg} !important; color: {p['accent_pale']} !important;
  border: 1px solid {line} !important;
}}
.modal-dialog .modal-dialog-button-box .modal-dialog-button:hover {{ background-color: {hover} !important; }}
.button.default, .modal-dialog-button.default {{ background-color: {a} !important; color: {p['on_accent']} !important; }}
.osd-window, .switcher-list, .workspace-switcher, .resize-popup {{
  background-color: {menu_bg} !important; color: {a} !important; border: 1px solid {line} !important;
}}
.switcher-list .item-box:selected, .switcher-list .item-box:outlined {{
  background-color: {active} !important; border-color: {a} !important;
}}
.search-entry, .run-dialog-entry, StEntry {{
  background-color: {rgba(bg, 0.85)} !important; color: {p['accent_white']} !important;
  border: 1px solid {rgba(a, 0.35)} !important; selection-background-color: {rgba(a, 0.45)} !important;
  caret-color: {a} !important;
}}
.search-entry:focus, StEntry:focus {{ border-color: {a} !important; }}

/* overview and app grid */
.overview-tile:hover, .overview-tile:focus, .grid-search-result:hover {{ background-color: {hover} !important; }}
.overview-tile:active, .overview-tile:checked, .grid-search-result:active {{ background-color: {active} !important; }}
.app-folder-dialog {{ background-color: {menu_bg} !important; border: 1px solid {line} !important; }}
.page-indicator .page-indicator-icon {{ background-color: {a} !important; }}
.workspace-thumbnail-indicator {{ border-color: {a} !important; }}
.window-caption {{ background-color: {menu_bg} !important; color: {a} !important; }}
.app-grid-running-dot, #dash .app-grid-running-dot {{ background-color: {a} !important; }}

/* Ubuntu Dock */
#dashtodockContainer #dash .dash-background {{
  background-color: {rgba(bg, 0.85)} !important;
  border: 1px solid {rgba(a, 0.28)} !important;
}}
#dashtodockContainer .dash-item-container .app-well-app:hover .overview-icon,
#dashtodockContainer .dash-item-container .show-apps:hover .overview-icon {{ background-color: {hover} !important; }}

/* lock screen */
#lockDialogGroup {{ background-color: {bg} !important; }}
.unlock-dialog-clock-time {{ color: {a} !important; font-weight: 300 !important; letter-spacing: 4px; }}
.unlock-dialog-clock-date, .unlock-dialog-clock-hint {{ color: {p['accent_pale']} !important; }}
.unlock-dialog .login-dialog-prompt-entry, .unlock-dialog StEntry {{
  background-color: {rgba(bg, 0.8)} !important; border: 1px solid {a} !important;
}}
.unlock-dialog .user-widget-label, .unlock-dialog .login-dialog-user-list-item {{ color: {a} !important; }}
"""


# --- Qt (qt6ct / qt5ct colour scheme) -------------------------------------------

def qt_colors(p):
    """qt5ct/qt6ct scheme: 21 roles x active/disabled/inactive, as #AARRGGBB."""
    def c(h, alpha=255):
        return '#%02x%s' % (alpha, h.lstrip('#'))
    a, bg = p['accent'], p['bg']
    fg = p['accent_pale']
    # WindowText Button Light Midlight Dark Mid Text BrightText ButtonText Base
    # Window Shadow Highlight HighlightedText Link LinkVisited AlternateBase
    # NoRole ToolTipBase ToolTipText PlaceholderText
    active = [fg, p['bg_high'], p['accent_dim'], p['bg_high'], p['bg_sunken'], p['bg_raised'],
              fg, p['accent_white'], fg, p['bg_sunken'], bg, '#000000', a, p['on_accent'],
              p['accent_bright'], p['purple'], p['bg_raised'], bg, p['bg_raised'], a,
              p['accent_dim']]
    disabled = list(active)
    for i in (0, 6, 8, 20):
        disabled[i] = p['accent_dim']
    row = lambda cols: ', '.join(c(x) for x in cols)  # noqa: E731
    return ('[ColorScheme]\n'
            f'active_colors={row(active)}\n'
            f'disabled_colors={row(disabled)}\n'
            f'inactive_colors={row(active)}\n')


def qtct_conf(scheme_path):
    """qt5ct.conf / qt6ct.conf (same format); fonts are left to the defaults."""
    return (f'[Appearance]\ncolor_scheme_path={scheme_path}\ncustom_palette=true\n'
            f'icon_theme=Yaru-dark\nstandard_dialogs=gtk3\nstyle=Fusion\n')


# --- terminals ------------------------------------------------------------------------

def ptyxis_palette(p):
    cols = ansi16(p)
    body = [f'Foreground={p["accent"]}', f'Background={p["bg"]}', f'Cursor={p["accent"]}']
    body += [f'Color{i}={c}' for i, c in enumerate(cols)]
    block = '\n'.join(body)
    return f'[Palette]\nName=eDEX Tron\nPrimary=true\n\n[Light]\n{block}\n\n[Dark]\n{block}\n'


def gnome_terminal_palette(p):
    return '[' + ', '.join(f"'{c}'" for c in ansi16(p)) + ']'


# --- CLI tools ------------------------------------------------------------------------

def starship_toml(p):
    a = p['accent']
    return f'''# eDEX-Tron prompt (generated). Your own ~/.config/starship.toml is not used
# inside eDEX-Tron shells; set EDEX_TRON_PROMPT=0 to turn this prompt off.
add_newline = false
format = """
[┌─](fg:{p['accent_dim']})$username[@](fg:{p['accent_dim']})$hostname [─](fg:{p['accent_dim']}) $directory$git_branch$git_status$python$nodejs$rust$golang$cmd_duration
[└─](fg:{p['accent_dim']})$status$character"""

[username]
show_always = true
format = "[$user]({a} bold)"
style_root = "{p['red']} bold"

[hostname]
ssh_only = false
format = "[$hostname]({a})"

[directory]
style = "{p['accent_bright']}"
format = "[$path]($style)[$read_only]({p['yellow']}) "
truncation_length = 4
truncate_to_repo = false

[git_branch]
format = "[⎇ $branch]({p['accent_pale']}) "

[git_status]
format = "[$all_status$ahead_behind]({p['yellow']}) "

[cmd_duration]
format = "[took $duration]({p['accent_dim']}) "

[status]
disabled = false
format = "[✕ $status]({p['red']}) "

[character]
success_symbol = "[>]({a} bold)"
error_symbol = "[>]({p['red']} bold)"

[python]
format = "[py $version]({p['accent_dim']}) "
[nodejs]
format = "[node $version]({p['accent_dim']}) "
[rust]
format = "[rs $version]({p['accent_dim']}) "
[golang]
format = "[go $version]({p['accent_dim']}) "
'''


LOGO = r'''
$1 ███████╗██████╗ ███████╗██╗  ██╗
$1 ██╔════╝██╔══██╗██╔════╝╚██╗██╔╝
$1 █████╗  ██║  ██║█████╗   ╚███╔╝
$1 ██╔══╝  ██║  ██║██╔══╝   ██╔██╗
$1 ███████╗██████╔╝███████╗██╔╝ ██╗
$1 ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝
$2      T R O N   ·   L I N U X
'''


def fastfetch_logo():
    return LOGO.lstrip('\n')


def fastfetch_jsonc(p, logo_path):
    import json
    cfg = {
        '$schema': 'https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json',
        'logo': {'type': 'file', 'source': logo_path,
                 'color': {'1': p['accent'], '2': p['accent_dim']},
                 'padding': {'top': 1, 'right': 3}},
        'display': {'separator': '  ', 'color': {'keys': p['accent'], 'title': p['accent_bright']},
                    'key': {'width': 10}},
        'modules': [
            'title', 'separator',
            {'type': 'os', 'key': 'OS'}, {'type': 'kernel', 'key': 'KERNEL'},
            {'type': 'uptime', 'key': 'UPTIME'}, {'type': 'shell', 'key': 'SHELL'},
            {'type': 'de', 'key': 'DESKTOP'}, {'type': 'cpu', 'key': 'CPU'},
            {'type': 'gpu', 'key': 'GPU'}, {'type': 'memory', 'key': 'MEMORY'},
            {'type': 'disk', 'key': 'DISK', 'folders': '/'},
            {'type': 'localip', 'key': 'LOCAL IP', 'compact': True},
            'break', {'type': 'colors', 'symbol': 'block'},
        ],
    }
    return '// eDEX-Tron fastfetch layout (generated)\n' + json.dumps(cfg, indent=2) + '\n'


def btop_theme(p):
    a, bg = p['accent'], p['bg']
    t = {
        'main_bg': bg, 'main_fg': p['accent_pale'], 'title': a, 'hi_fg': p['accent_white'],
        'selected_bg': p['bg_high'], 'selected_fg': a, 'inactive_fg': p['accent_dim'],
        'graph_text': p['accent_dim'], 'meter_bg': p['bg_high'], 'proc_misc': p['accent_bright'],
        'cpu_box': a, 'mem_box': a, 'net_box': a, 'proc_box': a, 'div_line': p['accent_faint'],
        'temp_start': p['accent_dim'], 'temp_mid': a, 'temp_end': p['red'],
        'cpu_start': p['accent_dim'], 'cpu_mid': a, 'cpu_end': p['accent_white'],
        'free_start': p['accent_faint'], 'free_mid': p['accent_dim'], 'free_end': a,
        'cached_start': p['accent_faint'], 'cached_mid': p['accent_dim'], 'cached_end': a,
        'available_start': p['accent_faint'], 'available_mid': p['accent_dim'], 'available_end': a,
        'used_start': p['accent_dim'], 'used_mid': a, 'used_end': p['accent_white'],
        'download_start': p['accent_faint'], 'download_mid': p['accent_dim'], 'download_end': a,
        'upload_start': p['accent_faint'], 'upload_mid': p['accent_dim'], 'upload_end': p['accent_bright'],
        'process_start': p['accent_dim'], 'process_mid': a, 'process_end': p['accent_white'],
    }
    return '# eDEX-Tron btop theme (generated)\n' + ''.join(f'theme[{k}]="{v}"\n' for k, v in t.items())


def tmux_conf(p):
    a, bg = p['accent'], p['bg']
    return f'''# eDEX-Tron tmux colours (generated)
set -g status-style "bg={bg},fg={a}"
set -g status-left "#[fg={bg},bg={a},bold] #S #[bg={bg}] "
set -g status-right "#[fg={p['accent_dim']}]%H:%M  #[fg={a}]#h "
set -g status-left-length 30
set -g window-status-format " #I:#W "
set -g window-status-current-format "#[fg={bg},bg={p['accent_bright']},bold] #I:#W "
set -g pane-border-style "fg={p['accent_faint']}"
set -g pane-active-border-style "fg={a}"
set -g message-style "bg={p['bg_high']},fg={a}"
set -g mode-style "bg={a},fg={bg}"
set -g clock-mode-colour "{a}"
'''


def nvim_colors(p):
    a, bg = p['accent'], p['bg']
    groups = {
        'Normal': {'fg': p['accent_pale'], 'bg': bg}, 'NormalFloat': {'fg': p['accent_pale'], 'bg': p['bg_raised']},
        'FloatBorder': {'fg': a, 'bg': p['bg_raised']}, 'Comment': {'fg': p['accent_dim'], 'italic': True},
        'Constant': {'fg': p['accent_bright']}, 'String': {'fg': p['green']}, 'Number': {'fg': p['yellow']},
        'Identifier': {'fg': p['accent_pale']}, 'Function': {'fg': a, 'bold': True},
        'Statement': {'fg': p['accent_white'], 'bold': True}, 'Keyword': {'fg': p['accent_white'], 'bold': True},
        'PreProc': {'fg': p['purple']}, 'Type': {'fg': p['blue']}, 'Special': {'fg': p['accent_bright']},
        'Error': {'fg': p['red']}, 'ErrorMsg': {'fg': p['red']}, 'WarningMsg': {'fg': p['yellow']},
        'Todo': {'fg': bg, 'bg': p['yellow']}, 'CursorLine': {'bg': p['bg_raised']},
        'CursorLineNr': {'fg': a, 'bold': True}, 'LineNr': {'fg': p['accent_faint']},
        'Visual': {'bg': p['bg_high']}, 'Search': {'fg': bg, 'bg': a}, 'IncSearch': {'fg': bg, 'bg': p['accent_white']},
        'StatusLine': {'fg': bg, 'bg': a}, 'StatusLineNC': {'fg': p['accent_dim'], 'bg': p['bg_raised']},
        'VertSplit': {'fg': p['accent_faint']}, 'WinSeparator': {'fg': p['accent_faint']},
        'Pmenu': {'fg': p['accent_pale'], 'bg': p['bg_raised']}, 'PmenuSel': {'fg': bg, 'bg': a},
        'SignColumn': {'bg': bg}, 'MatchParen': {'fg': p['accent_white'], 'bold': True, 'underline': True},
        'DiagnosticError': {'fg': p['red']}, 'DiagnosticWarn': {'fg': p['yellow']},
        'DiagnosticInfo': {'fg': p['blue']}, 'DiagnosticHint': {'fg': p['accent_dim']},
        'DiffAdd': {'fg': p['green']}, 'DiffDelete': {'fg': p['red']}, 'DiffChange': {'fg': p['yellow']},
    }

    def lua(v):
        return 'true' if v is True else f"'{v}'"
    lines = ['-- eDEX-Tron colours for Neovim (generated). Use with :colorscheme edex-tron',
             "vim.cmd('highlight clear')", "vim.o.background = 'dark'",
             "vim.g.colors_name = 'edex-tron'", 'local set = vim.api.nvim_set_hl']
    for name, spec in groups.items():
        body = ', '.join(f'{k} = {lua(v)}' for k, v in spec.items())
        lines.append(f"set(0, '{name}', {{ {body} }})")
    for i, c in enumerate(ansi16(p)):
        lines.append(f"vim.g.terminal_color_{i} = '{c}'")
    return '\n'.join(lines) + '\n'


def shell_block(gen_dir, shell='bash'):
    init = {'bash': 'starship init bash', 'zsh': 'starship init zsh'}[shell]
    return f'''if [[ $- == *i* ]]; then
  export EDEX_TRON_THEME=1
  if [ "${{EDEX_TRON_PROMPT:-1}}" = 1 ] && command -v starship >/dev/null 2>&1; then
    export STARSHIP_CONFIG="{gen_dir}/starship.toml"
    eval "$({init})"
  fi
  if [ -n "${{EDEX_TRON_HUD:-}}" ] && command -v fastfetch >/dev/null 2>&1; then
    fastfetch --config "{gen_dir}/fastfetch.jsonc"
  fi
  unset EDEX_TRON_HUD
fi'''
