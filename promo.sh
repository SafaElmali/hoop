#!/bin/bash
# Renders the promo video and cover image into media/ (needs ffmpeg).
#   ./promo.sh                     cover + both videos
#   ./promo.sh video|gameplay      quick simulation: prints where each throw ends up
#   ./promo.sh gameplay <out.mp4>  just the plain gameplay video (music, no captions)
#   ./promo.sh cover <out.png>     just the cover
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/promo media

sources=()
for file in Sources/Hoop/*.swift; do
  [[ "$file" == */main.swift ]] || sources+=("$file")
done
swiftc -O -target arm64-apple-macos14 "${sources[@]}" Promo/*.swift -o .build/promo/hoop-promo

if [[ $# -gt 0 ]]; then
  .build/promo/hoop-promo "$@"
else
  .build/promo/hoop-promo cover media/cover.png
  .build/promo/hoop-promo video media/hoop.mp4
  .build/promo/hoop-promo gameplay media/hoop-gameplay.mp4
fi
