#!/bin/bash
# Builds a universal (arm64 + x86_64) build/Hoop.app and zips it to build/Hoop-<version>.zip.
#   ./release.sh                                 ad-hoc signed, like build.sh
#   SIGN_IDENTITY="Developer ID Application: …"  sign with the hardened runtime
#   NOTARY_PROFILE=<profile>                     also notarize and staple (a notarytool keychain profile)
set -euo pipefail
cd "$(dirname "$0")"

if [[ -n "${NOTARY_PROFILE:-}" && -z "${SIGN_IDENTITY:-}" ]]; then
  echo "NOTARY_PROFILE needs SIGN_IDENTITY: Apple only notarizes Developer ID signed apps." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)"
APP="build/Hoop.app"
ZIP="build/Hoop-$VERSION.zip"

ARCHS="arm64 x86_64" ./build.sh
# --norsrc leaves out extended attributes: `unzip` would unpack them as ._ files inside the
# bundle and break its signature.
ditto -c -k --norsrc --keepParent "$APP" "$ZIP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  # Staple the ticket so the app opens offline, then zip the stapled app.
  xcrun stapler staple "$APP"
  ditto -c -k --norsrc --keepParent "$APP" "$ZIP"
fi

echo "Released $ZIP"
shasum -a 256 "$ZIP"
