#!/bin/bash
# build-assets.sh <name>... | --all
# Turns cut PNGs (Art/cut/<name>.png, transparent, from cutout.swift) into catalog art:
# resized to @2x and @3x of the manifest point size, written with a Contents.json into the
# right .spriteatlas / .imageset / AppIcon.appiconset. Replaces any placeholder of that name.
#
# Manifest "fit": "contain" (default) scales to fit inside W x H and centers on a transparent
# canvas of exactly W x H pixels; "cover" fills W x H and crops the overflow (backgrounds).
# AppIcon is flattened onto the violet launch color and written with no alpha channel.
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
      if [ "$fit" = cover ]; then
        magick "$src" -resize "${W}x${H}^" -gravity center -background none -extent "${W}x${H}" -depth 8 "PNG32:$out"
      else
        magick "$src" -resize "${W}x${H}" -gravity center -background none -extent "${W}x${H}" -depth 8 "PNG32:$out"
      fi
    done
  fi
  write_contents "$name" ""
  echo "built $name -> ${dir#$PLAY_IOS/}"
done
exit $fail
