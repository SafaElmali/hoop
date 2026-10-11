#!/bin/bash
# Builds build/Hoop.app (release, ad-hoc signed, with a generated icon).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Hoop"

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

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
