#!/usr/bin/env bash
# Builds an ad-hoc signed iPhone .ipa (the app and its widget extension, with their app group) for sideloading with
# AltStore or Sideloadly, which re-sign it with the installer's own Apple ID. See docs/sideload.md.
#   scripts/build-ipa.sh [out.ipa]    # default: dist/Meridian-iOS.ipa
# Needs Xcode and XcodeGen (generates ios/Meridian.xcodeproj if it isn't there yet).
set -euo pipefail
cd "$(dirname "$0")/.."

IPA="${1:-dist/Meridian-iOS.ipa}"
case "$IPA" in /*) ;; *) IPA="$PWD/$IPA" ;; esac
mkdir -p "$(dirname "$IPA")"

if [ ! -d ios/Meridian.xcodeproj ]; then
  command -v xcodegen >/dev/null || brew install xcodegen
  (cd ios && xcodegen)
fi

# Release build for devices, with code signing off. Unsigned device builds carry no entitlements,
# and AltStore / Sideloadly re-sign with the entitlements they read from the binary, so the bundles
# are ad-hoc signed below with the app group the widget shares with the app (without it the
# widget can't see the app's cities).
xcodebuild -project ios/Meridian.xcodeproj -scheme Meridian -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build-ipa \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

APP=build-ipa/Build/Products/Release-iphoneos/Meridian.app
test -d "$APP/PlugIns/MeridianWidget.appex" || { echo "Widget extension missing from $APP"; exit 1; }

WORK="$(mktemp -d)"
mkdir "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"
# Embed the entitlements xcodegen generated, inner bundle first.
P="$WORK/Payload/Meridian.app"
test -f ios/Widget/MeridianWidget.entitlements || { echo "ios/Widget/MeridianWidget.entitlements missing"; exit 1; }
test -f ios/Meridian/Meridian.entitlements || { echo "ios/Meridian/Meridian.entitlements missing"; exit 1; }
codesign --force --sign - --entitlements ios/Widget/MeridianWidget.entitlements "$P/PlugIns/MeridianWidget.appex"
codesign --force --sign - --entitlements ios/Meridian/Meridian.entitlements "$P"
for B in "$P/PlugIns/MeridianWidget.appex" "$P"; do
  ENT="$(codesign -d --entitlements - "$B" 2>&1)"
  grep -q group.com.bradcowdrey.meridian <<<"$ENT" || { echo "App group entitlement missing from $B"; exit 1; }
done
rm -f "$IPA"
(cd "$WORK" && zip -qry "$IPA" Payload)
rm -rf "$WORK"
ls -l "$IPA"
