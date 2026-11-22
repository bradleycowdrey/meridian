#!/usr/bin/env python3
"""Contact sheet: how a city plate sits in every row shape Meridian draws (square small widget to the
web's very wide rows), with the app's text block on the left and five hour tiles on the right drawn
over it, plus the text contrast. Usage: plate-fit.py OUT.png PLATE.jpg [focus_x focus_y] ...
PLATE:fx:fy:top  fx: landmark x (0-1), fy: skyline band centre, top: landmark tip height (0-1)."""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageStat

# (label, width, height): row shapes seen in the apps and widgets (points, scaled up for the sheet).
SHAPES = [("small widget 1:1", 300, 300), ("iPhone card 2.6:1", 780, 300), ("Android card 2.9:1", 870, 300),
          ("large widget row 4.4:1", 660, 150), ("medium widget row 6:1", 720, 120),
          ("Mac panel row 8:1", 800, 100), ("web row 14:1", 1120, 80)]
FONT = None
for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",):
    try: FONT = f; ImageFont.truetype(f, 10); break
    except Exception: FONT = None

def font(px):
    return ImageFont.truetype(FONT, px) if FONT else ImageFont.load_default()

def geometry(plate, w, h, fx, fy, top):
    """Cover-fit; the landmark (fx) into the gap between the text and the tiles; skyline band (fy)
    at the anchor; then the landmark's tip (top) kept at least 8% below the frame's top edge."""
    iw, ih = plate.size
    s = max(w / iw, h / ih)
    pw, ph = iw * s, ih * s
    gap_x = 0.36 * w if w / h > 1.4 else 0.78 * w       # square: the clear right-hand column
    x = min(max(gap_x - fx * pw, w - pw), 0)
    anchor = 0.52 if w / h > 1.4 else 0.6
    y = anchor * h - fy * ph
    if top is not None:
        y = max(y, 0.08 * h - top * ph)                 # the tip stays in view
    y = min(max(y, h - ph), 0)
    return pw, ph, x, y

def place(plate, w, h, fx, fy, top=None):
    pw, ph, x, y = geometry(plate, w, h, fx, fy, top)
    img = plate.resize((round(pw), round(ph)), Image.LANCZOS)
    return img.crop((round(-x), round(-y), round(-x) + w, round(-y) + h))

def row(plate, w, h, fx, fy, label, top=None):
    tile = place(plate, w, h, fx, fy, top).convert("RGB")
    pw, ph, ox, oy = geometry(plate, w, h, fx, fy, top)
    d = ImageDraw.Draw(tile, "RGBA")
    square = w / h <= 1.4
    th = max(18, int(h * (0.26 if not square else 0.16)))
    # the text block: time, name (and its region for the contrast measure)
    # rows: time and name top-left; square (the iPhone small widget): time, name, status bottom-left
    tx, ty = int(0.04 * w), int(h * (0.22 if not square else 0.50))
    region = (tx, ty, tx + int(w * (0.22 if not square else 0.62)), ty + int(th * (1.9 if not square else 2.6)))
    stat = ImageStat.Stat(tile.crop(region).convert("L"))
    mean, sd = stat.mean[0], stat.stddev[0]
    d.text((tx, ty), "20:39", fill="white", font=font(th), stroke_width=0)
    d.text((tx, ty + int(th * 1.05)), "Paris", fill="white", font=font(int(th * 0.55)))
    # five hour tiles on the right (bottom row for the square widget)
    n, gap = 5, max(3, int(h * 0.03))
    if square:
        n, tw, y0 = 0, 0, h                              # no tiles in the small widget
    else:
        tw = int(min(h * 0.62, w * 0.09))
        y0 = int(h * 0.19)
    x0 = w - tx - (n * tw + (n - 1) * gap)
    for i in range(n):
        x = x0 + i * (tw + gap)
        d.rounded_rectangle((x, y0, x + tw, y0 + int(tw * (1.2 if square else 1.0))), radius=max(4, tw // 6),
                            fill=(28, 52, 92, 235), outline=(255, 255, 255, 80))
    # the landmark: a slim box from its tip down to the skyline band, where it sits in this frame
    lm = None
    if top is not None:
        lx0, lx1 = ox + (fx - 0.02) * pw, ox + (fx + 0.02) * pw
        ly0, ly1 = oy + top * ph, oy + fy * ph
        boxes = [region] + [(x0 + i * (tw + gap), y0, x0 + i * (tw + gap) + tw, y0 + int(tw * (1.2 if square else 1.0))) for i in range(n)]
        def area(a):
            return max(0, a[2] - a[0]) * max(0, a[3] - a[1])
        full = area((lx0, ly0, lx1, ly1))
        vis = (max(lx0, 0), max(ly0, 0), min(lx1, w), min(ly1, h))
        hidden = sum(area((max(vis[0], b[0]), max(vis[1], b[1]), min(vis[2], b[2]), min(vis[3], b[3]))) for b in boxes)
        shown = (area(vis) - hidden) / full if full else 0
        tip_ok = 0 <= ly0 <= h and not any(b[0] <= (lx0 + lx1) / 2 <= b[2] and b[1] <= ly0 <= b[3] for b in boxes)
        lm = (shown, tip_ok)
        d.rectangle((lx0, ly0, lx1, ly1), outline=(255, 80, 80, 160))
    # verdict: text over a busy or bright patch is bad
    ok = mean < 150 and sd < 55
    lmtxt = "" if lm is None else f"  landmark shown {lm[0]*100:.0f}% tip {'ok' if lm[1] else 'HIDDEN'}"
    if lm is not None and (lm[0] < 0.6 or not lm[1]):
        ok = False
    print(f"{label}: text L={mean:.0f} sd={sd:.0f}{lmtxt}")
    d.text((4, h - 14), f"{label}  text bg L={mean:.0f} sd={sd:.0f}{lmtxt} {'OK' if ok else 'CHECK'}",
           fill=(255, 255, 0) if not ok else (180, 255, 180), font=font(10))
    return tile, ok

def sheet(out, plates):
    rows, oks = [], []
    for path, fx, fy, top in plates:
        plate = Image.open(path).convert("RGB")
        name = path.split("/")[-1]
        for label, w, h in SHAPES:
            t, ok = row(plate, w, h, fx, fy, f"{name} · {label}", top)
            rows.append(t); oks.append(ok)
    W = max(r.width for r in rows) + 20
    H = sum(r.height + 10 for r in rows) + 10
    canvas = Image.new("RGB", (W, H), (20, 20, 22))
    y = 10
    for r in rows:
        canvas.paste(r, (10, y)); y += r.height + 10
    canvas.save(out)
    print(f"{out}: {sum(oks)}/{len(oks)} rows with calm text backgrounds")

if __name__ == "__main__":
    # plate-fit.py OUT.png PLATE[:fx:fy[:top]] ...  (top = the landmark tip's height, 0-1)
    out, args = sys.argv[1], sys.argv[2:]
    plates = []
    for a in args:
        parts = a.split(":")
        fx = float(parts[1]) if len(parts) > 1 else 0.5
        fy = float(parts[2]) if len(parts) > 2 else 0.62
        top = float(parts[3]) if len(parts) > 3 else None
        plates.append((parts[0], fx, fy, top))
    sheet(out, plates)
