#!/bin/bash
# build-assets.sh <name>... | --all
# Turns cut PNGs (Art/cut/<name>.png, transparent, from cutout.swift) into catalog art:
# resized to @2x and @3x of the manifest point size, written with a Contents.json into the
# right .spriteatlas / .imageset / AppIcon.appiconset. Replaces any placeholder of that name.
#
# Manifest "fit": "contain" (default) scales to fit inside W x H and centers on a transparent
# canvas of exactly W x H pixels; "cover" fills W x H and crops the overflow (backgrounds).
# "fill" stretches to exactly W x H (card-face / card-back: <6% distortion so the card slot is full).
# Non-icon PNGs are palette-quantized with pngquant when installed (keeps the catalog small).
# AppIcon is flattened onto the violet launch color and written with no alpha channel.
#
# Consistent character scale. Cutouts are trimmed to their own bounding box, so scaling each one to
# fit independently would make a leap look smaller than a sit. Two groups share one scale instead:
#   cat<i>-<pose>   one factor per cat, 94% of the factor that fits that cat's idle sprite in the box,
#                   applied to all seven poses (a pose that still overflows is capped to fit), and
#                   bottom-aligned so every pose stands on the same baseline;
#   coat-*          one factor for the four faces, the smallest that fits any of them.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[ $# -ge 1 ] || { echo "usage: build-assets.sh <name>... | --all" >&2; exit 64; }

names=()
if [ "$1" = "--all" ]; then
  while read -r n; do [ -f "$CUT_DIR/$n.png" ] && names+=("$n"); done < <(manifest_names)
  [ ${#names[@]} -gt 0 ] || { echo "no cut PNGs in $CUT_DIR" >&2; exit 0; }
else
  names=("$@")
fi

# group_scale <name> <W> <H>: prints the shared source->target scale factor for names in a scale
# group, or nothing for ungrouped names. W x H is the target canvas in pixels.
group_scale() {
  local name="$1" W="$2" H="$3" refs=() mode ref
  case "$name" in
    cat[0-9]-*) refs=("$CUT_DIR/${name%%-*}-idle.png"); mode=idle ;;
    coat-*) refs=("$CUT_DIR"/coat-*.png); mode=min ;;
    *) return 0 ;;
  esac
  for ref in "${refs[@]}"; do [ -f "$ref" ] || return 0; done
  for ref in "${refs[@]}"; do magick identify -format '%w %h\n' "$ref"; done |
    awk -v W="$W" -v H="$H" -v mode="$mode" '
      { s = W / $1; t = H / $2; if (t < s) s = t; if (best == "" || s < best) best = s }
      END { if (mode == "idle") best *= 0.94; printf "%.6f", best }'
}

fail=0
for name in "${names[@]}"; do
  src="$CUT_DIR/$name.png"
  if [ -z "$(entry_field "$name" .name)" ]; then echo "error: '$name' is not in manifest.json" >&2; fail=1; continue; fi
  if [ ! -f "$src" ]; then echo "error: no cut art at $src" >&2; fail=1; continue; fi
  dir="$(entry_dir "$name")"
  dest="$(entry_field "$name" .dest)"
  fit="$(entry_field "$name" '.fit // "contain"')"
  read -r pw ph < <(point_size "$name")
  ensure_atlas_container "$name"
  mkdir -p "$dir"
  clear_images "$dir"
  if [ "$dest" = appicon ]; then
    magick "$src" -resize "1024x1024^" -gravity center -extent 1024x1024 \
      -background "#7B2FF7" -alpha remove -alpha off -depth 8 "PNG24:$dir/AppIcon.png"
  else
    for scale in 2 3; do
      W=$((pw * scale)); H=$((ph * scale)); out="$dir/${name}@${scale}x.png"
      gs="$(group_scale "$name" "$W" "$H")"
      if [ -n "$gs" ]; then
        read -r sw sh < <(magick identify -format '%w %h\n' "$src")
        # Never larger than the box, whatever the shared factor says.
        read -r nw nh < <(awk -v w="$sw" -v h="$sh" -v g="$gs" -v W="$W" -v H="$H" 'BEGIN {
          s = g; if (w * s > W) s = W / w; if (h * s > H) s = H / h;
          printf "%d %d\n", int(w * s + 0.5), int(h * s + 0.5) }')
        grav=center; case "$name" in cat*) grav=south ;; esac
        magick "$src" -resize "${nw}x${nh}!" -gravity "$grav" -background none -extent "${W}x${H}" -depth 8 "PNG32:$out"
      elif [ "$fit" = fill ]; then
        magick "$src" -resize "${W}x${H}!" -depth 8 "PNG32:$out"
      elif [ "$fit" = cover ]; then
        magick "$src" -resize "${W}x${H}^" -gravity center -background none -extent "${W}x${H}" -depth 8 "PNG32:$out"
      else
        magick "$src" -resize "${W}x${H}" -gravity center -background none -extent "${W}x${H}" -depth 8 "PNG32:$out"
      fi
      # 8-bit palette + alpha, ~3-4x smaller with no visible change on this flat glossy art. The
      # AppIcon above stays a full-colour 24-bit PNG. Skipped (files stay as written) without pngquant.
      if command -v pngquant >/dev/null; then pngquant --quality 40-95 --speed 1 --strip --force --output "$out" -- "$out" || true; fi
    done
  fi
  write_contents "$name" ""
  echo "built $name -> ${dir#$PLAY_IOS/}"
done
exit $fail
