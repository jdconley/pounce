#!/bin/bash
# sheet.sh <out-name> <cols> <name>... : labeled contact sheet of raw/<name>.png into raw/sheets/
ART="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ART/raw"
out="$1"; cols="$2"; shift 2; files=()
for n in "$@"; do [ -f "$n.png" ] && files+=(-label "$n" "$n.png"); done
magick montage "${files[@]}" -tile ${cols}x -geometry 300x300+6+6 -pointsize 18 -background "#ffffff" "sheets/$out.png"
echo "sheets/$out.png"
