"""eDEX-Tron for Linux (Ubuntu / GNOME).

A desktop theme based on eDEX-UI by Gabriel "Squared" Saillard (GPL-3.0).
"""
import os

PKG_DIR = os.path.dirname(os.path.abspath(__file__))
# Installed layout: /usr/share/edex-tron/{edex_tron,extension,data,shared}
# Source layout:    <repo>/linux/{edex_tron,extension,data}, shared = <repo>
APP_DIR = os.path.dirname(PKG_DIR)


def _version():
    for p in (os.path.join(APP_DIR, 'VERSION'),):
        try:
            with open(p) as f:
                return f.read().strip()
        except OSError:
            pass
    return '0.0.0'


VERSION = _version()
EXTENSION_UUID = 'edex-tron@mtv29.github.io'
APP_ID = 'io.github.mtv29.EdexTron'


def data_path(*parts):
    return os.path.join(APP_DIR, 'data', *parts)


def shared_path(*parts):
    """Files shared with the Windows edition (palette, generators, icon)."""
    installed = os.path.join(APP_DIR, 'shared', *parts)
    if os.path.exists(installed):
        return installed
    return os.path.join(os.path.dirname(APP_DIR), *parts)


def extension_source():
    return os.path.join(APP_DIR, 'extension', EXTENSION_UUID)
