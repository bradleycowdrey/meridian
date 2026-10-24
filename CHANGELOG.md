# What's new in Meridian

Meridian updates itself: it checks once a day and shows **Update** in the panel when a new
version is out. You can also choose ⋯ → **Check for Updates**, or download the latest
[Meridian.dmg](https://github.com/bradleycowdrey/meridian/releases/latest/download/Meridian.dmg).

## 0.7.9 · 24 October 2026

- **The widget shows up after updating**: macOS's widget service can keep a record of an older version's widget, which kept Meridian out of **Edit Widgets** until it was restarted from Terminal. Meridian now restarts it the first time a new version opens, and when you press Settings → **Refresh Widgets**. If Edit Widgets is open at the time, close and reopen it.

## 0.7.8 · 23 October 2026

- **The Mac widget works**: Meridian's widget now appears in **Edit Widgets**. It's now built with Xcode, which gives it the start-up code macOS needs to recognise it as a widget; before, macOS started it but it quit straight away.

## 0.7.7 · 22 October 2026

- **Share in the top bar**: the Share button now sits at the top left of the panel, next to the Meridian name.

## 0.7.6 · 22 October 2026

- **Panel opens under its menu bar item**: clicking Meridian in the menu bar opens the panel horizontally centred under Meridian's item, moved sideways only as far as needed to stay on screen.

## 0.7.5 · 21 October 2026

- **Terms of Use and Privacy**: Meridian asks you to agree once, the first time it opens. The terms are always one click away under ⋯ → **Terms & Privacy**, in **Settings**, and at [bradcowdrey.com/legal](https://bradcowdrey.com/legal).

## 0.7.4 · 21 October 2026

- **Signed and notarized by Apple**: Meridian is now signed with a Developer ID and checked by Apple, so it opens without the "can't verify the developer" warning.
- **Widget fix**: each time Meridian opens from Applications, it makes sure macOS is using this copy of its widget (older or duplicate copies of the app could hide it from Edit Widgets).
- **Refresh Widgets** button in Settings → General → Widget, if Meridian ever goes missing from Edit Widgets.

## 0.7.3 · 18 October 2026

- **Widgets refresh after an update**: the first time a new version opens, it tells macOS to redraw Meridian's widgets straight away, instead of waiting for their next scheduled refresh.

## 0.7.2 · 17 October 2026

A reliability release, from a full test pass of every feature at all five sizes.

- **Safer updates**: every download's checksum and code signature are verified before installing; Meridian never replaces itself while still running; and if an update can't install, it tells you after reopening.
- **Time travel stays put**: the hour you've moved to no longer shifts when the clock passes the hour, and the clock keeps ticking while a menu is open.
- **Travel-friendly**: the app and widget refresh straight away when your Mac changes time zone or wakes from sleep.
- **Cities**: the same city can't be added twice; at 12 cities, Meridian says so instead of doing nothing; blank renames are ignored; Edit switches off when the list is empty.
- **Search**: no duplicate "GMT+5" results, and impossible times like "UTC+5:75" are rejected.
- **Display**: half-hour time zones fit in 12-hour mode; days where daylight saving skips midnight still get the midnight marker; city names aren't cut off in Edit; "+2 day" where it applies; larger click targets at small sizes.
- **Widget**: shows "No cities yet" instead of placeholder cities, shows minutes for half-hour time zones, and draws sharper.

## 0.7.0 – 0.7.1 · 17 October 2026

- **Desktop widget** in small, medium and large, for the desktop or Notification Center. The large widget shows the day-and-night tiles. Right-click the desktop → **Edit Widgets** → search **Meridian**.

## 0.6.0 – 0.6.3 · 16–17 October 2026

- Fits on screen at every size, checked on a real Mac.
- "+1 / −1" day shown next to the menu bar city time and the time line.
- The delete and reorder controls in Edit respond at every size.
- Checks for updates once a day.

## 0.5.0 – 0.5.9 · 16 October 2026

- **Check for Updates**, with one-click install and restart.
- **SF Pro or Inter** typeface.
- Branded installer window.
- **Open as Window**, with a draggable window you can snap left, centre or right; drag the menu bar panel to detach it.
- "Hours from now" labels above the tiles, an evenly spaced tile grid and a centred "now" outline.

## 0.2.0 – 0.4.0 · 16 October 2026

- bradcowdrey.com look: warm dark colours, larger type, apple.com-style layout.
- Five interface sizes, Extra Small to Extra Large (⌘+ / ⌘−).
- Add, edit and reorder cities right in the panel.

## 0.1.0 · 16 October 2026

- First release: a simple world clock for the Mac menu bar.
