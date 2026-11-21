# The Daily Dish: build plan and split into sessions

> **For agentic workers:** this is the map. Each session writes or follows its own detailed plan
> (superpowers:writing-plans, then superpowers:subagent-driven-development or executing-plans).
> The server core's plan is already written: `2026-11-20-daily-games-1-server.md`.

**Goal:** four daily puzzles, a family board, streaks that count them, and a live board on the TV,
on every platform, all turned on in production at once.

**Spec:** `docs/superpowers/specs/2026-11-20-daily-games-design.md`. Every session reads it first,
with `AGENTS.md` and `docs/main-thread.md`.

## Global constraints (every session)

- **`PROTOCOL_VERSION` stays 1.** Changes are additive only.
- **`DAILY` stays off in production** until the launch session. Test against your own local dev
  server with `DAILY=on`, on a port of your own (below), never `:8787` or `:4343`.
- **The main thread draws, nothing else.**
  - Rule checks, network calls, decoding and image renders run off the main thread.
  - Hang and frame-budget gates hold on every new screen.
  - Each PR reports frame-rate results.
- **Original art and names only.** Copy only rule sets.
  - No Wordle, NYT, Block Blast or Zoodoku names, words, colors, sounds or layouts.
  - Pounce's art style is loud and cartoony, never beige or muted.
- **UI copy:**
  - one to three words on buttons, one short sentence for messages;
  - no emoji;
  - teach with the tip system.
  - Redesign the whole screen a change lands on.
- **Screenshots:** every UI PR carries before and after shots of each screen it touches, on:
  - iPhone SE and a large iPhone;
  - iPad, portrait and landscape;
  - the largest accessibility text size;
  - 1080p for TV screens.
- **Simulators:**
  - Use your own simulator and shut it down when done.
  - Never touch JD's phone.
- **Credentials:** never handle them. Anything needing a secret or an Apple account change goes to
  the lead session.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. PR bodies end
  with the Claude Code line.
- **App PR titles** are plain words a family member can read.
- **Don't merge.** Open the PR, get CI green, and report. The manager merges.

## Who owns which files

No two sessions write the same file. One-line additions to a registry are listed with the session
that owns that line.

| Session | Owns |
|---|---|
| **S1 server core** | `apps/play-api/src/daily/*.ts`, which is the root of that folder and not the game folders; the daily parts of `players/player.ts`, `streaks/*`, `notify/*`, `screens/*`, `index.ts`, `env.ts`, `wrangler.jsonc`; `tests/daily*.ts`; `fixtures/daily/protocol/`; `docs/daily-protocol.md`; the privacy text |
| **G1 Nine Lives** | `apps/play-api/src/daily/nine-lives/`; `fixtures/daily/nine-lives/`; `PounceKit/Sources/PounceKit/Daily/NineLives/` and its tests; `Pounce/Daily/NineLives/`; `apps/play-web/src/daily/nine-lives/`; its art and sounds; one line in each registry |
| **G2 Box Fort** | the same pattern, `box-fort` / `BoxFort` |
| **G3 Sniff** | the same pattern, `sniff` / `Sniff`, plus the word lists and their build script under `apps/play-api/src/daily/sniff/words/` |
| **G4 Cat Nap** | the same pattern, `cat-nap` / `CatNap` |
| **H1 the Dish in the app** | `PounceKit/Sources/PounceKit/Daily/*.swift` (root only: `DailyClient`, `DailyWire`, `DailyCatalog` (the Swift registry), `DailyBoardSocket`); `Pounce/Daily/*.swift` (root only: the Dish screen, board, stats, share, the puzzle-screen host); `HomeView.swift` and the Home redesign; tips |
| **H2 the Dish on the web** | `apps/play-web/src/daily/*.ts(x)` (root only: client, registry, board socket, Dish, board, stats, share, the puzzle host); `home.tsx` and the web home's redesign; its e2e tests |
| **T1 the TV board** | `PounceTV/Shell/` board and watch screens; `apps/play-web/src/ui/tv/` board and watch; the TV's home poster on both |
| **L1 launch** | the cross-platform check, `DAILY: "on"`, `LAUNCH` in `src/daily/days.ts`, What's New, the README, and the websites per `AGENTS.md` |

## The contracts that let sessions run side by side

1. **The server's game module:** `DailyModule` in `apps/play-api/src/daily/module.ts`, exactly as
   in the server plan's Task 3. A game session writes `src/daily/<game>/module.ts` exporting
   `const <game>: DailyModule<P, S, M>`, then adds one line to `src/daily/games.ts` once S1 has
   merged.
2. **The puzzle-screen contract (H1, H2).** H1 and H2 each define, in their first commit and before
   anything else, a host that runs any game:
   - **iOS:**
     - a `DailyGameView` protocol in `Pounce/Daily/DailyGameHost.swift`, built from a
       `DailyRunSession`;
     - the `DailyRunSession` actor in PounceKit `DailyClient.swift` exposes the start answer,
       `send(move:)`, `hint()`, `giveUp()`, the authoritative answers as an `AsyncStream`, and the
       server clock;
     - each game provides a `DailyGameView` plus a read-only `DailyWatchView` (for the TV), drawn
       from `publicState`.
   - **Web:** the same, as `DailyGameScreen` and `DailyWatchView` components taking a `RunSession`,
     in `apps/play-web/src/daily/host.tsx`.
   - The host draws the top bar, the clock, Show on TV, give up, the end screen and share. A game
     draws only its board and controls.
3. **Rules in two languages.**
   - TS rules are the truth. Each game's TS writes its golden vectors to
     `apps/play-api/fixtures/daily/<game>/`.
   - The Swift rules in `PounceKit/Daily/<Game>/` must pass every vector, read by path as
     `PounceKitTests/Fixtures.swift` does.
   - Sniff's marks are worked out only on the server. Its Swift side needs only the allowed-guess
     list check.

## Order

```
now:            S1 server core        G1  G2  G3  G4  (phase A: rules, puzzle maker, solver/grader,
                                                       vectors, Swift rules, the game's views driven
                                                       by a local state, no network)
S1 merged:      H1 app Dish           H2 web Dish     (games keep going on phase A)
H1, H2 merged:  G1..G4 phase B: the server module line, the host hookup, UI and e2e tests, then
                each game's PR
games merged:   T1 TV board and watching
T1 merged:      L1 launch
```

Each game session ends in one PR: its server module, rules, vectors, Swift rules, iPhone and iPad
screen, web screen and watch views. It pauses after phase A and is told by the lead when H1 and H2
have merged.

## Each session's done

- **S1:** the server plan's Task 11 PR, green.
- **G1 to G4:**
  - The puzzle maker is deterministic for a seed, with a property test over a year of dates.
  - Nine Lives and Cat Nap always have exactly one solution, and the weekday grades hold.
  - Every vector passes in TS and Swift.
  - The puzzle plays to the end in an iPhone UI test and a web Playwright test against a local
    server.
  - Frame gates pass, with screenshots, and the PR is green.
- **H1 and H2:**
  - Home redesigned with the Dish.
  - The Dish screen, board (overall and per game), stats, share card and tips.
  - The host plays the server's test game (`DAILY_TEST=on`) end to end.
  - Screenshots, frame gates, and the PR green.
- **T1:**
  - Link a board from a phone, and the board updates live.
  - The watch card and watching each game.
  - Apple TV simulator and the browser TV at 1080p, with frame gates and screenshots.
- **L1:**
  - The cross-platform check: iPhone, browser, Apple TV and browser TV show the same puzzle, and
    the same moves give the same score.
  - A forged result is refused.
  - Then `DAILY` goes on, and the websites are updated ("in the browser now, coming to the app"
    until the App Store version).

## Local dev server ports

Each session runs its own `wrangler dev`:

| Session | Port |
|---|---|
| S1 | 8801 |
| G1 | 8802 |
| G2 | 8803 |
| G3 | 8804 |
| G4 | 8805 |
| H1 | 8806 |
| H2 | 8807 |
| T1 | 8808 |
| L1 | 8809 |
