"""Render the theme's own sound effects, so the project can ship them.

eDEX-UI's sound set is part of its app bundle and is not ours to redistribute
(same position as United Sans), and bootstrap_assets.ps1 only copies it out of
a local eDEX-UI install. This synthesises a key click from scratch instead:
a filtered noise burst for the plastic edge plus a short damped tone for the
body of the stroke, which is roughly what a keyboard does.

    python src\\tools\\gen_sounds.py

Writes assets/sounds/gen/key.wav. Keep it short -- it plays on every keystroke,
so anything with a tail turns fast typing into mush -- and quiet, because it is
layered under whatever else is making noise.
"""
import argparse
import math
import os
import random
import struct
import wave

RATE = 44100


def click(dur=0.024, tone=190.0, bright=0.42, peak=0.45, seed=7):
    """One keystroke, as a list of floats in -1..1.

    `bright` is the noise lowpass coefficient: 1.0 is raw white noise (a sharp
    tick), low values roll off the top (a duller thud).
    """
    rnd = random.Random(seed)
    n = int(RATE * dur)
    attack = max(1, int(RATE * 0.0004))      # ramp in, or it starts on a pop
    lp = 0.0
    out = []
    for i in range(n):
        t = i / RATE
        lp += bright * (rnd.uniform(-1.0, 1.0) - lp)
        # Two decaying tones rather than one: the lower gives the stroke enough
        # weight to be heard over laptop speakers, where a pure tick vanishes.
        body = (math.sin(2 * math.pi * tone * t) * math.exp(-t / 0.008)
                + 0.6 * math.sin(2 * math.pi * (tone * 0.5) * t) * math.exp(-t / 0.012))
        env = math.exp(-t / (dur * 0.30))
        if i < attack:
            env *= i / attack
        out.append((lp * 0.85 + body * 0.55) * env)

    # Fade the last millisecond to zero: a truncated waveform clicks on its own.
    fade = max(1, int(RATE * 0.001))
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


if __name__ == '__main__':
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=os.path.join(root, 'assets', 'sounds', 'gen'))
    a = ap.parse_args()

    for name, kw in (('key.wav', {}),):
        path = os.path.join(a.out, name)
        n = write_wav(path, click(**kw))
        print(f'{name:10} {n:6} frames  {n / RATE * 1000:.0f} ms  -> {path}')
