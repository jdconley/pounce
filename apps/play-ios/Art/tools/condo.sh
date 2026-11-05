#!/bin/bash
# condo.sh: cuts raw/condo-1..10.png (whichever exist; condo-10 is required) into cut/ on one shared
# frame, so the Cat Condo grows in place instead of jumping in size from stage to stage.
#  1. Key each stage off the flat gray background (from the corners, plus enclosed gaps), no trim,
#     eroding the fringe 2px.
#  2. Align on the cushion. condo-1..9 are edits of condo-10 (prompts.py) and the edits drift in
#     scale, but every stage has the same round cushion at the bottom: the widest part of the bottom
#     BAND pixels is measured, and each stage is scaled and moved so its cushion matches condo-10's.
#  3. Crop all stages to one square: the union of their boxes widened to a square, bottom-aligned
#     (the app stands the cats on the frame's bottom edge).
# Then: build-assets.sh condo-1 ... condo-10.
set -euo pipefail
ART="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ART"
FUZZ="${FUZZ:-7}"; BAND="${BAND:-60}"
L=raw/logs; mkdir -p cut "$L"
[ -f raw/condo-10.png ] || { echo "condo.sh: missing raw/condo-10.png (the whole condo sets the frame)" >&2; exit 66; }
stages=(); for n in 1 2 3 4 5 6 7 8 9 10; do [ -f "raw/condo-$n.png" ] && stages+=("$n"); done
sign() { [ "$1" -ge 0 ] && echo "+$1" || echo "$1"; }

# cushion <keyed.png>: "width centerX bottomY" of the bottom BAND rows of the subject.
cushion() {
  local box y1 w x
  box="$(magick "$1" -format '%@' info:)"                       # WxH+X+Y of the whole subject
  y1=$(awk -F'[x+]' '{print $4 + $2}' <<< "$box")
  read -r w x < <(magick "$1" -crop "x${BAND}+0+$((y1 - BAND))" +repage -format '%@' info: | awk -F'[x+]' '{print $1, $3}')
  echo "$w $((x + w / 2)) $y1"
}

for n in "${stages[@]}"; do
  f="raw/condo-$n.png"
  W=$(magick identify -format %w "$f"); H=$(magick identify -format %h "$f")
  # Also key the background gray everywhere (tight fuzz) for gaps the corners can't reach, like the
  # space between a platform and the hammock under it.
  bg=$(magick "$f" -format '%[pixel:p{2,2}]' info:)
  magick "$f" -alpha set -fuzz "$FUZZ%" -fill none \
    -draw "color 0,0 floodfill" -draw "color $((W-1)),0 floodfill" \
    -draw "color 0,$((H-1)) floodfill" -draw "color $((W-1)),$((H-1)) floodfill" \
    -fuzz "${GAPFUZZ:-4}%" -transparent "$bg" \
    -alpha extract -morphology Erode Disk:2 "$L/condo-$n.mask.png"
  magick "$f" "$L/condo-$n.mask.png" -alpha off -compose copy_opacity -composite "PNG32:$L/condo-$n.keyed.png"
done

read -r cw cx cy < <(cushion "$L/condo-10.keyed.png")
W=$(magick identify -format %w raw/condo-10.png); H=$(magick identify -format %h raw/condo-10.png)
boxes=()
for n in "${stages[@]}"; do
  read -r w x y < <(cushion "$L/condo-$n.keyed.png")
  s=$(awk -v a="$cw" -v b="$w" 'BEGIN{printf "%.5f", a / b}')
  ox=$(awk -v c="$cx" -v x="$x" -v s="$s" 'BEGIN{printf "%d", c - x * s}')
  oy=$(awk -v c="$cy" -v y="$y" -v s="$s" 'BEGIN{printf "%d", c - y * s}')
  magick -size "${W}x${H}" xc:none \( "$L/condo-$n.keyed.png" -resize "$(awk -v s="$s" 'BEGIN{printf "%.3f", s * 100}')%" \) \
    -geometry "$(sign "$ox")$(sign "$oy")" -composite "PNG32:$L/condo-$n.aligned.png"
  boxes+=("$(magick "$L/condo-$n.aligned.png" -format '%@' info:)")
  echo "condo-$n cushion ${w}px -> x$s"
done

read -r x0 y0 x1 y1 < <(printf '%s\n' "${boxes[@]}" | awk -F'[x+]' '
  { x=$3; y=$4; r=$3+$1; b=$4+$2
    if (NR==1 || x<x0) x0=x; if (NR==1 || y<y0) y0=y; if (NR==1 || r>x1) x1=r; if (NR==1 || b>y1) y1=b }
  END { print x0, y0, x1, y1 }')
side=$(( (x1 - x0) > (y1 - y0) ? (x1 - x0) : (y1 - y0) )); side=$((side + 16))
left=$(( (x0 + x1) / 2 - side / 2 )); top=$((y1 + 8 - side))
echo "condo frame: ${side}x${side}$(sign $left)$(sign $top)"
for n in "${stages[@]}"; do
  magick "$L/condo-$n.aligned.png" -background none -gravity northwest -extent "${side}x${side}$(sign "$left")$(sign "$top")" \
    "PNG32:cut/condo-$n.png"
done
echo "cut ${#stages[@]} condo stages"
