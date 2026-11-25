#!/usr/bin/env python3
"""Writes Resources/Data/plates-remote.json (version 2), which tells the apps which photo every
city shows. scripts/metros.py decides the metros; this file turns its output into the index.

    scripts/photo-index.py [--plates PLATES_DIR] [--stage STAGE_DIR] [--base URL]

Which photo a city shows, in this order (all apps do the same):

  1. A built-in photo matched by the city's name (Resources/Data/skylines.json), as before.
  2. "towns": the city is a town of the city database inside a metro of 1M+ people (MSA level).
     towns[key] lists [name, lat, lon, ...] for each member town of that metro; the city matches
     a member with the same name (case and accents ignored) within 25 km. The key is a built-in
     photo (Littleton -> denver) or a hosted plate in "plates".
  3. "metros": a place that is not in the database (or has no exact match) uses the nearest metro
     centre in the same country (cc) whose radius r (km) covers it.
  4. Otherwise a default scene, picked by "scenes": the first rule whose zones list holds the city's
     time zone, or whose zone prefix matches, or (maxAbsLat) whose |latitude| is at most that;
     the last rule has no condition. A scene is the built-in photo "scene<name>".

A key in towns/metros that is neither built in nor in "plates" (its photo isn't published yet) is
skipped, so the city falls through to the next step.

"plates": hosted AI plates, downloaded once from base + key + "-day.jpg" / "-night.jpg" and placed
by focus, focusX and top like a built-in plate. With --plates, each <key>-day.jpg/<key>-night.jpg
pair in PLATES_DIR whose key is a generated metro is measured (scripts/plate-focus.py on the night
plate, scripts/plate-overrides.json applies) and, with --stage, written to STAGE_DIR for the orphan
`plates` branch (1536x512 JPEG). Without --plates the "plates" already in the index are kept.
"""
import argparse, csv, importlib.util, json, math, os, subprocess, sys, tempfile, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
INDEX = os.path.join(ROOT, 'Resources/Data/plates-remote.json')
BASE = 'https://raw.githubusercontent.com/bradleycowdrey/meridian/plates/'

SCENES = [
    {'scene': 'mountains', 'zones': [
        'America/Denver', 'America/Boise', 'America/La_Paz', 'America/Bogota', 'Asia/Kathmandu', 'Asia/Thimphu',
        'Asia/Kabul', 'Asia/Bishkek', 'Asia/Dushanbe', 'Asia/Yerevan', 'Asia/Tbilisi', 'Europe/Zurich',
        'Europe/Andorra', 'Europe/Vaduz', 'Africa/Addis_Ababa', 'Africa/Maseru', 'America/Guayaquil']},
    {'scene': 'desert', 'zones': [
        'Asia/Riyadh', 'Asia/Dubai', 'Asia/Qatar', 'Asia/Bahrain', 'Asia/Kuwait', 'Asia/Muscat', 'Asia/Aden',
        'Asia/Baghdad', 'Asia/Tehran', 'Asia/Amman', 'Asia/Ashgabat', 'Asia/Tashkent', 'Asia/Samarkand',
        'Africa/Cairo', 'Africa/Tripoli', 'Africa/Khartoum', 'Africa/Nouakchott', 'Africa/Niamey',
        'Africa/Ndjamena', 'Africa/Bamako', 'Africa/Algiers', 'Africa/Tunis', 'Africa/Casablanca',
        'Africa/El_Aaiun', 'America/Phoenix', 'America/Hermosillo']},
    {'scene': 'oldtown', 'prefix': 'Europe/'},
    {'scene': 'coast', 'maxAbsLat': 23.5},
    {'scene': 'river'},
]


def norm(s):
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode().lower()
    return ''.join(ch for ch in s if ch.isalnum())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--plates')
    ap.add_argument('--stage')
    ap.add_argument('--base', default=BASE)
    a = ap.parse_args()

    out = tempfile.mkdtemp()
    subprocess.run([sys.executable, os.path.join(HERE, 'metros.py'), out], check=True)
    metros = json.load(open(os.path.join(out, 'metro.json'), encoding='utf-8'))
    rows = list(csv.reader(open(os.path.join(out, 'metro-assign.tsv'), encoding='utf-8'), delimiter='\t'))[1:]
    man = json.load(open(os.path.join(ROOT, 'Resources/Data/skylines.json'), encoding='utf-8'))['cities']
    builtin = {c['key'] for c in man if not c.get('scene')}
    generated = {m['key']: m for m in metros if m['key'] not in builtin}

    # Metro centres: generated metros from metro.json; built-ins from their database row (the most
    # populous town carrying that key, the same row metros.py claims from) and the claim radius.
    centres = {}
    for m in metros:
        centres[m['key']] = (m['cc'], m['lat'], m['lon'], m['radius'])
    best = {}
    for r in rows:
        k = r[7]
        if k in builtin and (k not in best or int(r[6] or 0) > int(best[k][6] or 0)):
            best[k] = r
    for k, r in best.items():
        if k not in centres:
            centres[k] = (r[2], float(r[4]), float(r[5]), 0)
    # a built-in's radius: the farthest member town (so the fallback never reaches past the metro)
    def km(a1, o1, a2, o2):
        a1, o1, a2, o2 = map(math.radians, (a1, o1, a2, o2))
        h = math.sin((a2 - a1) / 2) ** 2 + math.cos(a1) * math.cos(a2) * math.sin((o2 - o1) / 2) ** 2
        return 6371 * 2 * math.asin(math.sqrt(h))
    reach = {}
    for r in rows:
        k = r[7]
        if k in centres:
            cc, la, lo, _ = centres[k]
            reach[k] = max(reach.get(k, 0), km(la, lo, float(r[4]), float(r[5])))
    metros_out = []
    for k, (cc, la, lo, R) in sorted(centres.items()):
        r = R if R else round(min(reach.get(k, 0) + 2, 80))
        metros_out.append({'key': k, 'cc': cc, 'lat': round(la, 2), 'lon': round(lo, 2), 'r': int(r)})

    towns = {}
    for r in rows:
        k = r[7]
        if k == 'default':
            continue
        towns.setdefault(k, []).extend([r[0], round(float(r[4]), 2), round(float(r[5]), 2)])

    # Hosted plates
    try:
        old = json.load(open(INDEX, encoding='utf-8'))
    except (OSError, ValueError):
        old = {}
    plates = {p['key']: p for p in old.get('plates', [])} if old.get('version') == 2 else {}
    if a.plates:
        spec = importlib.util.spec_from_file_location('plate_focus', os.path.join(HERE, 'plate-focus.py'))
        pf = importlib.util.module_from_spec(spec); spec.loader.exec_module(pf)
        from PIL import Image
        for k, m in generated.items():
            d, n = (os.path.join(a.plates, f'{k}-{t}.jpg') for t in ('day', 'night'))
            if not (os.path.exists(d) and os.path.exists(n)):
                continue
            meas = pf.measure(n)
            fx, fy, top = meas['focusX'], meas['focus'], meas['landmarkTop']
            if meas.get('check'):
                print(f'warning: {k}: landmark not found; focusX 0.38, top 0.40 kept. Look at this plate.')
                fx, top = 0.38, 0.40
            place = {'focus': round(fy, 3), 'focusX': round(fx, 3), 'top': round(top, 3)}
            plates[k] = dict({'key': k, 'name': m['name'], 'cc': m['cc'], 'zone': m['zone']}, **place, night=dict(place))
            if a.stage:
                os.makedirs(a.stage, exist_ok=True)
                for t, src in (('day', d), ('night', n)):
                    Image.open(src).convert('RGB').resize((1536, 512), Image.LANCZOS).save(
                        os.path.join(a.stage, f'{k}-{t}.jpg'), 'JPEG', quality=85, optimize=True)
    plates = {k: v for k, v in plates.items() if k in generated}

    index = {
        'version': 2,
        'base': a.base,
        'plates': [plates[k] for k in sorted(plates)],
        'metros': metros_out,
        'towns': towns,
        'scenes': SCENES,
    }
    with open(INDEX, 'w', encoding='utf-8') as f:
        json.dump(index, f, ensure_ascii=False, separators=(',', ':'))
        f.write('\n')
    n_towns = sum(len(v) // 3 for v in towns.values())
    print(f'{INDEX}: {len(plates)} hosted plates of {len(generated)} metros, {len(metros_out)} metro centres, '
          f'{n_towns} towns, {os.path.getsize(INDEX) // 1024} KB')


if __name__ == '__main__':
    main()
