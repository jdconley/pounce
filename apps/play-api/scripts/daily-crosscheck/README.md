# The Daily Dish cross-platform check

Proves, against a real local Worker, that the iPhone app, the web player and plain HTTP get the
same puzzle for the same game and date, that the same moves give the same result, and that the
server refuses cheating. Run it before a daily game launches or its rules change.

| File | What it does |
| --- | --- |
| `plan.ts` | From the server's `TOKEN_SECRET` and a date, using the server's own game modules: each game's public puzzle and its hash, one fixed move list (Nine Lives and Cat Nap from the solution, Sniff two guesses and the answer, Box Fort the plain greedy player), its pace past the game's floor, and the result the server must give. |
| `proxy.mjs` | A logging proxy in front of `wrangler dev`. Every client talks to it; it writes each `/v1/daily` request and answer, and which client sent it, as JSON lines. |
| `api.mjs` | Plays a plan over plain HTTP (`play`), with a forged result in every batch, and runs the anti-cheat probes (`cheat`). Nine Lives starts on its `"lives"` rules, as today's apps do, and its `cheat` run also checks three free hints, no fourth, and that a start without them keeps the first rules. |
| `analyze.py` | Rebuilds each finished run from the log: client, date, puzzle hash, accepted moves and reveals (hashed), and the server's result, checked against the plan. |
| `apps/play-ios/PounceUITests/DailyCrossCheckTests.swift` | The iPhone app plays the plan through its own controls. Skipped without `CROSSCHECK_PLAN`. |
| `apps/play-web/e2e/daily-crosscheck.spec.ts` | The web player does the same. No tests without `CROSSCHECK_PLAN`. |

## Run it

Pick a free port pair (never 8787 or 4343). The date is the server's day for the clients'
time zone (America/New_York in `api.mjs`; the simulator and Playwright use the Mac's).

```bash
SECRET=$(openssl rand -hex 32); OUT=$(mktemp -d)
pnpm --filter @pounce/play-web build
node apps/play-web/e2e/dev-server.mjs pnpm --dir apps/play-api exec wrangler dev --port 8809 --ip 127.0.0.1 \
  --persist-to "$OUT/state" --var TOKEN_SECRET:$SECRET --var GAMES:tiles --var LINK:on --var TV:on --var DAILY:on &
node apps/play-api/scripts/daily-crosscheck/proxy.mjs 8819 8809 "$OUT/log.jsonl" &
pnpm -s --filter @pounce/play-api crosscheck:plan $SECRET $(TZ=America/New_York date +%F) > "$OUT/plan.json"
```

Then, all pointed at the proxy on 8819:

```bash
for g in nine-lives box-fort sniff cat-nap; do
  node apps/play-api/scripts/daily-crosscheck/api.mjs play "$OUT/plan.json" $g
  node apps/play-api/scripts/daily-crosscheck/api.mjs cheat "$OUT/plan.json" $g
done
(cd apps/play-web && E2E_BASE=http://127.0.0.1:8819 CROSSCHECK_PLAN="$OUT/plan.json" \
  pnpm exec playwright test e2e/daily-crosscheck.spec.ts --project laptop-chrome)
(cd apps/play-ios && TEST_RUNNER_CROSSCHECK_PLAN="$OUT/plan.json" TEST_RUNNER_POUNCE_API_BASE_URL=http://localhost:8819 \
  xcodebuild test -project Pounce.xcodeproj -scheme Pounce -destination 'platform=iOS Simulator,id=<udid>' \
  -only-testing:PounceUITests/DailyCrossCheckTests)
python3 apps/play-api/scripts/daily-crosscheck/analyze.py "$OUT/log.jsonl" "$OUT/plan.json"
```

Mute the simulator first (`AGENTS.md`, Testing on this Mac). Every row `analyze.py` prints should
say `"pass": true`, with the same puzzle, moves and reveals hashes for a game on every client. The
times differ: they are the server's clock from start to the last move. Each `cheat` line should
say `"pass": true` too.
