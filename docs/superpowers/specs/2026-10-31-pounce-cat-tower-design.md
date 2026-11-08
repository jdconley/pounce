# Pounce + Cat Tower — Design

Date: 2026-10-31 · Owner: JD Conley (Conley Chaos LLC) · Status: draft for approval · Lives in `github.com/jdconley/pounce`

"Pounce" is a code name. Marks below: **(JD)** = decided by JD in conversation; **(call)** = builder/designer call made while writing this, open to override.

## 1. What this is and why

A native iOS app of small games for **couples** to play together, also usable by families or any group. It's a collection; the first game is **Cat Tower**, which plays by the exact rules of the classic 10-phase rummy game but with fully original theme, names, and art. **(JD)**

The point is shared play that feels alive: bright, chunky, juicy cartoon feel in the spirit of Bloons TD6 (satisfying pops, bounces, bursts on every action), but low CPU and battery. **(JD)**

**Success for v1:** JD, their partner, and family are playing Cat Tower via **TestFlight**, mixing same-couch, same-room, and across-the-world players in one game, and it feels delightful and obvious to use. **(JD)**

## 2. Goals, non-goals, anti-goals

**Goals**
- Cat Tower, faithful to the published 10-phase rules (§4).
- Any seat in a game can be: on a shared phone (pass-and-play), on its own phone nearby, or remote — all in the same game. **(JD)**
- Every game runs through a Cloudflare Durable Object that holds hidden state and enforces rules. **(JD)**
- Live/synchronous play by default, with presence; anyone can leave and come back. **(JD)**
- Computer players (bots) to fill seats. **(JD)**
- No login required to play; Sign in with Apple only for persistent social features. **(JD)**
- Visual, nearly text-free UI. **(JD)**
- Architecture that can host more games later (collection), without building those games now.

**Milestones within v1** **(call)** — all of the above is v1; it ships to TestFlight in this order:
- **M1 — Play together:** guest identity, create/join by code + share link, all three seat types in one game, live play + presence + resume, "your turn" push, one bot level (House Cat), full art + animation for the table. First TestFlight build.
- **M2 — Us & family:** Sign in with Apple, groups + push invites, Nearby list, nudges, history/stats, Kitten + Alley Cat, bot-takeover vote, reactions.

**Non-goals (v1)** **(call unless marked)**
- Public App Store release (TestFlight first **(JD)**). Android, iPad-optimized layout, Mac.
- Offline play of any kind (everything goes through Cloudflare **(JD)**), including solo vs. bots.
- Monetization, ads, analytics beyond crash logs.
- Text chat, voice, spectators, ranked matchmaking with strangers, Game Center.
- A second game (only the plumbing for one).

**Anti-goals** — things that would make this a failure even if it works
- **A text-heavy or complex UI.** If a first-timer can't play by poking at things, it's wrong. **(JD)**
- **Emoji anywhere in the UI.** All iconography is custom art. **(JD)**
- Anything that could read as the trademarked original: no use of its name, logo, card face layout, or its red/blue/green/yellow color scheme. Rules only.
- Clients that can see others' cards or cheat (server must never send hidden info).
- Battery/CPU hog: the table must sit near-idle when nothing is animating.

## 3. The experience

### 3.1 App shell ("Pounce")
- **Home:** a playful shelf/room with a big game tile for Cat Tower (only one tile; no fake "coming soon" tiles **(call)**), a big **Play** button, a **Join** button, **your tables** (every game you're in, with whose turn it is), and your groups (if signed in). Your cat avatar sits on screen. A person can be in **several games at once**; a "your turn" push opens that specific game. **(call)**
- **Identity:** first launch asks only for a name and lets you pick your cat from a roster of ~8 distinct pre-made cat characters (no part-mixing customization in v1 **(call)** — keeps the art pipeline tractable). That creates a **guest** identity on the server silently. **(JD: no login unless needed)**
- **Identity model** **(call):** *person* (name + cat, guest or Apple-linked), *device* (APNs token, Keychain credential), and *seat* (a person's place in one game) are separate. A phone can hold several local people (e.g., a partner or kid who only plays on your phone) — each picked/created once with name + cat and remembered on that phone. A seat can move devices mid-game via a "move my seat" code shown on the current device. Push for a shared-phone seat goes to the phone that holds it.
- **Sign in with Apple** is offered only when you try a persistent feature: create a group, invite someone by push, see history/stats. A guest upgrades in place, keeping everything. **(JD)**
- **Groups:** named saved groups ("Us", "Family"). Start a game with a group in one tap; members get a push invite. **(JD)** Creating a group and sending invites requires Sign in with Apple **(JD)**. Members are added by sharing a group invite link or picking from recent tablemates; an invitee can join as a guest (device-bound) and is nudged to sign in so membership survives a new phone. Local-only people on a phone can be added as members of that phone's owner's groups. **(call)**

### 3.2 Getting people into a game
- **Create:** Play → pick seats → get a **room code** (4–5 chars, unambiguous alphabet) and a **share link** `https://play.conleychaos.com/j/<CODE>` via the standard iOS share sheet (AirDrop, Messages, etc.). Tapping the link opens the app straight into the game (Universal Links); without the app, the page shows the code and a TestFlight link. **(JD)**
- **Join:** enter code, tap link, or tap a game in the **Nearby** list. Nearby phones advertise open games over Bluetooth/local Wi-Fi (MultipeerConnectivity) purely to exchange the code; gameplay still goes through Cloudflare. **(call)** True "touch phones together" (NameDrop-style) isn't available to third-party apps; the Nearby list is the substitute. **(call)**
- **Seats:** the host builds the table. Each seat is one of: a remote/own-phone player (joins by code/link/nearby/group invite), an **"on this phone"** player (pass-and-play, any phone can host extra local seats, not just the host's), or a **bot** (3 levels). 2–6 seats. **(call: 2–6, matching deck capacity)**
- **Pass-and-play:** when the turn moves to a seat on a shared phone, the phone shows a full-screen "pass to <cat + name>" curtain; the hand is revealed only after tap. Never shows two hands at once.

### 3.3 Live play, presence, leaving
- All moves broadcast live with animation to every phone. **(JD)**
- Each player's cat shows presence: **awake** (app open), **away** (backgrounded recently), **asleep** (offline). **(JD: should know if the person is online)**
- Closing the app loses nothing; reopening resumes the exact table. If it becomes your turn while you're away, you get a "your turn" push — guest or signed in. **(JD)**
- **No turn timer.** Others get a **nudge** button (rate-limited) that sends a gentle push/haptic. **(call)**
- If a player is gone a long time, the remaining humans can vote to let a bot play that seat until they return. **(call)**
- Games inactive for 7 days are closed and cleaned up. **(call)**
- **Reactions:** a small wheel of custom-art cat reactions (purr/heart, hiss, laugh, shocked, sleepy) that pop over your cat. Not chat; no free text. **(call — couples will want this; cut if it bloats v1)**

### 3.4 Look, feel, motion
- **Theme (JD approved):** each player's cat climbs a **10-shelf cat tower**; each shelf = one phase. Completing a phase = cat leaps up a shelf with a celebratory bounce, visible to all.
- **Cards:** numbers 1–12 in four **cat coats** instead of colors: orange tabby, tuxedo, calico, gray. Coats must be distinguishable by more than hue (pattern + a distinct coat glyph in the corner) for color-blind players. **(call on glyph)**
- **Wild = ball of yarn. Skip = cucumber** — the targeted cat leaps in terror. **(JD approved)**
- **Table:** cozy living-room rug. Discards get batted onto the pile by a paw.
- **Style:** bright, saturated, chunky shapes, thick outlines, BTD6-like juiciness: squash-and-stretch, particles (fur puffs, yarn bits, stars), screen-shake used sparingly, haptics on key moments.
- **Phase goal display:** pictograms of card groups (e.g., two stacks of three card-backs labeled by a "same number" or "in a row" glyph), never sentences. Legal drops glow; you drag cards to where they go; illegal drops snap back with a gentle "nope" wiggle.
- **Words only where nothing else works** (player names, room code, a few labels). **(JD)**
- **Style checkpoint:** before full art production, JD approves a style sample (one cat in 2 poses, 3 card faces, a slice of the tower and rug). **(call)**
- **Art production:** generate raster art with the Codex CLI (`codex exec`, image generation) — cats (poses: idle, leap, terrified, sleeping, celebrating), card faces, tower, rug, UI icons, reactions — then clean up/slice into atlases. **(JD: use codex for images; no emoji)**
- **Sound:** short punchy SFX (CC0/licensed or generated), optional light music; mute toggle. **(call)**
- **Design research:** use the Mobbin MCP to study lobby/join flows, onboarding, and game-table UIs before finalizing screens. **(JD)** Mobbin MCP is **not connected** in the current environment — must be connected first, or proceed without it.

## 4. Game rules (Cat Tower = standard 10-phase rules)

Rules aren't copyrightable; names and art are ours. **(JD)**

**Deck (108):** numbers 1–12, two of each number in each of 4 coats (96); 8 Yarn (wild); 4 Cucumber (skip).

**Phases (shelves):**
1. 2 sets of 3
2. 1 set of 3 + 1 run of 4
3. 1 set of 4 + 1 run of 4
4. 1 run of 7
5. 1 run of 8
6. 1 run of 9
7. 2 sets of 4
8. 7 cards of one coat
9. 1 set of 5 + 1 set of 2
10. 1 set of 5 + 1 set of 3

Set = same number (any coats). Run = consecutive numbers (any coats), no wraparound (12→1 not allowed). Coat group = any numbers, one coat.

**Round:** dealer rotates; deal 10 each; flip one to start the discard pile. Turn = draw one (deck or top of discard) → optionally lay down your **entire** current phase (only if you haven't this round) → if you've laid down, optionally **hit** (add cards to any laid-down group, yours or others', keeping it valid) → discard one. A Cucumber discarded skips a chosen player's next turn. Cucumbers can't be drawn from the discard pile. Round ends when someone empties their hand (last card may be discarded or played). Players who laid down their phase advance one shelf; others repeat it.

**Scoring (cards left in hand):** 1–9 = 5, 10–12 = 10, Cucumber = 15, Yarn = 25. Lowest total is better.

**Winning:** first to complete phase 10 wins; if several complete it the same round, lowest total score wins; if still tied, they share the win. **(call on final tie)**

**A decided hand ends early** (JD's playtest, 2026-11-08: his partner laid down phase 10 and he could not possibly win, but they had to play the hand out). Once anyone has laid down phase 10, this hand ends the game, so after every move the server checks whether the rest of the hand can still change anyone's place (phases completed, then lowest score). Each seat is bounded on its own: a seat that has laid down finishes one phase up, one that has not may still lay down (its phase or one up); its score lands between its score now (it may still go out) and its score plus 25 per card it holds (a hand never ends holding more cards than it holds now). When every pair of seats is ordered under those bounds, the hand stops there: it is scored as it stands (nobody went out, every seat counts the cards it holds, seats that laid down advance) and the game is over. Those standing scores lie inside the bounds, so the places, the winner and everything recorded come out as they would have. A decided game always has one winner (a tie can't be fixed while anyone holds cards). `gameOver` then carries `reason: "decided"`, and the game view carries `endReason: "decided"`; both are absent on a game that ended by going out or a deck run dry. In a two-player game this usually ends the moment one player lays down phase 10 while the other is a phase or more behind; with three or more, play goes on until the places below the winner are fixed too.

**Edge cases — builder calls, cross-check against the published rules sheet before implementing:**
- If the first discard flipped is a Cucumber, the first player is skipped.
- Yarn can be drawn from the discard pile.
- Each laid-down group must include at least one natural (non-Yarn) card. **(call)**
- **Yarn in a run** keeps the rank the player gave it, and a laid run shows each Yarn at that rank. A `layDown` group's `runStart` sets the ranks. Without it, the cards' order sets them when that order is a run: `4 5 6 Yarn` is 4-7 and `Yarn 4 5 6` is 3-6. Otherwise the run takes the lowest start that fits, the old default. Hits then use the run's real ends: on 4-7 a 3 or an 8 fits and a 7 doesn't. (JD's playtest, 2026-11-06: a Yarn must stay where it was laid.)
- A player can't be targeted by a Cucumber if they're already pending a skip; if everyone else is already pending, the Cucumber is just discarded. **(call)**
- Running out of draw pile: reshuffle discards except the top card.
- 2-player: Cucumber skips the only opponent (you take two turns in a row).
- **Forfeit** (house rule, JD's playtest 2026-11-08): any player may forfeit until the game is over. With one other player left, the game ends and that player wins. With more, the forfeiter is out and finishes last: their hand leaves play, they are never dealt in, given a turn or targeted by a Cucumber, they don't advance or win, and their laid groups stay to be hit on; the rest play on, and if one player is left, they win. Bots never forfeit. Details: iOS design §5.13.

## 5. Architecture

### 5.1 iOS client **(call)**
- **Swift 6, SwiftUI** for app shell/menus; **SpriteKit** for the game table (native engine, 2D, Metal-backed, low overhead). Considered: Unity/Godot (heavier, not native), SceneKit/RealityKit (3D overkill). SpriteKit fits "native + game engine + low CPU". **(JD: native + game engine; SpriteKit is the call)**
- **Low CPU:** render on demand — pause the `SKView` (or drop `preferredFramesPerSecond`) whenever no action/particle is running; resume on input or incoming event. Texture atlases; no per-frame work at idle. Target: near-0% CPU on an idle table.
- **Animation approach:** cats as layered sprite rigs (body, head, tail, paws as separate nodes) animated with SKActions for cheap, expressive motion; particles via `SKEmitterNode`; haptics via Core Haptics.
- Minimum iOS: **iOS 26** (iPhone 11 and newer) **(JD)**. iPhone portrait only.
- Client shows only what the server sends; it may precompute "is this a valid group" for glow hints, but the server is the authority.
- Features: Universal Links, APNs, Sign in with Apple, MultipeerConnectivity (nearby code exchange only), share sheet.

### 5.2 Backend on Cloudflare **(JD: Cloudflare + Durable Objects)**
- One TypeScript **Worker** (`play-api`) on `play.conleychaos.com` serving: HTTP API, WebSocket upgrades, Universal Links `apple-app-site-association`, and the `/j/<CODE>` landing page.
- **`GameRoom` Durable Object** (SQLite-backed), one per game, addressed by room code. Uses the **WebSocket Hibernation API** so idle games cost nothing. Holds full state, validates every action, runs bots, tracks presence, uses alarms for bot turns, away/asleep transitions, and 7-day cleanup.
- **Game-type plugin interface** inside the DO (`init/applyAction/viewFor(seat)/botAction`) so future games slot in; Cat Tower is the only implementation.
- **Accounts/groups/devices:** D1 (guests, Apple-linked users, cat avatars, groups, memberships, APNs device tokens, game history/stats). **(call)**
- **Protocol:** JSON over WebSocket, versioned. Client sends intents; server replies with per-seat views plus an ordered event stream (sequence numbers) for animation and resume-after-disconnect. A connection can control multiple seats (shared phone). Server never sends another seat's hand.
- **Auth:** guest gets a server-issued signed token stored in Keychain; Sign in with Apple links to it. Seat tokens authorize a device to act for a seat.
- **Push:** APNs from the Worker (token-based JWT, ES256 via WebCrypto). Verify early that Workers `fetch` reaches APNs over HTTP/2; fallback is a tiny relay. **(risk)**
- **Room codes:** short code → DO via `idFromName`; regenerate on collision with an active game.

### 5.3 Bots **(JD: build an AI)**
Server-side, three levels **(call)**: **Kitten** (greedy, obvious moves, sometimes suboptimal), **House Cat** (solid heuristic play), **Alley Cat** (tracks opponents' pickups/discards, avoids feeding them, smart Cucumber targeting). Short human-like delays and animated "thinking." Same bot code can take over a vacated seat.

### 5.4 Repo, hosting, deploy — its own open-source monorepo **(JD)**
- Pounce lives in its own **public** monorepo, `github.com/jdconley/pounce`, MIT licensed, so CI runs on free GitHub-hosted runners. **(JD)** It still deploys to the same Cloudflare account as the rest of Conley Chaos. (It began inside the private `everything` monorepo; it moved out before its first deploy.)
- Layout **(call)**: a pnpm workspace. `apps/play-api/` — the Worker + Durable Objects, `tsconfig` extending `../../tsconfig.base.json`. `apps/play-ios/` — the Xcode project (not a pnpm package). `packages/` — shared JS packages, when one is needed. Shared protocol/rule fixtures (JSON test vectors) live where both can read them so the Swift client and TS server agree.
- Deploys from `.github/workflows/ci.yml`: every push to `main` that passes lint, typecheck and tests runs `wrangler deploy`, syncs secrets on stdin, and smoke-checks `https://play.conleychaos.com/healthz`. The deploy skips itself until the Cloudflare secrets exist. New bindings/resources (DO migrations, D1, the custom domain `play.conleychaos.com` on the conleychaos.com zone) go in `wrangler.jsonc`, not hand clicks.
- Repo rules: tool versions from the pnpm catalog in `pnpm-workspace.yaml`, TDD, `minimumReleaseAge` for new packages, secrets only in GitHub Actions secrets and 1Password (never values in code — this repo is public).
- **iOS signing:** Apple team **Conley Chaos LLC (B222J9J7B8)** is signed in to Xcode on this Mac. Bundle ID `com.conleychaos.play` **(call)** — neutral identifiers (bundle ID, domain) so the code name "Pounce" can change freely; only the display name carries it. TestFlight uploads from this Mac via `xcodebuild` archive/export with automatic signing (or an App Store Connect API key from the `conleychaos` 1Password account if one exists — it was locked during discovery). iOS CI is out of scope for v1.
- **One-time manual setup (needs JD; Apple account-level):** App ID capabilities (Sign in with Apple, Push, Associated Domains), APNs auth key (.p8) into 1Password, App Store Connect app record, TestFlight testers.

## 6. Testing
- **Rules engine:** exhaustive unit tests (vitest) for every phase, group validation including Yarn, hitting, Cucumber targeting, round end, scoring, winning/ties, reshuffle. Written test-first.
- **GameRoom DO:** tests for hidden-info (no seat ever receives another's hand), action validation, reconnect/resume via sequence numbers, multi-seat connections, presence transitions, bot turns, cleanup.
- **Bots:** simulation harness running thousands of bot-vs-bot games to check for stalls/illegal moves and that levels rank Alley > House > Kitten.
- **iOS:** unit tests for protocol/model; UI smoke test of create → join → play a turn against a local `wrangler dev` server; manual playtests across shared/own/remote seats.
- **Performance:** Instruments check that an idle table is near-zero CPU and animations hold 60fps on an older supported iPhone.

## 7. Left to the builder
- Exact screen layouts (informed by Mobbin research), animation timings, sound selection, art cleanup pipeline.
- Rule edge-case confirmation against the published rules (§4 list).
- D1 schema, protocol message shapes, token formats, room-code alphabet.
- Bot heuristics within the three levels.
- Whether to wire TestFlight upload into CI later (macOS runner) vs. local uploads for v1.
