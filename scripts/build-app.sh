#!/usr/bin/env bash
# Builds Meridian.app (universal: Apple silicon + Intel) into ./dist.
# Usage: scripts/build-app.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-0.1.0}}"
VERSION="${VERSION#meridian-}"; VERSION="${VERSION#v}"  # "v0.1.0" or "meridian-v0.1.0" -> "0.1.0"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="dist/Meridian.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Meridian"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Meridian"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
# Bundled fonts (Inter, SIL Open Font License) for the Font setting.
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"

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
if [[ "${WIDGET_BUILD:-xcode}" == "xcode" ]]; then
  command -v xcodegen >/dev/null || brew install xcodegen
  (cd mac && xcodegen --quiet)
  xcodebuild -project mac/MeridianMacWidget.xcodeproj -target MeridianWidget -configuration Release \
    SYMROOT="$PWD/build/mac" OBJROOT="$PWD/build/mac/obj" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" -quiet build
  rm -rf "$APPEX"
  ditto build/mac/Release/MeridianWidget.appex "$APPEX"
else
  WIDGET_TMP="$(mktemp -d)"
  mkdir -p "$APPEX/Contents/MacOS"
  for arch in arm64 x86_64; do
    xcrun --sdk macosx swiftc -O -parse-as-library -application-extension \
      -target "$arch-apple-macos14.0" -module-name MeridianWidget \
      Widget/MeridianWidget.swift Widget/WidgetCities.swift Sources/Meridian/Shared/WidgetContent.swift \
      Sources/Meridian/Model/Place.swift Sources/Meridian/Model/CityDirectory.swift \
      -o "$WIDGET_TMP/MeridianWidget-$arch"
  done
  lipo -create "$WIDGET_TMP"/MeridianWidget-* -output "$APPEX/Contents/MacOS/MeridianWidget"
  sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Widget-Info.plist > "$APPEX/Contents/Info.plist"
fi

# Sign with a Developer ID if one is configured, otherwise ad-hoc (fine for sideloading).
IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then TIMESTAMP="--timestamp=none"; else TIMESTAMP="--timestamp"; fi
# Inside out: the widget with its sandbox entitlements first, then the app (no --deep, which
# would re-sign the widget without them).
codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" \
  --entitlements Resources/Widget.entitlements "$APPEX"
codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose "$APP"

echo "Built $APP ($VERSION build $BUILD)"
