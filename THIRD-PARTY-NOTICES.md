# Third-party notices

## eDEX-UI

eDEX-Tron is derived from **[eDEX-UI](https://github.com/GitSquared/edex-ui)**
by **Gabriel "Squared" Saillard** ([gaby.dev](https://gaby.dev)), licensed under
the GNU General Public License v3.0.

What this project takes from eDEX-UI:

- the `tron` colour palette (`themes/edex/tron.json`, copied unmodified)
- the visual language of its panels — caption rules with end ticks, the grid
  background, the module layout — reproduced from eDEX-UI's stylesheets
- the idea and arrangement of the home screen

eDEX-Tron is not affiliated with or endorsed by the eDEX-UI project. eDEX-UI is
archived upstream; please credit it when sharing this work.

## Not redistributed here

These are used only if eDEX-UI is already installed on your machine, in which
case setup copies them out of *your* install:

- **United Sans** — a commercial typeface by House Industries, bundled inside
  eDEX-UI. Without eDEX-UI, the theme uses Windows' own Bahnschrift and
  Consolas instead.
- **Fira Mono** (as bundled by eDEX-UI) — SIL Open Font License 1.1.
- **eDEX-UI sound effects** — part of eDEX-UI.

## Installed separately by setup

These are downloaded from their own publishers through `winget` and keep their
own licences; eDEX-Tron does not include them.

- [Rainmeter](https://www.rainmeter.net/) — GPL-2.0
- [TranslucentTB](https://github.com/TranslucentTB/TranslucentTB) — GPL-3.0
- [Python](https://www.python.org/) — PSF License
- [Pillow](https://python-pillow.org/), [NumPy](https://numpy.org/),
  [fontTools](https://github.com/fonttools/fonttools) — installed with `pip`
- [Windhawk](https://windhawk.net/) — optional, installed by you

## Linux edition

- The GNOME Shell extension keeps the HUD on the desktop layer using the
  technique from **[Desktop Icons NG](https://gitlab.com/rastersoft/desktop-icons-ng)**
  by Sergio Costas (GPL-3.0). No code is copied; the approach is credited.
- The package depends on software installed from Ubuntu's archive under its
  own licence: GTK 4 and VTE (LGPL), PyGObject (LGPL), psutil (BSD),
  Pillow (MIT-CMU), NumPy (BSD), and optionally starship (ISC),
  fastfetch (MIT), btop (Apache-2.0), tmux (ISC), qt6ct (BSD-2-Clause),
  GRUB (GPL-3.0) and Plymouth (GPL-2.0).
- The GRUB theme's fonts are converted at install time from the system's
  DejaVu Sans Mono (Bitstream Vera licence); none are shipped.
