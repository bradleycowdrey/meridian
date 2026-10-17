<p align="center"><img src="docs/icon.png" width="128" alt="Meridian icon"></p>

<h1 align="center">Meridian</h1>
<p align="center"><b>Every time zone at a glance.</b><br>
A tiny, free, open-source world clock for your Mac's menu bar.<br>
Made by <a href="https://bradcowdrey.com">Bradley Cowdrey · bradcowdrey.com</a></p>

<p align="center">
  <a href="https://github.com/bradleycowdrey/meridian/releases/latest/download/Meridian.dmg"><b>Download for Mac</b></a> ·
  <a href="https://bradcowdrey.com/app">Try it in your browser</a> ·
  <a href="https://github.com/bradleycowdrey/meridian/issues">Report an issue</a>
</p>

---

Meridian lines up your cities as day-and-night ribbons on one grid. Every column is the same
instant everywhere, so the line through the middle is *now*.

## Features

- **Day/night ribbons**: night navy, dawn peach, daylight sand and dusk orange, one row per city.
- **Time travel**: drag the strip, scroll, press ← →, or click any hour. **Now** snaps back.
- **Meeting overlap**: a cream mark shows hours when every city is inside working hours.
- **Copy the moment**: one click copies the selected time for every city, ready to paste into a chat or invite.
- **Easy to manage**: **Add** opens search right in the panel; **Edit** shows a delete button and a drag handle on every city.
- **Fast search**: city names, airport codes (`SFO`, `LHR`), abbreviations (`PST`, `CET`) or offsets (`UTC+5:30`).
- **The details**: day-change markers, half-hour and 45-minute zones, a `+1 day` badge, 12/24-hour time, custom city names, drag to reorder.
- **Desktop widget**: small, medium and large widgets for the desktop or Notification Center, with your cities in the same order (large adds the day/night tiles). Right-click the desktop → **Edit Widgets** → search **Meridian**.
- **Menu bar first**: show an icon, or a city and its time (`LON 14:32`). Open it as a desktop window that can float above everything.
- **Five sizes** (Extra Small to Extra Large, ⌘+ / ⌘−) and a choice of **SF Pro** or **Inter**, the typeface of bradcowdrey.com.
- **Automatic updates**: Meridian checks GitHub Releases once a day, verifies the download's SHA-256, then installs and restarts in one click. Turn it off or check manually in **Settings → General → Updates** or the ⋯ menu.
- Open at login. No account, no tracking, no network access. About 1 MB.

Native SwiftUI, universal binary (Apple silicon + Intel), macOS 14 Sonoma or later.

## Install (sideload)

Meridian is distributed directly, not through the Mac App Store.

1. Download [Meridian.dmg](https://github.com/bradleycowdrey/meridian/releases/latest/download/Meridian.dmg) (all versions are on [Releases](https://github.com/bradleycowdrey/meridian/releases))
   or [bradcowdrey.com/app](https://bradcowdrey.com/app), where you can also try it in your browser.
2. Open the DMG and drag **Meridian** to **Applications**.
3. First launch: if macOS says it can't verify the app, **right-click Meridian → Open → Open**, or run
   `xattr -dr com.apple.quarantine /Applications/Meridian.app`
4. Click the globe in your menu bar, then **Add** your cities.

## Build from source

Requires Xcode 15.3+ (Swift 5.10) on macOS 14+.

```sh
git clone https://github.com/bradleycowdrey/meridian.git
cd meridian
swift run                         # run in development
scripts/build-app.sh 0.1.0        # dist/Meridian.app (universal)
scripts/make-dmg.sh 0.1.0         # dist/Meridian-0.1.0.dmg
```

## Releasing

Bump the number in `VERSION` and push to `main`. GitHub Actions builds a universal app, packages a DMG and publishes it as release `v<VERSION>`, plus a stable `Meridian.dmg` that the download links always point to.

Optional secrets for Developer ID signing and notarization (removes the Gatekeeper prompt):
`DEVELOPER_ID_P12` (base64 .p12), `DEVELOPER_ID_P12_PASSWORD`, `CODESIGN_IDENTITY`,
`NOTARY_APPLE_ID`, `NOTARY_PASSWORD` (app-specific password), `NOTARY_TEAM_ID`.
Without them, builds are ad-hoc signed.

## Layout

```
Sources/Meridian/
  MeridianApp.swift       Menu bar, desktop window, settings
  Brand.swift             Name, author and links: rebrand here
  Model/                  Cities, search directory, settings and time maths
  Views/StripView.swift   The ribbons
  Views/ClockPanel.swift  Header, time-travel bar, add-city search
docs/                     Download page with a live web demo
```

## License

MIT © 2026 Bradley Cowdrey · [bradcowdrey.com](https://bradcowdrey.com)

Bundles the [Inter](https://rsms.me/inter/) typeface by Rasmus Andersson under the SIL Open Font License 1.1 (`Resources/Fonts/Inter-LICENSE.txt`).
