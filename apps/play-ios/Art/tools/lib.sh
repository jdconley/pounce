# Shared helpers for the art tools. Source this file; do not execute it.
# Paths are derived from this file's location: apps/play-ios/Art/tools/lib.sh.
PLAY_IOS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$PLAY_IOS/Art/manifest.json"
CATALOG="$PLAY_IOS/Pounce/Resources/Assets.xcassets"
CUT_DIR="$PLAY_IOS/Art/cut"
RAW_DIR="$PLAY_IOS/Art/raw"
INK="#1B0B3A"
# Palette: violet, hot magenta, electric teal, sunny orange, sky blue, lime.
PALETTE=("#7B2FF7" "#FF2BD6" "#12E0D0" "#FF8A00" "#2EA8FF" "#8BE000")

command -v jq >/dev/null || { echo "jq is required (brew install jq)" >&2; exit 2; }
command -v magick >/dev/null || { echo "ImageMagick 7 (magick) is required" >&2; exit 2; }

# manifest_names: every manifest entry name, one per line.
manifest_names() { jq -r '.[].name' "$MANIFEST"; }

# entry_field <name> <jq-expr-on-entry>
entry_field() { jq -r --arg n "$1" ".[] | select(.name==\$n) | $2" "$MANIFEST"; }

# entry_dir <name>: the catalog folder that holds this entry.
entry_dir() {
  local dest; dest="$(entry_field "$1" .dest)"
  [ -n "$dest" ] || { echo "unknown manifest name: $1" >&2; return 1; }
  case "$dest" in
    atlas:*) echo "$CATALOG/${dest#atlas:}.spriteatlas/$1.imageset" ;;
    imageset) echo "$CATALOG/$1.imageset" ;;
    appicon) echo "$CATALOG/AppIcon.appiconset" ;;
    *) echo "bad dest '$dest' for $1" >&2; return 1 ;;
  esac
}

# ensure_atlas_container <name>: write the .spriteatlas Contents.json if needed.
ensure_atlas_container() {
  local dest; dest="$(entry_field "$1" .dest)"
  case "$dest" in
    atlas:*)
      local d="$CATALOG/${dest#atlas:}.spriteatlas"
      mkdir -p "$d"
      [ -f "$d/Contents.json" ] || printf '{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' > "$d/Contents.json"
      ;;
  esac
}

# point_size <name>: "W H"
point_size() { entry_field "$1" '.points | "\(.[0]) \(.[1])"'; }

# write_contents <name> <suffix>: Contents.json for the entry. suffix is "" for real
# art and "_ph" for placeholders (the _ph filename is the placeholder marker).
write_contents() {
  local name="$1" suffix="$2" dir dest; dir="$(entry_dir "$name")"; dest="$(entry_field "$name" .dest)"
  if [ "$dest" = appicon ]; then
    cat > "$dir/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "AppIcon${suffix}.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  else
    cat > "$dir/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "${name}${suffix}@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "${name}${suffix}@3x.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  fi
}

# is_placeholder <name>: true when the entry has no art or only placeholder art.
is_placeholder() {
  local dir; dir="$(entry_dir "$1")" || return 0
  [ -f "$dir/Contents.json" ] || return 0
  grep -q '_ph' "$dir/Contents.json"
}

# clear_images <dir>: remove png files from an entry folder (keeps Contents.json).
clear_images() { find "$1" -maxdepth 1 -name '*.png' -delete 2>/dev/null || true; }
