#!/usr/bin/env python3
"""Publishes hosted AI city plates: writes the index the apps bundle and stages the photos for the
`plates` branch, from which the apps download them.

    scripts/publish-remote-plates.py PLATES_DIR ALIASES_JSON --out STAGE_DIR
        [--cities CITIES_JSON] [--index PATH] [--base URL] [--prune] [--dry-run]

PLATES_DIR holds <key>-day.jpg and <key>-night.jpg per city (1536x512, 3:1). <key> is the city's
key in the city list (CITIES_JSON, a list of {key, name, region, cc, zone, lat, lon, pop}; keys are
lowercase letters/digits with hyphens, for example chengdu-cn).

ALIASES_JSON is a list of [name, region, cc, zone, builtinKey, km]: a place that should show a
BUILT-IN photo (a key in Resources/Data/skylines.json), for example Brooklyn -> newyork.

For each city with both plates:

  1. the NIGHT plate is measured with scripts/plate-focus.py (scripts/plate-overrides.json applies,
     keyed by the plate key). The reading (focusX, focus, top) is used for day and night, as
     scripts/import-plates.py does for built-in plates. A check=true reading keeps focusX 0.38 and
     top 0.40 and prints a warning.
  2. both plates are written to STAGE_DIR as <key>-day.jpg / <key>-night.jpg (1536x512 progressive
     JPEG, at most 200 KB, same encoding as the built-in plates), with a README.md. STAGE_DIR is
     the content of the orphan `plates` branch: commit it as it is (flat, no folders).
  3. the index is written (default Resources/Data/plates-remote.json):

     {"version": 1, "base": "https://raw.githubusercontent.com/bradleycowdrey/meridian/plates/",
      "cities": [{"key", "names", "zone", "cc", "lat", "lon", "focus", "focusX", "top",
                  "night": {"focus", "focusX", "top"}}],
      "aliases": [{"names", "zone", "cc", "key"}]}

     The apps download base + key + "-day.jpg" and base + key + "-night.jpg".

A city with only one of its two plates, or a key not in the city list, is skipped with a warning
(hosted plates always come in pairs: the apps don't darken a day plate for them). With an empty
PLATES_DIR the index gets an empty city list and the aliases only, and --out may be left out.

Python 3 with Pillow and numpy only.
"""
import argparse
import importlib.util
import json
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_BASE = "https://raw.githubusercontent.com/bradleycowdrey/meridian/plates/"
DEFAULT_CITIES = os.path.join(ROOT, "scripts/plate-cities-tier1.json")
KEY_RE = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")

README = """# Meridian hosted city plates

This branch holds AI-generated city photos ("plates") that the Meridian apps download for cities
without a built-in photo. It is an orphan branch: it shares no history with `main` and holds only
images.

- `<key>-day.jpg` and `<key>-night.jpg`: 1536 x 512 JPEG (3:1), one pair per city, identical framing.
- The keys, names, time zones and placement numbers (focus, focusX, top) are in
  `Resources/Data/plates-remote.json` on `main`, which ships inside each app. The apps fetch
  `https://raw.githubusercontent.com/bradleycowdrey/meridian/plates/<key>-day.jpg` (and `-night.jpg`)
  only when "Download City Photos" is on, and only for cities in that index.
- Credit: Generated with AI for Meridian (AI-generated image).

Do not rename or delete a file here while a released app's index still lists its key.
Published with `scripts/publish-remote-plates.py`; see `docs/skylines.md`, "Hosted plates".
"""


def load_script(name):
    """A sibling script by file name (the names have hyphens, so they're loaded by path)."""
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def warn(msg):
    print(f"warning: {msg}", file=sys.stderr)


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
        if not KEY_RE.fullmatch(key):
            warn(f"{name}: the key must be lowercase letters/digits and hyphens; skipped")
            continue
        plates.setdefault(key, {})[kind] = os.path.join(folder, name)
    return plates


def load_cities(path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if isinstance(data, dict):
        data = data.get("cities")
    if not isinstance(data, list):
        raise SystemExit(f"{path}: expected a list of cities")
    cities = {}
    for c in data:
        key = c.get("key")
        if not key or not KEY_RE.fullmatch(key):
            warn(f"{path}: bad key {key!r}; skipped")
            continue
        if key in cities:
            warn(f"{path}: duplicate key {key}; the first entry is used")
            continue
        cities[key] = c
    return cities


def builtin_keys():
    with open(os.path.join(ROOT, "Resources/Data/skylines.json"), encoding="utf-8") as fh:
        data = json.load(fh)
    entries = data["cities"] if isinstance(data, dict) else data
    return {e["key"]: e for e in entries if isinstance(e, dict) and "key" in e}


def build_aliases(path, builtins):
    """[name, region, cc, zone, builtinKey, km] rows -> [{names, zone, cc, key}], grouped by
    (key, zone, cc) in first-seen order."""
    with open(path, encoding="utf-8") as fh:
        rows = json.load(fh)
    groups = {}
    for row in rows:
        if not isinstance(row, list) or len(row) < 5:
            warn(f"{path}: bad alias row {row!r}; skipped")
            continue
        name, _region, cc, zone, key = row[:5]
        if key not in builtins:
            warn(f"alias {name}: {key} is not a built-in key in skylines.json; skipped")
            continue
        g = groups.setdefault((key, zone, cc), {"names": [], "zone": zone, "cc": cc, "key": key})
        if name not in g["names"]:
            g["names"].append(name)
    return list(groups.values())


def builtin_clash(city, builtins):
    """The built-in key a city would already match (same name, case-insensitive, and zone), if any."""
    name = city["name"].casefold()
    for key, e in builtins.items():
        if e.get("zone") == city["zone"] and any(n.casefold() == name for n in e.get("names", [])):
            return key
    return None


def coord(v):
    return round(float(v), 2)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("plates", help="folder of <key>-day.jpg / <key>-night.jpg plates (1536x512)")
    ap.add_argument("aliases", help="JSON list of [name, region, cc, zone, builtinKey, km]")
    ap.add_argument("--out", help="folder to stage the plates branch in (created if missing)")
    ap.add_argument("--cities", default=DEFAULT_CITIES, help="city list JSON (key, name, region, cc, zone, lat, lon, pop)")
    ap.add_argument("--index", default=os.path.join(ROOT, "Resources/Data/plates-remote.json"),
                    help="where to write the index (default: Resources/Data/plates-remote.json)")
    ap.add_argument("--base", default=DEFAULT_BASE, help="the URL the photos are served from (ends with /)")
    ap.add_argument("--prune", action="store_true", help="delete JPEGs in --out that are not in the index")
    ap.add_argument("--dry-run", action="store_true", help="measure and print the plan; write nothing")
    args = ap.parse_args()

    if not os.path.isdir(args.plates):
        raise SystemExit(f"no folder {args.plates}")
    if not args.base.endswith("/"):
        raise SystemExit("--base must end with /")
    builtins = builtin_keys()
    aliases = build_aliases(args.aliases, builtins)
    plates = find_plates(args.plates)

    cities = {}
    if plates:
        if not os.path.exists(args.cities):
            raise SystemExit(f"no city list {args.cities} (pass --cities)")
        cities = load_cities(args.cities)
    for key in sorted(set(plates) - set(cities)):
        warn(f"{key}: not in {args.cities} (no names/zone to give it); skipped")
    for key in sorted(k for k in plates if k in cities and len(plates[k]) < 2):
        missing = "night" if "night" not in plates[key] else "day"
        warn(f"{key}: no {missing} plate (hosted plates come in pairs); skipped")
    todo = {k: v for k, v in plates.items() if k in cities and len(v) == 2}
    if todo and not args.out:
        raise SystemExit("--out is required when there are plates to publish")

    importer = load_script("import-plates")
    measure = load_script("plate-focus").measure
    plan = {}  # key -> (day image, night image, focusX, focus, top)
    for key in sorted(todo):
        c = cities[key]
        if key in builtins:
            warn(f"{key}: also a built-in key in skylines.json; skipped")
            continue
        clash = builtin_clash(c, builtins)
        if clash:
            warn(f"{key}: {c['name']} ({c['zone']}) already matches built-in {clash}; the apps will show the built-in photo")
        try:
            day = importer.load_plate(todo[key]["day"])
            night = importer.load_plate(todo[key]["night"])
        except (OSError, ValueError) as err:
            warn(f"{key}: {err}; skipped")
            continue
        # Measure the night plate as it will be published (PLATE_SIZE), under its own file name so
        # plate-focus.py finds the plate's entry in plate-overrides.json.
        with tempfile.TemporaryDirectory() as tmp:
            probe = os.path.join(tmp, f"{key}-night.jpg")
            night.save(probe, "JPEG", quality=95)
            m = measure(probe)
        fx, fy, top = float(m["focusX"]), float(m["focus"]), float(m["landmarkTop"])
        if m.get("check"):
            fx, top = importer.PLATE_FOCUS_X, importer.PLATE_TOP
            warn(f"{key}: landmark not found on the night plate; focusX kept at {fx:.2f}, top at {top:.2f}. "
                 "Check it with plate-fit.py")
        plan[key] = (day, night, round(fx, 3), round(fy, 3), round(top, 3))
        print(f"{key:24} focusX {fx:.3f}  focus {fy:.3f}  top {top:.3f}{'  CHECK' if m.get('check') else ''}")

    entries = []
    for key in sorted(plan, key=lambda k: (-(cities[k].get("pop") or 0), k)):
        _, _, fx, fy, top = plan[key]
        c = cities[key]
        place = {"focus": fy, "focusX": fx, "top": top}
        entries.append({"key": key, "names": [c["name"]], "zone": c["zone"], "cc": c["cc"],
                        "lat": coord(c["lat"]), "lon": coord(c["lon"]), **place, "night": dict(place)})
    index = {"version": 1, "base": args.base, "cities": entries, "aliases": aliases}

    print(f"\n{len(entries)} hosted cities, {len(aliases)} aliases ({sum(len(a['names']) for a in aliases)} names)")
    if args.dry_run:
        print(f"  {args.index}" + (f"; {2 * len(entries)} photos and README.md into {args.out}" if args.out else ""))
        print("dry run: nothing written")
        return

    if args.out:
        os.makedirs(args.out, exist_ok=True)
        for key, (day, night, *_rest) in sorted(plan.items()):
            dsize = importer.save_jpeg(day, os.path.join(args.out, f"{key}-day.jpg"))
            nsize = importer.save_jpeg(night, os.path.join(args.out, f"{key}-night.jpg"))
            print(f"staged {key}: day {dsize // 1024} KB, night {nsize // 1024} KB")
        with open(os.path.join(args.out, "README.md"), "w", encoding="utf-8") as fh:
            fh.write(README)
        wanted = {f"{k}-{v}.jpg" for k in plan for v in ("day", "night")}
        stray = sorted(f for f in os.listdir(args.out) if f.lower().endswith((".jpg", ".jpeg")) and f not in wanted)
        for f in stray:
            if args.prune:
                os.remove(os.path.join(args.out, f))
                print(f"removed {f} (not in the index)")
            else:
                warn(f"{args.out}/{f} is not in the index (kept; --prune deletes it)")

    os.makedirs(os.path.dirname(os.path.abspath(args.index)), exist_ok=True)
    tmp = args.index + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(index, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, args.index)
    print(f"wrote {args.index} (version 1, {len(entries)} cities, {len(aliases)} aliases)")


if __name__ == "__main__":
    main()
