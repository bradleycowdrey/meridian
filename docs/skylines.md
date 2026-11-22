# City photos (plates)

Every city row, card and widget in Meridian sits on a photo of its city. These are AI-generated
**plates**: one day and one night picture per city, framed the same way, so the apps can place
both with one set of numbers.

## What a plate looks like

- 1536 x 512 JPEG (3:1).
- The city's signature landmark stands at about **38% of the width**. The apps move that point
  into the gap between the name/time text and the hour tiles.
- The landmark's **tip is at about 40% of the height**, and its base stands in the skyline band.
  The apps keep that tip in view at every size.
- The **far-left quarter is calm** (low, hazy, no landmark), because the text sits there.
- The **right half is even cityscape**, because the hour tiles cover it.
- The **skyline band sits around 70-75% of the height**, with calm sky above it.
- The day and night plates of a city have **identical framing**. Only the light changes.

## 1. Generate

Plates are made with Lovable's image tool, one city at a time, from
`scripts/plate-cities.tsv`. Each row gives the city, its landmark (the thing at 38%) and the view
and its character. The prompt keeps the composition rules above word for word, then adds the row's
landmark and view. Make the day plate first, then the night plate *from the day plate* (same
framing, lit at night), so the two line up.

Save them as `<key>-day.jpg` and `<key>-night.jpg` in one folder. `<key>` is the city's key in
`Resources/Data/skylines.json` (lowercase letters only, for example `newyork`, `hochiminhcity`).

## 2. Measure

`scripts/plate-focus.py PLATE.jpg ...` prints, for each plate:

- `focusX`: where the landmark stands across the image, from 0 (left) to 1 (right). Plates come out at about 0.38.
- `focus`: the vertical centre of the skyline band, from 0 (top) to 1 (bottom).
- `landmarkTop`: the height of the landmark's tip, from 0 (top) to 1 (bottom). Plates come out at about 0.40.
  The manifest stores it as `top`.
- `check`: true when the reading is far from 0.38 (it probably caught an edge or a cloud). focusX is then kept at 0.38.
  The importer also sets `top` to 0.40, because the tip reading came from the same wrong spot.

Measure the **night** plate: lit towers stand out from a dark sky much more reliably than from a
bright one. The importer does this for you.

## 3. Import

```sh
scripts/import-plates.py ~/plates --dry-run   # measure and print the plan, write nothing
scripts/import-plates.py ~/plates             # write the photos and the manifest
```

For each city with plates, the script:

1. measures the night plate and uses that reading (`focusX`, `focus` and `top`, rounded to 3
   decimals) for the day plate too. A `check` reading keeps focusX 0.38 and top 0.40 and prints a
   warning, so look at that plate. A city with only a day plate is measured on the day plate.
2. writes the photos:
   - iOS: `ios/Meridian/Assets.xcassets/Skyline-<key>.imageset/skyline-<key>.jpg` and
     `Skyline-<key>-night.imageset/skyline-<key>-night.jpg`, each with its `Contents.json`.
   - Android: `android/app/src/main/res/drawable-nodpi/skyline_<key>.jpg` and `skyline_<key>_night.jpg`.
   - Mac: nothing extra. `scripts/build-app.sh` copies the Android JPEGs into the app, and shrinks
     copies to 600 px wide for the widget. The aspect ratio stays 3:1.
3. rewrites `Resources/Data/skylines.json` as version 3:

```json
{"version": 3, "cities": [
 {"key": "paris", "names": ["Paris", "CDG"], "zone": "Europe/Paris",
  "file": "skyline-paris.jpg",
  "credit": {"author": "Generated with AI for Meridian", "license": "AI-generated image", "source": ""},
  "focus": 0.762, "focusX": 0.363, "top": 0.375,
  "night": {"file": "skyline-paris-night.jpg", "credit": {...same...}, "focus": 0.762, "focusX": 0.363, "top": 0.375}}
]}
```

Cities with no plates in the folder keep their current photos and entry, untouched. The script
adds neither `focusX` nor `top` to them: the apps read a missing `focusX` as 0.5 (the photo's
centre), and a photo without `top` gets no tip rule (it is placed exactly as before). Leaving
`focusX` out matters: its presence is how the apps tell an AI plate from an old photo (see the
square-widget target below). A city with only a day plate is imported with `"night": null`, and its old night photo is
removed. The apps then draw their own night sky for it. A key the manifest doesn't have is skipped,
because the script has no names or time zone for it.

`--root DIR` imports into another copy of the repository, which is handy for a trial run.

## 4. Check

```sh
scripts/plate-fit.py sheet.png ~/plates/paris-night.jpg:0.363:0.762:0.375
```

This draws a contact sheet: the plate in every row shape the apps use (from the square small widget
to the very wide web row), with the text block and hour tiles drawn on top. Each argument is
`PLATE:focusX:focus:top`, using the importer's printed numbers. Look for a calm patch behind
the text, the landmark in the gap, and its tip in view. `plate-fit.py`'s `geometry()` is the
reference for the placement rule below; the apps follow it.

## How the apps place a plate

All platforms use the same rule:

1. Cover-fit the plate into the frame.
2. Slide it sideways so the image point at `focusX` lands on the target. In rows and wide widgets
   the target is the gap between the text and the tiles. In a square or small single-city widget
   (text bottom-left, no tiles) it is **78% of the frame's width**, the clear right-hand column,
   for a photo with a manifest `focusX` (an AI plate); a photo without `focusX` targets the
   frame's centre. Clamp it so the photo always covers the frame. If clamping keeps the landmark
   from reaching the target, zoom in by up to 15% more.
3. Vertically, put the skyline band (`focus`) at the row's anchor:
   `y = anchorY * frameH - focus * scaledH`.
4. The tip rule, when the photo has `top`: `y = max(y, 0.08 * frameH - top * scaledH)`, so the
   landmark's tip sits at least 8% of the frame's height below its top edge (pushing the photo
   down, never up). Then clamp `y` to `[frameH - scaledH, 0]` as always, so the photo still covers
   the frame. In a very wide, short row the clamp can win and crop the tip; that is the photo
   covering the frame, not a bug.

A v2 entry (no `focusX`) is read as 0.5. An entry without `top` skips step 4.
