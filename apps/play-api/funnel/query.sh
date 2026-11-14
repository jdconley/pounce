#!/bin/bash
# Runs saved funnel queries (funnel/queries.sql) on the funnel database and prints their rows.
# Usage: funnel/query.sh [name ...] [--local]
#   No name: every query. --local: the dev server's copy (.wrangler/state) instead of production.
# Wrangler must be signed in to the Cloudflare account for production (pnpm exec wrangler login).
set -euo pipefail
cd "$(dirname "$0")/.."
where=--remote
names=()
for arg in "$@"; do
  case "$arg" in
    --local) where=--local ;;
    --remote) where=--remote ;;
    *) names+=("$arg") ;;
  esac
done
all=$(sed -n 's/^-- name: //p' funnel/queries.sql)
[ ${#names[@]} -gt 0 ] || read -r -a names <<< "$(echo $all)"
# Wrangler's JSON answer as an aligned table.
TABLE='
let input = "";
process.stdin.on("data", (d) => (input += d)).on("end", () => {
  const rows = JSON.parse(input)[0]?.results ?? [];
  if (rows.length === 0) return console.log("(no rows)\n");
  const cols = Object.keys(rows[0]);
  const cell = (v) => (v === null ? "" : String(v));
  const width = cols.map((c) => Math.max(c.length, ...rows.map((r) => cell(r[c]).length)));
  const line = (vals) => vals.map((v, i) => v.padEnd(width[i])).join("  ").trimEnd();
  console.log([line(cols), line(width.map((w) => "-".repeat(w))), ...rows.map((r) => line(cols.map((c) => cell(r[c]))))].join("\n") + "\n");
});'
for name in "${names[@]}"; do
  sql=$(awk -v n="$name" '/^-- name: /{on = ($3 == n); next} on' funnel/queries.sql | grep -v '^--' || true)
  if [ -z "$sql" ]; then
    echo "No query named $name. Names: $(echo $all)" >&2
    exit 1
  fi
  echo "== $name"
  pnpm exec wrangler d1 execute conleychaos-play-funnel "$where" --json --command "$sql" | node -e "$TABLE"
done
