#!/usr/bin/env python3
"""Measures a city plate for placement: focusX = the landmark's horizontal position (the tallest
structure poking into the sky), focus = the skyline band's vertical centre. Prints JSON per file.
Usage: plate-focus.py PLATE.jpg ..."""
import json, sys
from PIL import Image, ImageFilter
import numpy as np

def measure(path):
    im = Image.open(path).convert("RGB")
    W = 600
    small = im.resize((W, int(W * im.height / im.width)), Image.LANCZOS).filter(ImageFilter.GaussianBlur(1))
    a = np.asarray(small).astype(float)
    H = a.shape[0]
    # sky model: the colour of each row's upper band, interpolated down the image (a gradient sky)
    sky_rows = a[: int(H * 0.2)].mean(axis=1)                      # per-row mean colour, top 20%
    top_c, low_c = sky_rows[:3].mean(0), sky_rows[-3:].mean(0)
    tops = np.zeros(W, dtype=int)
    for x in range(W):
        col = a[:, x]
        for y in range(int(H * 0.08), H):
            t = min(1.0, y / (H * 0.6))
            sky = top_c * (1 - t) + low_c * t
            if np.abs(col[y] - sky).sum() > 60:                       # leaves the sky
                # need it to stay non-sky for a few pixels (ignore thin wires, birds)
                if np.abs(col[min(H - 1, y + 3)] - sky).sum() > 60:
                    tops[x] = y; break
        else:
            tops[x] = H - 1
    smooth = np.convolve(tops, np.ones(5) / 5, mode="same")
    margin = int(W * 0.06)
    inner = smooth[margin:W - margin]
    lx = int(np.argmin(inner)) + margin
    # the landmark spans the columns within 6% of its peak height; take their middle
    peak = smooth[lx]
    band = np.where(smooth <= peak + H * 0.02)[0]
    near = band[np.abs(band - lx) < W * 0.05]
    lx = int(near.mean()) if len(near) else lx
    skyline = float(np.median(tops))
    focus = min(0.85, max(0.15, (skyline + (H * 0.85)) / 2 / H))   # middle of the band below the median skyline
    # Plates are generated with the landmark at 38% of the width: a reading far from that is a
    # misdetection (an edge, a cloud), so keep 0.38 and flag it for a look.
    check = abs(lx / W - 0.38) > 0.12
    if check:
        lx = int(0.38 * W)
    return {"file": path.split("/")[-1], "focusX": round(lx / W, 3), "check": check, "focus": round(focus, 3),
            "landmarkTop": round(peak / H, 3), "skyline": round(skyline / H, 3)}

if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(json.dumps(measure(p)))
