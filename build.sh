#!/bin/bash
# Builds build/Hoop.app (release, with a generated icon). release.sh zips it for a download.
#   ARCHS="arm64 x86_64"                         architectures to build (default: this Mac's)
#   SIGN_IDENTITY="Developer ID Application: …"  sign with the hardened runtime (default: ad-hoc)
set -euo pipefail
cd "$(dirname "$0")"

flags=(-c release)
for arch in ${ARCHS:-}; do
  flags+=(--arch "$arch")
done
swift build "${flags[@]}"
BIN="$(swift build "${flags[@]}" --show-bin-path)/Hoop"

APP="build/Hoop.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/Hoop.iconset
cp "$BIN" "$APP/Contents/MacOS/Hoop"
cp Info.plist "$APP/Contents/Info.plist"

"$BIN" --render-icon build/icon.png
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" build/icon.png --out "build/Hoop.iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) build/icon.png --out "build/Hoop.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/Hoop.iconset -o "$APP/Contents/Resources/Hoop.icns"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  # Hardened runtime blocks Apple Events to Finder unless the entitlement allows them.
  codesign --force --options runtime --timestamp --entitlements Hoop.entitlements --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP" >/dev/null
fi
echo "Built $APP"
