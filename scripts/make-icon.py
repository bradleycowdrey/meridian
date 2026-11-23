#!/usr/bin/env python3
"""Draws Meridian's app icon in the app's colours (the Two Degrees sky: day blue into night navy,
white type), with no band along the top.

The mark: the family C (as on Cowdrey One and Cowdrey.MD), with Meridian's three days and the "now" capsule in its opening.
The finish follows the Cowdrey One family: one bold glyph on a rich vertical gradient, with a
soft highlight top right, a shade bottom left, a top-edge sheen, and gentle depth under the bars.

  python3 scripts/make-icon.py      (needs Pillow and numpy)

Writes the iPhone icon (full-bleed square, opaque RGB; iOS rounds the corners), the Mac icon
(Apple's macOS rounded tile with its margin, edge light and soft shadow), docs/icon.png, the
share-preview mark and the Android launcher icons.
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
SS = 4  # supersampling


def hexc(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255)


SKY = [(0.00, hexc(0x5A8FCB)), (0.35, hexc(0x2E5A8E)), (0.70, hexc(0x16294A)), (1.00, hexc(0x0A0F1F))]
BAR_TINT = hexc(0xF2F5FA)
# Each bar: daylight as (position 0..1, white opacity) stops, left to right.
# The dark ends sit at .16 (not .12) so they still read at 29 px.
BARS = [
    [(0, .16), (.18, .30), (.38, .92), (1, .95)],          # morning: night into day
    [(0, .95), (.45, .92), (.70, .25), (1, .16)],          # afternoon into night
    [(0, .90), (.22, .85), (.42, .20), (1, .16)],          # evening
    [(0, .16), (.55, .16), (.78, .55), (1, .92)],          # before dawn
]


def blur(img, css_blur):
    """A CSS-style blur radius (in pixels) as a Gaussian."""
    return img.filter(ImageFilter.GaussianBlur(css_blur / 2))


def rrect_mask(S, box, radius):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return np.asarray(m, float) / 255


def layer(S, rgb, alpha):
    """An RGBA layer of one colour with a per-pixel alpha (0..1) array."""
    a = np.zeros((S, S, 4))
    a[..., :3] = rgb
    a[..., 3] = np.clip(alpha, 0, 1) * 255
    return Image.fromarray(a.round().astype(np.uint8), "RGBA")


def radial(S, cx, cy, rx, ry, a0, fade_at):
    """Elliptical falloff: a0 at the centre, 0 at `fade_at` of the radius (smooth)."""
    y, x = np.mgrid[0:S, 0:S]
    d = np.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2) / fade_at
    t = np.clip(1 - d, 0, 1)
    return a0 * t * t * (3 - 2 * t)


def art(size):
    """Full-bleed square artwork at `size` pixels."""
    S = size * SS
    t = np.linspace(0, 1, S)
    stops = [p for p, _ in SKY]
    rgb = np.stack([np.interp(t, stops, [c[i] for _, c in SKY]) for i in range(3)], axis=1)
    sky = np.repeat(rgb[:, None, :], S, axis=1)
    img = Image.fromarray(np.dstack([sky, np.full((S, S), 255.0)]).round().astype(np.uint8), "RGBA")

    # Depth: highlight top right, shade bottom left, a sheen along the top edge.
    img = Image.alpha_composite(img, layer(S, (255, 255, 255), radial(S, .78 * S, 0, .9 * S, .6 * S, .16, .60)))
    img = Image.alpha_composite(img, layer(S, (0, 0, 0), radial(S, 0, S, .9 * S, .6 * S, .28, .70)))
    band = 0.035 * S
    sheen = np.clip(1 - np.arange(S) / band, 0, 1)[:, None] * .10
    img = Image.alpha_composite(img, layer(S, (255, 255, 255), np.broadcast_to(sheen, (S, S))))

    # The family C (Cowdrey One, Cowdrey.MD): a bold white ring open on the right, centred 44% across,
    # outer radius 31.5%, stroke 10%, its round ends 40 degrees above and below the horizontal.
    cx, cy, ro, w = 0.443 * S, 0.5 * S, 0.315 * S, 0.10 * S
    rc = ro - w / 2
    yy, xx = np.mgrid[0:S, 0:S].astype(float)
    dist = np.hypot(xx - cx, yy - cy)
    ang = np.degrees(np.arctan2(yy - cy, xx - cx))           # 0 = right, +-180 = left
    aa = 1.5                                                 # antialias width in supersampled px
    ring = np.clip((w / 2 - np.abs(dist - rc)) / aa + .5, 0, 1) * (np.abs(ang) >= 40)
    for a in (40, -40):
        ex, ey = cx + rc * np.cos(np.radians(a)), cy + rc * np.sin(np.radians(a))
        ring = np.maximum(ring, np.clip((w / 2 - np.hypot(xx - ex, yy - ey)) / aa + .5, 0, 1))
    shadow = blur(layer(S, (0, 0, 0), ring * .22), 0.012 * S)
    shifted = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shifted.paste(shadow, (0, round(0.008 * S)))
    img = Image.alpha_composite(img, shifted)
    img = Image.alpha_composite(img, layer(S, (255, 255, 255), ring))

    # Meridian's mark in the opening (where Cowdrey.MD has "MD"): three days as bars of light and dark,
    # crossed by the "now" capsule.
    left, right, h = 0.545 * S, 0.885 * S, 0.042 * S
    xs = np.clip((np.arange(S) - left) / (right - left), 0, 1)
    for (a0, a1), cyb in zip([(.95, .95), (.40, .95), (.95, .40)], [0.435, 0.500, 0.565]):
        top = cyb * S - h / 2
        alpha = (a0 + (a1 - a0) * xs)[None, :]
        img = Image.alpha_composite(img, layer(S, BAR_TINT, rrect_mask(S, [left, top, right, top + h], h / 2) * alpha))

    # The "now" capsule: a white outline over a light glass fill, with a soft glow.
    cw = 0.062 * S
    ccx = 0.755 * S
    cx0, cx1 = ccx - cw / 2, ccx + cw / 2
    cy0, cy1 = 0.37 * S, 0.63 * S
    sw = 0.014 * S
    outline = rrect_mask(S, [cx0, cy0, cx1, cy1], cw / 2)
    inner = rrect_mask(S, [cx0 + sw, cy0 + sw, cx1 - sw, cy1 - sw], cw / 2 - sw)
    cap = np.clip(outline - inner, 0, 1)
    img = Image.alpha_composite(img, blur(layer(S, (255, 255, 255), cap * .35), 0.008 * S))
    img = Image.alpha_composite(img, layer(S, (255, 255, 255), inner * .16))
    img = Image.alpha_composite(img, layer(S, (255, 255, 255), cap))
    return img.resize((size, size), Image.LANCZOS)


def mac_tile(size=1024):
    """Apple's macOS icon grid: an 824-point rounded tile centred in 1024, with an edge light and
    a two-layer shadow (0 12 28 black .40, 0 2 4 black .25)."""
    S = size * SS
    k = S / 1024
    tile = round(S * 824 / 1024)
    off = (S - tile) // 2
    radius = round(tile * 0.2237)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    for dy, bl, a in [(12, 28, .40), (2, 4, .25)]:
        shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle([off, off + dy * k, off + tile, off + tile + dy * k], radius=radius,
                                                 fill=(0, 0, 0, round(a * 255)))
        out = Image.alpha_composite(out, blur(shadow, bl * k))
    face = art(tile // SS).resize((tile, tile), Image.LANCZOS)
    # Edge light: a 0.5 pt (1 px at 1024) inner stroke, white .14, on the top half fading out by 50%.
    sw = 1 * k
    full = rrect_mask(tile, [0, 0, tile - 1, tile - 1], radius)
    inset = rrect_mask(tile, [sw, sw, tile - 1 - sw, tile - 1 - sw], radius - sw)
    fade = np.clip(1 - np.arange(tile) / (tile * .5), 0, 1)[:, None]
    face = Image.alpha_composite(face, layer(tile, (255, 255, 255), np.clip(full - inset, 0, 1) * fade * .14))
    mask = Image.fromarray((full * 255).round().astype(np.uint8), "L")
    tile_img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    tile_img.paste(face, (off, off), mask)
    out = Image.alpha_composite(out, tile_img)
    return out.resize((size, size), Image.LANCZOS)


def rounded(img, frac=0.2237):
    """A rounded-square launcher icon (for Android's legacy icon slots)."""
    w = img.size[0]
    mask = Image.new("L", (w * SS, w * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w * SS - 1, w * SS - 1], radius=w * SS * frac, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask.resize(img.size, Image.LANCZOS))
    return out


if __name__ == "__main__":
    full = art(1024)
    full.convert("RGB").save(os.path.join(ROOT, "ios/Meridian/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
    mac = mac_tile(1024)
    mac.save(os.path.join(ROOT, "Resources/AppIcon.png"))
    mac.save(os.path.join(ROOT, "docs/icon.png"))
    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        rounded(art(px * 2).resize((px, px), Image.LANCZOS)).save(
            os.path.join(ROOT, f"android/app/src/main/res/mipmap-{folder}/ic_launcher.png"))
    # The mark in share previews: the icon as a rounded tile.
    mark = rounded(art(528)).resize((264, 264), Image.LANCZOS)
    mark.save(os.path.join(ROOT, "ios/Meridian/Assets.xcassets/Mark.imageset/Mark.png"))
    mark.save(os.path.join(ROOT, "android/app/src/main/res/drawable-nodpi/mark.png"))  # Android Terms screen
    print("icons written")
