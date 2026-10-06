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
- **the sound effects** in `assets\sounds\` — `granted.wav`,
  `keyboard.wav`, `stdin.wav` and the rest. They were composed for eDEX-UI
  v2.1.x and above by **IceWolf**
  ([soundcloud.com/iamicewolf](https://soundcloud.com/iamicewolf)) and are
  redistributed here under eDEX-UI's GPL-3.0. Please keep the credit if you
  fork this; he makes really cool stuff, go and listen to it.

eDEX-Tron is not affiliated with or endorsed by the eDEX-UI project. eDEX-UI is
archived upstream; please credit it when sharing this work.

## Not redistributed here

These are used only if eDEX-UI is already installed on your machine, in which
case setup copies them out of *your* install:

- **United Sans** — a commercial typeface by House Industries, bundled inside
  eDEX-UI. Without eDEX-UI, the theme uses Windows' own Bahnschrift and
  Consolas instead.

## Fonts shipped with the project

In `assets\fonts\`, with their licences beside them. Both are under the SIL
Open Font License 1.1, which permits redistribution, so unlike United Sans
these do not need an eDEX-UI install.

- **Fira Mono** — digitized data copyright Mozilla Foundation and Telefonica
  S.A.; the copy here is the Nerd Font patched build eDEX-UI bundles, which
  declares itself `FuraMono NF`. Licence: `LICENSE-FiraMono.txt`.
- **Fira Code** — copyright The Fira Code Project Authors
  ([github.com/tonsky/FiraCode](https://github.com/tonsky/FiraCode)), Fira Mono
  with programming ligatures. Licence: `LICENSE-FiraCode.txt`.

## Boot audio

`assets\sounds\boot.mp3` is the boot sequence from **Watch Dogs**, a game by
**Ubisoft**, who own it. It is included here because it is what the boot screen
was built around, and it is credited rather than passed off as ours; no claim of
ownership or of permission is made, and Ubisoft are welcome to ask for it to be
removed. The boot screen does not need it: `bootsound` in `theme.json` points
at any file you like, and with none it plays silently.

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
