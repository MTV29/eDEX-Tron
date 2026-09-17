"""Detect whether the eDEX grid is actually visible in a desktop capture.

Samples a clean strip of desktop and reports the horizontal luminance profile.
A rendered grid shows a regular ripple at the cell pitch; a flat profile means
the desktop is painting a solid colour instead.
"""
import sys
from PIL import Image

cap = Image.open(sys.argv[1]).convert('RGB')
x0, x1, y = 520, 980, 700          # below the icons, left of the HUD

lum = []
for x in range(x0, x1):
    r, g, b = cap.getpixel((x, y))
    lum.append(round(0.2126 * r + 0.7152 * g + 0.0722 * b, 1))

print(f'capture {cap.size}, strip y={y} x={x0}..{x1}')
print(f'min={min(lum)}  max={max(lum)}  spread={max(lum) - min(lum):.1f}')
print('profile:', ' '.join(f'{v:.0f}' for v in lum[:60]))

# a grid gives a repeating dark/light alternation; count the transitions
mid = (max(lum) + min(lum)) / 2
crossings = sum(1 for i in range(1, len(lum)) if (lum[i - 1] < mid) != (lum[i] < mid))
print(f'mid={mid:.1f}  crossings={crossings}  '
      f'=> {"GRID VISIBLE" if crossings > 8 and max(lum) - min(lum) > 3 else "FLAT / not rendering"}')
