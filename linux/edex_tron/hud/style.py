"""HUD stylesheet and font choice."""
import subprocess

from ..config import rgba


def _installed_families():
    try:
        out = subprocess.run(['fc-list', ':', 'family'], capture_output=True,
                             text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return set()
    fams = set()
    for line in out.splitlines():
        for f in line.split(','):
            fams.add(f.strip())
    return fams


def pick_fonts():
    """eDEX-UI's own fonts when the person has them, else Ubuntu's."""
    fams = _installed_families()

    def first(*names):
        for n in names:
            if n in fams:
                return n
        return names[-1]

    return {
        'main': first('United Sans Medium', 'United Sans Reg Medium', 'Ubuntu Sans', 'Cantarell', 'Sans'),
        'light': first('United Sans Light', 'UnitedSansReg-Light', 'Ubuntu Sans Light', 'Ubuntu Sans', 'Sans'),
        'mono': first('Fira Mono', 'FuraMono NF', 'Ubuntu Sans Mono', 'JetBrains Mono', 'DejaVu Sans Mono', 'Monospace'),
    }


def css(p, fonts, scale=1.0):
    def px(v):
        return f'{max(1, round(v * scale))}px'

    a = p['accent']
    return f"""
window.edex-hud, window.edex-hud > * {{
  background: transparent;
  color: {a};
  font-family: "{fonts['main']}";
  font-size: {px(13)};
}}
window.edex-hud.opaque {{ background: {p['bg']}; }}

.panel {{
  background: {rgba(p['bg'], 0.86)};
  padding: {px(6)} {px(8)} {px(8)} {px(8)};
}}
.panel-head {{ min-height: {px(20)}; }}
.panel-title {{
  font-size: {px(12)}; letter-spacing: 1px; color: {a};
}}
.panel-right {{ font-size: {px(12)}; color: {p['accent_dim']}; }}
button.panel-action {{
  font-size: {px(11)}; letter-spacing: 1px; min-height: 0;
  padding: 0 {px(6)}; border-radius: 0;
  background: transparent; color: {a};
  border: 1px solid {rgba(a, 0.45)};
  box-shadow: none;
}}
button.panel-action:hover {{ background: {rgba(a, 0.18)}; }}

.clock {{
  font-family: "{fonts['light']}"; font-size: {px(46)}; letter-spacing: 2px;
}}
.big {{ font-size: {px(20)}; }}
.kv-key {{ font-size: {px(10)}; color: {p['accent_dim']}; letter-spacing: 1px; }}
.kv-value {{ font-size: {px(13)}; }}
.mono, .mono label {{ font-family: "{fonts['mono']}"; font-size: {px(11)}; }}
.dim {{ color: {p['accent_dim']}; }}
.warn {{ color: {p['yellow']}; }}
.bad {{ color: {p['red']}; }}

.tabs {{ margin-bottom: {px(2)}; }}
.tabs button {{
  font-size: {px(11)}; letter-spacing: 1px; min-height: 0; border-radius: 0;
  padding: {px(2)} {px(10)}; box-shadow: none;
  background: transparent; color: {p['accent_dim']};
  border: none; border-bottom: 2px solid {rgba(a, 0.2)};
}}
.tabs button:checked {{ color: {p['bg']}; background: {a}; border-bottom-color: {a}; }}
.tabs button:hover {{ color: {a}; }}
vte-terminal {{ background: transparent; padding: {px(2)}; }}
.term-frame {{
  border: 1px solid {rgba(a, 0.35)};
  background: {rgba(p['bg'], 0.86)};
  padding: {px(6)};
}}

.tile {{
  background: transparent; border-radius: 0; box-shadow: none;
  border: 1px solid transparent; padding: {px(4)} {px(2)};
  color: {a};
}}
.tile:hover {{ border-color: {rgba(a, 0.5)}; background: {rgba(a, 0.10)}; }}
.tile label {{ font-size: {px(10)}; }}
.tile image {{ -gtk-icon-style: regular; }}
.tile.monochrome image {{ -gtk-icon-style: symbolic; color: {a}; }}
flowbox, flowboxchild {{ background: transparent; padding: 0; }}
flowboxchild:selected {{ background: transparent; }}

scrolledwindow, scrolledwindow > viewport {{ background: transparent; }}
scrollbar {{ background: transparent; }}
scrollbar slider {{ background: {rgba(a, 0.35)}; min-width: 3px; border-radius: 0; }}

popover contents, popover arrow {{
  background: {p['bg_raised']}; color: {a}; border: 1px solid {rgba(a, 0.45)}; border-radius: 0;
}}
popover modelbutton:hover {{ background: {rgba(a, 0.18)}; }}
"""
