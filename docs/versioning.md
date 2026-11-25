# Versioning

Meridian has one version number on Mac, iPhone and Android, starting at **2.0**.
It follows [Semantic Versioning](https://semver.org): **major.minor.patch**.
A trailing ".0" is left off, so it's 2.0, then 2.0.1 or 2.1.

| Change | Bump | Example |
| --- | --- | --- |
| Fixes and small polish, nothing new to learn | **patch** | 2.0 → 2.0.1 |
| New features or screens, all in the same app | **minor** | 2.0.x → 2.1 |
| A redesign or a big leap in what the app is (as 2.0 was) | **major** | 2.x → 3.0 |

The rules:

- **Same version everywhere.** A release that touches more than one platform uses the same number on all of them. A fix for one platform still bumps the shared number, and the others pick it up in their next release.
- **The build number is automatic and only ever goes up.**
  - iPhone: CI's run number, as `CFBundleVersion`.
  - Android: the commit count, as `versionCode`.
  - Mac: the commit count, as `CFBundleVersion` (the DMG and the Mac App Store build alike).

  Several TestFlight builds of one version (2.0 build 187, 2.0 build 190) are normal. The version changes only when a release goes out.
- **A version that has gone out is never reused.** That means on the App Store, in a GitHub release or as a shipped APK. To change what shipped, release the next number.
- **Where the number lives:**
  - `VERSION` for the Mac. Changing it publishes a GitHub release that the Mac app updates to.
  - The first word of `ios/APPSTORE` for the iPhone:
    - `2.1 beta` uploads to TestFlight.
    - `2.1 submit` uploads and submits for App Review.
    - `status` reports what App Store Connect shows.
  - The first word of `mac/APPSTORE` for the Mac App Store (the same App Store record as the iPhone app; the DMG from `VERSION` carries on unchanged). Changing the file on main runs `.github/workflows/mac-appstore.yml`:
    - `2.1.4 build` builds the App Store variant (`APPSTORE=1 scripts/build-app.sh`), signs it, packages the .pkg (`scripts/make-mas-pkg.sh`) and validates it with App Store Connect. Nothing is uploaded.
    - `2.1.4 upload` also takes the Mac screenshots, creates the macOS App Store version if it's missing, and uploads the .pkg, the Mac listing (`mac/fastlane/metadata`) and the screenshots. It doesn't submit.
    - `2.1.4 submit` does the same and submits for App Review.
    - `2.1.4 status` reports the macOS versions, builds and review state.

    The first Mac upload needs macOS added to the app in App Store Connect (Add Platform > macOS); the run says so if it isn't. Logs go to the `ci-mac-appstore` branch.
  - `versionName` in `android/app/build.gradle.kts` for Android. Builds for Google Play take the release's number instead (`v<VERSION>`, or `VERSION` for a run by hand; see [play/README.md](play/README.md)).
- **Submitting while an earlier version waits for review** withdraws it first (`2.1 submit` in `ios/APPSTORE` does this automatically), so the newer build replaces it. The Mac run doesn't: a macOS version waiting for review has to be removed from review in App Store Connect before the next `submit`.
- **Every release gets notes:** `CHANGELOG.md`, the README's "What's new", and `ios/fastlane/metadata/en-US/release_notes.txt` for the App Store (`mac/fastlane/metadata/en-US/release_notes.txt` for the Mac App Store, from its second version on).
