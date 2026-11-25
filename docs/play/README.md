# Meridian on Google Play

What's here: the store listing (`listing.json`), the 512 px icon (from the iPhone's full-bleed 1024 icon), the
feature graphic, and five phone screenshots, in the App Store's order: every time zone at a glance; drag the hours to
find a time; home screen widgets; go to any moment; search 34,000 cities. The screenshots are the Android emulator's
own (`ci-android` branch, `screenshots/screen-{main,travel,widgets,date,add}.png`), with the status and gesture bars
cropped and the sides extended to fit Play's 2:1 limit (1120 x 2238).

- **Listing:** `.github/workflows/play-listing.yml` sends this folder to Play when it changes on `main`, or when you
  run it by hand (Actions, Google Play listing, Run workflow).
- **Builds:** `.github/workflows/android.yml` builds the release App Bundle signed with the upload key and sends it to
  the closed test (`alpha`) for a new Meridian release (a new `VERSION` makes release.yml publish `v<VERSION>` and start
  the Android build on that tag; a `v*` tag you push does the same) and for runs you start by hand (Actions, Android
  app, Run workflow). Pushes to `main` build it too (kept as the run's artifact) but never go to Play.
- **Version codes:** the commit count (`git rev-list --count HEAD`, full history), as for the debug APK. Only commits
  on `main` go to Play, so each later upload has a higher code; building the same commit again is skipped by Play
  ("already used"). The version name is the release's (v2.1.6 gives 2.1.6) or `VERSION` for a run by hand, and
  "What's new" is that version's CHANGELOG section without its Mac lines.

## Android version

Meridian targets Android 16 (API level 36), as Google Play has required of new apps since 31 August 2026. On large
screens (tablets, unfolded phones) Android 16 ignores the portrait lock, so there the app keeps a phone's width,
centred; CI photographs that too (`screen-wide.png` on `ci-android`).

## One-time steps in Play Console

1. **Create app:** app name Meridian: Every Time Zone, default language English (United States), App, Free; accept
   the declarations. There's no package name to type: Play takes it (`com.bradcowdrey.meridian`) from the first App
   Bundle, and the API can't reach the app until then.
2. **Closed test:** Testing, Closed testing, use the default track (Closed testing - Alpha; the workflow releases to
   it). Testers: an email list with at least 12 people. Countries and regions: where your testers are (or all).
3. **First App Bundle, by hand:** with the signing secrets set, run Actions, Android app, Run workflow (on `main`).
   When it finishes, download the run's artifact `meridian-release-<version>-<code>` (a zip with the signed
   `Meridian-<version>.aab` and `.apk`). In the closed test: Create release, accept Play App Signing (the key in the
   secrets is the upload key), upload the `.aab`, save.
4. **Let the workflows in:** Users and permissions, invite the service account's email (from
   `PLAY_SERVICE_ACCOUNT_JSON`) for Meridian, with "Release to testing tracks" and "Manage store presence". Then run
   Actions, Google Play listing, Run workflow to fill in the store listing.
5. **App content** (Policy, App content) and **Store settings** (below), then send the release for review and roll it
   out to the closed test. From then on, new builds arrive on the closed test by themselves.
6. **12 testers, 14 days:** a personal developer account can apply for production only after a closed test with at
   least 12 testers who stay opted in for 14 days in a row. Send testers the opt-in link from the closed test page.

**Store settings:** category Productivity (the App Store has it under Utilities and Productivity; Play's nearest are
Productivity or Tools), contact email legal@bradcowdrey.com, website https://bradcowdrey.com/meridian (the listing
workflow sends both).

## Suggested answers for App content

Checked against the Android code (`android/`) and the Terms (`TERMS.md`, Sections 6, 15 and 25).

- **Privacy policy:** https://bradcowdrey.com/legal
- **Ads:** No, the app has no ads.
- **App access:** All functionality is available without special access (no account; the first launch only asks
  you to agree to the Terms and, optionally, to use your location).
- **Content rating:** category All Other App Types. Answer No to every question: no violence, sexuality, language,
  drugs, gambling or crude humour; users can't talk to or exchange content with other users (Share and Add to Calendar
  hand text to other apps); it doesn't share anyone's location with other users; no purchases; it isn't a web
  browser (links open your browser). Expect Everyone / PEGI 3 / IARC 3+. The only content not made for the app is
  photos of cities it downloads from Wikimedia Commons (a city's own Wikipedia photo, or a Commons "skyline night"
  photo whose title names the city).
- **Target audience:** 18 and over (Meridian is a work tool for planning across time zones; 13 and over is also
  fine). Not designed for children; doesn't appeal to children.
- **News app:** No. **Government app:** No. **Financial features:** none. **Health:** no health features.
  **Advertising ID:** not used (no ads or analytics libraries; no AD_ID permission).
- **Data safety:** see below.

### Data safety

What leaves the phone, from the code:

1. **Terms check** (`Store.kt`): at most once a day, Meridian reads TERMS.md from raw.githubusercontent.com. It sends
   nothing about you (only the IP address any connection shows).
2. **City photos** (`Photos.kt`; Settings, Download City Photos, on by default): for a city on your list with no
   built-in picture (111 cities have one), Meridian asks Wikipedia and Wikimedia Commons for a photo, at most once in
   30 days. The request has the city's name (and its country, to find the right Wikipedia page); Wikimedia also sees
   the IP address. The photo stays on the phone.
3. **My Location** (`Location.kt`; optional, Android asks for permission, approximate location only): the phone's own
   location service (Android's Geocoder, on most phones Google's) turns the position into a city name. Meridian keeps only the name, on the
   phone, and its own code never sends the position anywhere.

Where Google's definitions leave room for judgement: the names of the cities you add aren't data about you, but the
My Location card is named after the city you're in, and when that city has no built-in picture and Download City
Photos is on, its name goes to Wikimedia. Google counts "the city a user is in" as approximate location, and
"collected" as anything the app sends off the phone, even to someone other than you. So the careful answer is:

- **Does your app collect or share any of the required user data types?** Yes.
- **Location, Approximate location:** collected, yes; shared, yes (with Wikimedia, to get the city's photo);
  processed ephemerally, no (Wikimedia keeps its usual server logs); optional (you choose Use My Location, and can
  turn off Download City Photos); purpose App functionality (for both collection and sharing).
- **Everything else:** not collected. No precise location (approximate only), personal info (names of people on
  cards stay on the phone), contacts, calendar (Add to Calendar opens your calendar app), photos or files, app
  activity, web browsing, app info and performance (no crash reports or analytics), or device IDs.
- **Is all user data encrypted in transit?** Yes (every request is HTTPS).
- **Do you provide a way for users to request that their data is deleted?** No: nothing reaches you. Everything
  Meridian keeps is on the phone and goes with Clear storage or uninstalling.

If you judge Download City Photos (a setting the app explains: "Only the city's name is sent") to be the user's own
request, "shared" can be No. A stricter reading would also list App activity, Other user-generated content (the
names of other cities on the list, sent to Wikimedia for their photos), optional, for App functionality.

## Repository secrets

- `PLAY_SERVICE_ACCOUNT_JSON`: the Google Cloud service account's JSON key (as for the other apps). Without it,
  nothing is sent to Play and the workflows still pass.
- The upload key, by the same names as Bearings: `ANDROID_KEYSTORE_B64` (the `.jks` in base64, `base64 -w0 upload.jks`;
  `ANDROID_KEYSTORE` also works), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` (if
  different from the keystore's). Without them the release build is an unsigned check only, there's no artifact, and
  Play is skipped; the debug APK on `ci-android` is built as before either way.
