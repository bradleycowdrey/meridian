#!/usr/bin/env bash
# Packages the Mac App Store build (APPSTORE=1 scripts/build-app.sh) as dist/Meridian-<version>.pkg,
# the installer package App Store Connect takes for a Mac app.
# Usage: INSTALLER_IDENTITY="3rd Party Mac Developer Installer: ..." scripts/make-mas-pkg.sh <version>
#   INSTALLER_IDENTITY  a "3rd Party Mac Developer Installer" / "Mac Installer Distribution" identity
#   INSTALLER_KEYCHAIN  optional: the keychain that holds it (default: the keychain search list)
# The Developer ID build is packaged by scripts/make-dmg.sh instead; this never touches it.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-}}"
VERSION="${VERSION#meridian-}"; VERSION="${VERSION#v}"  # "v2.1.4" -> "2.1.4"
APP="dist/Meridian.app"
PKG="dist/Meridian-$VERSION.pkg"
PB=/usr/libexec/PlistBuddy

[[ -n "$VERSION" ]] || { echo "usage: scripts/make-mas-pkg.sh <version>" >&2; exit 1; }
[[ -d "$APP" ]] || { echo "error: no $APP; run APPSTORE=1 scripts/build-app.sh $VERSION first" >&2; exit 1; }
: "${INSTALLER_IDENTITY:?set INSTALLER_IDENTITY to the installer signing identity}"

# Only the App Store build goes in: its bundle ID, its version, its embedded profile.
ID="$($PB -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")"
SHORT="$($PB -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
BUILD="$($PB -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")"
if [[ "$ID" != "com.bradcowdrey.meridian" ]]; then
  echo "error: $APP is $ID, not the App Store build (com.bradcowdrey.meridian). Build it with APPSTORE=1." >&2; exit 1
fi
[[ "$SHORT" == "$VERSION" ]] || { echo "error: $APP is version $SHORT, not $VERSION" >&2; exit 1; }
for b in "$APP" "$APP/Contents/PlugIns/MeridianWidget.appex"; do
  [[ -f "$b/Contents/embedded.provisionprofile" ]] || { echo "error: $b has no embedded provisioning profile" >&2; exit 1; }
done
codesign --verify --deep --strict "$APP"

KEYCHAIN_ARGS=()
if [[ -n "${INSTALLER_KEYCHAIN:-}" ]]; then KEYCHAIN_ARGS=(--keychain "$INSTALLER_KEYCHAIN"); fi

rm -f "$PKG"
productbuild --component "$APP" /Applications \
  --sign "$INSTALLER_IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$PKG"
pkgutil --check-signature "$PKG"
shasum -a 256 "$PKG"
echo "Built $PKG ($ID $SHORT build $BUILD, $(du -h "$PKG" | cut -f1))"
