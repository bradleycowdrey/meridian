#!/usr/bin/env bash
# Builds Meridian.app (universal: Apple silicon + Intel) into ./dist.
# Usage: scripts/build-app.sh [version]
#
# Mac App Store build: APPSTORE=1 scripts/build-app.sh <version>
#   The same sources compiled with the APPSTORE condition (no self-updater, sandbox-safe paths),
#   bundle IDs com.bradcowdrey.meridian / com.bradcowdrey.meridian.widget, the sandboxed
#   *-AppStore.entitlements, and the Mac App Store provisioning profiles embedded. Needs:
#     CODESIGN_IDENTITY  an "Apple Distribution: ..." identity in the keychain
#     APP_PROFILE        Mac App Store profile for com.bradcowdrey.meridian (.provisionprofile)
#     WIDGET_PROFILE     Mac App Store profile for com.bradcowdrey.meridian.widget
#   Optional: TEAM_ID (default 2XV97FZ86G), MERIDIAN_BUILD (build number; default: commit count).
#   No notarization: scripts/make-mas-pkg.sh then packages it for App Store Connect.
# Without APPSTORE=1 nothing here changes: the Developer ID / DMG build is built as always.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-0.1.0}}"
VERSION="${VERSION#meridian-}"; VERSION="${VERSION#v}"  # "v0.1.0" or "meridian-v0.1.0" -> "0.1.0"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="dist/Meridian.app"

MAS=false
if [[ "${APPSTORE:-}" == "1" ]]; then
  MAS=true
  TEAM_ID="${TEAM_ID:-2XV97FZ86G}"
  APP_ID="com.bradcowdrey.meridian"
  WIDGET_ID="com.bradcowdrey.meridian.widget"
  # The App Store needs an integer build number that only goes up.
  BUILD="${MERIDIAN_BUILD:-$BUILD}"
  [[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "error: build number '$BUILD' is not an integer" >&2; exit 1; }
  [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] \
    || { echo "error: App Store version '$VERSION' must be numbers only, like 2.1.4" >&2; exit 1; }
  if [[ -z "${CODESIGN_IDENTITY:-}" || "${CODESIGN_IDENTITY}" == "-" ]]; then
    echo "error: APPSTORE=1 needs CODESIGN_IDENTITY (an Apple Distribution identity)" >&2; exit 1
  fi
  for f in "${APP_PROFILE:-}" "${WIDGET_PROFILE:-}" Resources/Meridian-AppStore.entitlements Resources/Widget-AppStore.entitlements; do
    [[ -n "$f" && -f "$f" ]] || { echo "error: APPSTORE=1 needs APP_PROFILE, WIDGET_PROFILE and the *-AppStore.entitlements files (missing: '${f}')" >&2; exit 1; }
  done
  echo "Mac App Store build: $APP_ID $VERSION ($BUILD)"
fi

# The App Store build has its own build folders, so it never reuses objects compiled without
# APPSTORE (and the default build never reuses App Store ones).
SWIFT_ARGS=(-c release --arch arm64 --arch x86_64)
if $MAS; then SWIFT_ARGS+=(--scratch-path .build/appstore -Xswiftc -DAPPSTORE); fi
swift build "${SWIFT_ARGS[@]}"
BIN="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)/Meridian"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Meridian"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
# Bundled fonts (Inter, SIL Open Font License) for the Font setting.
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
# Offline data: world cities and public holidays (scripts/gen-data.py).
cp Resources/Data/*.tsv "$APP/Contents/Resources/"
# City photos (day and night) from the one copy in git (Android's), and their manifest.
mkdir -p "$APP/Contents/Resources/Skylines"
cp android/app/src/main/res/drawable-nodpi/skyline_*.jpg "$APP/Contents/Resources/Skylines/"
cp Resources/Data/skylines.json "$APP/Contents/Resources/skylines.json"

# Icon: 1024px PNG -> .icns
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Desktop widget: a WidgetKit app extension. SwiftPM can't build .appex bundles, so it's built
# with Xcode from mac/project.yml (Widget/ plus the shared views and data format).
# WIDGET_BUILD=swiftc uses the old bare-compiler build instead (kept only for comparison: macOS
# starts that one but it can't identify itself as a widget, so it never appears in Edit Widgets).
APPEX="$APP/Contents/PlugIns/MeridianWidget.appex"
mkdir -p "$APP/Contents/PlugIns"
WIDGET_ROOT="build/mac"
WIDGET_XCODE_ARGS=()
WIDGET_SWIFTC_ARGS=()
if $MAS; then
  WIDGET_ROOT="build/mac-appstore"
  WIDGET_XCODE_ARGS=(PRODUCT_BUNDLE_IDENTIFIER="$WIDGET_ID" SWIFT_ACTIVE_COMPILATION_CONDITIONS="APPSTORE")
  WIDGET_SWIFTC_ARGS=(-D APPSTORE)
fi
if [[ "${WIDGET_BUILD:-xcode}" == "xcode" ]]; then
  command -v xcodegen >/dev/null || brew install xcodegen
  (cd mac && xcodegen --quiet)
  # ${a[@]+"${a[@]}"}: an empty list is fine under set -u, even in macOS's bash 3.2.
  xcodebuild -project mac/MeridianMacWidget.xcodeproj -target MeridianWidget -configuration Release \
    SYMROOT="$PWD/$WIDGET_ROOT" OBJROOT="$PWD/$WIDGET_ROOT/obj" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
    ${WIDGET_XCODE_ARGS[@]+"${WIDGET_XCODE_ARGS[@]}"} -quiet build
  rm -rf "$APPEX"
  ditto "$WIDGET_ROOT/Release/MeridianWidget.appex" "$APPEX"
else
  WIDGET_TMP="$(mktemp -d)"
  mkdir -p "$APPEX/Contents/MacOS"
  for arch in arm64 x86_64; do
    xcrun --sdk macosx swiftc -O -parse-as-library -application-extension \
      ${WIDGET_SWIFTC_ARGS[@]+"${WIDGET_SWIFTC_ARGS[@]}"} \
      -target "$arch-apple-macos14.0" -module-name MeridianWidget \
      Widget/MeridianWidget.swift Widget/WidgetCities.swift Sources/Meridian/Shared/WidgetContent.swift \
      Sources/Meridian/Model/Place.swift Sources/Meridian/Model/CityDirectory.swift \
      Sources/Meridian/Shared/MacSkylines.swift Sources/Meridian/Model/Sun.swift \
      Sources/Meridian/Model/WorkWeek.swift Sources/Meridian/Model/Holidays.swift \
      -o "$WIDGET_TMP/MeridianWidget-$arch"
  done
  lipo -create "$WIDGET_TMP"/MeridianWidget-* -output "$APPEX/Contents/MacOS/MeridianWidget"
  sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Widget-Info.plist > "$APPEX/Contents/Info.plist"
fi

# The widget is sandboxed: it reads its own smaller copies (600 px wide).
mkdir -p "$APPEX/Contents/Resources/Skylines"
for f in "$APP/Contents/Resources/Skylines"/*.jpg; do
  sips -Z 600 -s format jpeg -s formatOptions 72 "$f" --out "$APPEX/Contents/Resources/Skylines/$(basename "$f")" >/dev/null
done
cp Resources/Data/skylines.json "$APPEX/Contents/Resources/skylines.json"
# The cities' public holidays, for the widget's status (Holidays loads from the appex's bundle).
cp Resources/Data/holidays.tsv "$APPEX/Contents/Resources/"

if $MAS; then
  # App Store identity: the shared bundle IDs (universal purchase with the iPhone app), and the
  # export compliance answer (only Apple's own HTTPS/TLS is used) so uploads need no questions.
  PB=/usr/libexec/PlistBuddy
  $PB -c "Set :CFBundleIdentifier $APP_ID" "$APP/Contents/Info.plist"
  $PB -c "Set :CFBundleIdentifier $WIDGET_ID" "$APPEX/Contents/Info.plist"
  for plist in "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist"; do
    $PB -c "Delete :ITSAppUsesNonExemptEncryption" "$plist" 2>/dev/null || true
    $PB -c "Add :ITSAppUsesNonExemptEncryption bool false" "$plist"
    plutil -lint "$plist" >/dev/null
  done
  [[ "$($PB -c "Print :CFBundleVersion" "$APPEX/Contents/Info.plist")" == "$BUILD" ]] \
    || { echo "error: the widget's CFBundleVersion isn't $BUILD" >&2; exit 1; }
  # The app's Info.plist is hand-written (SwiftPM), so it lacks the toolchain keys Xcode stamps into
  # every bundle and App Store Connect checks (SDK and Xcode version). Copy them from the widget,
  # which Xcode built with the same toolchain moments ago.
  $PB -c "Delete :CFBundleSupportedPlatforms" "$APP/Contents/Info.plist" 2>/dev/null || true
  $PB -c "Add :CFBundleSupportedPlatforms array" -c "Add :CFBundleSupportedPlatforms:0 string MacOSX" "$APP/Contents/Info.plist"
  for key in DTCompiler DTPlatformBuild DTPlatformName DTPlatformVersion DTSDKBuild DTSDKName DTXcode DTXcodeBuild BuildMachineOSBuild; do
    value="$($PB -c "Print :$key" "$APPEX/Contents/Info.plist" 2>/dev/null || true)"
    [[ -n "$value" ]] || continue
    $PB -c "Delete :$key" "$APP/Contents/Info.plist" 2>/dev/null || true
    $PB -c "Add :$key string $value" "$APP/Contents/Info.plist"
  done
  plutil -lint "$APP/Contents/Info.plist" >/dev/null

  # The provisioning profiles, embedded where macOS and App Store Connect look for them. Each must
  # be for this team and bundle ID.
  embed_profile() {  # profile, bundle id, bundle
    local plist; plist="$(mktemp)"
    security cms -D -i "$1" > "$plist"
    local got; got="$($PB -c "Print :Entitlements:com.apple.application-identifier" "$plist" 2>/dev/null || true)"
    if [[ "$got" != "$TEAM_ID.$2" ]]; then
      echo "error: $1 is for '$got', not $TEAM_ID.$2" >&2; exit 1
    fi
    echo "Profile for $2: $($PB -c "Print :Name" "$plist") (expires $($PB -c "Print :ExpirationDate" "$plist"))"
    cp "$1" "$3/Contents/embedded.provisionprofile"
    rm -f "$plist"
  }
  embed_profile "$WIDGET_PROFILE" "$WIDGET_ID" "$APPEX"
  embed_profile "$APP_PROFILE" "$APP_ID" "$APP"

  # Entitlements: the committed sandbox files plus the app identifier and team the profiles grant
  # (Xcode adds these itself; codesign doesn't, and App Store Connect rejects a build without them).
  ENT_DIR="$(mktemp -d)"
  cp Resources/Widget-AppStore.entitlements "$ENT_DIR/Widget.entitlements"
  cp Resources/Meridian-AppStore.entitlements "$ENT_DIR/Meridian.entitlements"
  for pair in "Widget:$WIDGET_ID" "Meridian:$APP_ID"; do
    ent="$ENT_DIR/${pair%%:*}.entitlements"; id="${pair#*:}"
    $PB -c "Delete :com.apple.application-identifier" "$ent" 2>/dev/null || true
    $PB -c "Add :com.apple.application-identifier string $TEAM_ID.$id" "$ent"
    $PB -c "Delete :com.apple.developer.team-identifier" "$ent" 2>/dev/null || true
    $PB -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ent"
    plutil -lint "$ent" >/dev/null
  done
  WIDGET_ENTITLEMENTS="$ENT_DIR/Widget.entitlements"
  APP_ENTITLEMENTS="$ENT_DIR/Meridian.entitlements"
else
  WIDGET_ENTITLEMENTS=Resources/Widget.entitlements
  APP_ENTITLEMENTS=Resources/Meridian.entitlements
fi

# Sign with a Developer ID if one is configured, otherwise ad-hoc (fine for sideloading).
# (The App Store build signs with the Apple Distribution identity in CODESIGN_IDENTITY.)
IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then TIMESTAMP="--timestamp=none"; else TIMESTAMP="--timestamp"; fi
# Inside out: the widget with its sandbox entitlements first, then the app (no --deep, which
# would re-sign the widget without them).
codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" \
  --entitlements "$WIDGET_ENTITLEMENTS" "$APPEX"
codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" \
  --entitlements "$APP_ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose "$APP"

if $MAS; then
  # Every executable in an App Store app must be sandboxed.
  for b in "$APPEX" "$APP"; do
    signed="$(codesign -d --entitlements - --xml "$b" 2>/dev/null || true)"
    [[ "$signed" == *com.apple.security.app-sandbox* ]] \
      || { echo "error: $b is not signed with the app sandbox" >&2; exit 1; }
  done
  rm -rf "$ENT_DIR"
  echo "Built $APP for the Mac App Store ($APP_ID $VERSION build $BUILD)"
else
  echo "Built $APP ($VERSION build $BUILD)"
fi
