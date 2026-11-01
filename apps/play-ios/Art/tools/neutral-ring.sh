#!/bin/bash
# neutral-ring.sh: makes cut/ring.png a neutral light-gray ring (ink outline stays dark, highlights near white)
# so CatNode's SpriteKit tint (Palette.playerRings at colorBlendFactor 0.85) lands on the true seat colour
# instead of mixing with the generated purple. The generated purple take is kept as cut/ring.orig.png and is
# always the source, so re-running is idempotent. Then: build-assets.sh ring.
set -euo pipefail
C="$(cd "$(dirname "$0")/.." && pwd)/cut"
[ -f "$C/ring.orig.png" ] || cp "$C/ring.png" "$C/ring.orig.png"
magick "$C/ring.orig.png" -colorspace Gray -level "${RING_BLACK:-5}%,${RING_WHITE:-30}%" -gamma "${RING_GAMMA:-1.25}" -colorspace sRGB \
  \( "$C/ring.orig.png" -alpha extract \) -compose copy_opacity -composite "PNG32:$C/ring.png"
echo "cut/ring.png neutralised"
