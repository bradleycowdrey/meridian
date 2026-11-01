#!/usr/bin/env python3
"""Builds Meridian's offline data (Resources/Data), shared by the Mac, iPhone and Android apps.

  cities.tsv    name, region, country code, time zone, latitude, longitude, population
                (GeoNames cities of 15,000+ people, via the geonamescache package)
  holidays.tsv  country code, date, name: national public holidays for five years
                (the python-holidays package)

    pip install geonamescache holidays && python3 scripts/gen-data.py
"""
import datetime, os, geonamescache, holidays

out = os.path.join(os.path.dirname(__file__), "..", "Resources", "Data")
gc = geonamescache.GeonamesCache()
countries = {c: v["name"] for c, v in gc.get_countries().items()}
states = {v["code"]: v["name"] for v in gc.get_us_states().values()}
rows = []
for c in gc.get_cities().values():
    if c["population"] < 15000 or not c["timezone"]:
        continue
    cc = c["countrycode"]
    region = countries.get(cc, cc)
    if cc == "US" and c["admin1code"] in states:
        region = f'{states[c["admin1code"]]}, United States'
    name = c["name"].replace("\t", " ").replace("|", " ")
    rows.append((name, region, cc, c["timezone"], f'{c["latitude"]:.2f}', f'{c["longitude"]:.2f}', str(c["population"])))
rows.sort(key=lambda r: -int(r[6]))
with open(os.path.join(out, "cities.tsv"), "w") as f:
    for r in rows:
        f.write("\t".join(r) + "\n")

start = datetime.date.today().year
years = range(start, start + 5)
lines = []
for cc in sorted(holidays.list_supported_countries()):
    try:
        cls = holidays.country_holidays(cc, years=years)
        # English names where the country has them.
        langs = getattr(cls, "supported_languages", ()) or ()
        lang = next((l for l in ("en_US", "en_GB", "en") if l in langs), None)
        days = holidays.country_holidays(cc, years=years, language=lang) if lang else cls
    except Exception:
        continue
    for d, name in sorted(days.items()):
        # "Christmas Day; Boxing Day (observed)" style doubles keep the first.
        lines.append(f"{cc}\t{d:%Y%m%d}\t{name.split(';')[0].strip()}")
with open(os.path.join(out, "holidays.tsv"), "w") as f:
    f.write("\n".join(lines) + "\n")
print(len(rows), "cities;", len(lines), "holidays", f"{years.start}-{years.stop - 1}")
