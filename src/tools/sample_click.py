"""Cut one key click out of a recording of typing, and save it as a wav.

The key click is played on every keystroke through PlaySound, which wants PCM,
so a phone recording of a keyboard has to be decoded, searched for a single
clean press, trimmed and levelled before it is any use.

    python src\\tools\\sample_click.py "Recording.mp3"
    python src\\tools\\sample_click.py "Recording.mp3" --index 2 --play

Writes assets/sounds/key.wav, which the launcher prefers over the synthesised
assets/sounds/gen/key.wav. That folder is outside the repository: a recording
is the person's own, and nothing in assets\\sounds\\ is ever shipped.

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


def find_hits(samples, floor=0.18, gap_ms=90):
    """Where each press starts: a jump past `floor`, ignoring the ring after."""
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
    ap.add_argument('--floor', type=float, default=0.18, help='what counts as a press')
    ap.add_argument('--play', action='store_true', help='play the result')
    a = ap.parse_args()

    samples = decode(a.source)
    print(f'decoded {len(samples) / RATE:.1f}s')

    hits = find_hits(samples, a.floor)
    if not hits:
        raise SystemExit('no key presses found - try a lower --floor')
    print(f'found {len(hits)} press(es) at: '
          + ', '.join(f'{h / RATE:.2f}s' for h in hits[:12])
          + (' ...' if len(hits) > 12 else ''))

    if a.index is not None:
        if not 0 <= a.index < len(hits):
            raise SystemExit(f'--index must be 0..{len(hits) - 1}')
        chosen = hits[a.index]
    else:
        # The loudest press is usually the cleanest and the least clipped by
        # whatever the recording started or ended in the middle of.
        chosen = max(hits, key=lambda h: max(
            (abs(v) for v in samples[h:h + int(RATE * 0.03)]), default=0.0))
    print(f'taking the press at {chosen / RATE:.2f}s')

    clip = normalise(extract(samples, chosen, length_ms=a.length), a.peak)
    n = write_wav(a.out, clip)
    print(f'{n} frames, {n / RATE * 1000:.0f} ms, peak {a.peak:.2f} -> {a.out}')

    if a.play:
        import winsound
        for _ in range(5):
            winsound.PlaySound(a.out, winsound.SND_FILENAME)


if __name__ == '__main__':
    main()
