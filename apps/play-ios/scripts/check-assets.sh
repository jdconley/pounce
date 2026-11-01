#!/bin/bash
# Verifies that every Art/manifest.json name exists in the asset catalog (folder, valid
# Contents.json, and every PNG it references), that every sound exists, and that
# Pounce/Design/ArtName.swift mirrors the manifest. Exits 1 listing whatever is missing.
set -uo pipefail
cd "$(dirname "$0")/.."
MANIFEST=Art/manifest.json
CATALOG=Pounce/Resources/Assets.xcassets
SOUNDS=Pounce/Resources/Sounds
ARTNAME=Pounce/Design/ArtName.swift
SFX="pop flip bat thud nope sparkle whoosh scream leap fanfare tick"

command -v jq >/dev/null || { echo "check-assets: jq is required" >&2; exit 2; }
missing=()

while IFS=$'\t' read -r name dest; do
  case "$dest" in
    atlas:*) dir="$CATALOG/${dest#atlas:}.spriteatlas/$name.imageset" ;;
    imageset) dir="$CATALOG/$name.imageset" ;;
    appicon) dir="$CATALOG/AppIcon.appiconset" ;;
    *) missing+=("$name (bad dest '$dest')"); continue ;;
  esac
  if [ ! -f "$dir/Contents.json" ]; then missing+=("$name (no $dir/Contents.json)"); continue; fi
  files=$(jq -r '.images[]?.filename // empty' "$dir/Contents.json" 2>/dev/null) || { missing+=("$name (invalid Contents.json)"); continue; }
  [ -n "$files" ] || { missing+=("$name (Contents.json lists no images)"); continue; }
  while read -r f; do
    [ -f "$dir/$f" ] || missing+=("$name (missing file $f)")
  done <<< "$files"
  # ArtName.swift mirrors every name except the parametric cat sprites.
  case "$name" in
    cat[0-9]-*|AppIcon) ;;
    *) grep -q "\"$name\"" "$ARTNAME" || missing+=("$name (not in ArtName.swift)") ;;
  esac
done < <(jq -r '.[] | [.name, .dest] | @tsv' "$MANIFEST")

for s in $SFX; do
  [ -f "$SOUNDS/sfx-$s.caf" ] || missing+=("sfx-$s (no $SOUNDS/sfx-$s.caf)")
  grep -q "\"sfx-$s\"" "$ARTNAME" || missing+=("sfx-$s (not in ArtName.swift)")
done
for a in Cats Cards Table FX; do
  [ -f "$CATALOG/$a.spriteatlas/Contents.json" ] || missing+=("atlas $a (no Contents.json)")
done

if [ ${#missing[@]} -gt 0 ]; then
  echo "check-assets: ${#missing[@]} problem(s):" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi
echo "check-assets: OK ($(jq length "$MANIFEST") manifest entries, 11 sounds)"
