"""Lift the FLIGHTPATH WATCH mark out of the logo and export every icon asset.

Nothing here is redrawn. The source is a 191x72 screenshot of the logo, so the
plane-and-swoosh is barely 94 px wide; the job is to recover it cleanly enough
to survive being blown up to 432 px.

The trick is to work on ink *coverage* as a soft alpha rather than on a hard
black/white threshold. A threshold throws away the antialiasing, and the
antialiasing is exactly where the sub-pixel position of the true edge is
recorded -- discard it first and every upscale is a staircase. Instead the soft
alpha is resampled, blurred by about half a source pixel to melt the stairs,
and then pushed back to a hard edge with a smoothstep about the half-coverage
contour, which is where the edge of an antialiased shape actually lies.

Run from the repo root:  python scripts/make_icons.py
"""
import os

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SOURCE = os.path.join(REPO, 'assets', 'icon', 'flightpath_watch_logo.jpg')
ANDROID_RES = os.path.join(REPO, 'android', 'app', 'src', 'main', 'res')
IOS_ICONS = os.path.join(REPO, 'ios', 'Runner', 'Assets.xcassets',
                         'AppIcon.appiconset')

INK = (17, 17, 17)
WHITE = (255, 255, 255)

# Degrees anticlockwise. The mark is nearly 3:1, so laid flat in a square it
# shrinks to a stripe with empty bands above and below; tipped up it fills the
# tile and reads as a climb, which is what the swoosh is drawing anyway.
ICON_TILT = 26

DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def _ink_coverage():
    """The whole logo as ink coverage in 0..1, with JPEG noise clipped off."""
    grey = np.asarray(Image.open(SOURCE).convert('L'), dtype=np.float64) / 255.0
    coverage = 1.0 - grey
    # JPEG ringing leaves a few percent of ink on plain white and a few percent
    # of white in solid black. Clip both ends, then restretch so the surviving
    # range still spans nothing to full.
    return np.clip((coverage - 0.12) / (0.88 - 0.12), 0.0, 1.0)


def _components(mask):
    """Label 8-connected True regions. Iterative flood fill; the image is tiny."""
    height, width = mask.shape
    labels = np.zeros((height, width), dtype=np.int32)
    count = 0
    for sy in range(height):
        for sx in range(width):
            if not mask[sy, sx] or labels[sy, sx]:
                continue
            count += 1
            stack = [(sy, sx)]
            labels[sy, sx] = count
            while stack:
                y, x = stack.pop()
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        if (0 <= ny < height and 0 <= nx < width
                                and mask[ny, nx] and not labels[ny, nx]):
                            labels[ny, nx] = count
                            stack.append((ny, nx))
    return labels, count


def mark_alpha(scale=16, blur=0.50, low=0.45, high=0.55):
    """The plane-and-swoosh alone, as an L-mode alpha `scale` times source size."""
    coverage = _ink_coverage()
    labels, count = _components(coverage > 0.35)

    # The mark is the largest connected region by a wide margin: the wordmark is
    # set in separate letters, and no single glyph approaches a plane welded to
    # a swoosh.
    biggest = max(range(1, count + 1), key=lambda i: (labels == i).sum())
    keep = labels == biggest

    # Grow the selection by a pixel so the component keeps its own soft edge,
    # but no further -- the W of WATCH sits close enough that a plain bounding
    # box crop catches a slice of it.
    grown = np.asarray(
        Image.fromarray((keep * 255).astype(np.uint8))
        .filter(ImageFilter.MaxFilter(3)),
        dtype=np.float64,
    ) / 255.0
    coverage = coverage * grown

    rows, cols = np.nonzero(coverage > 0.05)
    coverage = coverage[rows.min():rows.max() + 1, cols.min():cols.max() + 1]
    coverage = np.pad(coverage, 2)

    small = Image.fromarray((coverage * 255).astype(np.uint8), mode='L')
    big = small.resize((small.width * scale, small.height * scale),
                       Image.LANCZOS)
    big = big.filter(ImageFilter.GaussianBlur(scale * blur))

    v = np.asarray(big, dtype=np.float64) / 255.0
    t = np.clip((v - low) / (high - low), 0.0, 1.0)
    return Image.fromarray((t * t * (3 - 2 * t) * 255).astype(np.uint8),
                           mode='L')


def _fit(alpha, box, tilt=0):
    """The alpha rotated and scaled to sit inside a `box` square, centred."""
    if tilt:
        alpha = alpha.rotate(tilt, resample=Image.BICUBIC, expand=True,
                             fillcolor=0)
        alpha = alpha.crop(alpha.getbbox())
    factor = box / max(alpha.width, alpha.height)
    return alpha.resize((max(1, round(alpha.width * factor)),
                         max(1, round(alpha.height * factor))), Image.LANCZOS)


def tile(alpha, side, fill, colour=INK, background=None, tilt=ICON_TILT):
    """One square icon: the mark at `fill` of the side, over `background`."""
    shaped = _fit(alpha, side * fill, tilt)
    out = Image.new('RGBA', (side, side),
                    background + (255,) if background else (0, 0, 0, 0))
    out.paste(Image.new('RGBA', shaped.size, colour + (255,)),
              ((side - shaped.width) // 2, (side - shaped.height) // 2), shaped)
    return out


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print('wrote', os.path.relpath(path, REPO), img.size)


def main():
    alpha = mark_alpha()

    # Legacy launcher icon: full bleed on white, because pre-26 launchers apply
    # their own mask to the corners.
    legacy = tile(alpha, 1024, fill=0.90, background=WHITE).convert('RGB')
    # Adaptive foreground: the outer third of the layer can be cropped away by
    # whatever mask the launcher chooses, so the mark is drawn small enough to
    # survive a circle.
    foreground = tile(alpha, 1024, fill=0.60)

    for name, factor in DENSITIES.items():
        px = round(48 * factor)
        icon = legacy.resize((px, px), Image.LANCZOS)
        save(icon, os.path.join(ANDROID_RES, 'mipmap-%s' % name,
                                'ic_launcher.png'))
        save(icon, os.path.join(ANDROID_RES, 'mipmap-%s' % name,
                                'ic_launcher_round.png'))
        save(foreground.resize((round(108 * factor),) * 2, Image.LANCZOS),
             os.path.join(ANDROID_RES, 'mipmap-%s' % name,
                          'ic_launcher_foreground.png'))

    # Store listing and a master to re-cut from, so the next resize starts from
    # this pipeline rather than from an already-downscaled PNG.
    save(legacy.resize((512, 512), Image.LANCZOS),
         os.path.join(REPO, 'assets', 'icon', 'ic_launcher-512.png'))

    # iOS masks the corners itself and rejects any alpha channel.
    for name, px in {
        '20x20@1x': 20, '20x20@2x': 40, '20x20@3x': 60,
        '29x29@1x': 29, '29x29@2x': 58, '29x29@3x': 87,
        '40x40@1x': 40, '40x40@2x': 80, '40x40@3x': 120,
        '60x60@2x': 120, '60x60@3x': 180,
        '76x76@1x': 76, '76x76@2x': 152,
        '83.5x83.5@2x': 167, '1024x1024@1x': 1024,
    }.items():
        save(legacy.resize((px, px), Image.LANCZOS),
             os.path.join(IOS_ICONS, 'Icon-App-%s.png' % name))

    # Widget: the mark left flat and drawn in white on the red pill. Flat
    # because the widget is wider than it is tall, which is the shape the mark
    # already is -- the tilt only exists to fill a square.
    widget_dp_w = 52
    height_dp = widget_dp_w * alpha.height / alpha.width
    for name, factor in DENSITIES.items():
        w = round(widget_dp_w * factor)
        h = max(1, round(height_dp * factor))
        shaped = alpha.resize((w, h), Image.LANCZOS)
        out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        out.paste(Image.new('RGBA', (w, h), (255, 255, 255, 255)), (0, 0),
                  shaped)
        save(out, os.path.join(ANDROID_RES, 'drawable-%s' % name,
                               'ic_plane.png'))


if __name__ == '__main__':
    main()
