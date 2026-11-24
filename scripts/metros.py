#!/usr/bin/env python3
"""Metro areas (MSA level) for Meridian's city photos.

Every metro area of 1,000,000 people or more gets a photo; every town inside one uses that
metro's photo (Littleton CO -> denver); everything else gets a default scene.

The city database (Resources/Data/cities.tsv) has no metro data and leaves out most towns under
~15,000 people, so metros are built from it:

  1. Data corrections from scripts/metro-rules.py: CC_BY_ZONE, COORD, POP, ZERO (rows that
     duplicate a parent row: they stay members but count 0).
  2. Pins: FIX and GROUP put a town in a named metro (or 'default') whatever the geometry.
  3. PRECORE seeds claim first, then the built-in photos (skylines.json) claim every town in the
     same country within RADIUS.get(key, radius(pop)), then SEED cores, then a greedy pass where
     each unclaimed town, largest first, becomes a core and claims its neighbours.
  4. MERGE moves a whole cluster to another key; ALIAS renames a cluster to its real city.
  5. A cluster gets a photo if it is built in, a forced seed, or totals 1,000,000+, and is not
     in DENY.

Usage: python3 scripts/metros.py [out-dir]   (run from the repository root)
Writes <out-dir>/metro.json (metros to generate) and <out-dir>/metro-assign.tsv (every town).
"""
import csv, json, math, os, re, sys, unicodedata
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'build', 'metros')
os.makedirs(OUT, exist_ok=True)

raw = list(csv.reader(open(os.path.join(ROOT, 'Resources/Data/cities.tsv'), encoding='utf-8'), delimiter='\t'))
rows = [[r[0], r[1], r[2], r[3], float(r[4]), float(r[5]), int(r[6] or 0)] for r in raw]
orig_cc = [r[2] for r in rows]


def slug(s):
    return re.sub(r'[^a-z0-9]', '', unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode().lower())


def dist(a, b):
    la1, lo1 = map(math.radians, a)
    la2, lo2 = map(math.radians, b)
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(h))


def radius(pop):
    return 60 if pop >= 5_000_000 else 50 if pop >= 2_000_000 else 40


BAD = []


def find(sel):
    name, cc = sel[0], sel[1]
    q = sel[2] if len(sel) > 2 else None
    hit = [i for i, r in enumerate(rows) if r[0] == name and r[2] == cc and
           (q is None or (isinstance(q, str) and r[1].startswith(q)) or (isinstance(q, float) and abs(r[4] - q) < 0.06))]
    if len(hit) != 1:
        BAD.append((sel, len(hit)))
    return hit[:1]


rules = {}
exec(open(os.path.join(ROOT, 'scripts', 'metro-rules.py'), encoding='utf-8').read(), rules)
CC_BY_ZONE, COORD, POP, ZERO = rules['CC_BY_ZONE'], rules['COORD'], rules['POP'], rules['ZERO']
FIX, GROUP, PRECORE, SEED = rules['FIX'], rules['GROUP'], rules['PRECORE'], rules['SEED']
RADIUS, MERGE, DENY, ALIAS = rules['RADIUS'], rules['MERGE'], set(rules['DENY']), rules['ALIAS']

# 1. Data corrections
for z, cc in CC_BY_ZONE.items():
    for r in rows:
        if r[3] == z:
            r[2] = cc
for sel, (la, lo) in COORD.items():
    for i in find(sel):
        rows[i][4], rows[i][5] = la, lo
for sel, p in POP.items():
    for i in find(sel):
        rows[i][6] = p
for sel in ZERO:
    for i in find(sel):
        rows[i][6] = 0
order = sorted(range(len(rows)), key=lambda i: -rows[i][6])

# 2. Pins
pin = {}
for sel, k in FIX.items():
    for i in find(sel):
        pin[i] = ALIAS.get(k, k)
for k, sels in GROUP.items():
    for sel in sels:
        for i in find(sel):
            pin[i] = ALIAS.get(k, k)

# Built-in photos, matched to their database row (same zone first, then the most populous).
man = json.load(open(os.path.join(ROOT, 'Resources/Data/skylines.json'), encoding='utf-8'))['cities']
builtin = []
for c in man:
    names = {n.lower() for n in c['names']}
    cand = [i for i in range(len(rows)) if rows[i][0].lower() in names]
    same_zone = [i for i in cand if rows[i][3] == c['zone']]
    cand = same_zone or cand
    if cand:
        i = max(cand, key=lambda i: rows[i][6])
        builtin.append((c['key'], i))
builtin_keys = {k for k, _ in builtin}

# 3. Claiming
core = [None] * len(rows)          # a key (str) or a core row (int)
centers = {}                       # key or core row -> (lat, lon, cc, radius, row)
forced = set()
for i, k in pin.items():
    core[i] = k


def claim(tag, la, lo, cc, R):
    for j in order:
        if core[j] is None and rows[j][2] == cc and dist((la, lo), (rows[j][4], rows[j][5])) <= R:
            core[j] = tag


def seed(lst):
    for s in lst:
        h = find(s['sel'])
        if not h:
            continue
        i = h[0]
        r = rows[i]
        key = ALIAS.get(s.get('key') or slug(r[0]) + '-' + r[2].lower(), s.get('key') or slug(r[0]) + '-' + r[2].lower())
        centers[key] = (r[4], r[5], r[2], s['r'], i)
        if s.get('force', True):
            forced.add(key)
        if core[i] is None:
            core[i] = key
        claim(key, r[4], r[5], r[2], s['r'])


seed(PRECORE)
for key, i in sorted(builtin, key=lambda b: -rows[b[1]][6]):
    r = rows[i]
    R = RADIUS.get(key, radius(r[6]))
    centers[key] = (r[4], r[5], r[2], R, i)
    claim(key, r[4], r[5], r[2], R)
seed(SEED)
for i in order:
    if core[i] is not None:
        continue
    r = rows[i]
    R = RADIUS.get(slug(r[0]) + '-' + r[2].lower(), radius(r[6]))
    core[i] = i
    centers[i] = (r[4], r[5], r[2], R, i)
    claim(i, r[4], r[5], r[2], R)

# Keys for greedy cores: slug-cc, numbered when two cores share a name; then ALIAS.
keyname = {}
groups = defaultdict(list)
for c in centers:
    if isinstance(c, int):
        groups[slug(rows[c][0]) + '-' + rows[c][2].lower()].append(c)
taken = {c for c in centers if not isinstance(c, int)}   # seed, PRECORE and built-in keys
for k, v in groups.items():
    n = 0
    for c in sorted(v, key=lambda c: -rows[c][6]):
        kk = k + (str(n + 1) if n else '')
        while kk in taken:                                   # never reuse a seed/built-in key
            n += 1
            kk = k + str(n + 1)
        n += 1
        taken.add(kk)
        keyname[c] = ALIAS.get(kk, kk)


def key_of(c):
    return keyname[c] if isinstance(c, int) else c


asg = [key_of(c) for c in core]

# 4. MERGE (pinned towns keep their pin)
for sel, k in MERGE.items():
    for i in find(sel):
        src = asg[i]
        for j in range(len(rows)):
            if asg[j] == src and j not in pin:
                asg[j] = ALIAS.get(k, k)

# Re-home a center whose key was renamed or merged away.
cent = {}
for c, v in centers.items():
    cent.setdefault(key_of(c), v)

# 5. Totals and the photo test
total = defaultdict(int)
for j, k in enumerate(asg):
    total[k] += rows[j][6]


def has_photo(k):
    if k == 'default' or k in DENY:
        return False
    return k in builtin_keys or k in forced or total[k] >= 1_000_000


result = [k if has_photo(k) else 'default' for k in asg]
gen = sorted({k for k in result if k != 'default' and k not in builtin_keys}, key=lambda k: -total[k])

errors = []
if BAD:
    errors.append('selectors not matching exactly one row: %r' % BAD)
targets = set(FIX.values()) | set(GROUP) | set(MERGE.values())
missing = sorted(ALIAS.get(k, k) for k in targets if k != 'default' and not has_photo(ALIAS.get(k, k)))
if missing:
    errors.append('pinned targets without a photo: %r' % missing)
if errors:
    sys.exit('\n'.join(errors))

# The photo's centre town: the cluster's most populous member (keeps a merged or pinned cluster on its city).
best = {}
for j, k in enumerate(result):
    if k != 'default' and (k not in best or rows[j][6] > rows[best[k]][6]):
        best[k] = j
metros = []
for k in gen:
    la, lo, cc, R, i = cent.get(k) or (0, 0, '', 40, best[k])   # a GROUP-only metro centres on its largest town
    if result[i] != k:
        i = best[k]
    r = rows[i]
    far = max(dist((r[4], r[5]), (rows[j][4], rows[j][5])) for j in range(len(rows)) if result[j] == k)
    metros.append(dict(key=k, name=r[0], region=r[1], cc=r[2], zone=r[3], lat=r[4], lon=r[5], pop=r[6],
                       metro=total[k], radius=R, reach=round(far, 1), forced=k in forced))
json.dump(metros, open(os.path.join(OUT, 'metro.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=0)

with open(os.path.join(OUT, 'metro-assign.tsv'), 'w', encoding='utf-8') as f:
    f.write('name\tregion\tcc\tzone\tlat\tlon\tpop\tphoto\n')
    for j, r in enumerate(raw):
        f.write('\t'.join(r[:7] + [result[j]]) + '\n')

nb = sum(1 for k in result if k in builtin_keys)
ng = sum(1 for k in result if k in set(gen))
print('metros to generate: %d  towns -> built-in: %d  towns -> new metro: %d  towns -> default: %d'
      % (len(gen), nb, ng, len(rows) - nb - ng))
