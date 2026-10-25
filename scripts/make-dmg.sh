#!/usr/bin/env bash
# Packages dist/Meridian.app into dist/Meridian-<version>.dmg: a branded installer window with
# the app and an Applications shortcut side by side.
# Notarizes it when NOTARY_APPLE_ID / NOTARY_PASSWORD / NOTARY_TEAM_ID are set.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-0.1.0}}"
VERSION="${VERSION#meridian-}"; VERSION="${VERSION#v}"  # "v0.1.0" or "meridian-v0.1.0" -> "0.1.0"
DMG="dist/Meridian-$VERSION.dmg"
WORK="$(mktemp -d)"
rm -f "$DMG"

NOTARIZE=false
if [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" && -n "${NOTARY_TEAM_ID:-}" ]]; then NOTARIZE=true; fi
# Attach Apple's ticket; retried, since fetching it from Apple occasionally drops the connection.
staple() {
  local attempt
  for attempt in 1 2 3 4 5; do
    xcrun stapler staple "$1" && return 0
    echo "Stapling $(basename "$1") failed (attempt $attempt); retrying in 30 s."
    sleep 30
  done
  return 1
}

notarize() {
  local out id status attempt
  # Up to three tries: a dropped connection to Apple shouldn't sink a release. If a submission
  # got an id before the connection dropped, keep waiting on that one instead of resubmitting.
  for attempt in 1 2 3; do
    if [[ -n "${id:-}" ]]; then
      out="$(xcrun notarytool wait "$id" --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" \
        --team-id "$NOTARY_TEAM_ID" --timeout 2h 2>&1)" || true
    else
      out="$(xcrun notarytool submit "$1" --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" \
        --team-id "$NOTARY_TEAM_ID" --wait --timeout 2h 2>&1)" || true
    fi
    echo "$out"
    [[ -z "${id:-}" ]] && id="$(echo "$out" | sed -n 's/^ *id: //p' | head -1)"
    status="$(echo "$out" | sed -n 's/^ *status: //p' | tail -1)"
    [[ "$status" == "Accepted" || "$status" == "Invalid" || "$status" == "Rejected" ]] && break
    echo "Notarization attempt $attempt didn't finish (status '${status:-none}'); retrying in 30 s."
    sleep 30
  done
  if [[ "$status" != "Accepted" ]]; then
    echo "::error::Notarization of $(basename "$1") ended with status '${status:-unknown}'."
    # Apple's report says exactly what it objected to.
    [[ -n "$id" ]] && xcrun notarytool log "$id" --apple-id "$NOTARY_APPLE_ID" \
      --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID" || true
    return 1
  fi
}

# Notarize and staple the app itself, so it opens cleanly however it's installed
# (from the DMG, or by the in-app updater).
if $NOTARIZE; then
  ditto -c -k --keepParent dist/Meridian.app "$WORK/Meridian.zip"
  notarize "$WORK/Meridian.zip"
  staple dist/Meridian.app
fi

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

if $NOTARIZE; then
  notarize "$DMG"
  # The app inside is already stapled, which is what Gatekeeper checks when it opens. An unstapled
  # DMG is still notarized (macOS looks the ticket up online), so a dropped connection to Apple's
  # ticket server here is a warning, not a failed release.
  if staple "$DMG"; then
    spctl -a -vvv -t open --context context:primary-signature "$DMG"
  else
    echo "::warning::The DMG is notarized but its ticket couldn't be stapled (Apple's ticket server kept dropping the connection)."
  fi
  spctl -a -vvv -t execute dist/Meridian.app
fi

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Packaged $DMG"
