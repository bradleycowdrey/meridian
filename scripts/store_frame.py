"""Shared drawing for Meridian's store screenshots (scripts/appstore-shots.py, scripts/mac-store-shots.py).

The look: Meridian's own deep navy-to-black gradient, a soft glow made from the capture itself and a
sky highlight near the top; the app in a frame drawn in code (an iPhone, or a Mac window).

The type, the caption layout and the device geometry follow the Cowdrey One App Store standard
(the same as Bearings' scripts/store-frames.js), so every app's screenshots match:
  eyebrow   SANS 600, uppercase, tracking 0.14em, white .82
  headline  Fraunces 560 (opsz 72), line-height 1.04, tracking -0.004em, white
  sub       SANS 600, line-height 1.2, tracking -0.01em, white .9, one line
One headline size and one sub size per set: the largest at which every line of every frame fits.

Fonts: TITLE is Fraunces (scripts/fonts/fraunces.woff2, OFL). SANS is SF Pro when the machine has it
(the macOS CI runners do; it is Apple's and never committed), else Inter SemiBold from
Resources/Fonts. Set STORE_FONT=inter to force Inter (for comparing on a Mac).

Python 3, Pillow and fontTools (with brotli, to read the woff2).
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIR = os.path.join(ROOT, "Resources", "Fonts")
TITLE_FONT = os.path.join(ROOT, "scripts", "fonts", "fraunces.woff2")

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
_WEIGHT = {"semibold": 600, "regular": 400}


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


_TITLE_AXES = {"wght": 560, "opsz": 72}
_title_path = None


def _title_ttf():
    """Fraunces at wght 560, opsz 72, as a static TTF (made once from the woff2 with fontTools)."""
    global _title_path
    if _title_path is None:
        import tempfile
        out = os.path.join(tempfile.gettempdir(), "store-frame-fonts", "Fraunces-560-opsz72.ttf")
        if not os.path.exists(out):
            from fontTools.ttLib import TTFont
            from fontTools.varLib import instancer
            face = TTFont(TITLE_FONT)
            static = instancer.instantiateVariableFont(face, dict(_TITLE_AXES))
            static.flavor = None
            os.makedirs(os.path.dirname(out), exist_ok=True)
            static.save(out + ".part")
            os.replace(out + ".part", out)
        _title_path = out
    return _title_path


def title_font(size):
    """The headline face: Fraunces 560, optical size 72."""
    try:
        return ImageFont.truetype(_title_ttf(), size)
    except ImportError:
        # No fontTools: let FreeType read the variable woff2 and set the axes itself.
        face = ImageFont.truetype(TITLE_FONT, size)
        names = [a["name"].decode("latin-1") if isinstance(a["name"], bytes) else str(a["name"])
                 for a in face.get_variation_axes()]
        face.set_variation_by_axes([_TITLE_AXES["opsz"] if "ptical" in n else _TITLE_AXES["wght"] for n in names])
        return face


def sans(size):
    """SANS weight 600: (face, family)."""
    return font("semibold", size)


# ---------------------------------------------------------------------------------------------
# Text, set as a browser sets it (Pillow has no tracking: each glyph is placed at its kerned
# advance plus the tracking, which CSS also adds after the last glyph, so it counts in the width)

def text_width(text, face, tracking):
    return face.getlength(text) + tracking * len(text)


def draw_tracked(layer, xy, text, face, tracking, fill):
    """Draws on an RGBA layer with the baseline at xy[1]."""
    draw = ImageDraw.Draw(layer)
    x0, baseline = xy
    for i, ch in enumerate(text):
        if ch == " ":
            continue
        x = x0 + face.getlength(text[:i]) + tracking * i
        draw.text((x, baseline), ch, font=face, fill=fill, anchor="ls")


def draw_line(layer, text, face, tracking, top, line_height, fill, centre_x):
    """One centred line in a CSS line box `line_height` tall starting at `top`: the font's
    ascent + descent sit centred in the box, as a browser lays it out."""
    ascent, descent = face.getmetrics()
    baseline = top + (line_height - (ascent + descent)) / 2 + ascent
    w = text_width(text, face, tracking)
    draw_tracked(layer, (centre_x - w / 2, baseline), text, face, tracking, fill)


# The caption layouts of the standard: where the block starts, its sizes and gaps.
IPHONE_CAPTION = {"top": 150, "side": 70, "eyebrow": 38, "gap1": 28, "head": 124, "gap2": 32, "sub": 52,
                  "head_floor": 96}
MAC_CAPTION = {"top": 112, "side": 300, "eyebrow": 40, "gap1": 24, "head": 104, "gap2": 24, "sub": 48,
               "head_floor": 72}

EYEBROW_FILL = (255, 255, 255, round(255 * 0.82))
HEAD_FILL = (255, 255, 255, 255)
SUB_FILL = (255, 255, 255, round(255 * 0.9))


def fit_sizes(layout, canvas_width, head_lines, subs):
    """One headline size and one sub size for the whole set: the largest (stepping down 2 px from
    the maximum) at which every headline line and every sub fits the caption width on one line."""
    room = canvas_width - 2 * layout["side"]

    def fits(lines, face_for, track_em, size):
        face = face_for(size)
        return all(text_width(l, face, track_em * size) <= room for l in lines)

    head = layout["head"]
    while head > layout["head_floor"] and not fits(head_lines, title_font, -0.004, head):
        head -= 2
    if not fits(head_lines, title_font, -0.004, head):
        raise SystemExit(f"[store-frame] a headline line is wider than {room} px even at {head} px")
    sub = layout["sub"]
    while sub > 24 and not fits(subs, lambda z: sans(z)[0], -0.01, sub):
        sub -= 2
    return head, sub


def draw_caption(canvas, layout, eyebrow, head_lines, sub, head_size, sub_size):
    """The eyebrow, headline and sub, centred. Returns a dict of where each sits (for checks)."""
    W = canvas.width
    cx = W / 2
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    y = layout["top"]
    e_size = layout["eyebrow"]
    e_face, _ = sans(e_size)
    draw_line(layer, eyebrow.upper(), e_face, 0.14 * e_size, y, e_size, EYEBROW_FILL, cx)
    marks = {"eyebrow_top": y, "eyebrow_size": e_size}
    y += e_size + layout["gap1"]
    h_face = title_font(head_size)
    lh = head_size * 1.04
    marks["head_top"], marks["head_size"] = y, head_size
    for line in head_lines:
        draw_line(layer, line, h_face, -0.004 * head_size, y, lh, HEAD_FILL, cx)
        y += lh
    y += layout["gap2"]
    s_face, _ = sans(sub_size)
    s_lh = sub_size * 1.2
    marks["sub_top"], marks["sub_size"] = y, sub_size
    draw_line(layer, sub, s_face, -0.01 * sub_size, y, s_lh, SUB_FILL, cx)
    marks["bottom"] = y + s_lh
    canvas.alpha_composite(layer)
    return marks


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


def stops_strip(n, stops):
    """A 1-pixel-high RGB strip `n` long through CSS-style colour stops [(t, (r, g, b)), ...]."""
    strip = Image.new("RGB", (n, 1))
    for i in range(n):
        t = i / max(1, n - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                u = (t - t0) / max(1e-9, t1 - t0)
                strip.putpixel((i, 0), tuple(round(a + (b - a) * u) for a, b in zip(c0, c1)))
                break
    return strip


def diagonal(size, stops):
    """CSS linear-gradient(135deg, ...) over a box of `size`: top-left to bottom-right."""
    w, h = size
    strip = stops_strip(w + h, stops)
    # Each pixel takes the strip's colour at x + y.
    return strip.transform((w, h), Image.AFFINE, (1, 1, 0, 0, 0, 0), resample=Image.BILINEAR)


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

def drop_shadow(canvas, mask, dy, blur, alpha, color=(0, 0, 0)):
    """Composites a soft black shadow of `mask` (canvas-sized L) onto canvas (RGBA)."""
    w, h = canvas.size
    k = 4 if blur >= 24 else 1   # blur big shadows small: fast, and smooth when scaled up
    small = mask.resize((max(1, w // k), max(1, h // k)), Image.BOX) if k > 1 else mask
    small = ImageChops.offset(small, 0, round(dy / k))
    if dy > 0:
        ImageDraw.Draw(small).rectangle((0, 0, small.width, round(dy / k) - 1), fill=0)
    small = small.filter(ImageFilter.GaussianBlur(blur / 2 / k))
    shadow = small.resize((w, h), Image.BICUBIC) if k > 1 else small
    canvas.alpha_composite(solid((w, h), color, shadow.point(lambda v: round(v * alpha))))


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
