# Pounce: Family Games

**Family game night, every night.** Little games for couples and families. Everyone can be on one
phone, on their own phone in the same room, or across the world, all in the same game. Play live,
or take your turn whenever you have a minute.

[Pounce on the App Store](https://apps.apple.com/app/id6829560061) (free, iPhone and iPad) ·
[play.conleychaos.com](https://play.conleychaos.com) · made by Conley Chaos LLC.

The games:

- **Cat Tower**: a set-collecting rummy game where cats climb a ten-shelf cat tower, one phase per
  shelf. Yarn is wild, and a Cucumber makes the next cat skip a turn.
- **Tuna Tiles**: tile rummy for two to four. Yarn is wild here too.
- **Birdwatch**: a trick-taking card game in teams for four to six. Bid for the hand, take the
  feeder's extra cards, name trump and win tricks; the Bird is the top trump. With five, the bid
  winner calls a card and whoever holds it is their secret partner. Three rule sets: Official,
  Tucker and Friesen. House Cats fill empty seats. In the browser now at
  [play.conleychaos.com/play](https://play.conleychaos.com/play) and on its TV page; coming to the
  iPhone, iPad and Apple TV app in 1.4 (now in App Review). Design:
  [docs/superpowers/specs/2026-11-25-birdwatch-design.md](docs/superpowers/specs/2026-11-25-birdwatch-design.md).
- **Toy Tumble**: Pounce's first real-time game, for two to six. Everyone plays at once on their
  own phone or computer, and the TV shows every box. Toys fall into your box; clear rows to send
  hairballs to everyone else, and pocket tricks to hit a player or save yourself. Win three rounds
  to take the game. House Cats can fill seats at Easy or Quick. In the browser now at
  [play.conleychaos.com/play](https://play.conleychaos.com/play) and on its TV page; coming to the
  iPhone, iPad and Apple TV app in 1.4 (now in App Review). Design:
  [docs/superpowers/specs/2026-11-26-toy-tumble-design.md](docs/superpowers/specs/2026-11-26-toy-tumble-design.md).
- **Purrtrait**: a draw-and-guess game for one room, two to ten players. The drawer draws a word
  on their phone, the TV shows the drawing as it is drawn, and everyone else calls out guesses.
  The drawer taps who got it, and both score. It needs a TV or a big screen in the room: it starts
  on the TV, and you join from the TV's code, which changes every 30 seconds. Drawings go only to
  that TV and are never saved. In the browser now: start it on
  [play.conleychaos.com/play/tv](https://play.conleychaos.com/play/tv) and draw in a phone's
  browser. Coming to the iPhone, iPad and Apple TV app in 1.4 (now in App Review). Design:
  [docs/superpowers/specs/2026-11-26-purrtrait-design.md](docs/superpowers/specs/2026-11-26-purrtrait-design.md).
- **The Daily Dish**: four new puzzles every day, the same for the whole family, with a family
  board and streaks. Sniff (find the five-letter word), Nine Lives (a number grid), Cat Nap (one
  cat in each row, column and patch) and Box Fort (drag blocks onto a rug). In the app since 1.2,
  and in the browser at [play.conleychaos.com/play/daily](https://play.conleychaos.com/play/daily).
  The server checks every move and works out every result
  ([docs/daily-protocol.md](docs/daily-protocol.md)). Since 27 November 2026 in the browser
  (the app in 1.4, now in App Review): Nine Lives has three lives and three free hints, puzzle clocks count only
  play time, and a puzzle you don't finish ranks below everyone who did, by how far you got.

Pounce on the TV: open [play.conleychaos.com/play/tv](https://play.conleychaos.com/play/tv) in a
browser on the big screen, and each phone (the app since 1.2, or a browser) shows just its own
cards. Show on TV moves a table there by its code. The Apple TV app is in TestFlight, and its first
App Store version, 1.4, is in App Review. See [apps/play-ios](apps/play-ios/README.md#the-apple-tv-app).

No ads, no chat, no public profiles, and no account needed to play. Children under 13 get a limited
version, and a parent decides whether they get turn alerts.

## Releases

| Version | Status | What's in it |
| --- | --- | --- |
| 1.0 | On the App Store since November 2026 | Cat Tower, live and turn-based tables, House Cat bots, streaks, widgets, the live table on the Lock Screen, parent consent for kids. |
| 1.1 | Released on the App Store on 16 November 2026 | Tuna Tiles. A faster first game: a House Cat holds a seat. Add players your way: Same room (scan a QR code), Far away (send a link) or This phone (pass and play). Invites that survive installing the app (Paste). A new Home, How to play videos, clearer Settings, tips. |
| 1.2 | Released on the App Store on 26 November 2026 | Pounce on the TV: your phone shows just your cards, Tap Table for the whole board, and Show on TV by scanning or typing the TV's code. The Daily Dish: Sniff, Nine Lives, Cat Nap and Box Fort, a family board, and streaks. The Apple TV app is not on the App Store yet. |
| 1.3 | Never released: pulled from App Review on 27 November 2026 for 1.4 | Birdwatch and the Cat Tower fixes, which shipped in 1.4 instead. |
| 1.4 | In App Review since 27 November 2026, for iPhone, iPad and Apple TV | Birdwatch (from 1.3). Toy Tumble, the first real-time game: falling toys, hairballs and tricks, 2 to 6 players at once, every box on the TV. Purrtrait, draw and guess in one room: the drawer draws on their phone, the TV shows it as it's drawn, 2 to 10 players. Both play on the web and its TV page now (Purrtrait since 27 November 2026); the iPhone, iPad and Apple TV app gets them in 1.4. Nine Lives with three lives and three free hints, and Dish clocks that stop when you leave (in the browser since 27 November 2026). |

Every merge to `main` that touches the app builds to TestFlight and goes to the Family and Friends
group (`apps/play-ios/README.md`, TestFlight). What each App Store version says is kept in the
repo: What's New and the listing in `docs/whats-new/`, the reviewer notes in
`docs/app-review-notes.md`, and the App Privacy answers in `docs/privacy/app-store-label.md`.

## Layout

| Path | What it is |
| --- | --- |
| `apps/play-api` | The game server: a Cloudflare Worker with one Durable Object per room. It owns the rules, the bots and the hidden hands, and referees the Daily Dish's puzzles (`src/daily`). It also serves the website (below). |
| `apps/play-ios` | The iOS app (SwiftUI shell, SpriteKit table). See its [README](apps/play-ios/README.md). |
| `apps/play-web` | Pounce in a browser, at `play.conleychaos.com/play`: every game and the Daily Dish for Android, laptops and anyone without an iPhone, installable as an app. It imports the server's rules and protocol from `apps/play-api`, so it can't drift from the game. |
| `docs/superpowers` | The design spec, implementation plans and follow-up notes. |

## Develop

Requires Node 24 and pnpm 10.

```bash
pnpm install
pnpm check   # lint, typecheck and tests
```

`apps/play-api` tests include a 300-game bot simulation and Miniflare
integration tests for the Worker and Durable Objects.

## First-run funnel data

Where new players get stuck: anonymous, per-device first times for each getting-started step, in
the D1 database `conleychaos-play-funnel` on our own Cloudflare account. `docs/funnel.md` says what
is kept and how to query it (`apps/play-api/funnel/query.sh`).

## Local dev server

Run the game server on your machine (the iOS Debug build talks to it at
`http://localhost:8787`):

```bash
cp apps/play-api/.dev.vars.example apps/play-api/.dev.vars   # gitignored
# fill TOKEN_SECRET with the output of: openssl rand -hex 32
pnpm --filter @pounce/play-api exec wrangler dev --port 8787
```

The example `.dev.vars` sets `GAMES=tiles,birdwatch,tumble,purrtrait`, as production does, which
lets the local server deal the tile game, Birdwatch, Toy Tumble and Purrtrait as well as Cat Tower;
`apps/play-ios/scripts/dev-server.sh` passes `tiles,birdwatch,tumble` unless `DEV_SERVER_GAMES`
says otherwise. Production's `GAMES` in `apps/play-api/wrangler.jsonc` is
`tiles,birdwatch,tumble,purrtrait`: apps from version 1.1 deal and play the tile game, version 1.0
never sees a tile table, only 1.3 and the web player see Birdwatch tables, and only 1.4 and the web
player see Toy Tumble and Purrtrait tables. Only a TV makes a Purrtrait table, so it also needs
`TV` on. The web player shows Toy Tumble and Purrtrait on its shelf when it is built with
`WEB_TUMBLE=on` and `WEB_PURRTRAIT=on`, as the deploy and the e2e runs do.

## The website

The same Worker serves the public site at `play.conleychaos.com`: the landing page (`/`), help
(`/support`), the privacy policy (`/privacy`) and the invite pages. They are plain HTML built in
`apps/play-api/src/http`, with no scripts and nothing loaded from another host.

How the site offers the app follows two settings, with no code change:

| Setting | Where | Effect |
| --- | --- | --- |
| `APP_STORE_URL` | `vars` in `apps/play-api/wrangler.jsonc`, set to `https://apps.apple.com/app/id6829560061` since 1.0 was released | The landing page shows Apple's "Download on the App Store" badge beside "Play in your browser", and a QR code on desktop; every page gets Safari's Smart App Banner; `/get` goes to the App Store. |
| `TESTFLIGHT_URL` | the same `vars`, the public beta link | Before release, used in place of the App Store. Now only for an invite to a table the App Store's version can't open yet (below). |
| neither | | The page says "Coming soon to the App Store" and offers only "Play in your browser". |

The invite pages (`/j/<code>`, `/p/<token>`) promise only what the App Store's current version can
do, using the version Apple's public lookup reports (cached, never waited on). Paste invite and Tuna
Tiles arrived in 1.1. So while the App Store still has 1.0, a Tuna Tiles invite's button goes to the
TestFlight beta, and other invites say "tap Join" (or "tap this link again") instead of "tap
Paste". Once the App Store has 1.1, every invite goes to the App Store with Paste, by itself
(`GAME_SINCE` and `PASTE_SINCE` in `apps/play-api/src/http/links.ts`). Birdwatch is in TestFlight
builds from 1.3, but its first App Store version is 1.4 (1.3 was pulled from review): until the
App Store has 1.4, a Birdwatch invite sends iPhones to the beta and says the game is coming to the
iPhone app, and the landing page, help and llms.txt say it plays in the browser and comes to the
app in 1.4, now in App Review (`IN_REVIEW`). Toy Tumble
needs 1.4, and no app build has it yet, the beta included (`BETA_LACKS`), so a Toy Tumble invite
offers only Play in your browser, on every device, and says the game is coming to the iPhone app in
1.4. Once TestFlight builds 1.4, take `tumble` out of `BETA_LACKS` and its invites work as
Birdwatch's do. A Purrtrait table has no invite: it is joined only from the code on its TV, so its
`/j/` page says "Scan the code on the TV.", and the TV's QR (`/e/<code>?near=<key>`) opens the web
player only without the app: `PURRTRAIT_APPLINKS` is on since 1.4 went to App Review, so with the
app it opens there (a 1.2 app can't draw it). The landing page, help and
llms.txt say Purrtrait starts on the browser TV page and is coming to the iPhone, iPad and Apple TV
app in 1.4, now in App Review.

`/get` redirects to whichever link is set (or home), so other sites and the QR code can point at
`https://play.conleychaos.com/get`.

The page's images and gameplay clip are built from the app icon, the cat art and the App Store
preview under `apps/play-ios`, and real screenshots of both games, the web player and the TV
(`SCREENS` in the script, from `docs/screenshots` and `apps/play-ios/Art/screenshots`). They are
committed in `apps/play-api/public`. After any of those change, rebuild them (needs `ffmpeg`,
`cwebp` and ImageMagick):

```bash
node apps/play-api/scripts/build-site-media.mjs
```

## The web player

`apps/play-web` (Vite, Preact, the table in plain DOM moved by transforms) builds into
`apps/play-api/public/play` and ships inside the Worker, from the same commit: the deploy job
builds it right before `wrangler deploy`. Design: `docs/superpowers/specs/2026-11-15-web-player-design.md`.

```bash
pnpm --filter @pounce/play-web build                       # into apps/play-api/public/play
pnpm --filter @pounce/play-api exec wrangler dev --port 8790 # then open http://localhost:8790/play/
```

For quick edits, `pnpm --filter @pounce/play-web dev` serves it at `http://localhost:5180/play/`
with the API proxied to `DEV_SERVER_URL` (default `http://localhost:8787`). Its tests
(`pnpm --filter @pounce/play-web test`) include a contract test of the web client against the
real Worker. The art and sounds are built from the iOS app's (`node apps/play-web/scripts/build-art.mjs`).

## Deploy

Every push to `main` that passes CI deploys `apps/play-api` to
`play.conleychaos.com`. The deploy skips itself until these GitHub Actions
secrets exist:

| Secret | Required | What it is |
| --- | --- | --- |
| `CLOUDFLARE_API_TOKEN` | yes | Token that can edit Workers and the `conleychaos.com` zone's routes. |
| `CLOUDFLARE_ACCOUNT_ID` | yes | The Cloudflare account that holds `conleychaos.com`. |
| `PLAY_API_TOKEN_SECRET` | yes | Signs device tokens. Generate with `openssl rand -hex 32`. Without it the API answers 503 and the smoke check fails. |
| `PLAY_API_APNS_KEY_P8` | no | APNs auth key (.p8 contents) for "your turn" pushes. Set it together with the key ID. |
| `PLAY_API_APNS_KEY_ID` | no | The APNs key's ID. |
| `PLAY_API_SIWA_KEY_P8` | yes for the App Store | Sign in with Apple key (.p8 contents). Sign-in works without it, but the API keeps no Apple tokens, so it can't revoke them on account deletion as App Review requires. One key with both APNs and Sign in with Apple enabled can serve both pairs. Set it together with the key ID. |
| `PLAY_API_SIWA_KEY_ID` | no | The Sign in with Apple key's ID. |
| `PLAY_API_VAPID_PUBLIC_KEY` | no | The web player's push key pair (Web Push, VAPID). Set both at once with `node apps/play-api/scripts/vapid-keys.mjs`, which makes the pair and stores it with `gh secret set` (the private key is never shown). Without them browsers are never asked to notify. |
| `PLAY_API_VAPID_PRIVATE_KEY` | no | Its private half (made by the same script). |
| `PLAY_API_TWILIO_ACCOUNT_SID` | no | Twilio account SID (`AC…`), for parent consent (daily habit PR 9). Set all four Twilio secrets or none: without them no code is sent and a kitten's consent can't start. |
| `PLAY_API_TWILIO_API_KEY_SID` | no | A Twilio API key's SID (`SK…`): signs in to Verify (basic auth). |
| `PLAY_API_TWILIO_API_KEY_SECRET` | no | That API key's secret. |
| `PLAY_API_TWILIO_VERIFY_SERVICE_SID` | no | The Verify Service (`VA…`) that texts the parent a six-digit code. |

Parent consent uses **Twilio Verify**: Twilio texts the parent a code from its own pre-registered
senders, so Pounce needs no phone number of its own, no Messaging Service, no webhook and no A2P
10DLC or toll-free verification. Setup, all in the Twilio console:

1. **Verify, then Services, then Create new.** Friendly name `Pounce` (Verify's text reads "Your
   Pounce verification code is: …"), code length **6**, channel **SMS** on. Copy the Service SID
   (`VA…`).
2. Geo permissions for Verify (in the Service's settings, or Messaging's SMS geographic
   permissions): allow the **United States and Canada** only. The API sends codes only to +1
   numbers.
3. **Account, then API keys and tokens, then Create API key.** Friendly name `Pounce play-api`,
   type **Standard**. Copy its SID (`SK…`) and secret now; the secret isn't shown again.
4. Your account SID (`AC…`) is on the console's home page.
5. In GitHub, add the four secrets above (Settings, then Secrets and variables, then Actions). The
   next deploy syncs them; a partial set is skipped with a warning.

## License

[MIT](LICENSE)
