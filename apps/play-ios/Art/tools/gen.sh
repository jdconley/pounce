#!/bin/bash
# gen.sh <prompt.txt> <out.png> [ref.png...]
# Generates one image with the Codex CLI, using the chosen style sample (and any extra
# reference images) as visual input. The PNG lands at <out.png> (conventionally under
# Art/raw/, which is gitignored). Fails if the file doesn't appear.
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: gen.sh <prompt.txt> <out.png> [ref.png...]" >&2
  exit 64
fi

ART="$(cd "$(dirname "$0")/.." && pwd)"
STYLE="$ART/style-samples/chosen-d-loud-toy.png"
prompt="$1"; out="$2"; shift 2

[ -f "$prompt" ] || { echo "gen.sh: prompt file not found: $prompt" >&2; exit 66; }
[ -f "$STYLE" ] || { echo "gen.sh: style sample missing: $STYLE" >&2; exit 66; }
command -v codex >/dev/null || { echo "gen.sh: codex CLI not found" >&2; exit 69; }

mkdir -p "$(dirname "$out")"
abs_out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
rm -f "$abs_out"

images=(-i "$STYLE")
for ref in "$@"; do
  [ -f "$ref" ] || { echo "gen.sh: reference image not found: $ref" >&2; exit 66; }
  images+=(-i "$ref")
done

{
  cat "$prompt"
  printf '\n\nSave the PNG as %s\n' "$abs_out"
} | codex exec --skip-git-repo-check -s workspace-write "${images[@]}" -- -

if [ ! -s "$abs_out" ]; then
  echo "gen.sh: codex finished but $abs_out was not created" >&2
  exit 1
fi
echo "$abs_out"
