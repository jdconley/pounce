#!/bin/bash
# frame-tile.sh: builds cut/game-tile.png (1399x1024, the 164x120 pt Home hero) from raw/game-tile.png:
# the cover art center-cropped into a rounded window with a thick glossy violet rim and ink outlines
# (matches mock m1). Run after generating raw/game-tile.png; then build-assets.sh game-tile.
set -euo pipefail
ART="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"
W=1399; H=1024; INK="#1B0B3A"; VIO="#7B2FF7"; LIL="#C9A6FF"
IW=$((W-168)); IH=$((H-168))
magick "$ART/raw/game-tile.png" -gravity center -crop "$(( 1024*IW/IH ))x1024+0+0" +repage -resize "${IW}x${IH}!" "$T/art.png"
magick -size ${IW}x${IH} xc:black -fill white -draw "roundrectangle 0,0 $((IW-1)),$((IH-1)) 90,90" "$T/mask.png"
magick "$T/art.png" "$T/mask.png" -alpha off -compose copy_opacity -composite "$T/art-r.png"
magick -size ${W}x${H} xc:none \
  -fill "$INK" -draw "roundrectangle 0,0 $((W-1)),$((H-1)) 140,140" \
  -fill "$VIO" -draw "roundrectangle 16,16 $((W-17)),$((H-17)) 126,126" \
  -fill none -stroke "$LIL" -strokewidth 9 -draw "roundrectangle 34,34 $((W-35)),$((H-35)) 112,112" \
  -stroke none -fill "$INK" -draw "roundrectangle 66,66 $((W-67)),$((H-67)) 104,104" \
  "$T/art-r.png" -geometry +84+84 -compose over -composite "PNG32:$ART/cut/game-tile.png"
rm -rf "$T"; echo "cut/game-tile.png framed"
