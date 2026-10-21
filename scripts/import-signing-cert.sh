#!/usr/bin/env bash
# CI only: imports the Developer ID certificate (base64 .p12 in $P12, password in $P12_PASSWORD)
# into a temporary keychain and exports CODESIGN_IDENTITY for later steps.
set -euo pipefail
KEYCHAIN="$RUNNER_TEMP/build.keychain"
echo "$P12" | base64 --decode > "$RUNNER_TEMP/cert.p12"
security create-keychain -p ci "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p ci "$KEYCHAIN"
security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign
rm -f "$RUNNER_TEMP/cert.p12"
# Apple's Developer ID intermediate, so codesign can build the full chain.
curl -fsSL -o "$RUNNER_TEMP/DeveloperIDG2CA.cer" https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
security import "$RUNNER_TEMP/DeveloperIDG2CA.cer" -k "$KEYCHAIN" || true
security set-key-partition-list -S apple-tool:,apple: -s -k ci "$KEYCHAIN" >/dev/null
# Add to the search list (keeping the existing keychains).
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
fi
if [[ -z "$IDENTITY" ]]; then
  echo "::error::No 'Developer ID Application' identity in the certificate. Export that certificate (with its private key) as the .p12."
  security find-identity -v -p codesigning "$KEYCHAIN"
  exit 1
fi
echo "Signing as: $IDENTITY"
echo "CODESIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
