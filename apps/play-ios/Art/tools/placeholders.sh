#!/bin/bash
# Renders placeholder art for every manifest entry that has no real art yet, at @2x/@3x
# of its point size, so the app builds and lays out with final sizes. Real art later
# replaces these by name (build-assets.sh). Placeholder files carry a "_ph" suffix in
# the imageset; that suffix is how "still a placeholder" is tracked.
#
#   placeholders.sh              render placeholders for entries without real art
#   placeholders.sh --force      re-render every placeholder (never touches real art)
#   placeholders.sh --report     list entries still on placeholders, then a count line
#   placeholders.sh --count      print just the number of placeholders remaining
set -euo pipefail
source "$(dirname "$0")/lib.sh"

mode="render"; force=0
for a in "$@"; do
  case "$a" in
    --report) mode=report ;;
    --count) mode=count ;;
    --force) force=1 ;;
    *) echo "usage: placeholders.sh [--force|--report|--count]" >&2; exit 64 ;;
  esac
done

if [ "$mode" != render ]; then
  n=0
  while read -r name; do
    if is_placeholder "$name"; then
      n=$((n + 1))
      [ "$mode" = report ] && echo "$name"
    fi
  done < <(manifest_names)
  if [ "$mode" = report ]; then echo "placeholders remaining: $n"; else echo "$n"; fi
  exit 0
fi

# render <name> <scale> <dir>: draw one placeholder PNG (white paw cue on a palette-colored,
# thick-ink-outlined rounded rect; AppIcon is a flat 1024 square with no alpha).
render() {
  local name="$1" scale="$2" dir="$3" suffix="_ph"
  read -r pw ph < <(point_size "$name")
  local W=$((pw * scale)) H=$((ph * scale))
  local sum; sum=$(printf '%s' "$name" | cksum | cut -d' ' -f1)
  local color="${PALETTE[$((sum % 6))]}"
  local dest; dest="$(entry_field "$name" .dest)"
  local out="$dir/${name}${suffix}@${scale}x.png"
  [ "$(entry_field "$name" .dest)" = appicon ] && out="$dir/AppIcon${suffix}.png"
  local label="$name"
  local draw
  draw=$(awk -v W="$W" -v H="$H" 'BEGIN{
    m=(W<H)?W:H; sw=m*0.06; if(sw<2)sw=2; r=m*0.22; if(r>m*0.3)r=m*0.3
    printf "roundrectangle %.1f,%.1f %.1f,%.1f %.1f,%.1f", sw/2,sw/2,W-sw/2-1,H-sw/2-1,r,r
  }')
  local sw; sw=$(awk -v W="$W" -v H="$H" 'BEGIN{m=(W<H)?W:H; s=m*0.06; if(s<2)s=2; printf "%.1f", s}')
  # Paw cue: pad + four toes, sized to the shorter side, centered a little above middle.
  local paw
  paw=$(awk -v W="$W" -v H="$H" 'BEGIN{
    m=(W<H)?W:H; cx=W/2; cy=H*0.46;
    s=m*0.9; if(s>400)s=400
    printf "ellipse %.1f,%.1f %.1f,%.1f 0,360 ", cx, cy+s*0.10, s*0.20, s*0.15
    printf "ellipse %.1f,%.1f %.1f,%.1f 0,360 ", cx-s*0.23, cy-s*0.07, s*0.07, s*0.09
    printf "ellipse %.1f,%.1f %.1f,%.1f 0,360 ", cx-s*0.08, cy-s*0.19, s*0.07, s*0.09
    printf "ellipse %.1f,%.1f %.1f,%.1f 0,360 ", cx+s*0.08, cy-s*0.19, s*0.07, s*0.09
    printf "ellipse %.1f,%.1f %.1f,%.1f 0,360", cx+s*0.23, cy-s*0.07, s*0.07, s*0.09
  }')
  if [ "$dest" = appicon ]; then
    magick -size "${W}x${H}" "xc:${PALETTE[0]}" \
      -fill "${PALETTE[1]}" -stroke "$INK" -strokewidth "$(awk -v W=$W 'BEGIN{printf "%.1f", W*0.03}')" \
      -draw "circle $((W/2)),$((H/2)) $((W/2)),$((H/8))" \
      -fill white -stroke "$INK" -strokewidth "$(awk -v W=$W 'BEGIN{printf "%.1f", W*0.012}')" -draw "$(awk -v W="$W" -v H="$H" 'BEGIN{
        cx=W/2; cy=H/2; s=W*0.6
        printf "ellipse %.1f,%.1f %.1f,%.1f 0,360 ", cx, cy+s*0.12, s*0.22, s*0.17
        printf "ellipse %.1f,%.1f %.1f,%.1f 0,360 ", cx-s*0.27, cy-s*0.06, s*0.08, s*0.10
        printf "ellipse %.1f,%.1f %.1f,%.1f 0,360 ", cx-s*0.09, cy-s*0.21, s*0.08, s*0.10
        printf "ellipse %.1f,%.1f %.1f,%.1f 0,360 ", cx+s*0.09, cy-s*0.21, s*0.08, s*0.10
        printf "ellipse %.1f,%.1f %.1f,%.1f 0,360", cx+s*0.27, cy-s*0.06, s*0.08, s*0.10
      }')" -alpha off -depth 8 "PNG24:$out"
    return
  fi
  local m=$(( W < H ? W : H ))
  local args=(-size "${W}x${H}" xc:none
    -fill "$color" -stroke "$INK" -strokewidth "$sw" -draw "$draw"
    -fill white -stroke "$INK" -strokewidth "$(awk -v m=$m 'BEGIN{s=m*0.015; if(s<1)s=1; printf "%.1f", s}')" -draw "$paw")
  # Tiny label only on entries big enough to carry one (placeholders are temporary).
  if [ "$m" -ge $((80 * scale / 2)) ]; then
    local ps; ps=$(awk -v m="$m" 'BEGIN{p=m*0.07; if(p>40)p=40; if(p<12)p=12; printf "%d", p}')
    args+=(-font Helvetica-Bold -pointsize "$ps" -fill white -stroke "$INK" -strokewidth 1
           -gravity south -annotate "+0+$(awk -v sw="$sw" 'BEGIN{printf "%d", sw*1.8}')" "$label")
  fi
  magick "${args[@]}" -depth 8 "PNG32:$out"
}

count=0
while read -r name; do
  dir="$(entry_dir "$name")"
  if [ -f "$dir/Contents.json" ]; then
    is_placeholder "$name" || continue        # real art is never overwritten
    [ "$force" -eq 1 ] || continue            # placeholder already rendered
  fi
  ensure_atlas_container "$name"
  mkdir -p "$dir"
  clear_images "$dir"
  if [ "$(entry_field "$name" .dest)" = appicon ]; then
    render "$name" 1 "$dir"
  else
    render "$name" 2 "$dir"
    render "$name" 3 "$dir"
  fi
  write_contents "$name" "_ph"
  count=$((count + 1))
done < <(manifest_names)
echo "placeholders rendered: $count"
