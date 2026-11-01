#!/bin/bash
# run.sh <jobs.txt>: each line "name [ref.png]"; runs gen.sh 4-wide on prompts/<batch>/<name>.txt into raw/<name>.png;
# keeps a previous take as raw/old/<name>.vN.png. Logs go to raw/logs/ (mkdir -p raw/logs raw/old first).
ART="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ART"
one() {
  name="$1"; ref="$2"; out="raw/$name.png"
  if [ -f "$out" ]; then n=1; while [ -f "raw/old/$name.v$n.png" ]; do n=$((n+1)); done; mkdir -p raw/old; mv "$out" "raw/old/$name.v$n.png"; fi
  start=$(date +%s)
  if tools/gen.sh "$(ls prompts/*/"$name".txt | head -1)" "$out" $ref > "raw/logs/$name.log" 2>&1; then r=ok; else r=FAIL; fi
  echo "$(date +%H:%M:%S) $name $r $(( $(date +%s)-start ))s"
}
export -f one
grep -v '^\s*$' "$1" | xargs -P4 -L1 bash -c 'one "$0" "$1"'
