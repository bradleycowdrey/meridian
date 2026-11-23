#!/usr/bin/env python3
"""Mac App Store screenshots for Meridian, composed from the self-test's renders.

    scripts/mac-store-shots.py <selftest dir> <out dir>

<selftest dir> is what `Meridian --selftest <dir>` wrote. It reads:
  store-panel.png        the menu bar panel at 2x (falls back to menubar-panel.png, upscaled)
  store-widget-large.png the widgets at 3x (fall back to widget-*.png, 2x)
  store-widget-medium.png
  store-widget-small.png
  store-window.png       the desktop window at Large, 2x (optional)

and writes 01-*.png ... into <out dir>: 3 to 5 images, each exactly 2880x1800 RGB (no alpha),
the size the Mac App Store takes for 16:10 screenshots. Each has a headline and subline over a
dark navy backdrop (with a glow made from the app itself), and the app as a floating window with
Apple's soft two-layer shadow; the first hangs the panel from a translucent menu bar.

A missing optional input skips that shot. It always makes at least 3 from the panel and the
widgets, and exits with an error if it can't (no panel at all).

Fonts: SF Pro when present (macOS), else Inter from Resources/Fonts. Python 3 and Pillow only.
"""
import argparse
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageStat

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import store_frame as sf  # noqa: E402

W, H = 2880, 1800

HEADLINE_TOP = 120
HEADLINE_SIZE = 88
HEADLINE_TRACKING = -1.2 * 104 / 88    # store_frame scales tracking by size/104; this gives -1.2 at 88
SUBLINE_SIZE = 44
SUBLINE_GAP = 18
TEXT_WIDTH = 2400
CLEARANCE = 64                         # text to frame top, at least

STAGE_TOP = 400                        # the frame's top
STAGE_W, STAGE_H = 2240, 1300          # the largest a frame gets
WINDOW_RADIUS = 20

MENU_BAR_Y = 372                       # the menu bar strip in the first shot
MENU_BAR_H = 74


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

def scaled(image, factor):
    return image.resize((max(1, round(image.width * factor)), max(1, round(image.height * factor))), Image.LANCZOS)


def stage(headline, subline, glow_source, glow_box):
    """The backdrop and the headline; returns the canvas and the text's bottom edge."""
    canvas = sf.background((W, H), glow_source, glow_box, plate_scale=1.3, plate_alpha=0.26)
    block = sf.headline_block(W, headline, subline, HEADLINE_SIZE, SUBLINE_SIZE, HEADLINE_TRACKING,
                              TEXT_WIDTH, SUBLINE_GAP)
    bottom = sf.draw_headline(canvas, block, HEADLINE_TOP, W)
    return canvas, bottom


def check_clear(bottom, frame_top):
    if frame_top - bottom < CLEARANCE:
        log(f"warning: text ends {frame_top - bottom:.0f} px above the frame (want {CLEARANCE})")


def window(canvas, art, x, y, radius=WINDOW_RADIUS):
    """A floating window: continuous corners, a 1 px white .14 edge, and the two-layer shadow
    (0 50 140 black .6, plus 0 10 30 black .4)."""
    box = (x, y, x + art.width, y + art.height)
    mask = sf.shape_mask(canvas.size, box, radius)
    sf.drop_shadow(canvas, mask, 50, 140, 0.60)
    sf.drop_shadow(canvas, mask, 10, 30, 0.40)
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer.paste(art.convert("RGBA"), (x, y))
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    canvas.alpha_composite(layer)
    canvas.alpha_composite(sf.solid(canvas.size, (255, 255, 255, 36), sf.ring_mask(canvas.size, box, radius, 1)))


def widget(canvas, art, x, y):
    """A widget face (its own rounded alpha), lifted: 0 24 60 black .55, plus 0 2 6 black .35,
    with a faint light edge as macOS draws it."""
    alpha = Image.new("L", canvas.size, 0)
    alpha.paste(art.getchannel("A"), (x, y))
    sf.drop_shadow(canvas, alpha, 24, 60, 0.55)
    sf.drop_shadow(canvas, alpha, 2, 6, 0.35)
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer.paste(art, (x, y))
    canvas.alpha_composite(layer)
    edge = ImageChops.subtract(alpha, alpha.filter(ImageFilter.MinFilter(3)))
    canvas.alpha_composite(sf.solid(canvas.size, (255, 255, 255, 26), edge))


def fit(image, max_w=STAGE_W, max_h=STAGE_H, max_factor=1.4):
    return scaled(image, min(max_w / image.width, max_h / image.height, max_factor))


# ---------------------------------------------------------------------------------------------
# Menu bar (first shot)

def _icon_layer(size_px, draw_fn, ss=4):
    big = Image.new("L", (size_px * ss, size_px * ss), 0)
    draw_fn(ImageDraw.Draw(big), size_px * ss)
    return big.resize((size_px, size_px), Image.LANCZOS)


def _globe(draw, s):
    w = max(1, round(s * 0.075))
    pad = w
    draw.ellipse((pad, pad, s - pad, s - pad), outline=255, width=w)
    draw.ellipse((s * 0.30, pad, s * 0.70, s - pad), outline=255, width=w)
    draw.line((pad, s / 2, s - pad, s / 2), fill=255, width=w)
    draw.arc((s * 0.08, s * 0.10, s * 0.92, s * 0.50), 20, 160, fill=255, width=w)
    draw.arc((s * 0.08, s * 0.50, s * 0.92, s * 0.90), 200, 340, fill=255, width=w)


def _wifi(draw, s):
    w = max(1, round(s * 0.10))
    cx, cy = s / 2, s * 0.86
    for r in (0.80, 0.54):
        R = s * r
        draw.arc((cx - R, cy - R, cx + R, cy + R), 225, 315, fill=255, width=w)
    R = s * 0.28
    draw.pieslice((cx - R, cy - R, cx + R, cy + R), 225, 315, fill=255)


def _battery(draw, s):
    w = max(1, round(s * 0.06))
    top, bottom = s * 0.30, s * 0.70
    draw.rounded_rectangle((s * 0.02, top, s * 0.86, bottom), radius=s * 0.10, outline=255, width=w)
    draw.rounded_rectangle((s * 0.02 + w * 2, top + w * 2, s * 0.86 - w * 2, bottom - w * 2), radius=s * 0.05, fill=255)
    draw.rounded_rectangle((s * 0.90, s * 0.43, s * 0.97, s * 0.57), radius=s * 0.03, fill=255)


def menu_bar(canvas, icon_x):
    """A 2880-wide translucent menu bar strip with Meridian's globe highlighted at icon_x."""
    y0, y1 = MENU_BAR_Y, MENU_BAR_Y + MENU_BAR_H
    region = canvas.crop((0, y0, W, y1)).convert("RGB")
    blurred = region.resize((W // 8, MENU_BAR_H // 8 or 1), Image.BOX).filter(ImageFilter.GaussianBlur(3))
    blurred = blurred.resize((W, MENU_BAR_H), Image.BICUBIC)
    strip = Image.blend(blurred, Image.new("RGB", blurred.size, (0, 0, 0)), 0.35).convert("RGBA")
    canvas.paste(strip, (0, y0))
    hair = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(hair).rectangle((0, y1 - 1, W, y1 - 1), fill=255)
    canvas.alpha_composite(sf.solid(canvas.size, (255, 255, 255, 18), hair))
    hair = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(hair).rectangle((0, y0, W, y0), fill=255)
    canvas.alpha_composite(sf.solid(canvas.size, (255, 255, 255, 14), hair))

    cy = y0 + MENU_BAR_H / 2
    # The front app's menus on the left (Finder, as on a fresh desktop).
    text = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    x = 56
    for i, title in enumerate(("Finder", "File", "Edit", "View", "Go", "Window", "Help")):
        face, _ = sf.font("semibold" if i == 0 else "regular", 27)
        ascent, descent = face.getmetrics()
        sf.draw_tracked(text, (x, cy + (ascent - descent) / 2), title, face, 0, (255, 255, 255, 235))
        x += face.getlength(title) + 44
    canvas.alpha_composite(text)
    # The Meridian item, highlighted as it is while its panel is open.
    hw, hh = 76, 50
    sel = (icon_x - hw / 2, cy - hh / 2, icon_x + hw / 2, cy + hh / 2)
    canvas.alpha_composite(sf.solid(canvas.size, (255, 255, 255, 52), sf.shape_mask(canvas.size, sel, 10)))
    items = [(icon_x, 32, _globe, 255)]
    # The system items to its right.
    x = icon_x + hw / 2 + 52
    for fn, size in ((_wifi, 34), (_battery, 46)):
        items.append((x + size / 2, size, fn, 235))
        x += size + 40
    for cx, size, fn, alpha in items:
        m = _icon_layer(size, fn)
        layer = Image.new("L", canvas.size, 0)
        layer.paste(m, (round(cx - size / 2), round(cy - size / 2)))
        canvas.alpha_composite(sf.solid(canvas.size, (255, 255, 255, alpha), layer))
    return y1


# ---------------------------------------------------------------------------------------------
# The shots

def menu_bar_shot(panel, headline, subline):
    art = fit(panel, STAGE_W, H - (MENU_BAR_Y + MENU_BAR_H + 12) - 90, 1.1)
    # Hang it at the right third, under the menu bar item.
    icon_x = round(W * 2 / 3)
    x = min(max(icon_x - art.width // 2, 140), W - 140 - art.width)
    y = MENU_BAR_Y + MENU_BAR_H + 12
    canvas, bottom = stage(headline, subline, panel, (x, y, x + art.width, y + art.height))
    check_clear(bottom, MENU_BAR_Y)
    menu_bar(canvas, icon_x)
    window(canvas, art, x, y, radius=round(WINDOW_RADIUS * art.width / panel.width * 1.1))
    return canvas


def framed_shot(image, headline, subline):
    art = fit(image)
    x = (W - art.width) // 2
    canvas, bottom = stage(headline, subline, image, (x, STAGE_TOP, x + art.width, STAGE_TOP + art.height))
    check_clear(bottom, STAGE_TOP)
    window(canvas, art, x, STAGE_TOP)
    return canvas


def widgets_shot(large, medium, small, headline, subline):
    """Large on the left; medium over small on the right, as on a desktop."""
    gap_pt = 28
    lw, lh = large.width / 3, large.height / 3
    right = [w for w in (medium, small) if w is not None]
    rw = max((w.width / 3 for w in right), default=0)
    group_w = lw + (gap_pt + rw if right else 0)
    group_h = max(lh, sum(w.height / 3 for w in right) + gap_pt * (len(right) - 1))
    factor = min(STAGE_W / group_w, STAGE_H / group_h, 3.2)
    x0 = round((W - group_w * factor) / 2)
    y0 = STAGE_TOP + round((STAGE_H - group_h * factor) / 2 * 0.6)
    canvas, bottom = stage(headline, subline, large, (x0, y0, x0 + round(group_w * factor), y0 + round(group_h * factor)))
    check_clear(bottom, y0)
    widget(canvas, scaled(large, factor / 3), x0, y0)
    y = y0
    for w in right:
        art = scaled(w, factor / 3)
        widget(canvas, art, round(x0 + (lw + gap_pt) * factor), y)
        y += art.height + round(gap_pt * factor)
    return canvas


def panel_and_widget_shot(panel, large, headline, subline):
    """The panel with the large widget beside it, at the same physical scale (2x and 3x renders)."""
    gap = 96
    w_art = scaled(large, 2 / 3)
    group_w = panel.width + gap + w_art.width
    group_h = max(panel.height, w_art.height)
    factor = min(STAGE_W / group_w, STAGE_H / group_h, 1.3)
    p = scaled(panel, factor)
    wg = scaled(w_art, factor)
    total = p.width + round(gap * factor) + wg.width
    x = (W - total) // 2
    canvas, bottom = stage(headline, subline, panel, (x, STAGE_TOP, x + total, STAGE_TOP + p.height))
    check_clear(bottom, STAGE_TOP)
    window(canvas, p, x, STAGE_TOP)
    widget(canvas, wg, x + p.width + round(gap * factor), STAGE_TOP + (p.height - wg.height) // 2)
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("selftest_dir")
    parser.add_argument("out_dir")
    args = parser.parse_args()

    src, out = args.selftest_dir, args.out_dir
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
    win = pick_window(src)
    log("widgets: " + ", ".join(f"{n} {'yes' if w is not None else 'missing'}"
                                for n, w in (("large", large), ("medium", medium), ("small", small))))
    log(f"window: {'yes' if win is not None else 'missing'}")
    _, family = sf.font("semibold", 20)
    log(f"font: {'SF Pro' if family == 'sf' else 'Inter'}")

    shots = [("01-menu-bar.png", lambda: menu_bar_shot(
        panel, "The world, from your menu bar.", "One click shows every city you follow."))]
    if large is not None:
        shots.append(("02-widgets.png", lambda: widgets_shot(
            large, medium, small, "Time zones on your desktop.", "Widgets in every size.")))
        shots.append(("03-working-hours.png", lambda: panel_and_widget_shot(
            panel, large, "See who’s at work.", "Working and off hours for every city.")))
    elif medium is not None:
        shots.append(("02-widgets.png", lambda: widgets_shot(
            medium, None, small, "Time zones on your desktop.", "Widgets in every size.")))
    if win is not None:
        shots.append(("04-window.png", lambda: framed_shot(
            win, "Plan across time zones.", "Drag the hours to find a time for everyone.")))
    # Never fewer than three: the panel again, framed as a window.
    extra = [("05-working-hours.png", "See who’s at work.", "Working and off hours for every city."),
             ("06-plan.png", "Plan across time zones.", "Drag the hours to find a time for everyone.")]
    while len(shots) < 3 and extra:
        name, text, sub = extra.pop(0)
        shots.append((name, lambda text=text, sub=sub: framed_shot(panel, text, sub)))

    for name, make in shots[:5]:
        image = sf.finish(sf.dither(make()), (W, H), os.path.join(out, name))
        log(f"wrote {name} {image.width}x{image.height} {image.mode}")
    log(f"{min(len(shots), 5)} screenshots in {out}")


if __name__ == "__main__":
    main()
