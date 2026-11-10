#!/usr/bin/env python3
"""Fetch a freely licensed DAY and NIGHT skyline photo for each city in scripts/skyline-cities.txt.

Runs in CI (.github/workflows/skylines.yml), which publishes the output to the ci-skylines branch;
scripts/import-skylines.sh copies that into the apps. Needs Python 3.11+, Pillow and the network
(except --selftest, which runs offline).

For every city and each kind it searches Wikimedia Commons:
  DAY:   "<city> skyline", "<city> cityscape", "<city> skyline day"
  NIGHT: "<city> skyline night", "<city> at night", "<city> night skyline", "<city> night"
It keeps only CC0 / public domain / CC BY / CC BY-SA files (never NC or ND) whose title names the
city, scores wide landscape skyline shots highest (a "night" title is a bonus for NIGHT; no
"night"/"dusk"/"sunset" in the title is a bonus for DAY), and then CLASSIFIES BY PIXELS: for the
top few candidates a 330px thumbnail is measured (mean linear luminance of the whole image and of
its top third, the sky, plus the share of very bright pixels):
  DAY   needs sky >= 0.25 and whole >= 0.15                        (a bright daytime sky)
  NIGHT needs whole <= 0.10, sky <= 0.08 and >= 0.5% pixels >= 0.6  (dark, with lit windows)
Golden-hour shots that fit neither are rejected for both. The DAY search falls back to the
city's Wikipedia lead image (same licence and pixel checks). A pinned file (field 5 for DAY,
field 6 for NIGHT) is used as is; its luminance is only reported.

The chosen photo's 1280px thumbnail is cropped to 2:1 (slightly above the middle), resized to
1000x500 and saved as a progressive JPEG (quality 62, stepping down to 48 while over 64 KB).

Output (in --out, default ./out):
  ios/Skyline-<key>.imageset/{skyline-<key>.jpg, Contents.json}                 DAY
  ios/Skyline-<key>-night.imageset/{skyline-<key>-night.jpg, Contents.json}     NIGHT
  android/skyline_<key>.jpg, android/skyline_<key>_night.jpg
  skylines.json        manifest v2: [{key, names, zone, file, credit, focus, night: {file, credit, focus} | null}]
                       focus = vertical centre (0..1) of the skyline band, see skyline_focus()
                       (top-level file/credit are the DAY photo, so older apps keep working; a
                       city is listed only when it has a DAY photo)
  contact-sheet.jpg    each city's DAY and NIGHT side by side with measured luminance
  report.txt           per city and kind: the chosen file and its luminance, or why none

Usage: fetch-skylines.py [--cities FILE] [--out DIR] [--only key,key] [--limit N] [--selftest]
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
import tempfile
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field

USER_AGENT = "MeridianSkylines/2.0 (https://bradcowdrey.com/meridian; photo pipeline for the Meridian app)"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
WIKI_SUMMARY = "https://en.wikipedia.org/api/rest_v1/page/summary/"
THUMB_WIDTH = 1280
OUT_W, OUT_H = 1000, 500
JPEG_QUALITY = 62
MAX_BYTES = 64 * 1024  # busy skylines get a little more compression to stay near 40-60 KB
REQUEST_GAP = 1.0  # seconds between requests (be polite to Wikimedia)
PROBE_WIDTH = 330  # thumbnail measured for day/night; Wikimedia's standard widths: 250/330/500/960/1280
PROBE_COUNT = 6  # top-scored candidates measured per kind

DAY, NIGHT = "day", "night"
QUERIES = {
    DAY: ("{} skyline", "{} cityscape", "{} skyline day"),
    NIGHT: ("{} skyline night", "{} at night", "{} night skyline", "{} night"),
}
# Pixel thresholds (mean linear luminance, 0..1). Golden hour falls between and is used for neither.
DAY_MIN_SKY, DAY_MIN_WHOLE = 0.25, 0.15
NIGHT_MAX_WHOLE, NIGHT_MAX_SKY = 0.10, 0.08
NIGHT_BRIGHT_LUM, NIGHT_MIN_BRIGHT = 0.6, 0.005
# Second chance for a city with no strict night photo: a "night" title that is still clearly dark
# (blue-hour and well-lit downtown shots that the strict test turns away).
NIGHT_RELAXED_WHOLE, NIGHT_RELAXED_SKY, NIGHT_RELAXED_BRIGHT = 0.20, 0.15, 0.002
NIGHT_TITLE = re.compile(r"night|nocturn|\bnuit\b|\bnoche\b|\bnacht\b", re.I)
NOT_DAY_TITLE = re.compile(r"night|nocturn|dusk|sunset|twilight|blue[ _]hour|evening", re.I)

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
    file_override: str | None = None  # DAY pin (field 5)
    excluded: set[str] = field(default_factory=set)  # DAY excludes (field 5)
    night_override: str | None = None  # NIGHT pin (field 6)
    night_excluded: set[str] = field(default_factory=set)  # NIGHT excludes (field 6)

    def pin(self, kind: str) -> str | None:
        return self.night_override if kind == NIGHT else self.file_override

    def excludes(self, kind: str) -> set[str]:
        return self.night_excluded if kind == NIGHT else self.excluded

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


def parse_pins(extra: str) -> tuple[str | None, set[str]]:
    """"File:X.jpg" -> ("File:X.jpg", {}); "-File:A.jpg;-File:B.jpg" -> (None, {"File:A.jpg", "File:B.jpg"})."""
    extra = extra.strip()
    if not extra:
        return None, set()
    excluded = {e.strip()[1:].strip() for e in extra.split(";") if e.strip().startswith("-")}
    return (None if extra.startswith("-") else extra), excluded


def parse_cities(text: str) -> list[City]:
    cities: list[City] = []
    seen: dict[str, str] = {}
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 3 or not parts[0] or not parts[2]:
            raise ValueError(f"line {n}: expected 'Name|Wikipedia title|Zone|aliases|day pins|night pins': {raw!r}")
        name, title, zone = parts[0], parts[1] or parts[0], parts[2]
        aliases = [a.strip() for a in re.split(r"[;,]", parts[3])] if len(parts) > 3 else []
        # Field 5 (DAY) and field 6 (NIGHT): "File:X.jpg" pins that file; "-File:A.jpg;-File:B.jpg"
        # rules those files out of the search.
        day_pin, day_ex = parse_pins(parts[4] if len(parts) > 4 else "")
        night_pin, night_ex = parse_pins(parts[5] if len(parts) > 5 else "")
        city = City(name, title, zone, [a for a in aliases if a], day_pin, day_ex, night_pin, night_ex)
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


def score_candidate(title: str, info: dict, kind: str = DAY) -> float | None:
    """Higher is better; None means never use it. The title only nudges the score: whether a photo
    is DAY or NIGHT is decided by its pixels (classify)."""
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
    if kind == NIGHT and NIGHT_TITLE.search(title):
        score += 2
    if kind == DAY and not NOT_DAY_TITLE.search(title):
        score += 1.5
    return score


def _fold(text: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFKD", text).lower() if c.isalnum() or c == " ")


def names_city(title: str, city: City) -> bool:
    """A search hit must name the city (or an alias): "Sydney Skyline" is no photo of Casablanca."""
    t = _fold(title.replace("_", " "))
    words = [city.name, city.title.split(",")[0], *city.aliases]
    return any(len(w) >= 3 and _fold(w) in t for w in words if not (w.isupper() and len(w) == 3))


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


def thumb_url(info: dict, width: int) -> str | None:
    """The Commons thumbnail URL of `width` px (use a standard width: 250/330/500/960/1280).

    Built from imageinfo's thumburl ('.../thumb/a/ab/F.jpg/1280px-F.jpg') or, when Commons gave
    the original instead, from its url ('.../a/ab/F.jpg'). None for a file narrower than `width`
    (then use the original)."""
    if (info.get("width") or 0) <= width:
        return None
    turl = info.get("thumburl") or ""
    m = re.match(r"^(.*/thumb/.+?/)(\d+)px-([^/]+)$", turl)
    if m:
        return f"{m.group(1)}{width}px-{m.group(3)}"
    url = info.get("url") or ""
    m = re.match(r"^(https?://[^/]+/wikipedia/commons/)([0-9a-f]/[0-9a-f]{2}/)([^/]+)$", url)
    if m:
        return f"{m.group(1)}thumb/{m.group(2)}{m.group(3)}/{width}px-{m.group(3)}"
    return None


# ---------------------------------------------------------------- images

# sRGB 0..255 -> linear 0..1
_LINEAR = [(v / 255 / 12.92) if v <= 10 else (((v / 255) + 0.055) / 1.055) ** 2.4 for v in range(256)]


@dataclass
class Luma:
    whole: float  # mean linear luminance of the whole image
    sky: float  # ... of the top third
    bright: float  # share of pixels with luminance >= NIGHT_BRIGHT_LUM

    def __str__(self) -> str:
        return f"lum {self.whole:.3f}, sky {self.sky:.3f}, bright {self.bright * 100:.1f}%"

    def as_dict(self) -> dict:
        return {"whole": round(self.whole, 4), "sky": round(self.sky, 4), "bright": round(self.bright, 4)}


def measure(img, width: int = PROBE_WIDTH) -> Luma:
    """Mean linear (Rec. 709) luminance of the image and its top third, and the bright-pixel share."""
    from PIL import Image

    img = img.convert("RGB")
    if img.width > width:
        # Nearest-neighbour keeps lit windows as bright as they are (a filter would smear them
        # below NIGHT_BRIGHT_LUM) while sampling evenly, so the means are unbiased too.
        img = img.resize((width, max(1, round(img.height * width / img.width))), Image.NEAREST)
    w, h = img.size
    sky_rows = max(1, h // 3)
    lin = _LINEAR
    total = sky = 0.0
    bright = 0
    px = img.tobytes()
    for i in range(w * h):
        r, g, b = px[3 * i], px[3 * i + 1], px[3 * i + 2]
        y = 0.2126 * lin[r] + 0.7152 * lin[g] + 0.0722 * lin[b]
        total += y
        if i < sky_rows * w:
            sky += y
        if y >= NIGHT_BRIGHT_LUM:
            bright += 1
    n = w * h
    return Luma(total / n, sky / (sky_rows * w), bright / n)


def classify(l: Luma) -> str | None:
    """DAY, NIGHT, or None (golden hour, overcast gloom, anything in between)."""
    if l.sky >= DAY_MIN_SKY and l.whole >= DAY_MIN_WHOLE:
        return DAY
    if l.whole <= NIGHT_MAX_WHOLE and l.sky <= NIGHT_MAX_SKY and l.bright >= NIGHT_MIN_BRIGHT:
        return NIGHT
    return None


def why_not(l: Luma, kind: str) -> str:
    if kind == DAY:
        bits = [f"sky {l.sky:.3f} < {DAY_MIN_SKY}" if l.sky < DAY_MIN_SKY else "",
                f"lum {l.whole:.3f} < {DAY_MIN_WHOLE}" if l.whole < DAY_MIN_WHOLE else ""]
    else:
        bits = [f"lum {l.whole:.3f} > {NIGHT_MAX_WHOLE}" if l.whole > NIGHT_MAX_WHOLE else "",
                f"sky {l.sky:.3f} > {NIGHT_MAX_SKY}" if l.sky > NIGHT_MAX_SKY else "",
                f"bright {l.bright * 100:.2f}% < {NIGHT_MIN_BRIGHT * 100:g}%" if l.bright < NIGHT_MIN_BRIGHT else ""]
    return ", ".join(b for b in bits if b) or "ok"


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


FOCUS_DEFAULT = 0.62  # the apps' anchor for a photo without "focus"


def _percentile(values: list[float], p: float) -> float:
    """Linear-interpolated percentile (numpy's default method)."""
    s = sorted(values)
    k = (len(s) - 1) * p / 100
    i = int(k)
    j = min(i + 1, len(s) - 1)
    return s[i] + (s[j] - s[i]) * (k - i)


def skyline_focus(img) -> float:
    """Vertical centre (0..1 of the height) of the skyline band: the first row, from the top, whose
    edge energy rises above the plain sky's, placed a quarter of the way down a ~30%-tall band.
    The apps put focus x imageHeight at the row's vertical centre."""
    g = img.convert("L").resize((250, 125))
    w, h = g.size
    px = g.tobytes()
    e: list[float] = []  # mean |dx| + |dy| per row, rows 0..h-2
    for y in range(h - 1):
        r = y * w
        total = 0
        for x in range(w - 1):
            p = px[r + x]
            total += abs(px[r + x + 1] - p) + abs(px[r + w + x] - p)
        e.append(total / (w - 1))
    n = len(e)
    sm = [sum(e[k] for k in range(i - 2, i + 3) if 0 <= k < n) / 5 for i in range(n)]  # 5-row box, zero-padded
    p30, p90 = _percentile(sm, 30), _percentile(sm, 90)
    thr = p30 + 0.35 * (p90 - p30)
    top = next((i for i, v in enumerate(sm) if v > thr), 0.4 * n)
    return round(min(0.85, max(0.15, top / n + 0.30 * 0.25)), 3)


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


def contact_sheet(rows: list[tuple[str, tuple[str, str] | None, tuple[str, str] | None]], path: str,
                  pairs_per_row: int = 3, tw: int = 300) -> None:
    """rows: (city name, (DAY label, jpeg) or None, (NIGHT label, jpeg) or None); each city's DAY and
    NIGHT side by side, labelled with the measured luminance."""
    from PIL import Image, ImageDraw, ImageFont

    if not rows:
        return
    th = tw // 2
    label_h = 38
    gap = 12
    pair_w = 2 * tw + gap
    nrows = (len(rows) + pairs_per_row - 1) // pairs_per_row
    sheet = Image.new("RGB", (pairs_per_row * pair_w, nrows * (th + label_h)), (0, 0, 0))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.load_default(size=13)
    except TypeError:  # Pillow < 10.1
        font = ImageFont.load_default()
    for i, (name, day, night) in enumerate(rows):
        x0, y = (i % pairs_per_row) * pair_w, (i // pairs_per_row) * (th + label_h)
        for j, (kind, item) in enumerate(((DAY, day), (NIGHT, night))):
            x = x0 + j * tw
            if item is None:
                draw.rectangle((x, y, x + tw - 1, y + th - 1), outline=(90, 90, 90))
                draw.text((x + 8, y + th // 2 - 8), f"no {kind} photo", fill=(150, 150, 150), font=font)
                label = f"{name} {kind.upper()}"
            else:
                label, jpg = item
                try:
                    with Image.open(jpg) as im:
                        sheet.paste(im.convert("RGB").resize((tw, th)), (x, y))
                except Exception:
                    pass
            for k, line in enumerate(label.split("\n")[:2]):
                draw.text((x + 6, y + th + 3 + k * 16), line, fill=(235, 235, 235), font=font)
    sheet.save(path, "JPEG", quality=70, progressive=True, optimize=True)


def write_photo(img, out: str, key: str, kind: str) -> tuple[str, str, int]:
    """Writes the iOS imageset and Android drawable; returns (file name, iOS jpeg path, bytes)."""
    suffix_ios, suffix_android = ("-night", "_night") if kind == NIGHT else ("", "")
    fname = f"skyline-{key}{suffix_ios}.jpg"
    imageset = os.path.join(out, "ios", f"Skyline-{key}{suffix_ios}.imageset")
    ios_jpg = os.path.join(imageset, fname)
    size = save_jpeg(img, ios_jpg)
    with open(os.path.join(imageset, "Contents.json"), "w", encoding="utf-8") as fh:
        json.dump(imageset_contents(fname), fh, indent=1)
        fh.write("\n")
    shutil.copyfile(ios_jpg, os.path.join(out, "android", f"skyline_{key}{suffix_android}.jpg"))
    return fname, ios_jpg, size


def manifest_entry(city: City, day: dict, night: dict | None) -> dict:
    """day / night: {"file", "credit", "focus"}. Top-level file, credit and focus are the DAY photo
    (manifest v1 shape plus focus); a missing focus is written as FOCUS_DEFAULT."""
    def focus(d: dict) -> float:
        return d.get("focus", FOCUS_DEFAULT)

    return {"key": city.key, "names": city.names, "zone": city.zone, "file": day["file"], "credit": day["credit"],
            "night": {"file": night["file"], "credit": night["credit"], "focus": focus(night)} if night else None,
            "focus": focus(day)}


def write_manifest(entries: list[dict], path: str) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(entries, fh, indent=1, ensure_ascii=False)
        fh.write("\n")


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


@dataclass
class Pick:
    title: str
    info: dict
    credit: dict
    how: str
    luma: Luma | None


class Prober:
    """Measures candidates from a small thumbnail, once per file (a file seen by both kinds is fetched once)."""

    def __init__(self, f: Fetcher):
        self.f = f
        self.cache: dict[str, Luma | str] = {}

    def luma(self, title: str, info: dict) -> Luma | str:
        if title not in self.cache:
            from PIL import Image

            url = thumb_url(info, PROBE_WIDTH) or info.get("thumburl") or info.get("url")
            try:
                with Image.open(io.BytesIO(self.f.get(url))) as im:
                    self.cache[title] = measure(im)
            except Exception as e:
                self.cache[title] = f"thumbnail failed: {type(e).__name__}: {e}"
        return self.cache[title]


def lead_candidate(f: Fetcher, city: City) -> tuple[str, dict, dict] | str:
    found = lead_image(f, city)
    if not found:
        return "no Commons lead image"
    credit = credit_from(found[1])
    w, h = found[1].get("width") or 0, found[1].get("height") or 0
    if credit and w >= 800 and h and w / h >= 1.2 and not SKIP_TITLE.search(found[0]):
        return found[0], found[1], credit
    return f"lead image {found[0]} unusable (licence or shape)"


def choose(f: Fetcher, prober: Prober, city: City, kind: str) -> Pick | str:
    """The DAY or NIGHT photo for a city, or the reason there is none."""
    pin = city.pin(kind)
    if pin:
        found = commons_file(f, pin)
        if not found:
            return f"pinned {pin} not found"
        credit = credit_from(found[1])
        if not credit:
            return f"pinned {pin} has a licence we can't use"
        l = prober.luma(found[0], found[1])
        return Pick(found[0], found[1], credit, "pinned", l if isinstance(l, Luma) else None)

    reasons: list[str] = []
    candidates: dict[str, tuple[float, dict, dict, str]] = {}
    for pattern in QUERIES[kind]:
        query = pattern.format(city.search_name)
        try:
            results = commons_search(f, query)
        except Exception as e:  # keep going with the next query
            reasons.append(f"search '{query}' failed: {e}")
            continue
        usable = bad_licence = 0
        for title, info in results:
            if title in city.excludes(kind) or title in candidates or not names_city(title, city):
                continue
            score = score_candidate(title, info, kind)
            if score is None:
                continue
            credit = credit_from(info)
            if not credit:
                bad_licence += 1
                continue
            candidates[title] = (score, info, credit, query)
            usable += 1
        if not usable:
            reasons.append(f"'{query}': {len(results)} results, none new and usable ({bad_licence} bad licence)")

    ranked = sorted(candidates.items(), key=lambda kv: -kv[1][0])[:PROBE_COUNT]
    measured = 0

    def try_ranked(items) -> Pick | None:
        nonlocal measured
        for title, (score, info, credit, query) in items:
            l = prober.luma(title, info)
            if isinstance(l, str):
                reasons.append(f"{title}: {l}")
                continue
            measured += 1
            if classify(l) == kind:
                how = query if query == "Wikipedia lead image" else f"search '{query}' (score {score:g})"
                return Pick(title, info, credit, how, l)
            reasons.append(f"{title}: not {kind} ({why_not(l, kind)})")
        return None

    picked = try_ranked(ranked)
    if picked:
        return picked
    if kind == NIGHT:  # second chance: titled as night and clearly dark, if a little brighter
        for title, (score, info, credit, query) in ranked:
            if not NIGHT_TITLE.search(title):
                continue
            l = prober.luma(title, info)
            if isinstance(l, str):
                continue
            if (l.whole <= NIGHT_RELAXED_WHOLE and l.sky <= NIGHT_RELAXED_SKY and l.bright >= NIGHT_RELAXED_BRIGHT
                    and classify(l) != DAY):
                return Pick(title, info, credit, f"search '{query}' (score {score:g}, relaxed night)", l)
    tried = len(ranked)
    if kind == DAY:  # last resort: the city's Wikipedia lead image, if it is a usable daytime photo
        try:
            lead = lead_candidate(f, city)
        except Exception as e:
            lead = f"lead image failed: {e}"
        if isinstance(lead, str):
            reasons.append(lead)
        elif lead[0] in city.excluded:
            reasons.append(f"lead image {lead[0]} is excluded")
        elif lead[0] not in dict(ranked):
            tried += 1
            picked = try_ranked([(lead[0], (0.0, lead[1], lead[2], "Wikipedia lead image"))])
            if picked:
                return picked
    reasons.append(f"{measured} of {tried} top candidates measured, none looked like {kind}"
                   if tried else "no usable candidates")
    return "; ".join(reasons)


# ---------------------------------------------------------------- main

def run(args) -> int:
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
    prober = Prober(f)
    manifest: list[dict] = []
    report: list[str] = []
    sheet: list[tuple[str, tuple[str, str] | None, tuple[str, str] | None]] = []
    nights = 0
    for i, city in enumerate(cities, 1):
        print(f"[{i}/{len(cities)}] {city.name}", flush=True)
        done: dict[str, dict] = {}
        tiles: dict[str, tuple[str, str]] = {}
        for kind in (DAY, NIGHT):
            tag = f"{kind.upper():<5}"
            try:
                picked = choose(f, prober, city, kind)
                if isinstance(picked, str):
                    report.append(f"SKIP  {tag} {city.key:<18} {city.name}: {picked}")
                    continue
                url = picked.info.get("thumburl") or picked.info.get("url")
                with Image.open(io.BytesIO(f.get(url))) as im:
                    img = crop_resize(im)
                fname, jpg, size = write_photo(img, out, city.key, kind)
                done[kind] = {"file": fname, "credit": picked.credit, "focus": skyline_focus(img)}
                lum = str(picked.luma) if picked.luma else "lum not measured"
                tiles[kind] = (f"{city.name} {kind.upper()} - {picked.credit['license']}\n{lum}", jpg)
                report.append(f"OK    {tag} {city.key:<18} {picked.title}  [{picked.credit['license']}; "
                              f"{picked.credit['author']}]  {lum}; via {picked.how}, {size // 1024} KB")
            except Exception as e:
                report.append(f"SKIP  {tag} {city.key:<18} {city.name}: error {type(e).__name__}: {e}")
        if DAY in done:
            manifest.append(manifest_entry(city, done[DAY], done.get(NIGHT)))
            nights += NIGHT in done
        elif NIGHT in done:
            # A city is listed only with a DAY photo; drop the orphaned NIGHT files.
            shutil.rmtree(os.path.join(out, "ios", f"Skyline-{city.key}-night.imageset"), ignore_errors=True)
            try:
                os.remove(os.path.join(out, "android", f"skyline_{city.key}_night.jpg"))
            except OSError:
                pass
            tiles.pop(NIGHT, None)
            report.append(f"DROP  NIGHT {city.key:<18} {city.name}: no DAY photo, so the NIGHT photo is not used")
        sheet.append((city.name, tiles.get(DAY), tiles.get(NIGHT)))

    write_manifest(manifest, os.path.join(out, "skylines.json"))
    try:
        contact_sheet(sheet, os.path.join(out, "contact-sheet.jpg"))
    except Exception as e:
        report.append(f"contact sheet failed: {e}")
    summary = f"{len(manifest)} of {len(cities)} cities have a DAY photo; {nights} of those also have a NIGHT photo"
    with open(os.path.join(out, "report.txt"), "w", encoding="utf-8") as fh:
        fh.write(summary + "\n\n" + "\n".join(report) + "\n")
    print(summary)
    return 0 if manifest or not cities else 1


# ---------------------------------------------------------------- self-test (offline)

def selftest() -> int:
    """Offline checks: city parsing, thumbnail URLs, day/night thresholds on synthetic images,
    scoring, image output and manifest/contact-sheet writing."""
    import random

    from PIL import Image, ImageDraw

    failures: list[str] = []

    def check(cond: bool, what: str) -> None:
        print(("ok    " if cond else "FAIL  ") + what)
        if not cond:
            failures.append(what)

    # Parsing: fields 5 (DAY) and 6 (NIGHT) share one syntax.
    text = "\n".join([
        "# comment",
        "Los Angeles|Los Angeles|America/Los_Angeles|LA;LAX|-File:A night.jpg",
        "São Paulo|São Paulo|America/Sao_Paulo|GRU||File:SP night.jpg",
        "Paris|Paris|Europe/Paris|CDG|File:Paris day.jpg|-File:N1.jpg;-File:N2.jpg",
        "Oslo||Europe/Oslo",
    ])
    la, sp, paris, oslo = parse_cities(text)
    check(la.excluded == {"File:A night.jpg"} and la.file_override is None and la.night_override is None
          and not la.night_excluded, "field 5 excludes apply to DAY only")
    check(sp.key == "saopaulo" and sp.file_override is None and not sp.excluded
          and sp.night_override == "File:SP night.jpg", "empty field 5 + field 6 pin")
    check(paris.pin(DAY) == "File:Paris day.jpg" and paris.excludes(NIGHT) == {"File:N1.jpg", "File:N2.jpg"}
          and paris.pin(NIGHT) is None, "day pin + night excludes")
    check(oslo.title == "Oslo" and oslo.pin(DAY) is None and oslo.pin(NIGHT) is None, "three-field line")
    try:
        parse_cities("Oslo|Oslo|Europe/Oslo\nOSLO|Oslo|Europe/Oslo")
        check(False, "duplicate key rejected")
    except ValueError:
        check(True, "duplicate key rejected")
    here = os.path.dirname(os.path.abspath(__file__))
    real = os.path.join(here, "skyline-cities.txt")
    if os.path.exists(real):
        with open(real, encoding="utf-8") as fh:
            cs = parse_cities(fh.read())
        check(len(cs) > 50 and all(c.night_override is None or c.night_override.startswith("File:") for c in cs),
              f"skyline-cities.txt parses ({len(cs)} cities)")

    # Thumbnail URLs.
    info = {"width": 4000, "thumburl": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/F_x.jpg/1280px-F_x.jpg",
            "url": "https://upload.wikimedia.org/wikipedia/commons/a/ab/F_x.jpg"}
    check(thumb_url(info, 330) == "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/F_x.jpg/330px-F_x.jpg",
          "thumb URL from thumburl")
    info2 = {"width": 1000, "url": "https://upload.wikimedia.org/wikipedia/commons/a/ab/F_x.jpg"}
    check(thumb_url(info2, 330) == "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/F_x.jpg/330px-F_x.jpg",
          "thumb URL from original url")
    check(thumb_url({"width": 300, "url": info2["url"]}, 330) is None, "no thumb for a narrow file")

    # Classification on synthetic images.
    rnd = random.Random(7)

    def scene(sky, ground, lights=0, size=(PROBE_WIDTH, PROBE_WIDTH // 2), light=2):
        """Sky over the top half, ground below, `lights` lit windows of light x light px."""
        im = Image.new("RGB", size, ground)
        d = ImageDraw.Draw(im)
        d.rectangle((0, 0, size[0], size[1] // 2), fill=sky)
        for _ in range(lights):
            x, y = rnd.randrange(size[0] - light), rnd.randrange(size[1] // 2, size[1] - light)
            d.rectangle((x, y, x + light - 1, y + light - 1), fill=(255, 236, 190))
        return im

    day = measure(scene((150, 195, 240), (110, 110, 105)))
    night = measure(scene((8, 12, 30), (12, 12, 14), lights=200))
    dark_unlit = measure(scene((8, 12, 30), (12, 12, 14)))
    golden = measure(scene((200, 110, 60), (40, 30, 25), lights=200))  # after sunset: warm sky, lit, not dark
    grey = measure(scene((120, 120, 125), (70, 70, 70)))
    print(f"      day {day}; night {night}; unlit {dark_unlit}; golden {golden}; overcast {grey}")
    check(classify(day) == DAY, "bright blue sky is DAY")
    check(classify(night) == NIGHT, "dark sky with lit windows is NIGHT")
    check(classify(dark_unlit) is None, "dark without lights is neither")
    check(classify(golden) is None, "golden hour / dusk is neither")
    check(classify(measure(scene((8, 12, 30), (12, 12, 14), lights=900, size=(1320, 660), light=6))) == NIGHT,
          "NIGHT survives downscaling a larger image to the probe width")
    check(classify(grey) is None, "dull overcast is neither")
    check(classify(Luma(0.30, 0.25, 0.0)) == DAY and classify(Luma(0.149, 0.5, 0.0)) is None, "DAY thresholds")
    check(classify(Luma(0.10, 0.08, 0.005)) == NIGHT and classify(Luma(0.10, 0.081, 0.01)) is None
          and classify(Luma(0.05, 0.05, 0.0049)) is None, "NIGHT thresholds")
    check(abs(measure(Image.new("RGB", (330, 165), (255, 255, 255))).whole - 1.0) < 1e-6
          and measure(Image.new("RGB", (330, 165), (0, 0, 0))).whole == 0.0, "luminance range 0..1")

    # Skyline focus: where the sky ends, a quarter of the way down the visible band.
    def horizon(frac, size=(1000, 500)):
        """Flat sky above `frac` of the height, busy city (random windows) below."""
        im = Image.new("RGB", size, (150, 195, 240))
        d = ImageDraw.Draw(im)
        y0 = round(size[1] * frac)
        d.rectangle((0, y0, size[0], size[1]), fill=(70, 70, 75))
        for _ in range(3000):
            x, y = rnd.randrange(size[0] - 4), rnd.randrange(y0, size[1] - 4)
            d.rectangle((x, y, x + 3, y + 3), fill=(230, 225, 200))
        return im

    f40, f66 = skyline_focus(horizon(0.40)), skyline_focus(horizon(0.66))
    check(abs(f40 - (0.40 + 0.075)) <= 0.03 and abs(f66 - (0.66 + 0.075)) <= 0.03 and f66 > f40,
          f"focus follows the horizon (0.40 -> {f40}, 0.66 -> {f66})")
    check(skyline_focus(Image.new("RGB", (1000, 500), (150, 195, 240))) == round(0.4 + 0.075, 3),
          "featureless photo -> 0.4 H fallback")
    check(skyline_focus(horizon(0.0)) == 0.15 and skyline_focus(horizon(0.97)) == 0.85, "focus clamped to 0.15..0.85")
    check(_percentile([1, 2, 3, 4, 5], 30) == 2.2 and _percentile([7], 90) == 7, "percentile (linear)")
    repo = os.path.dirname(here)
    app_manifest = os.path.join(repo, "Resources", "Data", "skylines.json")
    assets = os.path.join(repo, "ios", "Meridian", "Assets.xcassets")
    if os.path.exists(app_manifest):
        with open(app_manifest, encoding="utf-8") as fh:
            app = {e.get("key"): e for e in json.load(fh)}
        sf = app.get("sanfrancisco") or {}
        jpg = os.path.join(assets, "Skyline-sanfrancisco-night.imageset", "skyline-sanfrancisco-night.jpg")
        want = (sf.get("night") or {}).get("focus")
        if want is not None and os.path.exists(jpg):
            with Image.open(jpg) as im:
                got = skyline_focus(im)
            check(got == want, f"San Francisco NIGHT focus matches the app manifest ({got} vs {want})")

    # Scoring nudges.
    big = {"width": 4000, "height": 2000, "mime": "image/jpeg"}
    check(score_candidate("File:X skyline at night.jpg", big, NIGHT) > score_candidate("File:X skyline.jpg", big, NIGHT),
          "night title bonus for NIGHT")
    check(score_candidate("File:X skyline.jpg", big, DAY) > score_candidate("File:X skyline sunset.jpg", big, DAY),
          "no-dusk title bonus for DAY")
    check(score_candidate("File:X skyline collage.jpg", big, DAY) is None, "SKIP_TITLE still applies")

    # choose() end to end with a fake Commons: pixels decide, titles only nudge.
    def jpeg(im) -> bytes:
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=90)
        return buf.getvalue()

    pics = {
        "File:Paris skyline at night.jpg": jpeg(scene((235, 150, 70), (60, 45, 35))),  # titled night, golden pixels
        "File:Paris skyline 2020.jpg": jpeg(scene((150, 195, 240), (110, 110, 105))),
        "File:Paris skyline lights.jpg": jpeg(scene((8, 12, 30), (12, 12, 14), lights=200)),
        "File:Paris skyline night excluded.jpg": jpeg(scene((8, 12, 30), (12, 12, 14), lights=200)),
    }
    lic = {"LicenseShortName": {"value": "CC BY-SA 4.0"}, "Artist": {"value": "<a>Someone</a>"}}

    def fake_info(title: str) -> dict:
        name = title[5:].replace(" ", "_")
        return {"width": 4000, "height": 2000, "mime": "image/jpeg", "extmetadata": lic,
                "url": f"https://upload.wikimedia.org/wikipedia/commons/a/ab/{name}",
                "thumburl": f"https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/{name}/1280px-{name}",
                "descriptionurl": "https://commons.wikimedia.org/wiki/" + title}

    class FakeFetcher:
        def __init__(self):
            self.urls: list[str] = []

        def json(self, url, params=None):
            q = (params or {}).get("gsrsearch", "")
            hits = [t for t in pics if ("night" in q) == ("night" in t or "lights" in t) or "skyline" in q]
            return {"query": {"pages": [{"title": t, "index": i, "imageinfo": [fake_info(t)]}
                                        for i, t in enumerate(hits)]}}

        def get(self, url, params=None):
            self.urls.append(url)
            name = urllib.parse.unquote(url.rsplit("px-", 1)[-1]).replace("_", " ")
            return pics["File:" + name]

    paris6 = parse_cities("Paris|Paris|Europe/Paris|||-File:Paris skyline night excluded.jpg")[0]
    ff = FakeFetcher()
    pr = Prober(ff)
    d_pick = choose(ff, pr, paris6, DAY)
    n_pick = choose(ff, pr, paris6, NIGHT)
    check(isinstance(d_pick, Pick) and d_pick.title == "File:Paris skyline 2020.jpg", f"DAY pick: {getattr(d_pick, 'title', d_pick)}")
    check(isinstance(n_pick, Pick) and n_pick.title == "File:Paris skyline lights.jpg",
          f"NIGHT pick by pixels, not title: {getattr(n_pick, 'title', n_pick)}")
    check(all("/330px-" in u for u in ff.urls) and len(ff.urls) == len(set(ff.urls)),
          f"probes use 330px thumbs, each file once ({len(ff.urls)} fetched)")
    check(n_pick.credit["author"] == "Someone" if isinstance(n_pick, Pick) else False, "credit carried")

    # Output and manifest.
    with tempfile.TemporaryDirectory() as tmp:
        for sub in ("ios", "android"):
            os.makedirs(os.path.join(tmp, sub))
        credit = {"author": "A", "license": "CC BY-SA 4.0", "licenseUrl": "", "source": "https://x"}
        dimg = crop_resize(scene((150, 195, 240), (110, 110, 105), size=(1280, 720)))
        nimg = crop_resize(scene((8, 12, 30), (12, 12, 14), lights=1500, size=(1280, 720), light=4))
        check(dimg.size == (OUT_W, OUT_H), "crop to 1000x500")
        dname, djpg, dsize = write_photo(dimg, tmp, paris.key, DAY)
        nname, njpg, nsize = write_photo(nimg, tmp, paris.key, NIGHT)
        check(dname == "skyline-paris.jpg" and nname == "skyline-paris-night.jpg", "file names")
        check(all(os.path.exists(os.path.join(tmp, p)) for p in (
            "ios/Skyline-paris.imageset/Contents.json", "ios/Skyline-paris-night.imageset/skyline-paris-night.jpg",
            "android/skyline_paris.jpg", "android/skyline_paris_night.jpg")), "iOS imagesets and Android drawables")
        check(dsize <= MAX_BYTES and nsize <= MAX_BYTES, f"JPEG sizes {dsize} / {nsize} bytes")
        with open(os.path.join(tmp, "ios/Skyline-paris-night.imageset/Contents.json"), encoding="utf-8") as fh:
            check(json.load(fh)["images"][0]["filename"] == nname, "night Contents.json names its file")
        dfocus, nfocus = skyline_focus(dimg), skyline_focus(nimg)
        entries = [manifest_entry(paris, {"file": dname, "credit": credit, "focus": dfocus},
                                  {"file": nname, "credit": credit, "focus": nfocus}),
                   manifest_entry(oslo, {"file": "skyline-oslo.jpg", "credit": credit}, None)]
        mpath = os.path.join(tmp, "skylines.json")
        write_manifest(entries, mpath)
        with open(mpath, encoding="utf-8") as fh:
            back = json.load(fh)
        check(isinstance(back, list) and back[0]["file"] == dname and back[0]["credit"] == credit
              and back[0]["night"] == {"file": nname, "credit": credit, "focus": nfocus} and back[1]["night"] is None
              and back[0]["focus"] == dfocus and back[1]["focus"] == FOCUS_DEFAULT
              and set(back[0]) == {"key", "names", "zone", "file", "credit", "night", "focus"}, "manifest v2 shape + focus")
        sheet = os.path.join(tmp, "contact-sheet.jpg")
        contact_sheet([("Paris", ("Paris DAY\n" + str(day), djpg), ("Paris NIGHT\n" + str(night), njpg)),
                       ("Oslo", None, None)], sheet)
        with Image.open(sheet) as im:
            check(im.size == (3 * (2 * 300 + 12), 150 + 38), f"contact sheet {im.size}")

    print(f"\nselftest: {'FAILED ' + str(len(failures)) if failures else 'all passed'}")
    return 1 if failures else 0


def main(argv: list[str] | None = None) -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cities", default=os.path.join(here, "skyline-cities.txt"))
    ap.add_argument("--out", default="out")
    ap.add_argument("--only", default="", help="comma-separated keys to fetch (default: all)")
    ap.add_argument("--limit", type=int, default=0, help="stop after this many cities (testing)")
    ap.add_argument("--selftest", action="store_true", help="run the offline self-test and exit")
    args = ap.parse_args(argv)
    return selftest() if args.selftest else run(args)


if __name__ == "__main__":
    sys.exit(main())
