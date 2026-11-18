#!/usr/bin/env python3
"""Mac App Store screenshots for Meridian, composed from the self-test's renders.

    scripts/mac-store-shots.py <selftest dir> <out dir> [--photos <dir>]

<selftest dir> is what `Meridian --selftest <dir>` wrote. It reads:
  store-panel.png        the menu bar panel at 2x (falls back to menubar-panel.png, upscaled)
  store-widget-large.png the widgets at 3x (fall back to widget-*.png, 2x)
  store-widget-medium.png
  store-widget-small.png
  store-window.png       the desktop window at Large, 2x (optional)

and writes 01-*.png ... into <out dir>: 3 to 5 images, each exactly 2880x1800 RGB (no alpha),
the size the Mac App Store takes for 16:10 screenshots. Each puts the app on a dark desktop made
from a blurred night skyline (Android's copies of the city photos; a navy gradient without them)
with one caption line in white, set in Inter from Resources/Fonts.

A missing optional input skips that shot. It always makes at least 3 from the panel and the
widgets, and exits with an error if it can't (no panel at all).

Python 3 and Pillow only.
"""
import argparse
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageStat

W, H = 2880, 1800
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIR = os.path.join(ROOT, "Resources", "Fonts")
PHOTO_DIR = os.path.join(ROOT, "android", "app", "src", "main", "res", "drawable-nodpi")

# Caption band at the top, the app below it.
CAPTION_Y = 150          # top of the caption line
CAPTION_SIZE = 84
STAGE_TOP = 330          # where the app's area starts
STAGE_BOTTOM = H - 120   # and ends
NAVY = (9, 14, 34)


def log(message):
    print(f"[store-shots] {message}")


# ---------------------------------------------------------------------------------------------
# Inputs

def load(path):
    try:
        image = Image.open(path)
        image.load()
        return image.convert("RGBA")
    except (OSError, ValueError):
        return None


def mostly_blank(image):
    """True for an all-one-colour render (a capture that drew nothing)."""
    stat = ImageStat.Stat(image.convert("L"))
    return stat.stddev[0] < 3


def matches(big, small):
    """Whether a high-resolution render shows the same thing as the 1x capture."""
    if small is None:
        return True
    reduced = big.resize(small.size, Image.LANCZOS).convert("RGB")
    diff = ImageChops.difference(reduced, small.convert("RGB"))
    return sum(ImageStat.Stat(diff).mean) / 3 < 24


def pick_panel(src):
    """The menu bar panel at the highest resolution that's sound."""
    small = load(os.path.join(src, "menubar-panel.png"))
    big = load(os.path.join(src, "store-panel.png"))
    if big is not None and not mostly_blank(big) and matches(big, small):
        return big, "store-panel.png"
    if big is not None:
        log("store-panel.png looks wrong (blank or not the panel); using menubar-panel.png")
    if small is not None and not mostly_blank(small):
        # 1x capture: bring it to 2x so it's placed like the 2x render.
        up = small.resize((small.width * 2, small.height * 2), Image.LANCZOS)
        return up.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2)), "menubar-panel.png (upscaled)"
    return None, None


def pick_widget(src, name):
    """A widget face, normalised to 3x (the store render; the 2x one scaled up to match)."""
    big = load(os.path.join(src, f"store-widget-{name}.png"))
    if big is not None and not mostly_blank(big):
        return big
    small = load(os.path.join(src, f"widget-{name}.png"))
    if small is not None and not mostly_blank(small):
        return small.resize((small.width * 3 // 2, small.height * 3 // 2), Image.LANCZOS)
    return None


def pick_window(src):
    big = load(os.path.join(src, "store-window.png"))
    if big is not None and not mostly_blank(big):
        return big
    return None


# ---------------------------------------------------------------------------------------------
# Drawing

def font(size):
    for name in ("Inter-Medium.ttf", "Inter-SemiBold.ttf", "Inter-Regular.ttf"):
        path = os.path.join(FONT_DIR, name)
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    for path in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc",
                 "/Library/Fonts/Arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                pass
    try:
        return ImageFont.load_default(size)   # Pillow 10.1+
    except TypeError:
        return ImageFont.load_default()


def backdrop(photo_key, photos):
    """A dark desktop: the city's night skyline, blurred and dimmed, under a navy wash."""
    canvas = None
    path = os.path.join(photos, f"skyline_{photo_key}_night.jpg") if photo_key else ""
    if path and os.path.exists(path):
        try:
            photo = Image.open(path).convert("RGB")
            # Cover 16:10, blur small (fast and smooth), then scale up.
            pw, ph = photo.size
            target = 16 / 10
            if pw / ph > target:
                cw = int(ph * target)
                photo = photo.crop(((pw - cw) // 2, 0, (pw - cw) // 2 + cw, ph))
            else:
                ch = int(pw / target)
                photo = photo.crop((0, (ph - ch) // 2, pw, (ph - ch) // 2 + ch))
            small = photo.resize((360, 225), Image.LANCZOS).filter(ImageFilter.GaussianBlur(9))
            small = ImageEnhance.Color(small).enhance(1.25)
            canvas = small.resize((W, H), Image.BICUBIC)
        except OSError:
            canvas = None
    if canvas is None:
        canvas = Image.new("RGB", (W, H), NAVY)

    # Navy wash: heavier at the top (behind the caption) and the bottom, lighter in the middle.
    wash = Image.new("RGB", (W, H), NAVY)
    mask = Image.new("L", (1, H))
    for y in range(H):
        t = y / (H - 1)
        mask.putpixel((0, y), int(255 * (0.74 - 0.34 * (1 - abs(2 * t - 0.9)))))
    canvas = Image.composite(wash, canvas, mask.resize((W, H)))

    # Soft vignette towards the corners.
    vignette = Image.new("L", (W // 8, H // 8), 0)
    ImageDraw.Draw(vignette).ellipse((-W // 40, -H // 40, W // 8 + W // 40, H // 8 + H // 40), fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(40)).resize((W, H), Image.BICUBIC)
    canvas = Image.composite(canvas, Image.new("RGB", (W, H), (0, 0, 0)), vignette.point(lambda v: 110 + v * 145 // 255))

    # A touch of grain so the gradients don't band.
    noise = Image.effect_noise((W // 2, H // 2), 6).resize((W, H), Image.NEAREST)
    canvas = Image.blend(canvas, Image.merge("RGB", (noise, noise, noise)), 0.025)
    return canvas


def rounded(image, radius):
    """The image with rounded corners (combined with any transparency it already has)."""
    mask = Image.new("L", (image.width * 2, image.height * 2), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, mask.width - 1, mask.height - 1), radius * 2, fill=255)
    mask = mask.resize(image.size, Image.LANCZOS)
    out = image.copy()
    out.putalpha(ImageChops.multiply(image.getchannel("A"), mask))
    return out


def hairline(image, radius, alpha=40):
    """A faint light edge, as macOS draws round dark windows."""
    line = Image.new("L", (image.width * 2, image.height * 2), 0)
    ImageDraw.Draw(line).rounded_rectangle((1, 1, line.width - 2, line.height - 2), radius * 2, outline=alpha, width=3)
    line = line.resize(image.size, Image.LANCZOS)
    white = Image.new("RGBA", image.size, (255, 255, 255, 0))
    white.putalpha(line)
    return Image.alpha_composite(image, white)


def place(canvas, image, x, y):
    """Pastes the image with a soft drop shadow, as a window on the desktop."""
    alpha = image.getchannel("A")
    pad = 160
    shadow = Image.new("L", (image.width + 2 * pad, image.height + 2 * pad), 0)
    shadow.paste(alpha.point(lambda a: a * 150 // 255), (pad, pad))
    shadow = shadow.resize((shadow.width // 4, shadow.height // 4), Image.LANCZOS)
    shadow = shadow.filter(ImageFilter.GaussianBlur(14)).resize((image.width + 2 * pad, image.height + 2 * pad), Image.BICUBIC)
    black = Image.new("RGB", shadow.size, (0, 0, 0))
    canvas.paste(black, (x - pad, y - pad + 28), shadow)
    canvas.paste(image, (x, y), image)


def scaled(image, factor):
    return image.resize((max(1, round(image.width * factor)), max(1, round(image.height * factor))), Image.LANCZOS)


def fit(image, max_w, max_h, max_factor):
    return scaled(image, min(max_w / image.width, max_h / image.height, max_factor))


def caption(canvas, text):
    draw = ImageDraw.Draw(canvas)
    face = font(CAPTION_SIZE)
    size = CAPTION_SIZE
    while draw.textlength(text, font=face) > W - 320 and size > 48:
        size -= 4
        face = font(size)
    width = draw.textlength(text, font=face)
    draw.text(((W - width) / 2, CAPTION_Y), text, font=face, fill=(255, 255, 255))


def finish(canvas, out_dir, name):
    image = canvas.convert("RGB")
    assert image.size == (W, H), image.size
    path = os.path.join(out_dir, name)
    image.save(path, "PNG", optimize=True)
    log(f"wrote {name} {image.width}x{image.height} {image.mode}")
    return path


# ---------------------------------------------------------------------------------------------
# The shots

def panel_shot(panel, text, photo, photos):
    canvas = backdrop(photo, photos)
    caption(canvas, text)
    art = fit(panel, W - 640, STAGE_BOTTOM - STAGE_TOP, 1.35)
    art = hairline(rounded(art, round(22 * art.width / panel.width)), round(22 * art.width / panel.width))
    place(canvas, art, (W - art.width) // 2, STAGE_TOP + (STAGE_BOTTOM - STAGE_TOP - art.height) // 2)
    return canvas


def widgets_shot(large, medium, small, text, photo, photos):
    """Large on the left; medium over small on the right, as on a desktop."""
    canvas = backdrop(photo, photos)
    caption(canvas, text)
    gap_pt = 24
    # Work in the widgets' own points (3x renders), then scale the group to fit.
    lw, lh = large.width / 3, large.height / 3
    right = [w for w in (medium, small) if w is not None]
    rw = max((w.width / 3 for w in right), default=0)
    group_w = lw + (gap_pt + rw if right else 0)
    group_h = max(lh, sum(w.height / 3 for w in right) + gap_pt * (len(right) - 1))
    factor = min((W - 700) / group_w, (STAGE_BOTTOM - STAGE_TOP) / group_h, 3.2)
    x0 = round((W - group_w * factor) / 2)
    y0 = round(STAGE_TOP + (STAGE_BOTTOM - STAGE_TOP - group_h * factor) / 2)
    place(canvas, scaled(large, factor / 3), x0, y0)
    y = y0
    for w in right:
        art = scaled(w, factor / 3)
        place(canvas, art, round(x0 + (lw + gap_pt) * factor), y)
        y += art.height + round(gap_pt * factor)
    return canvas


def panel_and_widget_shot(panel, widget, text, photo, photos):
    """The panel with a widget beside it, as on a desktop in use."""
    canvas = backdrop(photo, photos)
    caption(canvas, text)
    stage_h = STAGE_BOTTOM - STAGE_TOP
    gap = 64
    # Widget about as tall as the stage allows, the panel taking the rest of the width.
    wgt = scaled(widget, min((stage_h - 120) / widget.height, 1.0))
    p = fit(panel, W - 2 * 130 - gap - wgt.width, stage_h - 120, 1.25)
    if p.height > wgt.height:   # keep the pair balanced
        wgt = scaled(widget, p.height / widget.height)
    radius = round(22 * p.width / panel.width)
    p = hairline(rounded(p, radius), radius)
    total = p.width + gap + wgt.width
    x = (W - total) // 2
    place(canvas, p, x, STAGE_TOP + (stage_h - p.height) // 2)
    place(canvas, wgt, x + p.width + gap, STAGE_TOP + (stage_h - wgt.height) // 2)
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("selftest_dir")
    parser.add_argument("out_dir")
    parser.add_argument("--photos", default=PHOTO_DIR, help="folder of skyline_<city>_night.jpg backdrops")
    args = parser.parse_args()

    src, out, photos = args.selftest_dir, args.out_dir, args.photos
    os.makedirs(out, exist_ok=True)
    # Clear earlier shots so a skipped one can't linger and be uploaded.
    for name in os.listdir(out):
        if name.lower().endswith(".png"):
            os.remove(os.path.join(out, name))

    panel, panel_source = pick_panel(src)
    if panel is None:
        sys.exit("[store-shots] no panel render (store-panel.png or menubar-panel.png) in " + src)
    log(f"panel from {panel_source}, {panel.width}x{panel.height}")
    large, medium, small = (pick_widget(src, n) for n in ("large", "medium", "small"))
    window = pick_window(src)
    log("widgets: " + ", ".join(f"{n} {'yes' if w is not None else 'missing'}"
                                for n, w in (("large", large), ("medium", medium), ("small", small))))
    log(f"window: {'yes' if window is not None else 'missing'}")

    shots = [("01-menu-bar.png", lambda: panel_shot(
        panel, "Every time zone at a glance, in your menu bar.", "newyork", photos))]
    if large is not None:
        shots.append(("02-widgets.png", lambda: widgets_shot(
            large, medium, small, "Desktop widgets, each city on its skyline.", "tokyo", photos)))
        shots.append(("03-working-hours.png", lambda: panel_and_widget_shot(
            panel, large, "Working hours, weekends and holidays for every country.", "paris", photos)))
    elif medium is not None:
        shots.append(("02-widgets.png", lambda: widgets_shot(
            medium, None, small, "Desktop widgets, each city on its skyline.", "tokyo", photos)))
    if window is not None:
        shots.append(("04-window.png", lambda: panel_shot(
            window, "Open it as a window, in five sizes.", "london", photos)))
    # Never fewer than three: more of the panel, on other cities.
    extra = [("05-day-and-night.png", "Each city by day or by night, on its own skyline.", "hongkong"),
             ("06-who-is-working.png", "See who is working, wherever they are.", "sydney")]
    while len(shots) < 3 and extra:
        name, text, photo = extra.pop(0)
        shots.append((name, lambda text=text, photo=photo: panel_shot(panel, text, photo, photos)))

    for name, make in shots[:5]:
        finish(make(), out, name)
    log(f"{min(len(shots), 5)} screenshots in {out}")


if __name__ == "__main__":
    main()
