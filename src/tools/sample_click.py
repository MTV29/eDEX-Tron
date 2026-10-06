"""Cut one key click out of a recording of typing, and save it as a wav.

The key click is played on every keystroke through PlaySound, which wants PCM,
so a phone recording of a keyboard has to be decoded, searched for a single
clean press, trimmed and levelled before it is any use.

    python src\\tools\\sample_click.py "Recording.mp3"
    python src\\tools\\sample_click.py "Recording.mp3" --index 2 --play

Writes assets/sounds/key.wav, which the launcher prefers over the synthesised
assets/sounds/gen/key.wav. Overwrites the recording that ships, so keep a copy
if you want it back.

Needs miniaudio for the decode (pip install --user miniaudio); it is a
development tool, not something the theme needs at runtime.
"""
import argparse
import math
import os
import struct
import sys
import wave

RATE = 44100


def decode(path):
    """The file as mono floats at RATE, however it was encoded."""
    import miniaudio
    d = miniaudio.decode_file(path, nchannels=1, sample_rate=RATE)
    return [s / 32768.0 for s in d.samples]


def envelope(samples, step_ms=5.0):
    """Peak level in each short window, which is what "loud" means here."""
    win = max(1, int(RATE * step_ms / 1000.0))
    return [max((abs(v) for v in samples[i:i + win]), default=0.0)
            for i in range(0, max(0, len(samples) - win), win)], win


def find_hits(samples, floor=0.05, gap_ms=90):
    """Where each press starts: a jump past `floor`, ignoring the ring after.

    `gap_ms` is how long after one press to stop looking for the next. Set it
    too high on a recording of fast typing and several presses are treated as
    one, so the clip taken from it contains all of them -- which plays as
    several clicks per keystroke. Check the result with --report before
    trusting it.
    """
    gap = int(RATE * gap_ms / 1000.0)
    hits = []
    i = 0
    while i < len(samples):
        if abs(samples[i]) >= floor and (not hits or i - hits[-1] > gap):
            hits.append(i)
            i += gap
        else:
            i += 1
    return hits


def clarity(samples, start, back_ms=100.0):
    """How far a press rises above the room it was recorded in.

    Picking the *loudest* press is a trap: a phone recording has quiet
    stretches with clean isolated presses and noisy stretches where the hum is
    nearly as loud as the key. The loudest sample usually comes from the noisy
    part, and normalising it afterwards just makes the hum loud too. What
    matters is the gap between the press and the few hundred milliseconds
    before it.
    """
    look = int(RATE * 0.03)
    peak = max((abs(v) for v in samples[start:start + look]), default=0.0)
    a = max(0, start - int(RATE * back_ms / 1000.0))
    before = sorted(abs(v) for v in samples[a:start]) or [0.0]
    floor = before[len(before) // 2]          # median, so one tick cannot skew it
    return peak / max(floor, 1e-5), peak, floor


def extract(samples, start, before_ms=4, length_ms=55):
    """One press: a little lead-in, then the press and its decay."""
    a = max(0, start - int(RATE * before_ms / 1000.0))
    b = min(len(samples), a + int(RATE * length_ms / 1000.0))
    clip = samples[a:b]

    # In at 1ms and out over the last 8ms, so neither end clicks on its own.
    fade_in = max(1, int(RATE * 0.001))
    for i in range(min(fade_in, len(clip))):
        clip[i] *= i / fade_in
    fade_out = max(1, int(RATE * 0.008))
    for i in range(min(fade_out, len(clip))):
        clip[-1 - i] *= i / fade_out
    return clip


def normalise(clip, peak):
    loudest = max((abs(v) for v in clip), default=0.0)
    if loudest <= 0:
        return clip
    return [v / loudest * peak for v in clip]


def describe(clip):
    """Print the clip's shape, and say so if it holds more than one press."""
    env, win = envelope(clip)
    print('   envelope: ' + ' '.join(f'{v:.2f}' for v in env))
    peaks = [i for i in range(1, len(env) - 1)
             if env[i] > 0.25 and env[i] >= env[i - 1] and env[i] > env[i + 1]]
    # A smooth swell rises to one peak and falls away. Two presses give two
    # peaks with a real dip *between* them -- the quiet lead-in before the
    # first peak is not a dip, which is what this used to mistake it for.
    separate = 1 if peaks else 0
    for a, b in zip(peaks, peaks[1:]):
        trough = min(env[a:b + 1])
        if trough < min(env[a], env[b]) * 0.4:
            separate += 1
    if separate > 1:
        print(f'   WARNING: {separate} separate transients -- this will sound '
              'like that many clicks per keystroke.')
        print('   Use a shorter --length, or a different --index.')
    else:
        print('   one transient: good for a keystroke')


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


def main():
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap = argparse.ArgumentParser()
    ap.add_argument('source', help='a recording containing one or more key presses')
    ap.add_argument('--out', default=os.path.join(root, 'assets', 'sounds', 'key.wav'))
    ap.add_argument('--index', type=int, default=None,
                    help='which press to take (default: the loudest)')
    ap.add_argument('--length', type=float, default=55.0, help='milliseconds to keep')
    ap.add_argument('--peak', type=float, default=0.85, help='level to normalise to')
    ap.add_argument('--floor', type=float, default=0.05, help='what counts as a press')
    ap.add_argument('--play', action='store_true', help='play the result')
    ap.add_argument('--report', action='store_true',
                    help="show the result's envelope, and warn if it holds "
                         "more than one transient")
    ap.add_argument('--whole', action='store_true',
                    help='the file is already one sound: just trim the silence '
                         'off each end and bring the level up')
    a = ap.parse_args()

    samples = decode(a.source)
    print(f'decoded {len(samples) / RATE:.1f}s')

    if a.whole:
        # Sounds meant to be played whole -- eDEX-UI's own set, for instance --
        # are usually a short event padded with silence and mastered quietly.
        # Looking for "presses" in one of those finds nothing useful.
        quiet = max((abs(v) for v in samples), default=0.0) * 0.02
        first = next((i for i, v in enumerate(samples) if abs(v) > quiet), 0)
        last = next((i for i in range(len(samples) - 1, -1, -1)
                     if abs(samples[i]) > quiet), len(samples) - 1)
        clip = samples[max(0, first - int(RATE * 0.002)):last + int(RATE * 0.004)]
        fade = max(1, int(RATE * 0.004))
        for i in range(min(fade, len(clip))):
            clip[-1 - i] *= i / fade
        clip = normalise(clip, a.peak)
        n = write_wav(a.out, clip)
        print(f'{n} frames, {n / RATE * 1000:.0f} ms, peak {a.peak:.2f} -> {a.out}')
        if a.report:
            describe(clip)
        if a.play:
            import winsound
            for _ in range(5):
                winsound.PlaySound(a.out, winsound.SND_FILENAME)
        return

    hits = find_hits(samples, a.floor)
    if not hits:
        raise SystemExit('no key presses found - try a lower --floor')
    print(f'found {len(hits)} press(es) at: '
          + ', '.join(f'{h / RATE:.2f}s' for h in hits[:12])
          + (' ...' if len(hits) > 12 else ''))

    scored = sorted(((clarity(samples, h), h) for h in hits), reverse=True)
    print('clearest presses:')
    for (ratio, peak, floor), h in scored[:5]:
        print(f'  {h / RATE:6.2f}s  peak {peak:.3f} over {floor:.3f}  ({ratio:.0f}x)')

    if a.index is not None:
        if not 0 <= a.index < len(hits):
            raise SystemExit(f'--index must be 0..{len(hits) - 1}')
        chosen = hits[a.index]
    else:
        chosen = scored[0][1]
    print(f'taking the press at {chosen / RATE:.2f}s')

    clip = normalise(extract(samples, chosen, length_ms=a.length), a.peak)
    n = write_wav(a.out, clip)
    print(f'{n} frames, {n / RATE * 1000:.0f} ms, peak {a.peak:.2f} -> {a.out}')
    if a.report:
        describe(clip)

    if a.play:
        import winsound
        for _ in range(5):
            winsound.PlaySound(a.out, winsound.SND_FILENAME)


if __name__ == '__main__':
    main()
