#!/usr/bin/env python3
"""Imports AI-generated city plates into the apps and rewrites the manifest as version 3.

    scripts/import-plates.py PLATES_DIR [--root REPO] [--dry-run]

PLATES_DIR holds <key>-day.jpg and <key>-night.jpg per city (1536x512, 3:1; <key> as in
Resources/Data/skylines.json, e.g. newyork). For each city with plates:

  1. The NIGHT plate is measured with scripts/plate-focus.py's measure(): focusX (the landmark's
     horizontal position, 0-1) and focus (the skyline band's vertical centre, 0-1). Day and night
     plates of a city share their framing, so the night reading is used for both (lit towers stand
     out from a dark sky more reliably than from a bright one). A reading flagged check=true keeps
     focusX 0.38 (the plates' composition rule) and prints a warning: look at that plate.
  2. The plates are written to
       ios/Meridian/Assets.xcassets/Skyline-<key>.imageset/skyline-<key>.jpg       (+ Contents.json)
       ios/Meridian/Assets.xcassets/Skyline-<key>-night.imageset/skyline-<key>-night.jpg
       android/app/src/main/res/drawable-nodpi/skyline_<key>.jpg and skyline_<key>_night.jpg
     (the Mac app copies the Android JPEGs at build time, scripts/build-app.sh).
  3. Resources/Data/skylines.json is rewritten as {"version": 3, "cities": [...]}: every entry keeps
     its key/names/zone; imported cities get file/credit/focus/focusX and night {file, credit, focus,
     focusX} with the AI credit. Cities without plates in PLATES_DIR keep their photos and entry
     untouched (only a missing "focusX" is added, as 0.5, the photo's centre).

A city with only a day plate is imported with "night": null and its old night photo removed (a
night photo with different framing would not line up with the new day plate). A city with only a
night plate, or a key the manifest doesn't have, is skipped with a warning.

Python 3 with Pillow and numpy only.
"""
import argparse
import importlib.util
import json
import os
import shutil
import sys
import tempfile

from PIL import Image

PLATE_SIZE = (1536, 512)
JPEG_QUALITY = 74          # progressive; stepped down (not below JPEG_MIN_QUALITY) while over MAX_BYTES
JPEG_MIN_QUALITY = 52
MAX_BYTES = 200 * 1024
DEFAULT_FOCUS_X = 0.5      # v2 entries (no focusX): the photo's centre
PLATE_FOCUS_X = 0.38       # the plates' composition rule: the landmark at 38% of the width
AI_CREDIT = {"author": "Generated with AI for Meridian", "license": "AI-generated image", "source": ""}
IMAGESET_CONTENTS = {"images": [{"filename": None, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}

HERE = os.path.dirname(os.path.abspath(__file__))


def load_measure():
    """plate-focus.py's measure() (the file name has a hyphen, so it's loaded by path)."""
    spec = importlib.util.spec_from_file_location("plate_focus", os.path.join(HERE, "plate-focus.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.measure


def warn(msg):
    print(f"warning: {msg}", file=sys.stderr)


def read_manifest(path):
    """The entries of a v2 (bare list) or v3 ({"version": 3, "cities"|"entries": [...]}) manifest."""
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for k in ("cities", "entries", "skylines", "photos", "items"):
            if isinstance(data.get(k), list):
                return data[k]
    raise SystemExit(f"{path}: no list of cities found")


def find_plates(folder):
    """{key: {"day": path, "night": path}} for <key>-day.jpg / <key>-night.jpg in folder."""
    plates = {}
    for name in sorted(os.listdir(folder)):
        base, ext = os.path.splitext(name)
        if ext.lower() not in (".jpg", ".jpeg") or "-" not in base:
            continue
        key, kind = base.rsplit("-", 1)
        if kind not in ("day", "night"):
            continue
        if not key.isalnum() or key != key.lower() or not key.isascii():
            warn(f"{name}: the key must be lowercase letters/digits (as in skylines.json); skipped")
            continue
        plates.setdefault(key, {})[kind] = os.path.join(folder, name)
    return plates


def load_plate(path):
    """The plate as RGB at PLATE_SIZE (resized, with a warning, when it isn't; refused when not ~3:1)."""
    im = Image.open(path)
    im.load()
    im = im.convert("RGB")
    if im.size != PLATE_SIZE:
        aspect = im.width / im.height
        if abs(aspect - PLATE_SIZE[0] / PLATE_SIZE[1]) > 0.03:
            raise ValueError(f"{path}: {im.width}x{im.height} is not 3:1")
        warn(f"{os.path.basename(path)}: {im.width}x{im.height}, resized to {PLATE_SIZE[0]}x{PLATE_SIZE[1]}")
        im = im.resize(PLATE_SIZE, Image.LANCZOS)
    return im


def save_jpeg(img, path):
    """Progressive JPEG, stepping the quality down while over MAX_BYTES. Returns the size in bytes."""
    q = JPEG_QUALITY
    while True:
        img.save(path, "JPEG", quality=q, progressive=True, optimize=True)
        size = os.path.getsize(path)
        if size <= MAX_BYTES or q <= JPEG_MIN_QUALITY:
            return size
        q -= 4


def write_imageset(assets, set_name, file_name, img):
    """Skyline-<...>.imageset with the photo and a Contents.json like the existing ones."""
    d = os.path.join(assets, f"{set_name}.imageset")
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    contents = json.loads(json.dumps(IMAGESET_CONTENTS))
    contents["images"][0]["filename"] = file_name
    with open(os.path.join(d, "Contents.json"), "w", encoding="utf-8") as fh:
        json.dump(contents, fh, indent=1)
        fh.write("\n")
    return save_jpeg(img, os.path.join(d, file_name))


def remove_android(drawables, res_name):
    for f in os.listdir(drawables):
        if os.path.splitext(f)[0] == res_name:
            os.remove(os.path.join(drawables, f))


def add_missing_focus_x(entry):
    """A kept (v2) entry: focusX 0.5 where it is missing, day and night; nothing else changes."""
    if not isinstance(entry.get("focusX"), (int, float)):
        entry["focusX"] = DEFAULT_FOCUS_X
    night = entry.get("night")
    if isinstance(night, dict) and not isinstance(night.get("focusX"), (int, float)):
        night["focusX"] = DEFAULT_FOCUS_X


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("plates", help="folder of <key>-day.jpg / <key>-night.jpg plates (1536x512)")
    ap.add_argument("--root", default=os.path.dirname(HERE), help="repository root to import into (default: this repo)")
    ap.add_argument("--dry-run", action="store_true", help="measure and print the plan; write nothing")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    manifest_path = os.path.join(root, "Resources/Data/skylines.json")
    assets = os.path.join(root, "ios/Meridian/Assets.xcassets")
    drawables = os.path.join(root, "android/app/src/main/res/drawable-nodpi")
    for p in (manifest_path, assets, drawables):
        if not os.path.exists(p):
            raise SystemExit(f"missing {p} (is --root the repository?)")
    if not os.path.isdir(args.plates):
        raise SystemExit(f"no folder {args.plates}")

    entries = read_manifest(manifest_path)
    known = {e.get("key") for e in entries if isinstance(e, dict)}
    plates = find_plates(args.plates)
    for key in sorted(set(plates) - known):
        warn(f"{key}: not in skylines.json (no names/zone to give it); skipped")
    for key in sorted(k for k in plates if k in known and "day" not in plates[k]):
        warn(f"{key}: night plate without a day plate; skipped")
    todo = {k: v for k, v in plates.items() if k in known and "day" in v}
    if not todo:
        raise SystemExit(f"no usable plates in {args.plates}")

    measure = load_measure()
    plan = {}  # key -> (day image, night image | None, focusX, focus)
    for key in sorted(todo):
        p = todo[key]
        try:
            day = load_plate(p["day"])
            night = load_plate(p["night"]) if "night" in p else None
        except (OSError, ValueError) as err:
            warn(f"{key}: {err}; skipped")
            continue
        # measure() reads a file; measure the plate as it will be written (PLATE_SIZE).
        src = night if night is not None else day
        with tempfile.TemporaryDirectory() as tmp:
            probe = os.path.join(tmp, f"{key}.png")
            src.save(probe)
            m = measure(probe)
        fx, fy = float(m["focusX"]), float(m["focus"])
        which = "night" if night is not None else "day"
        if m.get("check"):
            fx = PLATE_FOCUS_X
            warn(f"{key}: landmark not found on the {which} plate; focusX kept at {PLATE_FOCUS_X}. Check it with plate-fit.py")
        if night is None:
            warn(f"{key}: no night plate; measured the day plate, night set to null (the old night photo is removed)")
        plan[key] = (day, night, round(fx, 3), round(fy, 3))
        print(f"{key:16} focusX {fx:.3f}  focus {fy:.3f}  (from {which}{', CHECK' if m.get('check') else ''})"
              f"  landmarkTop {m.get('landmarkTop')}  skyline {m.get('skyline')}")

    kept = [e.get("key") for e in entries if e.get("key") not in plan]
    print(f"\n{len(plan)} cities to import, {len(kept)} kept as they are (focusX 0.5 added where missing)")
    if args.dry_run:
        for key in sorted(plan):
            day, night, fx, fy = plan[key]
            print(f"  {key}: Skyline-{key}.imageset, skyline_{key}.jpg"
                  + (f"; Skyline-{key}-night.imageset, skyline_{key}_night.jpg" if night is not None else "; night: null"))
        print(f"  {manifest_path}: version 3, {len(entries)} cities")
        print("dry run: nothing written")
        return

    for key, (day, night, fx, fy) in sorted(plan.items()):
        size = write_imageset(assets, f"Skyline-{key}", f"skyline-{key}.jpg", day)
        remove_android(drawables, f"skyline_{key}")
        save_jpeg(day, os.path.join(drawables, f"skyline_{key}.jpg"))
        shutil.rmtree(os.path.join(assets, f"Skyline-{key}-night.imageset"), ignore_errors=True)
        remove_android(drawables, f"skyline_{key}_night")
        nsize = 0
        if night is not None:
            nsize = write_imageset(assets, f"Skyline-{key}-night", f"skyline-{key}-night.jpg", night)
            save_jpeg(night, os.path.join(drawables, f"skyline_{key}_night.jpg"))
        print(f"wrote {key}: day {size // 1024} KB" + (f", night {nsize // 1024} KB" if night is not None else ""))

    out = []
    for e in entries:
        key = e.get("key")
        if key not in plan:
            add_missing_focus_x(e)
            out.append(e)
            continue
        _, night, fx, fy = plan[key]
        new = {k: e[k] for k in ("key", "names", "zone") if k in e}
        new.update({"file": f"skyline-{key}.jpg", "credit": dict(AI_CREDIT), "focus": fy, "focusX": fx})
        new["night"] = ({"file": f"skyline-{key}-night.jpg", "credit": dict(AI_CREDIT), "focus": fy, "focusX": fx}
                        if night is not None else None)
        out.append(new)
    tmp = manifest_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump({"version": 3, "cities": out}, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, manifest_path)
    print(f"wrote {manifest_path} (version 3, {len(out)} cities)")


if __name__ == "__main__":
    main()
