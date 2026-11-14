# First-run funnel: new players and invited players

## Goal

Get as many people as possible playing a game with their family, and enjoying it, as fast as
possible. Pounce brings people together: a family in the living room each on their own phone,
parents with grown kids who live far away, teenagers up in their bedrooms. The "aha" is a first
game with your people, not a solo tutorial.

Measure of success: time and taps from first launch (or from tapping an invite) to the first
card played, and how many people reach a game with another human. JD's standing UI rules apply
(`AGENTS.md`): redesign whole screens, terse copy (labels 1-3 words, messages one short
sentence), fit iPhone SE, a large iPhone, iPad both orientations and the largest text size,
teach with tips, no emoji, before/after screenshots.

## Where we are (walked on 2026-11-13)

Screens: `apps/play-ios/Art/screenshots/first-run/before-*.png`. Re-run any time with
`apps/play-ios/scripts/funnel-shots.sh` (`FunnelShotTests`). Research with sources:
`docs/research/2026-11-13-onboarding-research.md`.

- New player: age check, then name (keyboard up, covering the cats; empty name only wiggles;
  typed names wait up to 3 s on the filter), then Home with two posters and three tips in a row
  (Practice is cut off behind the dock on a 17 Pro). Play on a poster opens a lobby where you sit
  alone: "Needs 2 players.", Start greyed out. The fastest real path is the Practice pill.
  Pass and play is two taps deep in "Add a player".
- Invited, app installed: age and name screens say nothing about the invite; the lobby the guest
  lands in leads with the host's code and share buttons.
- Invited, app not installed: the web page says "Install Pounce, then tap this link again"; the
  invite is lost through the install. Share text says "Cat Tower" even for Tuna Tiles.
- Join: a wrong code just shakes, no words. Full table: "No open seat." with only Home.
- No analytics at all.

## The three parts (approved by JD 2026-11-13)

### Part 1: first game in under a minute (iOS)
- Play on a game poster opens a lobby that is ready to play. Empty seats offer the ways people
  actually play together, right on the rug rather than in a menu:
  - people in the same room each on their own phone (scan the QR / nearby code),
  - far-away family (send the invite through Messages),
  - someone sharing this phone (pass and play),
  - a House Cat.
  A first-time host gets a House Cat in the first open seat so Start is lit; a person joining
  takes that seat over (or another one). The designer decides the exact layout.
- Home's first visit: one tip, not three in a row; Practice reachable, never under the dock.
- Name screen: a cat and a suggested name already chosen so the check works in one tap; typing
  your own name is one tap away; the keyboard never covers the cats; the name filter never
  blocks the screen.
- Invited guests see who invited them: on the name screen after the age check ("Grandma saved
  you a seat" with her cat, from a peek at the room) and a guest's lobby that shows the table
  and its people, not the host's sharing controls.

### Part 2: invites that survive the install (web + server + iOS plumbing)
- Web page for `/j/<code>` and `/p/<token>`: who invited you, which game and table, one big
  button. The button copies the invite link to the clipboard and then opens the store. Short copy.
  Per-table Open Graph title and image for the Messages preview (server-rendered). Smart App
  Banner wired to `APP_STORE_URL` so it turns on when 1.0 ships.
- iOS: on first launch (and on Join), when the pasteboard holds a likely URL
  (`detectPatterns`, no prompt), offer a "Paste invite" control (system paste control, no "Allow
  paste?" alert) that opens that table. Codes typed on Join keep working.
- Share text and titles name the table's real game. Join explains a wrong code in words. A full
  table offers a way forward.

### Part 3: funnel data on our own server
- Each device gets an anonymous id (not linked to the person, no third parties). The server
  records when that device first reached each milestone, so we can query a database: installed
  and launched, age done, named, Home seen, first table created, invite sent, invite opened
  (web and app), joined a table, first move, first game finished, first game with another human,
  push answered, and day-1/day-7 return. Store the source (organic, `/j` link, `/p` link,
  pasted invite) and the game.
- Update the privacy page and the App Store privacy answers to match. JD approved using backend
  data for analytics on 2026-11-13.

## Who owns what (parallel sessions; avoid each other's files)

| Part | Owns | Must not edit |
| --- | --- | --- |
| 1 | `PickCatView`, `LobbyView`, `HomeView`, `Tips.swift`, `UITips`, `LobbyPlan`, `CoachMark`, lobby/home tests | `play-api/`, `JoinView`, `ShareRoom`, deep-link handling |
| 2 | `play-api/src/http/links.ts` and invite pages, `ShareRoom`, `JoinView`, `CodeKeypad`, deep-link and paste handling in `AppModel`, `pounces.ts` game choice | the screens Part 1 owns, except one small overlay hook in `HomeView` for "Paste invite" |
| 3 | new funnel tables and endpoint in `play-api`, `privacy.ts`, a `Funnel` reporter in `PounceKit`, one-line milestone calls | screen layouts |

Each part lands as its own PR with auto-merge, rebased onto main; whoever merges second resolves
conflicts. Each uses its own simulator and dev-server port.
