#!/usr/bin/env python3
"""iPhone App Store screenshots for Meridian, composed from the simulator captures.

    scripts/appstore-shots.py <captures dir> <out dir>

Reads 01-main.png ... 05-add.png (6.9-inch simulator captures, 1320x2868) and writes the same
file names into <out dir>: each exactly 1320x2868 RGB (no alpha), the 6.9-inch App Store size.
Each frame has Meridian's dark navy backdrop (with a glow made from the capture) and the
Cowdrey One store caption and iPhone, the same as every app in the family (see store_frame.py):
an uppercase eyebrow at y 150, a two-line Fraunces headline and a one-line sub, then the capture in
an iPhone drawn in code (body 1024 px wide, centred, top at y 640: titanium rim, black bezel,
62 pt screen corners, the Dynamic Island, side buttons and a two-layer shadow).

A capture that isn't 1320x2868 is scaled to the screen like the others. A capture with no
caption below (a new screen) gets a frame with the generic caption.
<out dir> may be the captures dir itself: every capture is read before anything is written.

Fonts: Fraunces (scripts/fonts) for the headline; SF Pro when present (macOS), else Inter
SemiBold from Resources/Fonts. Python 3, Pillow and fontTools.
"""
import argparse
import os
import sys

from PIL import Image, ImageChops

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import store_frame as sf  # noqa: E402

W, H = 1320, 2868

# Eyebrow (the feature on the screen), the headline's two lines and the sub, for each capture
# (the file name's stem after the number).
COPY = {
    "main": ("Time zones", ("Every time zone", "at a glance."), "Your cities, photos and hours side by side."),
    "travel": ("Planner", ("Find a time", "that works."), "Drag the hours and every city follows."),
    "widgets": ("Widgets", ("Your cities on", "your Home Screen."), "Widgets for Home Screen and Lock Screen."),
    "date": ("Date & time", ("Go to", "any moment."), "Pick a date and time, and see it everywhere."),
    "add": ("City search", ("Search", "34,000 cities."), "Add any place on Earth in a tap."),
}
GENERIC = COPY["main"]

# The phone, as Bearings draws it (scripts/store-frames.js, DEVICES.iphone): body width, its top,
# the bezel and rim as fractions of the body, the screen's corner radius in points at 3x.
BODY = 1024
BODY_TOP = 640
INSET = 0.036
RIM = 0.011
RADIUS_PT = 62
PT = 3
SHADOW = (3, 9, 22)
RIM_STOPS = [(0.00, (0x8A, 0x8D, 0x93)), (0.14, (0x43, 0x46, 0x4B)), (0.45, (0x26, 0x28, 0x2C)),
             (0.70, (0x2E, 0x30, 0x34)), (0.88, (0x55, 0x58, 0x5E)), (1.00, (0x9A, 0x9D, 0xA3))]
BUTTON_STOPS = [(0.0, (0x2B, 0x2D, 0x31)), (0.5, (0x74, 0x77, 0x7D)), (1.0, (0x2B, 0x2D, 0x31))]
CLEARANCE = 60                                 # caption to the phone's top, at least


def log(message):
    print(f"[appstore-shots] {message}")


def load(path):
    image = Image.open(path)
    image.load()
    return image.convert("RGB")


def geometry(capture_size):
    """The phone's boxes on the canvas for a capture of `capture_size`."""
    cap_w, cap_h = capture_size
    left = (W - BODY) / 2
    inset, rim = round(BODY * INSET), round(BODY * RIM)
    sw = BODY - 2 * inset
    k = sw / cap_w
    sh = round(cap_h * k)
    bh = sh + 2 * inset
    sr = RADIUS_PT * PT * k
    return {"left": left, "top": BODY_TOP, "inset": inset, "rim": rim, "sw": sw, "sh": sh, "bh": bh,
            "k": k, "sr": sr, "br": sr + inset,
            "screen": (left + inset, BODY_TOP + inset, left + inset + sw, BODY_TOP + inset + sh)}


def _rect(canvas, box, radius, fill):
    """A plain (circular-cornered, as CSS draws border-radius) rounded rectangle."""
    canvas.alpha_composite(sf.solid(canvas.size, fill, sf.shape_mask(canvas.size, box, radius, continuous=False)))


def phone(canvas, capture):
    """Draws the iPhone with the capture on its screen; returns the body box."""
    g = geometry(capture.size)
    size = canvas.size
    x0, y0 = g["left"], g["top"]
    bh, br = g["bh"], g["br"]
    body = (x0, y0, x0 + BODY, y0 + bh)

    # Buttons first, so the body covers their inner half: Action, volume up and down on the left;
    # the side button and Camera Control on the right.
    bw, out = round(BODY * 0.011), -round(BODY * 0.0065)
    btn_r = BODY * 0.006
    for side, t, h, r in (("l", 0.17, 0.04, btn_r), ("l", 0.235, 0.068, btn_r), ("l", 0.318, 0.068, btn_r),
                          ("r", 0.265, 0.105, btn_r), ("r", 0.56, 0.055, bw)):
        bx = x0 + out if side == "l" else x0 + BODY - out - bw
        box = (bx, y0 + bh * t, bx + bw, y0 + bh * (t + h))
        m = sf.shape_mask(size, box, min(r, bw / 2), continuous=False)
        grad = sf.stops_strip(bw * 4, BUTTON_STOPS).resize((bw, max(1, round(box[3] - box[1]))), Image.BILINEAR)
        layer = Image.new("RGBA", size, (0, 0, 0, 0))
        layer.paste(grad.convert("RGBA"), (round(bx), round(box[1])))
        layer.putalpha(ImageChops.multiply(layer.getchannel("A"), m))
        canvas.alpha_composite(layer)

    # Body: the two-layer shadow, then the metal rim (135deg gradient).
    body_mask = sf.shape_mask(size, body, br, continuous=False)
    sf.drop_shadow(canvas, body_mask, BODY * 0.07, BODY * 0.13, 0.55, SHADOW)
    sf.drop_shadow(canvas, body_mask, BODY * 0.012, BODY * 0.03, 0.35, SHADOW)
    rim_art = sf.diagonal((BODY, round(bh)), RIM_STOPS).convert("RGBA")
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(rim_art, (round(x0), round(y0)))
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), body_mask))
    canvas.alpha_composite(layer)

    # Black bezel inside the rim, with a faint light edge.
    rim = g["rim"]
    bezel = (x0 + rim, y0 + rim, x0 + BODY - rim, y0 + bh - rim)
    _rect(canvas, bezel, br - rim, (0, 0, 0, 255))
    canvas.alpha_composite(sf.solid(size, (255, 255, 255, round(255 * 0.07)),
                                    sf.ring_mask(size, bezel, br - rim, max(2, BODY * 0.0022), continuous=False)))

    # Screen: the capture scaled to the screen's width, with 62 pt corners.
    screen = g["screen"]
    shot = capture.resize((g["sw"], g["sh"]), Image.LANCZOS).convert("RGBA")
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(shot, (round(screen[0]), round(screen[1])))
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), sf.shape_mask(size, screen, g["sr"], continuous=False)))
    canvas.alpha_composite(layer)

    # The Dynamic Island: 126 x 37.33 pt, 11 pt from the top, with a faint edge and a lens.
    k, p = g["k"], PT * g["k"]
    iw, ih, it = 126 * PT * k, 37.33 * PT * k, 11 * PT * k
    island = (W / 2 - iw / 2, screen[1] + it, W / 2 + iw / 2, screen[1] + it + ih)
    outer = (island[0] - 0.6 * p, island[1] - 0.6 * p, island[2] + 0.6 * p, island[3] + 0.6 * p)
    _rect(canvas, outer, ih / 2 + 0.6 * p, (0, 0, 0, round(255 * 0.9)))
    _rect(canvas, island, ih / 2, (0, 0, 0, 255))
    canvas.alpha_composite(sf.solid(size, (255, 255, 255, round(255 * 0.09)),
                                    sf.ring_mask(size, island, ih / 2, 1.2 * p, continuous=False)))
    d = ih * 0.4
    lens = (island[2] - ih * 0.3 - d, island[1] + ih * 0.3, island[2] - ih * 0.3, island[1] + ih * 0.3 + d)
    _lens(canvas, lens, 0.8 * p)
    return body


def _lens(canvas, box, ring):
    """radial-gradient(circle at 35% 35%, #2a3550, #0b0f1a 55%, #05070c), with a faint ring."""
    ss = 8
    n = max(4, round((box[2] - box[0]) * ss))
    art = Image.new("RGB", (n, n))
    px = art.load()
    cx = cy = 0.35 * n
    far = ((n - cx) ** 2 + (n - cy) ** 2) ** 0.5   # farthest-corner, as CSS sizes it
    stops = [(0.0, (0x2A, 0x35, 0x50)), (0.55, (0x0B, 0x0F, 0x1A)), (1.0, (0x05, 0x07, 0x0C))]
    for y in range(n):
        for x in range(n):
            t = min(1.0, ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / far)
            for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
                if t0 <= t <= t1:
                    u = (t - t0) / (t1 - t0)
                    px[x, y] = tuple(round(a + (b - a) * u) for a, b in zip(c0, c1))
                    break
    size = canvas.size
    w = max(1, round(box[2] - box[0]))
    art = art.resize((w, w), Image.LANCZOS).convert("RGBA")
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(art, (round(box[0]), round(box[1])))
    m = sf.shape_mask(size, (round(box[0]), round(box[1]), round(box[0]) + w, round(box[1]) + w), w / 2, continuous=False)
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), m))
    canvas.alpha_composite(layer)
    outer = (box[0] - ring, box[1] - ring, box[2] + ring, box[3] + ring)
    canvas.alpha_composite(sf.solid(size, (255, 255, 255, round(255 * 0.05)),
                                    sf.ring_mask(size, outer, (outer[2] - outer[0]) / 2, ring, continuous=False)))


def compose(capture, copy, head_size, sub_size):
    eyebrow, lines, sub = copy
    g = geometry(capture.size)
    canvas = sf.background((W, H), capture, g["screen"])
    marks = sf.draw_caption(canvas, sf.IPHONE_CAPTION, eyebrow, list(lines), sub, head_size, sub_size)
    clear = BODY_TOP - marks["bottom"]
    if clear < CLEARANCE:
        log(f"warning: caption ends {clear:.0f} px above the phone (want {CLEARANCE})")
    phone(canvas, capture)
    return sf.dither(canvas), marks, clear


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("captures_dir")
    parser.add_argument("out_dir")
    args = parser.parse_args()

    names = sorted(n for n in os.listdir(args.captures_dir) if n.lower().endswith(".png"))
    if not names:
        sys.exit(f"[appstore-shots] no PNG captures in {args.captures_dir}")
    captures = {n: load(os.path.join(args.captures_dir, n)) for n in names}   # read all first
    os.makedirs(args.out_dir, exist_ok=True)
    _, family = sf.font("semibold", 20)
    log(f"font: {'SF Pro' if family == 'sf' else 'Inter'}")

    copies = {name: COPY.get(os.path.splitext(name)[0].split("-", 1)[-1], GENERIC) for name in names}
    # One headline size and one sub size for the whole set.
    head_size, sub_size = sf.fit_sizes(sf.IPHONE_CAPTION, W, [l for c in copies.values() for l in c[1]],
                                       [c[2] for c in copies.values()])
    log(f"type: headline {head_size} px, sub {sub_size} px")

    for name in names:
        capture = captures[name]
        if capture.size != (W, H):
            log(f"note: {name} is {capture.width}x{capture.height}, scaled to the screen")
        image, marks, clear = compose(capture, copies[name], head_size, sub_size)
        out = sf.finish(image, (W, H), os.path.join(args.out_dir, name))
        log(f"wrote {name} {out.width}x{out.height} {out.mode}: {copies[name][0].upper()} / "
            f"{' / '.join(copies[name][1])} / {copies[name][2]} (clear {clear:.0f} px)")


if __name__ == "__main__":
    main()
