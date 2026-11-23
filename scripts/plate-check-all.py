#!/usr/bin/env python3
"""Checks every city plate in a folder (<key>-day.jpg, <key>-night.jpg): measures the landmark on the
night plate (plate-focus.py), places both plates in every row shape (plate-fit.py) and passes a city
when its landmark is at least 85% visible with the tip in view in every shape (the thin web row: tip
in view). Writes report.json and a contact sheet of every city (small widget + iPhone card + Mac row).
Usage: plate-check-all.py PLATE_DIR OUT_DIR"""
import importlib.util, json, os, sys
from PIL import Image, ImageDraw

here = os.path.dirname(os.path.abspath(__file__))
def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(here, name + ".py"))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
focus = load("plate-focus")
fit = load("plate-fit")

def check(pdir, out):
    os.makedirs(out, exist_ok=True)
    keys = sorted({f.rsplit("-", 1)[0] for f in os.listdir(pdir) if f.endswith("-day.jpg")})
    report, thumbs = {}, []
    import io, contextlib
    for k in keys:
        night = os.path.join(pdir, f"{k}-night.jpg")
        day = os.path.join(pdir, f"{k}-day.jpg")
        m = focus.measure(night if os.path.exists(night) else day)
        fx, fy, top = m["focusX"], m["focus"], m["landmarkTop"] if not m["check"] else 0.40
        res = {"focusX": fx, "focus": fy, "top": round(top, 3), "check": m["check"], "fails": []}
        for variant, path in (("day", day), ("night", night)):
            if not os.path.exists(path):
                res["fails"].append(f"{variant}: missing"); continue
            plate = Image.open(path).convert("RGB")
            for label, w, h in fit.SHAPES:
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    tile, ok = fit.row(plate, w, h, fx, fy, label, top)
                line = buf.getvalue()
                shown = float(line.split("landmark shown ")[1].split("%")[0]) / 100 if "landmark shown" in line else 0
                tip = "tip ok" in line
                need = 0.0 if "web" in label else 0.85
                if shown < need or not tip:
                    res["fails"].append(f"{variant} {label}: shown {shown:.0%}{'' if tip else ', tip hidden'}")
                if label.startswith(("small", "iPhone", "Mac")):
                    thumbs.append((k, variant, label, tile))
        if m["check"]:
            res["fails"].append("landmark not detected near 38% (check by eye)")
        res["pass"] = not res["fails"]
        report[k] = res
    json.dump(report, open(os.path.join(out, "report.json"), "w"), indent=1)
    # contact sheet: one line per city and variant: small widget, iPhone card, Mac row
    rows = {}
    for k, v, label, t in thumbs:
        rows.setdefault((k, v), []).append(t)
    H = 150
    lines = []
    for (k, v), ts in sorted(rows.items()):
        scaled = [t.resize((int(t.width * H / t.height), H)) if t.height != H else t for t in ts]
        scaled = [s if s.width <= 900 else s.resize((900, int(s.height * 900 / s.width))) for s in scaled]
        W = sum(s.width for s in scaled) + 10 * len(scaled) + 170
        line = Image.new("RGB", (W, H), (20, 20, 22))
        d = ImageDraw.Draw(line)
        d.text((6, 6), f"{k}\n{v}\n{'PASS' if report[k]['pass'] else 'FAIL'}", fill=(255, 255, 255) if report[k]["pass"] else (255, 120, 120))
        x = 170
        for s in scaled:
            line.paste(s, (x, (H - s.height) // 2)); x += s.width + 10
        lines.append(line)
    for i in range(0, len(lines), 24):
        chunk = lines[i:i + 24]
        W = max(l.width for l in chunk)
        sheet = Image.new("RGB", (W, sum(l.height + 6 for l in chunk)), (10, 10, 12))
        y = 0
        for l in chunk:
            sheet.paste(l, (0, y)); y += l.height + 6
        sheet.save(os.path.join(out, f"sheet-{i // 24 + 1:02d}.jpg"), quality=82)
    passed = sum(r["pass"] for r in report.values())
    print(f"{passed}/{len(report)} cities pass")
    for k, r in report.items():
        if not r["pass"]:
            print(k, "; ".join(r["fails"][:4]))

if __name__ == "__main__":
    check(sys.argv[1], sys.argv[2])
