#!/usr/bin/env python3
"""Draws Meridian's app icon in the app's colours (the Two Degrees sky: day blue into night navy,
white type), with no band along the top.

The mark: four days as bars of light and dark (one per city), crossed by the "now" capsule.

  python3 scripts/make-icon.py      (needs Pillow)

Writes the iPhone icon (full-bleed square; iOS rounds the corners), the Mac icon (Apple's macOS
rounded tile with its margin and soft shadow), docs/icon.png, the share-preview mark and the Android launcher icons.
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
SS = 4  # supersampling


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def hexc(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255)


SKY = [(0.0, hexc(0x4A80BD)), (0.5, hexc(0x1F416B)), (1.0, hexc(0x0B1022))]
# Each bar: daylight as (position 0..1, white opacity) stops, left to right.
BARS = [
    [(0, .12), (.18, .30), (.38, .92), (1, .95)],          # morning: night into day
    [(0, .95), (.45, .92), (.70, .25), (1, .12)],          # afternoon into night
    [(0, .90), (.22, .85), (.42, .20), (1, .12)],          # evening
    [(0, .12), (.55, .14), (.78, .55), (1, .92)],          # before dawn
]


def art(size):
    """Full-bleed square artwork at `size` pixels."""
    S = size * SS
    t = np.linspace(0, 1, S)[:, None]
    stops = np.array([p for p, _ in SKY])
    rgb = np.stack([np.interp(t[:, 0], stops, [c[i] for _, c in SKY]) for i in range(3)], axis=1)
    sky = np.repeat(rgb[:, None, :], S, axis=1)
    img = Image.fromarray(np.dstack([sky, np.full((S, S), 255.0)]).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)

    left, right, h = 0.165 * S, 0.835 * S, 0.098 * S
    centers = [0.30, 0.445, 0.59, 0.735]
    xs = np.clip((np.arange(S) - left) / (right - left), 0, 1)
    for stops_, cy in zip(BARS, centers):
        top = cy * S - h / 2
        alpha = np.interp(xs, [p for p, _ in stops_], [a for _, a in stops_])
        layer = np.zeros((S, S, 4))
        layer[..., :3] = 255
        layer[..., 3] = np.broadcast_to(alpha * 255, (S, S))
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).rounded_rectangle([left, top, right, top + h], radius=h / 2, fill=255)
        bar = Image.fromarray(layer.astype(np.uint8), "RGBA")
        bar.putalpha(Image.fromarray((np.asarray(mask, float) / 255 * layer[..., 3]).astype(np.uint8), "L"))
        img = Image.alpha_composite(img, bar)

    # The "now" capsule: a white outline over a faint glass fill, with a soft glow.
    cw = 0.112 * S
    cx0, cx1 = S / 2 - cw / 2, S / 2 + cw / 2
    cy0, cy1 = 0.215 * S, 0.82 * S
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle([cx0, cy0, cx1, cy1], radius=cw / 2, outline=(255, 255, 255, 120), width=round(0.03 * S))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(0.012 * S)))
    cap = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cap)
    cd.rounded_rectangle([cx0, cy0, cx1, cy1], radius=cw / 2, fill=(255, 255, 255, 34))
    cd.rounded_rectangle([cx0, cy0, cx1, cy1], radius=cw / 2, outline=(255, 255, 255, 255), width=round(0.019 * S))
    img = Image.alpha_composite(img, cap)
    return img.resize((size, size), Image.LANCZOS)


def mac_tile(size=1024):
    """Apple's macOS icon grid: an 824-point rounded tile centred in 1024, with a soft shadow."""
    S = size * SS
    tile = round(S * 824 / 1024)
    off = (S - tile) // 2
    radius = round(tile * 0.2237)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([off, off + S * 0.012, off + tile, off + tile + S * 0.012], radius=radius, fill=(0, 0, 0, 110))
    out = Image.alpha_composite(out, shadow.filter(ImageFilter.GaussianBlur(S * 0.014)))
    face = art(tile // SS * SS // SS).resize((tile, tile), Image.LANCZOS)
    mask = Image.new("L", (tile, tile), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, tile - 1, tile - 1], radius=radius, fill=255)
    out.paste(face, (off, off), mask)
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
    rounded(art(528)).resize((264, 264), Image.LANCZOS).save(os.path.join(ROOT, "ios/Meridian/Assets.xcassets/Mark.imageset/Mark.png"))
    print("icons written")
