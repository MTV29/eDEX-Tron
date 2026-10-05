"""Render the theme's own sound effects, so the project can ship them.

eDEX-UI's sound set is part of its app bundle and is not ours to redistribute
(same position as United Sans), and bootstrap_assets.ps1 only copies it out of
a local eDEX-UI install. These are synthesised from scratch instead.

    python src\\tools\\gen_sounds.py

Writes into assets/sounds/gen/. The key click plays on every keystroke, so it
has to be short enough not to turn fast typing into mush -- but it also has to
be loud enough to hear over laptop speakers, which a polite little tick is not.

Design notes for the click: a noise transient for the "contact" of the key, a
quick downward sine sweep for the electronic blip eDEX-UI is after, and a ring
an octave and a half up for sparkle. All three decay inside 45ms.
"""
import argparse
import math
import os
import random
import struct
import wave

RATE = 44100


def envelope(i, n, attack_ms=0.4, decay=0.30):
    """Fast attack, exponential decay, silent at the end."""
    t = i / RATE
    dur = n / RATE
    env = math.exp(-t / (dur * decay))
    attack = max(1, int(RATE * attack_ms / 1000.0))
    if i < attack:
        env *= i / attack
    return env


def blip(dur=0.045, start_hz=2100.0, end_hz=950.0, noise=0.35, sparkle=0.25,
         peak=0.8, seed=11):
    """One keystroke: transient, downward sweep, and a high ring."""
    rnd = random.Random(seed)
    n = int(RATE * dur)
    out = []
    phase = 0.0
    lp = 0.0
    for i in range(n):
        t = i / RATE
        frac = i / max(1, n - 1)

        # Sweep down. Integrating the frequency keeps the phase continuous --
        # stepping sin(2*pi*f(t)*t) instead would click audibly at the seams.
        f = start_hz + (end_hz - start_hz) * (frac ** 0.55)
        phase += 2.0 * math.pi * f / RATE
        tone = math.sin(phase)

        # Contact noise, only in the first few milliseconds.
        lp += 0.5 * (rnd.uniform(-1.0, 1.0) - lp)
        transient = lp * math.exp(-t / 0.0035)

        ring = math.sin(phase * 2.5) * math.exp(-t / 0.010)

        out.append((tone + transient * noise + ring * sparkle) * envelope(i, n))

    fade = max(1, int(RATE * 0.002))
    for i in range(fade):
        out[-1 - i] *= i / fade

    loudest = max(abs(v) for v in out) or 1.0
    return [v / loudest * peak for v in out]


def write_wav(path, samples):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    frames = b''.join(struct.pack('<h', int(max(-1.0, min(1.0, v)) * 32767))
                      for v in samples)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    return len(frames) // 2


SOUNDS = {
    'key.wav': {},
    # A second, lower blip for Enter and Backspace, should the launcher ever
    # want to tell them apart. Rendered now so it ships with the rest.
    'key-alt.wav': {'start_hz': 1500.0, 'end_hz': 700.0, 'sparkle': 0.15},
}


if __name__ == '__main__':
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=os.path.join(root, 'assets', 'sounds', 'gen'))
    ap.add_argument('--peak', type=float, default=0.8,
                    help='peak amplitude, 0..1 (how loud the click is)')
    a = ap.parse_args()

    for name, kw in SOUNDS.items():
        kw = dict(kw)
        kw.setdefault('peak', a.peak)
        path = os.path.join(a.out, name)
        n = write_wav(path, blip(**kw))
        print(f'{name:12} {n:5} frames  {n / RATE * 1000:.0f} ms  peak {kw["peak"]:.2f}  -> {path}')
