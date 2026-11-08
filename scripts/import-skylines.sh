#!/usr/bin/env bash
# Copies the skyline photos published by .github/workflows/skylines.yml into the apps.
#
#   git fetch origin ci-skylines && git worktree add /tmp/ci-skylines origin/ci-skylines
#   scripts/import-skylines.sh /tmp/ci-skylines
#
# iOS:     ios/Meridian/Assets.xcassets/Skyline-<key>.imageset
# Android: android/app/src/main/res/drawable-nodpi/skyline_<key>.jpg
# Both:    Resources/Data/skylines.json (the manifest the apps match cities against)
#
# Only cities in the manifest are copied; an existing Skyline-* photo is replaced only when the
# manifest has that city, so the built-in London/New York/San Francisco/Tokyo photos stay
# otherwise (and keep their entry in the imported manifest, credited from skyline-credits.json).
# PRUNE=1 also removes photos of cities that are no longer in the manifest (never those four).
set -euo pipefail

src="${1:?usage: import-skylines.sh <checked-out ci-skylines tree>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$src/skylines.json"
assets="$root/ios/Meridian/Assets.xcassets"
drawables="$root/android/app/src/main/res/drawable-nodpi"
keep_always="london newyork sanfrancisco tokyo"

[ -f "$manifest" ] || { echo "no skylines.json in $src" >&2; exit 1; }
[ -d "$assets" ] || { echo "missing $assets" >&2; exit 1; }
mkdir -p "$drawables" "$root/Resources/Data"

keys="$(python3 -c 'import json,re,sys
for e in json.load(open(sys.argv[1], encoding="utf-8")):
    k = e.get("key", "")
    if re.fullmatch(r"[a-z]+", k): print(k)' "$manifest")"
[ -n "$keys" ] || { echo "the manifest lists no photos; nothing imported" >&2; exit 1; }

copied=0; missing=0
for key in $keys; do
  set_src="$src/ios/Skyline-$key.imageset"
  jpg_src="$src/android/skyline_$key.jpg"
  if [ ! -f "$set_src/Contents.json" ] || [ ! -f "$jpg_src" ]; then
    echo "skip $key: photo missing in $src" >&2; missing=$((missing + 1)); continue
  fi
  rm -rf "$assets/Skyline-$key.imageset"
  cp -R "$set_src" "$assets/Skyline-$key.imageset"
  rm -f "$drawables/skyline_$key."*
  cp "$jpg_src" "$drawables/skyline_$key.jpg"
  copied=$((copied + 1))
done

# PRUNE=1: remove photos of cities no longer in the manifest (never the four original ones).
if [ "${PRUNE:-0}" = 1 ]; then
for dir in "$assets"/Skyline-*.imageset; do
  [ -d "$dir" ] || continue
  key="$(basename "$dir" .imageset)"; key="${key#Skyline-}"
  case " $keep_always " in *" $key "*) continue ;; esac
  grep -qx "$key" <<<"$keys" || { rm -rf "$dir"; echo "removed iOS Skyline-$key"; }
done
for f in "$drawables"/skyline_*; do
  [ -f "$f" ] || continue
  key="$(basename "$f")"; key="${key#skyline_}"; key="${key%.*}"
  case " $keep_always " in *" $key "*) continue ;; esac
  grep -qx "$key" <<<"$keys" || { rm -f "$f"; echo "removed Android skyline_$key"; }
done
fi

# The manifest lists only photos that are in the app; an original photo the run didn't cover
# keeps an entry (so the apps, which use the manifest once it exists, still show it).
python3 - "$manifest" "$root/Resources/Data/skylines.json" "$assets" "$root/Resources/Data/skyline-credits.json" <<'PY'
import json, os, sys
src, dst, assets, old_credits = sys.argv[1:5]
entries = [e for e in json.load(open(src, encoding="utf-8"))
           if os.path.isdir(os.path.join(assets, f"Skyline-{e.get('key', '')}.imageset"))]
originals = {
    "london": ("London", ["LHR", "LGW"], "Europe/London"),
    "newyork": ("New York", ["New York City", "NYC", "JFK", "LGA", "EWR", "Manhattan"], "America/New_York"),
    "sanfrancisco": ("San Francisco", ["SF", "SFO", "Bay Area"], "America/Los_Angeles"),
    "tokyo": ("Tokyo", ["HND", "NRT"], "Asia/Tokyo"),
}
credits = {}
if os.path.exists(old_credits):
    credits = {c.get("key"): c for c in json.load(open(old_credits, encoding="utf-8"))}
have = {e["key"] for e in entries}
for key, (name, aliases, zone) in originals.items():
    if key in have or not os.path.isdir(os.path.join(assets, f"Skyline-{key}.imageset")):
        continue
    old = credits.get(key, {})
    entries.append({"key": key, "names": [name, *aliases], "zone": zone, "file": f"skyline-{key}.jpg",
                    "credit": {"author": "", "license": "", "licenseUrl": "", "source": old.get("commons", "")}})
    print(f"kept original {key} (not in this run)")
with open(dst, "w", encoding="utf-8") as fh:
    json.dump(entries, fh, indent=1, ensure_ascii=False)
    fh.write("\n")
print(f"wrote {dst} ({len(entries)} cities)")
PY

echo "imported $copied photos ($missing missing)"
