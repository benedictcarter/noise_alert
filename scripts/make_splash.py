"""Compose the launch splash artwork.

The native splash cannot render text, so the wordmark has to be baked into a
bitmap. Drawn once at 4x and downsampled, rather than drawn at each density,
so the letterforms stay identical across handsets.
"""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = ROOT + '/android/app/src/main/res'

INK = (26, 26, 26, 255)

# 4x working scale: everything below is in mdpi units multiplied by this.
S = 4
PLANE_W = 132 * S
GAP = 18 * S
FONT_PX = 34 * S
LINE_GAP = 4 * S

font = ImageFont.truetype('C:/Windows/Fonts/ARIALNB.TTF', FONT_PX)
LINES = ['FLIGHTPATH', 'WATCH', 'REPORT']

# --- the plane, lifted off its white background ------------------------------
src = Image.open(ROOT + '/assets/icon/ic_launcher-512.png').convert('L')
alpha = src.point(lambda v: 255 - v)          # black ink -> opaque
plane = Image.new('RGBA', src.size, INK[:3] + (0,))
plane.putalpha(alpha)
plane = plane.crop(plane.getbbox())
plane = plane.resize((PLANE_W, round(PLANE_W * plane.height / plane.width)),
                     Image.LANCZOS)

# --- measure the wordmark ----------------------------------------------------
probe = ImageDraw.Draw(Image.new('RGBA', (1, 1)))
sizes = []
for line in LINES:
    l, t, r, b = probe.textbbox((0, 0), line, font=font)
    sizes.append((l, t, r, b))
text_w = max(r - l for l, t, r, b in sizes)
text_h = sum(b - t for l, t, r, b in sizes) + LINE_GAP * (len(LINES) - 1)

W = max(plane.width, text_w)
H = plane.height + GAP + text_h
canvas = Image.new('RGBA', (W, H), (255, 255, 255, 0))
canvas.alpha_composite(plane, ((W - plane.width) // 2, 0))

draw = ImageDraw.Draw(canvas)
y = plane.height + GAP
for line, (l, t, r, b) in zip(LINES, sizes):
    draw.text(((W - (r - l)) // 2 - l, y - t), line, font=font, fill=INK)
    y += (b - t) + LINE_GAP

# --- write one per density ---------------------------------------------------
for suffix, scale in [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2),
                      ('xxhdpi', 3), ('xxxhdpi', 4)]:
    out = canvas.resize((round(W * scale / S), round(H * scale / S)),
                        Image.LANCZOS)
    d = '%s/drawable-%s' % (RES, suffix)
    os.makedirs(d, exist_ok=True)
    out.save(d + '/splash_wordmark.png')
    print(suffix, out.size)
