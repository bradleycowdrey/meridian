#!/usr/bin/env bash
# CI only: imports a signing certificate (base64 .p12 in $P12, password in $P12_PASSWORD) into a
# temporary keychain and exports CODESIGN_IDENTITY for later steps. CERT_KIND is the certificate
# type: "Developer ID Application" (default, the Mac app) or "Apple Distribution" (the App Store).
set -euo pipefail
KIND="${CERT_KIND:-Developer ID Application}"
KEYCHAIN="$RUNNER_TEMP/build.keychain"
echo "$P12" | base64 --decode > "$RUNNER_TEMP/cert.p12"
security create-keychain -p ci "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p ci "$KEYCHAIN"
security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign
rm -f "$RUNNER_TEMP/cert.p12"
# Apple's intermediate certificate, so codesign can build the full chain.
if [[ "$KIND" == "Developer ID Application" ]]; then CA=DeveloperIDG2CA; else CA=AppleWWDRCAG3; fi
curl -fsSL -o "$RUNNER_TEMP/$CA.cer" "https://www.apple.com/certificateauthority/$CA.cer"
security import "$RUNNER_TEMP/$CA.cer" -k "$KEYCHAIN" || true
security set-key-partition-list -S apple-tool:,apple: -s -k ci "$KEYCHAIN" >/dev/null
# Add to the search list (keeping the existing keychains).
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | sed -n "s/.*\"\($KIND: .*\)\"/\1/p" | head -1)"
fi
if [[ -z "$IDENTITY" ]]; then
  echo "::error::No '$KIND' identity in the certificate. Export that certificate (with its private key) as the .p12."
  security find-identity -v -p codesigning "$KEYCHAIN"
  exit 1
fi
echo "Signing as: $IDENTITY"
echo "CODESIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
