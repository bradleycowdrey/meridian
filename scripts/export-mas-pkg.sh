#!/usr/bin/env bash
# Packages the Mac App Store build as dist/Meridian-<version>.pkg WITHOUT a local installer
# certificate: wraps dist/Meridian.app (APPSTORE=1 scripts/build-app.sh) in an Xcode archive and
# exports it for App Store Connect with automatic, cloud-managed signing, the way Xcode's
# Distribute App does. Used when the team's two Mac Installer Distribution certificates are taken.
# Usage: ASC_KEY_ID=... ASC_ISSUER_ID=... scripts/export-mas-pkg.sh <version>
#   needs the API key at ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-}}"
VERSION="${VERSION#v}"
APP="dist/Meridian.app"
PKG="dist/Meridian-$VERSION.pkg"
PB=/usr/libexec/PlistBuddy
: "${ASC_KEY_ID:?}"; : "${ASC_ISSUER_ID:?}"
KEY="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
[[ -n "$VERSION" && -d "$APP" && -f "$KEY" ]] || { echo "error: need a version, $APP and the API key" >&2; exit 1; }
[[ "$($PB -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")" == "com.bradcowdrey.meridian" ]] \
  || { echo "error: $APP is not the App Store build" >&2; exit 1; }

WORK="$(mktemp -d)"
ARCHIVE="$WORK/Meridian.xcarchive"
mkdir -p "$ARCHIVE/Products/Applications"
ditto "$APP" "$ARCHIVE/Products/Applications/Meridian.app"
SHORT="$($PB -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
BUILD="$($PB -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")"
python3 - "$ARCHIVE/Info.plist" "$SHORT" "$BUILD" "$WORK/ExportOptions.plist" <<'PY'
import plistlib, sys, datetime
path, short, build, opts = sys.argv[1:5]
plistlib.dump({
    "ApplicationProperties": {
        "ApplicationPath": "Applications/Meridian.app",
        "Architectures": ["arm64", "x86_64"],
        "CFBundleIdentifier": "com.bradcowdrey.meridian",
        "CFBundleShortVersionString": short,
        "CFBundleVersion": build,
        "SigningIdentity": "Apple Distribution",
        "Team": "2XV97FZ86G",
    },
    "ArchiveVersion": 2,
    "CreationDate": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
    "Name": "Meridian",
    "SchemeName": "Meridian",
}, open(path, "wb"))
plistlib.dump({
    "method": "app-store-connect",
    "destination": "export",
    "signingStyle": "automatic",
    "teamID": "2XV97FZ86G",
    "uploadSymbols": False,
    "manageAppVersionAndBuildNumber": False,
}, open(opts, "wb"))
PY

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$WORK/export" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"

OUTPKG="$(ls "$WORK/export"/*.pkg | head -1)"
[[ -f "$OUTPKG" ]] || { echo "error: the export made no .pkg" >&2; ls -la "$WORK/export" >&2; exit 1; }
cp "$OUTPKG" "$PKG"
pkgutil --check-signature "$PKG"
# What the cloud signing produced (signer and entitlements of the app inside), for the log.
X="$WORK/x"; pkgutil --expand-full "$PKG" "$X" >/dev/null
INNER="$(find "$X" -maxdepth 4 -name Meridian.app -type d | head -1)"
if [[ -n "$INNER" ]]; then
  codesign -dvv "$INNER" 2>&1 | grep -E "Authority|TeamIdentifier" || true
  codesign -d --entitlements - --xml "$INNER" 2>/dev/null | plutil -p - || true
fi
rm -rf "$WORK"
echo "Packaged $PKG (cloud-signed)"
