#!/usr/bin/env python3
"""Clean review sheets of every city plate as the apps show it (no debug marks): per city, the small
widget (day), the phone card by day and by night, and the Mac panel row by night, with the city's name.
Usage: plate-review.py PLATE_DIR OUT_DIR"""
import csv, importlib.util, io, contextlib, os, sys
from PIL import Image, ImageDraw

here = os.path.dirname(os.path.abspath(__file__))
def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(here, name + ".py"))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
focus, fit = load("plate-focus"), load("plate-fit")
names = {r["key"]: r["city"] for r in csv.DictReader(open(os.path.join(here, "plate-cities.tsv")), delimiter="\t")}
SHOTS = [("day", "small widget 1:1", 300, 300), ("day", "iPhone card 2.6:1", 780, 300),
         ("night", "iPhone card 2.6:1", 780, 300), ("night", "Mac panel row 8:1", 800, 100)]

def main(pdir, out):
    os.makedirs(out, exist_ok=True)
    keys = sorted({f.rsplit("-", 1)[0] for f in os.listdir(pdir) if f.endswith("-day.jpg")}, key=lambda k: names.get(k, k))
    H, lines = 200, []
    for k in keys:
        m = focus.measure(os.path.join(pdir, f"{k}-night.jpg"))
        top = 0.40 if m["check"] else m["landmarkTop"]
        tiles = []
        for variant, label, w, h in SHOTS:
            plate = Image.open(os.path.join(pdir, f"{k}-{variant}.jpg")).convert("RGB")
            with contextlib.redirect_stdout(io.StringIO()):
                t, _ = fit.row(plate, w, h, m["focusX"], m["focus"], label, top, name=names.get(k, k), debug=False)
            s = H / t.height if h >= 200 else 0.66 * H / t.height
            tiles.append(t.resize((int(t.width * s), int(t.height * s)), Image.LANCZOS))
        W = sum(t.width for t in tiles) + 14 * len(tiles)
        line = Image.new("RGB", (W, H), (14, 14, 16))
        x = 0
        for t in tiles:
            line.paste(t, (x, (H - t.height) // 2)); x += t.width + 14
        lines.append(line)
    per = 20
    for i in range(0, len(lines), per):
        chunk = lines[i:i + per]
        W = max(l.width for l in chunk)
        sheet = Image.new("RGB", (W + 24, sum(l.height + 12 for l in chunk) + 12), (8, 8, 10))
        y = 12
        for l in chunk:
            sheet.paste(l, (12, y)); y += l.height + 12
        sheet.save(os.path.join(out, f"cities-{i // per + 1}.jpg"), quality=84)
    print(len(keys), "cities")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
