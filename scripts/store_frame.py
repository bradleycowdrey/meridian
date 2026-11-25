"""Drawing for Meridian's Mac App Store screenshots (scripts/mac-store-shots.py). The iPhone set is on the
Cowdrey family standard instead (scripts/appstore-shots.mjs, design/app-store/store-frame.mjs).

The look, from the finish spec: a deep navy-to-black gradient, a soft glow made from the capture
itself, a sky highlight near the top, a centred headline and subline, and the app in a frame drawn
in code (an iPhone body, or a floating Mac window) with Apple's two-layer soft shadow.

Fonts: SF Pro when the machine has it (the macOS CI runners do), else Inter from Resources/Fonts.
Set STORE_FONT=inter to force Inter (for comparing on a Mac).

Python 3 and Pillow only.
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIR = os.path.join(ROOT, "Resources", "Fonts")

# Background tokens.
GRADIENT = ((0.00, (0x0E, 0x1A, 0x33)), (0.45, (0x08, 0x10, 0x1F)), (1.00, (0x00, 0x00, 0x00)))
SKY = (0x4A, 0x80, 0xBD)


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


_HANGING = {"a", "an", "the", "your", "my", "and", "or", "every", "any", "each"}


def balanced_lines(text, face, tracking, max_width, max_lines=2):
    """One line if it fits, else the two-line break with the most even lines (as Apple sets them)."""
    if text_width(text, face, tracking) <= max_width or max_lines < 2:
        return [text]
    words = text.split()
    best = None
    for i in range(1, len(words)):
        a, b = " ".join(words[:i]), " ".join(words[i:])
        wa, wb = text_width(a, face, tracking), text_width(b, face, tracking)
        if max(wa, wb) > max_width:
            continue
        # Prefer an even pair, with the first line not much shorter than the second, and never
        # leave a small word hanging at the end of the first line.
        score = abs(wa - wb) + (max(0, wb - wa) * 0.5)
        if words[i - 1].lower().strip(",") in _HANGING:
            score += max_width
        if best is None or score < best[0]:
            best = (score, [a, b])
    return best[1] if best else None


def headline_block(width, text, sub, size, sub_size, tracking, max_width, gap, line_height=1.08):
    """Fits the headline (at most two lines) and the one-line subline.

    Returns a dict with the faces, lines and the block's height (top of the first line's em box
    to the bottom of the subline's)."""
    while True:
        face, family = font("semibold", size)
        track = tracking * size / 104 if family == "sf" else tracking * size / 104 - size * 0.008
        lines = balanced_lines(text, face, track, max_width)
        if lines or size <= 40:
            break
        size -= 2
    lines = lines or [text]
    s_size = sub_size
    while True:
        s_face, _ = font("regular", s_size)
        s_track = -0.2 * s_size / 50
        if text_width(sub, s_face, s_track) <= max_width or s_size <= 28:
            break
        s_size -= 1
    lh = round(size * line_height)
    height = lh * len(lines) + gap + round(s_size * 1.2)
    return {"face": face, "track": track, "lines": lines, "lh": lh, "size": size, "sub": sub,
            "s_face": s_face, "s_track": s_track, "s_size": s_size, "gap": gap,
            "height": height, "family": family}


def draw_headline(canvas, block, top, width):
    """Centred headline and subline; `top` is the top of the first line box."""
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    face, lh, size = block["face"], block["lh"], block["size"]
    ascent, descent = face.getmetrics()
    # Put the em box (ascent+descent scaled to the size) centred in each line box.
    em = ascent + descent
    for i, line in enumerate(block["lines"]):
        w = text_width(line, face, block["track"])
        baseline = top + i * lh + (lh - em) / 2 + ascent
        draw_tracked(layer, ((width - w) / 2, baseline), line, face, block["track"], (255, 255, 255, 255))
    s_face = block["s_face"]
    s_ascent, s_descent = s_face.getmetrics()
    s_top = top + lh * len(block["lines"]) + block["gap"]
    s_lh = round(block["s_size"] * 1.2)
    w = text_width(block["sub"], s_face, block["s_track"])
    baseline = s_top + (s_lh - (s_ascent + s_descent)) / 2 + s_ascent
    draw_tracked(layer, ((width - w) / 2, baseline), block["sub"], s_face, block["s_track"],
                 (255, 255, 255, round(255 * 0.64)))
    canvas.alpha_composite(layer)
    return s_top + s_lh


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


# ---------------------------------------------------------------------------------------------
# Background

def _gradient(size):
    w, h = size
    strip = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        for (t0, c0), (t1, c1) in zip(GRADIENT, GRADIENT[1:]):
            if t0 <= t <= t1:
                u = (t - t0) / (t1 - t0)
                u = u * u * (3 - 2 * u)   # smooth the joins
                strip.putpixel((0, y), tuple(round(a + (b - a) * u) for a, b in zip(c0, c1)))
                break
    return strip.resize(size, Image.BILINEAR)


def _radial(size, centre, radius, color, alpha, ellipse=1.0):
    """A soft radial light, `alpha` at the centre fading to 0 at `radius` (eased)."""
    w, h = size
    k = 8
    sw, sh = max(1, w // k), max(1, h // k)
    m = Image.new("L", (sw, sh))
    cx, cy, r = centre[0] / k, centre[1] / k, radius / k
    px = m.load()
    for y in range(sh):
        for x in range(sw):
            d = math.hypot(x - cx, (y - cy) / ellipse) / r
            v = max(0.0, 1 - d)
            px[x, y] = round(255 * alpha * v * v * (3 - 2 * v))
    m = m.resize((w, h), Image.BICUBIC)
    return solid((w, h), color, m)


def background(size, capture, plate_box, plate_scale=1.4, plate_alpha=0.28, glow_blur=120):
    """The designed backdrop: gradient, a glow plate made from the capture, a sky highlight."""
    w, h = size
    canvas = _gradient(size).convert("RGBA")

    # Glow plate: the capture, enlarged, blurred, a little more saturated, faint.
    if capture is not None:
        x0, y0, x1, y1 = plate_box
        pw, ph = round((x1 - x0) * plate_scale), round((y1 - y0) * plate_scale)
        k = 8
        small = capture.convert("RGB").resize((max(1, pw // k), max(1, ph // k)), Image.BOX)
        small = ImageEnhance.Color(small).enhance(1.2)
        pad = round(glow_blur * 1.5 / k)
        # Pad with the capture stretched, so the blur fades its own colours rather than black.
        framed = small.resize((small.width + 2 * pad, small.height + 2 * pad), Image.BILINEAR)
        framed.paste(small, (pad, pad))
        alpha = Image.new("L", framed.size, 0)
        alpha.paste(255, (pad, pad, pad + small.width, pad + small.height))
        framed = framed.filter(ImageFilter.GaussianBlur(glow_blur / k))
        alpha = alpha.filter(ImageFilter.GaussianBlur(glow_blur / k))
        plate = framed.convert("RGBA")
        plate.putalpha(alpha.point(lambda v: round(v * plate_alpha)))
        plate = plate.resize((framed.width * k, framed.height * k), Image.BICUBIC)
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        layer = Image.new("RGBA", size, (0, 0, 0, 0))
        layer.paste(plate, (round(cx - plate.width / 2), round(cy - plate.height / 2)))
        canvas.alpha_composite(layer)

    canvas.alpha_composite(_radial(size, (w * 0.5, h * 0.18 if h > w else h * 0.10), w * 0.6, SKY, 0.22,
                                   ellipse=1.0 if h > w else 0.75))
    return canvas


def dither(canvas, amount=0.018):
    """A trace of fine grain, so the long dark gradients don't band in PNG."""
    w, h = canvas.size
    if not amount:
        return canvas
    # Zero-mean grain: 128 +/- a little, added with an offset of -128.
    noise = Image.effect_noise((w, h), 40).point(lambda v: round(128 + (v - 128) * amount * 3))
    rgb = canvas.convert("RGB")
    out = ImageChops.add(rgb, Image.merge("RGB", (noise, noise, noise)), 1.0, -128)
    return out.convert("RGBA")


def finish(canvas, size, path):
    """Writes an RGB PNG (no alpha) at exactly `size`."""
    image = canvas.convert("RGB")
    assert image.size == size, (image.size, size)
    image.save(path, "PNG", optimize=True)
    return image
