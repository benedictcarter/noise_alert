"""Draw the Flightpath Watch mark and export every Android icon asset.

The mark is the plane-and-swoosh from the FLIGHTPATH WATCH logo. The wordmark
itself is left out on purpose: at 48 dp a launcher icon has room for a shape or
for words, not both, and the shape is the half that survives the shrink.
"""
import math
import os

from PIL import Image, ImageDraw

ROOT = 's:/code/noise_alert/android/app/src/main/res'
SS = 4  # supersample factor; Pillow has no anti-aliased polygon fill

GREEN = (102, 187, 51, 255)
BLACK = (17, 17, 17, 255)
WHITE = (255, 255, 255, 255)

# Top view of an airliner, nose at +x, span on y, normalised to +/-1.
# Only the upper half is listed; the lower half is its mirror. The wing root is
# set well aft so a nose is still visible at 48 px, where a mid-set wing eats it.
_HALF = [
    (1.00, 0.000),
    (0.93, 0.050),
    (0.82, 0.078),
    (0.20, 0.092),   # wing leading edge leaves the fuselage
    (-0.05, 0.900),  # wingtip, leading corner
    (-0.18, 0.900),  # wingtip, trailing corner
    (-0.25, 0.160),  # wing trailing edge rejoins the fuselage
    (-0.62, 0.098),
    (-0.72, 0.340),  # tailplane
    (-0.84, 0.340),
    (-0.86, 0.092),
    (-0.96, 0.068),
    (-1.00, 0.000),
]


def plane_polygon(cx, cy, size, degrees):
    """The silhouette as absolute points, scaled and rotated about its centre."""
    pts = _HALF + [(x, -y) for x, y in reversed(_HALF[1:-1])]
    rad = math.radians(degrees)
    cos, sin = math.cos(rad), math.sin(rad)
    out = []
    for x, y in pts:
        # y is negated first: image space grows downward, the shape is written
        # in maths space, and a plane mirrored about its axis is a different
        # plane -- the wings would sweep forwards.
        px, py = x * size, -y * size
        out.append((cx + px * cos - py * sin, cy + px * sin + py * cos))
    return out


def _bezier(p0, p1, p2, t):
    u = 1 - t
    return (u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
            u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1])


def swoosh_polygon(p0, p1, p2, w0, w1, steps=180):
    """A tapering ribbon along a quadratic curve: a contrail, thick at the plane.

    Thickness is offset along the curve normal rather than vertically, so the
    ribbon keeps its weight through the bend instead of pinching at the top.
    """
    upper, lower = [], []
    for i in range(steps + 1):
        t = i / steps
        x, y = _bezier(p0, p1, p2, t)
        # Derivative of the quadratic, normalised, rotated a quarter turn.
        u = 1 - t
        dx = 2 * u * (p1[0] - p0[0]) + 2 * t * (p2[0] - p1[0])
        dy = 2 * u * (p1[1] - p0[1]) + 2 * t * (p2[1] - p1[1])
        length = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / length, dx / length
        # Grow on a curve, so the thin end reads as a point rather than a
        # chopped-off ribbon.
        w = (w0 + (w1 - w0) * (t ** 0.8)) / 2
        upper.append((x + nx * w, y + ny * w))
        lower.append((x - nx * w, y - ny * w))
    return upper + list(reversed(lower))


def draw_mark(size, scale, plane_colour=BLACK, swoosh_colour=GREEN,
              background=None):
    """The mark on a square canvas. `scale` is the fraction of the side it fills."""
    n = size * SS
    img = Image.new('RGBA', (n, n), background or (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Everything below is written against a unit square centred on the canvas,
    # so one set of coordinates serves every export size.
    def pt(x, y):
        return (n / 2 + (x - 0.5) * n * scale, n / 2 + (y - 0.5) * n * scale)

    if swoosh_colour is not None:
        d.polygon(
            swoosh_polygon(
                pt(0.04, 0.92), pt(0.44, 0.90), pt(0.86, 0.44),
                w0=0.012 * n * scale, w1=0.105 * n * scale,
            ),
            fill=swoosh_colour,
        )

    d.polygon(
        plane_polygon(*pt(0.52, 0.42), size=0.44 * n * scale, degrees=-30),
        fill=plane_colour,
    )
    return img.resize((size, size), Image.LANCZOS)


def save(img, rel):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print('wrote', rel, img.size)


DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def main():
    # ------------------------------------------------------------ launcher --
    # Legacy icon: the mark on white, full bleed, because pre-26 launchers mask
    # the corners themselves.
    legacy = draw_mark(1024, scale=0.86, background=WHITE)
    # Adaptive foreground: a third of the layer can be cropped by the mask, so
    # the mark is drawn small enough to survive a circle.
    foreground = draw_mark(1024, scale=0.56)

    for name, factor in DENSITIES.items():
        px = int(48 * factor)
        icon = legacy.resize((px, px), Image.LANCZOS)
        save(icon, 'mipmap-%s/ic_launcher.png' % name)
        save(icon, 'mipmap-%s/ic_launcher_round.png' % name)
        fg = int(108 * factor)
        save(foreground.resize((fg, fg), Image.LANCZOS),
             'mipmap-%s/ic_launcher_foreground.png' % name)

    # Store listing / iOS master, kept in the repo so the next resize starts
    # from artwork rather than from an already-downscaled PNG.
    save(legacy.resize((512, 512), Image.LANCZOS),
         '../../../../../assets/icon/ic_launcher-512.png')

    # -------------------------------------------------------------- widget --
    # White, and no swoosh: green on the widget's red is unreadable, and at
    # 28 dp the arc collapses into a smudge anyway.
    plane = draw_mark(256, scale=0.98, plane_colour=WHITE, swoosh_colour=None)
    for name, factor in DENSITIES.items():
        px = int(28 * factor)
        save(plane.resize((px, px), Image.LANCZOS), 'drawable-%s/ic_plane.png' % name)


if __name__ == '__main__':
    main()
