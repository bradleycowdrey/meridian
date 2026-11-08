#!/usr/bin/env python3
"""Fetch a freely licensed skyline photo for each city in scripts/skyline-cities.txt.

Runs in CI (.github/workflows/skylines.yml), which publishes the output to the ci-skylines branch;
scripts/import-skylines.sh copies that into the apps. Needs Python 3.11+, Pillow and the network.

For every city it searches Wikimedia Commons ("<city> skyline", then "<city> cityscape"), keeps
only CC0 / public domain / CC BY / CC BY-SA files (never NC or ND), prefers wide landscape
skyline/panorama shots, and falls back to the city's Wikipedia lead image when that passes the
same licence check. The chosen photo is cropped to 2:1, resized to 1000x500 and saved as a
progressive JPEG (quality 62, about 40-60 KB).

Output (in --out, default ./out):
  ios/Skyline-<key>.imageset/{skyline-<key>.jpg, Contents.json}
  android/skyline_<key>.jpg
  skylines.json        manifest: [{key, names, zone, file, credit{author, license, licenseUrl, source}}]
  contact-sheet.jpg    every photo with its name, to check by eye
  report.txt           the file chosen for each city, or why it was skipped

Usage: fetch-skylines.py [--cities FILE] [--out DIR] [--only key,key] [--limit N]
"""

from __future__ import annotations

import argparse
import html
import io
import json
import os
import re
import shutil
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field

USER_AGENT = "MeridianSkylines/1.0 (https://bradcowdrey.com/meridian; photo pipeline for the Meridian app)"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
WIKI_SUMMARY = "https://en.wikipedia.org/api/rest_v1/page/summary/"
THUMB_WIDTH = 1280
OUT_W, OUT_H = 1000, 500
JPEG_QUALITY = 62
MAX_BYTES = 64 * 1024  # busy skylines get a little more compression to stay near 40-60 KB
REQUEST_GAP = 1.0  # seconds between requests (be polite to Wikimedia)

ALLOWED_LICENCE = re.compile(r"^(cc0|cc-zero|public domain|pd\b|pd-|cc[ -]by(-sa)?\b)", re.I)
BANNED_LICENCE = re.compile(r"\b(nc|nd)\b|-nc|-nd|noncommercial|noderiv", re.I)
SKIP_TITLE = re.compile(
    r"collage|montage|mosaic|\bmap\b|locator|location|flag|coat[ _]of[ _]arms|emblem|seal\b|logo|"
    r"diagram|chart|plan\b|banner|poster|stamp|postcard|drawing|painting|engraving|lithograph|"
    r"illustration|\bsvg\b|\.svg|\.gif|\.tif|\.tiff|"
    # Things merely named "Skyline": cars, ships, restaurants, hotels.
    r"nissan|gt-?r\b|\bcar\b|navire|\bship\b|vessel|container|restaurant|hotel|motel|diner|power[ _]lines",
    re.I,
)
GOOD_TITLE = re.compile(r"skyline|panorama|cityscape|\bview\b|aerial|downtown|vista", re.I)


# ---------------------------------------------------------------- cities

@dataclass
class City:
    name: str
    title: str
    zone: str
    aliases: list[str] = field(default_factory=list)
    file_override: str | None = None
    excluded: set[str] = field(default_factory=set)

    @property
    def key(self) -> str:
        return city_key(self.name)

    @property
    def names(self) -> list[str]:
        out: list[str] = []
        for n in [self.name, *self.aliases]:
            if n and n.lower() not in (o.lower() for o in out):
                out.append(n)
        return out

    @property
    def search_name(self) -> str:
        """"Portland, Oregon" -> "Portland Oregon" (a better search than the bare display name)."""
        return re.sub(r"\s+", " ", re.sub(r"[,_()]", " ", self.title)).strip()


def city_key(name: str) -> str:
    """Lowercase letters only, accents folded: "São Paulo" -> "saopaulo", "Washington DC" -> "washingtondc"."""
    folded = unicodedata.normalize("NFKD", name)
    return "".join(c for c in folded.lower() if "a" <= c <= "z")


def parse_cities(text: str) -> list[City]:
    cities: list[City] = []
    seen: dict[str, str] = {}
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 3 or not parts[0] or not parts[2]:
            raise ValueError(f"line {n}: expected 'Name|Wikipedia title|Zone|aliases': {raw!r}")
        name, title, zone = parts[0], parts[1] or parts[0], parts[2]
        aliases = [a.strip() for a in re.split(r"[;,]", parts[3])] if len(parts) > 3 else []
        # Field 5: "File:X.jpg" pins that file; "-File:A.jpg;-File:B.jpg" rules those files out of the search.
        extra = parts[4] if len(parts) > 4 and parts[4] else ""
        excluded = [e.strip()[1:].strip() for e in extra.split(";") if e.strip().startswith("-")]
        override = None if (not extra or extra.startswith("-")) else extra
        city = City(name, title, zone, [a for a in aliases if a], override, set(excluded))
        if not city.key:
            raise ValueError(f"line {n}: {name!r} has no letters for a key")
        if city.key in seen:
            raise ValueError(f"line {n}: key {city.key!r} of {name!r} is already used by {seen[city.key]!r}")
        seen[city.key] = name
        cities.append(city)
    return cities


# ---------------------------------------------------------------- licences and metadata

def strip_html(value: str | None) -> str:
    if not value:
        return ""
    text = re.sub(r"<[^>]+>", " ", value)
    text = html.unescape(text)
    return re.sub(r"\s+", " ", text).strip()


def licence_ok(short_name: str | None) -> bool:
    if not short_name:
        return False
    s = strip_html(short_name).strip()
    return bool(ALLOWED_LICENCE.search(s)) and not BANNED_LICENCE.search(s)


def meta_value(ext: dict, name: str) -> str:
    v = ext.get(name) or {}
    return strip_html(v.get("value") if isinstance(v, dict) else str(v))


def credit_from(info: dict) -> dict | None:
    """The credit for an imageinfo entry, or None if its licence isn't one we may use."""
    ext = info.get("extmetadata") or {}
    licence = meta_value(ext, "LicenseShortName")
    if not licence_ok(licence):
        return None
    author = meta_value(ext, "Artist") or meta_value(ext, "Credit") or "Unknown author"
    if len(author) > 120:
        author = author[:117].rstrip() + "..."
    return {
        "author": author,
        "license": licence,
        "licenseUrl": meta_value(ext, "LicenseUrl"),
        "source": info.get("descriptionurl") or "",
    }


def score_candidate(title: str, info: dict) -> float | None:
    """Higher is better; None means never use it."""
    if SKIP_TITLE.search(title):
        return None
    w, h = info.get("width") or 0, info.get("height") or 0
    if w < 800 or h < 300:
        return None
    mime = info.get("mime") or ""
    if mime and mime not in ("image/jpeg", "image/png", "image/webp"):
        return None
    aspect = w / h
    if aspect < 1.2:
        return None  # portrait or square: a 2:1 crop throws most of it away
    score = 0.0
    if 1.6 <= aspect <= 3.2:
        score += 3
    elif aspect > 3.2:
        score += 1  # very wide panorama: still usable, centre crop
    else:
        score += 0.5
    if w >= 1600:
        score += 2
    elif w >= 1280:
        score += 1
    if GOOD_TITLE.search(title):
        score += 2
    if re.search(r"skyline", title, re.I):
        score += 1
    return score


def file_name_from_url(url: str) -> str | None:
    """'.../commons/thumb/a/ab/Foo_bar.jpg/1280px-Foo_bar.jpg' or '.../commons/a/ab/Foo_bar.jpg' -> 'Foo_bar.jpg'."""
    path = urllib.parse.urlparse(url).path
    parts = [p for p in path.split("/") if p]
    if not parts:
        return None
    if "thumb" in parts:
        i = parts.index("thumb")
        if len(parts) > i + 3:
            return urllib.parse.unquote(parts[i + 3])
    return urllib.parse.unquote(parts[-1])


# ---------------------------------------------------------------- images

def crop_resize(img, out_w: int = OUT_W, out_h: int = OUT_H):
    """Crop to out_w:out_h (centred across, slightly above the middle down), then resize."""
    from PIL import Image

    img = img.convert("RGB")
    w, h = img.size
    target = out_w / out_h
    if w / h > target:
        cw = round(h * target)
        left = (w - cw) // 2
        box = (left, 0, left + cw, h)
    else:
        ch = round(w / target)
        top = round((h - ch) * 0.42)
        box = (0, top, w, top + ch)
    return img.crop(box).resize((out_w, out_h), Image.LANCZOS)


def save_jpeg(img, path: str, quality: int = JPEG_QUALITY, max_bytes: int = MAX_BYTES) -> int:
    """Progressive JPEG at `quality`, stepping down (not below 48) while it is over max_bytes."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    q = quality
    while True:
        img.save(path, "JPEG", quality=q, progressive=True, optimize=True)
        size = os.path.getsize(path)
        if size <= max_bytes or q <= 48:
            return size
        q -= 4


def imageset_contents(filename: str) -> dict:
    return {"images": [{"filename": filename, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}


def contact_sheet(entries: list[tuple[str, str]], path: str, cols: int = 5, tw: int = 300) -> None:
    """entries: (label, jpeg path)."""
    from PIL import Image, ImageDraw, ImageFont

    if not entries:
        return
    th = tw // 2
    label_h = 22
    rows = (len(entries) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * (th + label_h)), (26, 24, 22))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.load_default(size=14)
    except TypeError:  # Pillow < 10.1
        font = ImageFont.load_default()
    for i, (label, jpg) in enumerate(entries):
        x, y = (i % cols) * tw, (i // cols) * (th + label_h)
        try:
            with Image.open(jpg) as im:
                sheet.paste(im.convert("RGB").resize((tw, th)), (x, y))
        except Exception:
            continue
        draw.text((x + 6, y + th + 3), label, fill=(235, 235, 235), font=font)
    sheet.save(path, "JPEG", quality=70, progressive=True, optimize=True)


# ---------------------------------------------------------------- network

class Fetcher:
    def __init__(self, gap: float = REQUEST_GAP, retries: int = 5):
        self.gap = gap
        self.retries = retries
        self._last = 0.0

    def get(self, url: str, params: dict | None = None) -> bytes:
        if params:
            url = url + ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
        delay = 5.0
        for attempt in range(self.retries + 1):
            wait = self.gap - (time.monotonic() - self._last)
            if wait > 0:
                time.sleep(wait)
            self._last = time.monotonic()
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept-Encoding": "identity"})
            try:
                with urllib.request.urlopen(req, timeout=60) as resp:
                    return resp.read()
            except urllib.error.HTTPError as e:
                if e.code in (429, 500, 502, 503, 504) and attempt < self.retries:
                    retry_after = e.headers.get("Retry-After") if e.headers else None
                    pause = float(retry_after) if retry_after and retry_after.isdigit() else delay
                    print(f"    HTTP {e.code}, retrying in {pause:.0f}s", flush=True)
                    time.sleep(min(pause, 120))
                    delay *= 2
                    continue
                raise
            except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
                if attempt < self.retries:
                    print(f"    {e}, retrying in {delay:.0f}s", flush=True)
                    time.sleep(delay)
                    delay *= 2
                    continue
                raise
        raise RuntimeError("unreachable")

    def json(self, url: str, params: dict | None = None) -> dict:
        return json.loads(self.get(url, params).decode("utf-8"))


IMAGEINFO = {"prop": "imageinfo", "iiprop": "url|size|mime|extmetadata", "iiurlwidth": str(THUMB_WIDTH)}


def commons_search(f: Fetcher, query: str) -> list[tuple[str, dict]]:
    data = f.json(COMMONS_API, {
        "action": "query", "format": "json", "formatversion": "2",
        "generator": "search", "gsrsearch": f"{query} filetype:bitmap", "gsrnamespace": "6", "gsrlimit": "25",
        **IMAGEINFO,
    })
    pages = (data.get("query") or {}).get("pages") or []
    pages.sort(key=lambda p: p.get("index", 0))
    return [(p["title"], p["imageinfo"][0]) for p in pages if p.get("imageinfo")]


def commons_file(f: Fetcher, title: str) -> tuple[str, dict] | None:
    if not title.lower().startswith("file:"):
        title = "File:" + title
    data = f.json(COMMONS_API, {"action": "query", "format": "json", "formatversion": "2", "titles": title, **IMAGEINFO})
    for p in (data.get("query") or {}).get("pages") or []:
        if p.get("imageinfo") and not p.get("missing"):
            return p["title"], p["imageinfo"][0]
    return None


def lead_image(f: Fetcher, city: City) -> tuple[str, dict] | None:
    try:
        data = f.json(WIKI_SUMMARY + urllib.parse.quote(city.title.replace(" ", "_"), safe=""))
    except urllib.error.HTTPError:
        return None
    src = (data.get("originalimage") or data.get("thumbnail") or {}).get("source")
    name = file_name_from_url(src) if src else None
    return commons_file(f, name) if name else None


def choose(f: Fetcher, city: City) -> tuple[str, dict, dict, str] | str:
    """(title, imageinfo, credit, how) or the reason nothing was chosen."""
    if city.file_override:
        found = commons_file(f, city.file_override)
        if not found:
            return f"override {city.file_override} not found"
        credit = credit_from(found[1])
        if not credit:
            return f"override {city.file_override} has a licence we can't use"
        return found[0], found[1], credit, "override"

    reasons: list[str] = []
    for query in (f"{city.search_name} skyline", f"{city.search_name} cityscape"):
        best = None
        rejected_licence = 0
        try:
            results = commons_search(f, query)
        except Exception as e:  # keep going with the next query
            reasons.append(f"search '{query}' failed: {e}")
            continue
        for title, info in results:
            if title in city.excluded:
                continue
            score = score_candidate(title, info)
            if score is None:
                continue
            credit = credit_from(info)
            if not credit:
                rejected_licence += 1
                continue
            if best is None or score > best[0]:
                best = (score, title, info, credit)
        if best:
            return best[1], best[2], best[3], f"search '{query}' (score {best[0]:g})"
        reasons.append(f"'{query}': {len(results)} results, none usable ({rejected_licence} bad licence)")

    try:
        found = lead_image(f, city)
    except Exception as e:
        found = None
        reasons.append(f"lead image failed: {e}")
    if found:
        credit = credit_from(found[1])
        w, h = found[1].get("width") or 0, found[1].get("height") or 0
        if credit and w >= 800 and h and w / h >= 1.2 and not SKIP_TITLE.search(found[0]):
            return found[0], found[1], credit, "Wikipedia lead image"
        reasons.append(f"lead image {found[0]} unusable (licence or shape)")
    else:
        reasons.append("no Commons lead image")
    return "; ".join(reasons)


# ---------------------------------------------------------------- main

def main(argv: list[str] | None = None) -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cities", default=os.path.join(here, "skyline-cities.txt"))
    ap.add_argument("--out", default="out")
    ap.add_argument("--only", default="", help="comma-separated keys to fetch (default: all)")
    ap.add_argument("--limit", type=int, default=0, help="stop after this many cities (testing)")
    args = ap.parse_args(argv)

    from PIL import Image  # fail early if Pillow is missing

    with open(args.cities, encoding="utf-8") as fh:
        cities = parse_cities(fh.read())
    if args.only:
        wanted = {k.strip() for k in args.only.split(",") if k.strip()}
        cities = [c for c in cities if c.key in wanted]
    if args.limit:
        cities = cities[: args.limit]

    out = args.out
    for sub in ("ios", "android"):
        shutil.rmtree(os.path.join(out, sub), ignore_errors=True)
        os.makedirs(os.path.join(out, sub), exist_ok=True)

    f = Fetcher()
    manifest: list[dict] = []
    report: list[str] = []
    sheet: list[tuple[str, str]] = []
    for i, city in enumerate(cities, 1):
        print(f"[{i}/{len(cities)}] {city.name}", flush=True)
        try:
            picked = choose(f, city)
            if isinstance(picked, str):
                report.append(f"SKIP  {city.key:<18} {city.name}: {picked}")
                continue
            title, info, credit, how = picked
            url = info.get("thumburl") or info.get("url")
            data = f.get(url)
            with Image.open(io.BytesIO(data)) as im:
                img = crop_resize(im)
            fname = f"skyline-{city.key}.jpg"
            imageset = os.path.join(out, "ios", f"Skyline-{city.key}.imageset")
            ios_jpg = os.path.join(imageset, fname)
            size = save_jpeg(img, ios_jpg)
            with open(os.path.join(imageset, "Contents.json"), "w", encoding="utf-8") as fh:
                json.dump(imageset_contents(fname), fh, indent=1)
                fh.write("\n")
            shutil.copyfile(ios_jpg, os.path.join(out, "android", f"skyline_{city.key}.jpg"))
            manifest.append({"key": city.key, "names": city.names, "zone": city.zone, "file": fname, "credit": credit})
            sheet.append((f"{city.name} - {credit['license']}", ios_jpg))
            report.append(f"OK    {city.key:<18} {title}  [{credit['license']}; {credit['author']}]  via {how}, {size // 1024} KB")
        except Exception as e:
            report.append(f"SKIP  {city.key:<18} {city.name}: error {type(e).__name__}: {e}")

    with open(os.path.join(out, "skylines.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    try:
        contact_sheet(sheet, os.path.join(out, "contact-sheet.jpg"))
    except Exception as e:
        report.append(f"contact sheet failed: {e}")
    summary = f"{len(manifest)} of {len(cities)} cities have a photo"
    with open(os.path.join(out, "report.txt"), "w", encoding="utf-8") as fh:
        fh.write(summary + "\n\n" + "\n".join(report) + "\n")
    print(summary)
    return 0 if manifest or not cities else 1


if __name__ == "__main__":
    sys.exit(main())
