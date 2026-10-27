"""Draws the K mark (octagon, a K, and a lightning bolt through its diagonal) into the Android icon files.

Run from the repo root:  python tools/gen_k_icons.py
Needs Pillow. Geometry matches lib/vigil/widgets/hud.dart (32 x 32 design box).
"""
import os
from PIL import Image, ImageDraw

RES = os.path.join('android', 'app', 'src', 'main', 'res')
BG = (6, 11, 22, 255)  # #060B16
SIGNAL = (63, 182, 255, 255)  # #3FB6FF
ICE = (207, 232, 255, 255)  # #CFE8FF
WHITE = (255, 255, 255, 255)

OCTAGON = [9.4, 1, 22.6, 1, 31, 9.4, 31, 22.6, 22.6, 31, 9.4, 31, 1, 22.6, 1, 9.4]
K = [8, 7, 12.6, 7, 12.6, 15, 19.6, 7, 25, 7, 17.2, 15.4, 25.2, 25, 19.6, 25, 14, 18.2, 12.6, 19.8, 12.6, 25, 8, 25]
GLOW = [23.6, 5.2, 16.4, 13.2, 18.8, 13.4, 11.2, 22.4, 14.6, 15.8, 12.2, 15.6, 19.8, 5.2]
CORE = [22.6, 6, 16.9, 12.6, 18.9, 12.8, 12.6, 20.4, 15.2, 15.2, 13.4, 15, 19.6, 6]


def mark(size, fraction, background=None, mono=None):
    """The mark on a [size] square, filling [fraction] of it. [mono] draws everything in one colour."""
    ss = 4  # supersample, then shrink for smooth edges
    big = size * ss
    img = Image.new('RGBA', (big, big), background or (0, 0, 0, 0))
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
    d.polygon(pts(GLOW), fill=mono or SIGNAL)
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
    save(mark(px, 0.8, background=BG), f'mipmap-{folder}/ic_launcher.png')

save(mark(96, 0.92, mono=WHITE), 'drawable-xxhdpi/ic_stat_vigil.png')
