"""Draws the K mark (octagon, a K, and a lightning bolt through its diagonal) into the Android icon files.

Run from the repo root:  python tools/gen_k_icons.py
Needs Pillow. Geometry matches lib/vigil/widgets/hud.dart (32 x 32 design box).
"""
import os
from PIL import Image, ImageDraw

RES = os.path.join('android', 'app', 'src', 'main', 'res')
# Storm violet: a gradient tile, a white octagon, an ice K and a violet bolt with a white core.
GRAD = ((39, 89, 240), (109, 60, 245), (138, 60, 240))  # #2759F0 -> #6D3CF5 -> #8A3CF0
SIGNAL = (255, 255, 255, 255)  # octagon edge
ICE = (220, 230, 255, 255)  # #DCE6FF
BOLT = (91, 47, 214, 255)  # #5B2FD6
WHITE = (255, 255, 255, 255)

OCTAGON = [9.4, 1, 22.6, 1, 31, 9.4, 31, 22.6, 22.6, 31, 9.4, 31, 1, 22.6, 1, 9.4]
K = [8, 7, 12.6, 7, 12.6, 15, 19.6, 7, 25, 7, 17.2, 15.4, 25.2, 25, 19.6, 25, 14, 18.2, 12.6, 19.8, 12.6, 25, 8, 25]
GLOW = [23.6, 5.2, 16.4, 13.2, 18.8, 13.4, 11.2, 22.4, 14.6, 15.8, 12.2, 15.6, 19.8, 5.2]
CORE = [22.6, 6, 16.9, 12.6, 18.9, 12.8, 12.6, 20.4, 15.2, 15.2, 13.4, 15, 19.6, 6]


def gradient_tile(size):
    """The 135 degree primary gradient as a square tile."""
    img = Image.new('RGBA', (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2.0 * (size - 1))
            if t < 0.6:
                a, b, u = GRAD[0], GRAD[1], t / 0.6
            else:
                a, b, u = GRAD[1], GRAD[2], (t - 0.6) / 0.4
            px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3)) + (255,)
    return img


def mark(size, fraction, background=None, mono=None):
    """The mark on a [size] square, filling [fraction] of it. [mono] draws everything in one colour."""
    ss = 4  # supersample, then shrink for smooth edges
    big = size * ss
    img = gradient_tile(big) if background == 'gradient' else Image.new('RGBA', (big, big), background or (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    box = big * fraction
    off = (big - box) / 2
    k = box / 32

    def pts(p):
        return [(off + p[i] * k, off + p[i + 1] * k) for i in range(0, len(p), 2)]

    oct_pts = pts(OCTAGON)
    stroke = max(2, int(round(2.0 * k)))
    d.line(oct_pts + [oct_pts[0]], fill=mono or SIGNAL, width=stroke, joint='curve')
    d.polygon(pts(K), fill=mono or ICE)
    d.polygon(pts(GLOW), fill=mono or BOLT)
    d.polygon(pts(CORE), fill=mono or WHITE)
    return img.resize((size, size), Image.LANCZOS)


def save(img, rel):
    path = os.path.join(RES, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print(path, img.size)


for folder, px in (('mdpi', 108), ('hdpi', 162), ('xhdpi', 216), ('xxhdpi', 324), ('xxxhdpi', 432)):
    # the adaptive icon insets 16% itself, so the mark fills the canvas
    save(mark(px, 0.74), f'drawable-{folder}/ic_launcher_foreground.png')
    save(mark(px, 0.74, mono=WHITE), f'drawable-{folder}/ic_launcher_monochrome.png')

for folder, px in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
    save(mark(px, 0.8, background='gradient'), f'mipmap-{folder}/ic_launcher.png')

save(mark(96, 0.92, mono=WHITE), 'drawable-xxhdpi/ic_stat_vigil.png')
