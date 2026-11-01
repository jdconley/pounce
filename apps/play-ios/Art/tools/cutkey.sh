#!/bin/bash
# cutkey.sh <name>...: fallback cutout by flood-filling the flat gray background from the 4 corners
# (fuzz 7%), eroding alpha 2px, trimming with 4px padding. For subjects Vision mis-masks (white interiors).
ART="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ART"
for n in "$@"; do
  f="raw/$n.png"; W=$(magick identify -format %w "$f"); H=$(magick identify -format %h "$f")
  if [ -n "${GLOBAL:-}" ]; then  # key out every background-gray pixel (subjects with no gray, enclosed gaps)
    bg=$(magick "$f" -format '%[pixel:p{2,2}]' info:)
    magick "$f" -alpha set -fuzz ${FUZZ:-7}% -transparent "$bg" "PNG32:cut/$n.png"
  else
  magick "$f" -alpha set -fuzz ${FUZZ:-7}% -fill none \
    -draw "color 0,0 floodfill" -draw "color $((W-1)),0 floodfill" -draw "color 0,$((H-1)) floodfill" -draw "color $((W-1)),$((H-1)) floodfill" \
    "PNG32:cut/$n.png"
  fi
  magick "cut/$n.png" -alpha extract -morphology Erode Disk:2 "raw/logs/$n.mask.png"
  magick "$f" "raw/logs/$n.mask.png" -alpha off -compose copy_opacity -composite -compose over \
    -trim +repage -bordercolor none -border 4 "PNG32:cut/$n.png"
  echo "$n $(magick identify -format '%wx%h %[pixel:p{0,0}]' cut/$n.png) (keyed)"
done
