"""Where the watts come from, with no GTK in sight.

Kept apart from hud/panels.py so the arithmetic can be tested without a
desktop, a battery or a particular kernel: every function here takes the
numbers it needs rather than reading them itself, and the reading is done in
one small place at the bottom.

Three sources, in the order they are worth having:

  /sys/class/power_supply/BAT*/power_now   what the machine is drawing from
                                           the battery, in microwatts
  /sys/class/powercap/intel-rapl:0/        Intel RAPL, a microjoule counter;
    energy_uj                              watts are the difference over time
  nvidia-smi --query-gpu=power.draw        the card, where the tools exist

RAPL is a counter, not a gauge, so a single read says nothing -- two reads and
the seconds between them say everything. It also wraps, and on most kernels
since 2020 it is root-only (reading it finely enough leaks AES keys), so
"unavailable" is an ordinary outcome rather than an error.
"""
import glob
import os
import subprocess
import time

BAT_GLOB = '/sys/class/power_supply/BAT*'
RAPL_GLOB = '/sys/class/powercap/intel-rapl:[0-9]*'


def watts_from_microwatts(uw):
    """power_now is in microwatts; some firmware reports it negative on
    discharge and some reports the magnitude. The sign is not information."""
    if uw is None:
        return None
    return abs(float(uw)) / 1_000_000.0


def watts_from_energy(before_uj, after_uj, seconds, wrap_at=None):
    """Average watts between two RAPL readings.

    Returns None rather than a number when the pair cannot mean anything: no
    time between them, or a counter that went backwards without a wrap point
    to explain it.
    """
    if before_uj is None or after_uj is None or not seconds or seconds <= 0:
        return None
    delta = after_uj - before_uj
    if delta < 0:
        if not wrap_at:
            return None
        delta += wrap_at
        if delta < 0:
            return None
    return (delta / 1_000_000.0) / seconds


def format_watts(w):
    if w is None:
        return '--'
    if w >= 100:
        return f'{w:.0f}W'
    return f'{w:.1f}W'


def format_remaining(seconds):
    """psutil gives seconds, or a sentinel when it does not know."""
    if seconds is None or seconds < 0 or seconds > 60 * 60 * 48:
        return None
    h, m = divmod(int(seconds) // 60, 60)
    return f'{h}h {m:02d}m' if h else f'{m}m'


def battery_line(percent, status, watts):
    """The caption for the battery row: "61% discharging  12.4W"."""
    if percent is None:
        return None
    state = (status or '').strip().lower() or 'unknown'
    if state == 'discharging':
        state = 'on battery'
    text = f'{int(percent)}% {state}'
    if watts:
        text += f'  {format_watts(watts)}'
    return text


# --- reading the machine -----------------------------------------------------

def _read_int(path):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


def _read_text(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def battery():
    """(percent, status, watts) -- or (None, None, None) with no battery."""
    for base in sorted(glob.glob(BAT_GLOB)):
        percent = _read_int(os.path.join(base, 'capacity'))
        if percent is None:
            continue
        status = _read_text(os.path.join(base, 'status'))
        uw = _read_int(os.path.join(base, 'power_now'))
        if uw is None:
            # Some firmware exposes current and voltage instead of power.
            cur = _read_int(os.path.join(base, 'current_now'))
            volt = _read_int(os.path.join(base, 'voltage_now'))
            if cur is not None and volt is not None:
                uw = abs(cur) * volt / 1_000_000.0
        return percent, status, watts_from_microwatts(uw)
    return None, None, None


class RaplCounter:
    """Successive reads of the package energy counter, turned into watts."""

    def __init__(self):
        self.path = None
        self.wrap = None
        for base in sorted(glob.glob(RAPL_GLOB)):
            # Only the package domain; the sub-domains are parts of it.
            if _read_text(os.path.join(base, 'name')) not in ('package-0', 'package'):
                continue
            path = os.path.join(base, 'energy_uj')
            if _read_int(path) is None:
                continue          # present but root-only, which is usual
            self.path = path
            self.wrap = _read_int(os.path.join(base, 'max_energy_range_uj'))
            break
        self._last = None
        self._at = None

    @property
    def available(self):
        return self.path is not None

    def watts(self, now=None):
        """Watts since the previous call, or None on the first one."""
        if not self.path:
            return None
        value = _read_int(self.path)
        now = time.monotonic() if now is None else now
        if value is None:
            return None
        previous, at = self._last, self._at
        self._last, self._at = value, now
        if previous is None:
            return None
        return watts_from_energy(previous, value, now - at, self.wrap)


def gpu_watts():
    """The card's draw, where nvidia-smi exists. None otherwise."""
    try:
        out = subprocess.run(
            ['nvidia-smi', '--query-gpu=power.draw', '--format=csv,noheader,nounits'],
            capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    first = (out.stdout or '').strip().splitlines()
    if not first:
        return None
    try:
        value = float(first[0].strip())
    except ValueError:
        return None
    return value if value > 0 else None
