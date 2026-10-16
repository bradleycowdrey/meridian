#!/usr/bin/env bash
# Packages dist/Meridian.app into dist/Meridian-<version>.dmg: a branded installer window with
# the app and an Applications shortcut side by side.
# Notarizes it when NOTARY_APPLE_ID / NOTARY_PASSWORD / NOTARY_TEAM_ID are set.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-0.1.0}}"
VERSION="${VERSION##*v}"  # "v0.1.0" or "meridian-v0.1.0" -> "0.1.0"
DMG="dist/Meridian-$VERSION.dmg"
WORK="$(mktemp -d)"
rm -f "$DMG"

# Styled installer window (branded background, fixed layout, no toolbar) via dmgbuild,
# which writes Finder's .DS_Store directly instead of scripting Finder.
styled() {
  python3 -m venv "$WORK/venv" >/dev/null
  "$WORK/venv/bin/pip" install --quiet "dmgbuild>=1.6,<2"
  tiffutil -cathidpicheck Resources/dmg/background.png Resources/dmg/background@2x.png \
    -out "$WORK/background.tiff" >/dev/null
  "$WORK/venv/bin/dmgbuild" -s scripts/dmg-settings.py \
    -D app=dist/Meridian.app \
    -D background="$WORK/background.tiff" \
    -D icon=dist/Meridian.app/Contents/Resources/AppIcon.icns \
    "Meridian" "$DMG"
}

# Plain fallback so a release still ships if the styled build ever fails.
plain() {
  mkdir -p "$WORK/stage"
  cp -R dist/Meridian.app "$WORK/stage/"
  ln -s /Applications "$WORK/stage/Applications"
  hdiutil create -volname "Meridian" -srcfolder "$WORK/stage" -ov -format UDZO "$DMG"
}

if ! styled; then
  echo "::warning::Styled DMG failed; packaging a plain DMG instead."
  rm -f "$DMG"
  plain
fi

if [[ -n "${CODESIGN_IDENTITY:-}" && "${CODESIGN_IDENTITY}" != "-" ]]; then
  codesign --sign "$CODESIGN_IDENTITY" --timestamp "$DMG"
fi

if [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" && -n "${NOTARY_TEAM_ID:-}" ]]; then
  xcrun notarytool submit "$DMG" --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" \
    --team-id "$NOTARY_TEAM_ID" --wait
  xcrun stapler staple "$DMG"
fi

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Packaged $DMG"
