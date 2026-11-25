"""Shared drawing for Meridian's Mac App Store stages (scripts/mac-store-shots.py): fonts for the menu bar's
titles, continuous-corner masks and Apple's two-layer soft shadow.

The App Store pictures themselves (ground, headline, sub-line, the iPhone, and where a Mac stage sits) come from
the Cowdrey family's template, scripts/store-frame.mjs, run by scripts/store-frames.mjs.

Fonts: SF Pro when the machine has it (the macOS CI runners do), else Inter from Resources/Fonts.
Set STORE_FONT=inter to force Inter (for comparing on a Mac).

Python 3 and Pillow only.
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIR = os.path.join(ROOT, "Resources", "Fonts")


# ---------------------------------------------------------------------------------------------
# Fonts

_SF_STATIC = {
    "semibold": ("/System/Library/Fonts/SF-Pro-Display-Semibold.otf",
                 "/Library/Fonts/SF-Pro-Display-Semibold.otf"),
    "regular": ("/System/Library/Fonts/SF-Pro-Display-Regular.otf",
                "/Library/Fonts/SF-Pro-Display-Regular.otf"),
}
_SF_VARIABLE = ("/System/Library/Fonts/SFNS.ttf",)
_INTER = {"semibold": ("Inter-SemiBold.ttf", "Inter-Medium.ttf"), "regular": ("Inter-Regular.ttf",)}
_WEIGHT = {"semibold": 590, "regular": 400}


def _variable(path, weight, size):
    """SFNS.ttf at the given weight, with the display optical size for large text."""
    face = ImageFont.truetype(path, size)
    try:
        axes = face.get_variation_axes()
    except (OSError, AttributeError):
        return face   # not variable: take it as it is
    values = []
    for axis in axes:
        name = axis.get("name", b"")
        name = (name.decode("latin-1") if isinstance(name, bytes) else str(name)).lower()
        lo, hi = axis["minimum"], axis["maximum"]
        if "weight" in name or name == "wght":
            values.append(max(lo, min(hi, _WEIGHT[weight])))
        elif "optical" in name or name == "opsz":
            values.append(max(lo, min(hi, size / 2)))   # px at 2x/3x -> roughly points
        else:
            values.append(axis.get("default", lo))
    face.set_variation_by_axes(values)
    return face


def font(weight, size):
    """Returns (font, family) with family "sf" or "inter"."""
    if os.environ.get("STORE_FONT", "").lower() != "inter":
        for path in _SF_STATIC[weight]:
            if os.path.exists(path):
                try:
                    return ImageFont.truetype(path, size), "sf"
                except OSError:
                    pass
        for path in _SF_VARIABLE:
            if os.path.exists(path):
                try:
                    return _variable(path, weight, size), "sf"
                except (OSError, ValueError):
                    pass
    for name in _INTER[weight]:
        path = os.path.join(FONT_DIR, name)
        if os.path.exists(path):
            return ImageFont.truetype(path, size), "inter"
    raise SystemExit(f"[store-frame] no font for {weight}: SF Pro or {FONT_DIR}/Inter-*.ttf")


# ---------------------------------------------------------------------------------------------
# Text (Pillow has no tracking: each glyph is placed at its kerned advance plus the tracking)

def text_width(text, face, tracking):
    return face.getlength(text) + tracking * max(0, len(text) - 1)


def draw_tracked(layer, xy, text, face, tracking, fill):
    """Draws on an RGBA layer with the baseline at xy[1]."""
    draw = ImageDraw.Draw(layer)
    x0, baseline = xy
    for i, ch in enumerate(text):
        if ch == " ":
            continue
        x = x0 + face.getlength(text[:i]) + tracking * i
        draw.text((x, baseline), ch, font=face, fill=fill, anchor="ls")


# ---------------------------------------------------------------------------------------------
# Shapes (masks are drawn supersampled and reduced, so every curve is anti-aliased)

def squircle_points(box, radius, steps=24):
    """A rounded rectangle with continuous (Apple-style) corners: each corner is a superellipse
    that starts 1.28 radius from the corner, so the curve eases into the straight edge."""
    x0, y0, x1, y1 = box
    r = min(radius * 1.28, (x1 - x0) / 2, (y1 - y0) / 2)
    n = 5.0
    pts = []
    corners = ((x1 - r, y0 + r, 0), (x1 - r, y1 - r, 90), (x0 + r, y1 - r, 180), (x0 + r, y0 + r, 270))
    for cx, cy, start in corners:
        for k in range(steps + 1):
            t = math.radians(start - 90 + 90 * k / steps)
            c, s = math.cos(t), math.sin(t)
            px = cx + r * math.copysign(abs(c) ** (2 / n), c)
            py = cy + r * math.copysign(abs(s) ** (2 / n), s)
            pts.append((px, py))
    return pts


def shape_mask(size, box, radius, ss=3, continuous=True):
    """An L mask of `size` with a filled rounded rectangle at `box`."""
    w, h = size
    big = Image.new("L", (w * ss, h * ss), 0)
    draw = ImageDraw.Draw(big)
    bx = tuple(v * ss for v in box)
    if continuous:
        draw.polygon(squircle_points(bx, radius * ss), fill=255)
    else:
        draw.rounded_rectangle(bx, radius * ss, fill=255)
    return big.resize((w, h), Image.LANCZOS)


def ring_mask(size, box, radius, width, ss=3, continuous=True):
    """The band `width` px wide just inside the rounded rectangle at `box`."""
    outer = shape_mask(size, box, radius, ss, continuous)
    x0, y0, x1, y1 = box
    inner = shape_mask(size, (x0 + width, y0 + width, x1 - width, y1 - width), max(0, radius - width), ss, continuous)
    return ImageChops.subtract(outer, inner)


def linear(size, top_color, bottom_color, horizontal=False):
    """An RGB linear gradient."""
    w, h = size
    n = w if horizontal else h
    strip = Image.new("RGB", (n, 1) if horizontal else (1, n))
    for i in range(n):
        t = i / max(1, n - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(top_color, bottom_color))
        strip.putpixel((i, 0) if horizontal else (0, i), c)
    return strip.resize(size, Image.BILINEAR)


def solid(size, color, alpha_mask):
    layer = Image.new("RGBA", size, color + (0,) if len(color) == 3 else color)
    if len(color) == 4:
        alpha_mask = alpha_mask.point(lambda v: v * color[3] // 255)
    layer.putalpha(alpha_mask)
    return layer


# ---------------------------------------------------------------------------------------------
# Shadows: CSS box-shadow "0 dy blur rgba(0,0,0,a)" from a shape mask

def drop_shadow(canvas, mask, dy, blur, alpha):
    """Composites a soft black shadow of `mask` (canvas-sized L) onto canvas (RGBA)."""
    w, h = canvas.size
    k = 4 if blur >= 24 else 1   # blur big shadows small: fast, and smooth when scaled up
    small = mask.resize((max(1, w // k), max(1, h // k)), Image.BOX) if k > 1 else mask
    small = ImageChops.offset(small, 0, round(dy / k))
    if dy > 0:
        ImageDraw.Draw(small).rectangle((0, 0, small.width, round(dy / k) - 1), fill=0)
    small = small.filter(ImageFilter.GaussianBlur(blur / 2 / k))
    shadow = small.resize((w, h), Image.BICUBIC) if k > 1 else small
    canvas.alpha_composite(solid((w, h), (0, 0, 0), shadow.point(lambda v: round(v * alpha))))
