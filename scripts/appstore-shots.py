#!/usr/bin/env python3
"""iPhone App Store screenshots for Meridian, composed from the simulator captures.

    scripts/appstore-shots.py <captures dir> <out dir>

Reads 01-main.png ... 05-add.png (6.9-inch simulator captures, 1320x2868) and writes the same
file names into <out dir>: each exactly 1320x2868 RGB (no alpha), the 6.9-inch App Store size.
Each frame has a headline and subline over a dark navy backdrop (with a glow made from the
capture), and the capture inside an iPhone drawn in code: a titanium-edged body with continuous
corners, the Dynamic Island, and a soft two-layer shadow. The phone runs off the bottom edge.

A capture that isn't 1320x2868 is scaled to the screen like the others. A capture with no
headline below (a new screen) gets a frame with the generic headline.
<out dir> may be the captures dir itself: every capture is read before anything is written.

Fonts: SF Pro when present (macOS), else Inter from Resources/Fonts. Python 3 and Pillow only.
"""
import argparse
import os
import sys

from PIL import Image, ImageChops, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import store_frame as sf  # noqa: E402

W, H = 1320, 2868

# Headline / subline for each capture (the file name's stem after the number).
COPY = {
    "main": ("Every time zone at a glance.", "Your cities, photos and hours side by side."),
    "travel": ("Find a time that works.", "Drag the hours and every city follows."),
    "widgets": ("Your cities on your Home Screen.", "Widgets for Home Screen and Lock Screen."),
    "date": ("Go to any moment.", "Pick a date and time, and see it everywhere."),
    "add": ("Search 34,000 cities.", "Add any place on Earth in a tap."),
}
GENERIC = ("Every time zone at a glance.", "Your cities, photos and hours side by side.")

# Type.
HEADLINE_TOP = 170
HEADLINE_SIZE = 104
HEADLINE_TRACKING = -1.5
SUBLINE_SIZE = 50
SUBLINE_GAP = 24
TEXT_WIDTH = 1120

# The phone. The screen is the capture at 1060 wide; the body is 16 px wider on each side.
SCREEN_W = 1060
SCREEN_H = round(SCREEN_W * 2868 / 1320)      # 2303
SCREEN_RADIUS = 134
BODY_INSET = 16
BODY_RADIUS = 150
# The screen runs ~47 px past the bottom: the home indicator goes, the Now bar and ruler stay.
SCREEN_TOP = H + 47 - SCREEN_H                 # 612
CLEARANCE = 80                                 # text to frame top, at least


def log(message):
    print(f"[appstore-shots] {message}")


def load(path):
    image = Image.open(path)
    image.load()
    return image.convert("RGB")


def phone(canvas, capture):
    """Draws the iPhone with the capture on its screen."""
    sx0 = (W - SCREEN_W) // 2
    sy0 = SCREEN_TOP
    screen = (sx0, sy0, sx0 + SCREEN_W, sy0 + SCREEN_H)
    body = (sx0 - BODY_INSET, sy0 - BODY_INSET, sx0 + SCREEN_W + BODY_INSET, sy0 + SCREEN_H + BODY_INSET)
    size = canvas.size

    body_mask = sf.shape_mask(size, body, BODY_RADIUS)

    # Shadow: 0 40 120 black .55, plus 0 8 24 black .35.
    sf.drop_shadow(canvas, body_mask, 40, 120, 0.55)
    sf.drop_shadow(canvas, body_mask, 8, 24, 0.35)

    # Side buttons, just proud of the frame (action and volume left, side button right).
    bx0, by0, bx1, by1 = body
    bh = by1 - by0
    buttons = [(bx0 - 5, 0.135, 0.165), (bx0 - 5, 0.205, 0.265), (bx0 - 5, 0.290, 0.350), (bx1 - 1, 0.230, 0.330)]
    for x, t0, t1 in buttons:
        box = (x, by0 + bh * t0, x + 6, by0 + bh * t1)
        m = sf.shape_mask(size, box, 3, continuous=False)
        canvas.alpha_composite(sf.solid(size, (0x2C, 0x2C, 0x30), m))
        hl = sf.shape_mask(size, (box[0] + (1 if x < bx0 else 3), box[1] + 2, box[0] + (3 if x < bx0 else 5), box[3] - 2), 1,
                           continuous=False)
        canvas.alpha_composite(sf.solid(size, (255, 255, 255, 22), hl))

    # Body: the titanium band (a 3 px rim, light top-left to dark bottom-right), then black glass.
    rim = sf.linear(size, (0x3A, 0x3A, 0x3E), (0x1C, 0x1C, 0x1E))
    rim_layer = rim.convert("RGBA")
    rim_layer.putalpha(body_mask)
    canvas.alpha_composite(rim_layer)
    band = (bx0 + 3, by0 + 3, bx1 - 3, by1 - 3)
    canvas.alpha_composite(sf.solid(size, (0x1A, 0x1A, 0x1C), sf.shape_mask(size, band, BODY_RADIUS - 3)))
    # Inner 1.5 px rim of white .10 where the band meets the rim.
    canvas.alpha_composite(sf.solid(size, (255, 255, 255, 26), sf.ring_mask(size, band, BODY_RADIUS - 3, 1.5)))
    glass = (bx0 + 7, by0 + 7, bx1 - 7, by1 - 7)
    canvas.alpha_composite(sf.solid(size, (0x02, 0x02, 0x03), sf.shape_mask(size, glass, BODY_RADIUS - 7)))

    # Screen: the capture with continuous corners.
    shot = capture.resize((SCREEN_W, SCREEN_H), Image.LANCZOS).convert("RGBA")
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(shot, (sx0, sy0))
    screen_mask = sf.shape_mask(size, screen, SCREEN_RADIUS)
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), screen_mask))
    canvas.alpha_composite(layer)

    # Dynamic Island, at the iPhone 16 Pro Max proportions (126 x 37 pt, 11 pt down, on a 440 pt screen).
    k = SCREEN_W / 440
    iw, ih, it = 126 * k, 37 * k, 11 * k
    island = (W / 2 - iw / 2, sy0 + it, W / 2 + iw / 2, sy0 + it + ih)
    canvas.alpha_composite(sf.solid(size, (0, 0, 0), sf.shape_mask(size, island, ih / 2, continuous=False)))
    # The camera lens, barely there (as on the real glass, the island itself vanishes on black).
    lens = (island[2] - ih * 0.5 - ih * 0.13, island[1] + ih * 0.37, island[2] - ih * 0.5 + ih * 0.13, island[3] - ih * 0.37)
    canvas.alpha_composite(sf.solid(size, (0x0B, 0x0D, 0x16), sf.shape_mask(size, lens, ih, continuous=False)))

    # A faint light edge round the glass, as the frame catches the light.
    canvas.alpha_composite(sf.solid(size, (255, 255, 255, 10), sf.ring_mask(size, glass, BODY_RADIUS - 7, 1)))
    return body


def compose(capture, headline, subline):
    body_top = SCREEN_TOP - BODY_INSET
    screen_box = ((W - SCREEN_W) // 2, SCREEN_TOP, (W + SCREEN_W) // 2, SCREEN_TOP + SCREEN_H)
    canvas = sf.background((W, H), capture, screen_box)

    block = sf.headline_block(W, headline, subline, HEADLINE_SIZE, SUBLINE_SIZE, HEADLINE_TRACKING,
                              TEXT_WIDTH, SUBLINE_GAP)
    # Two lines start at 170. One line sits centred in the same band, so the gap above the
    # phone stays balanced.
    band_bottom = body_top - CLEARANCE - 20
    if len(block["lines"]) >= 2:
        top = HEADLINE_TOP
    else:
        top = HEADLINE_TOP + (band_bottom - HEADLINE_TOP - block["height"]) / 2
    bottom = sf.draw_headline(canvas, block, top, W)
    clear = body_top - bottom
    if clear < CLEARANCE:
        log(f"warning: text ends {clear:.0f} px above the phone (want {CLEARANCE})")

    phone(canvas, capture)
    return sf.dither(canvas), block, clear


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

    for name in names:
        capture = captures[name]
        if capture.size != (W, H):
            log(f"note: {name} is {capture.width}x{capture.height}, scaled to the screen")
        stem = os.path.splitext(name)[0].split("-", 1)[-1]
        headline, subline = COPY.get(stem, GENERIC)
        image, block, clear = compose(capture, headline, subline)
        out = sf.finish(image, (W, H), os.path.join(args.out_dir, name))
        log(f"wrote {name} {out.width}x{out.height} {out.mode}: {' / '.join(block['lines'])} "
            f"({block['size']} px, clear {clear:.0f} px)")


if __name__ == "__main__":
    main()
