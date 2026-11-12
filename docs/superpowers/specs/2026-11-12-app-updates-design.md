# App updates: design

Date: 2026-11-12. Status: built in two pull requests, the server (`apps/play-api`, on top of the tile game wiring) and the app (`apps/play-ios`).

Pounce learns when a newer version exists and asks people to update at the moments it matters: when someone invites them to a game their app can't draw, and when the server no longer supports their version. Everything is additive. Version 1.0 is in App Review against production and can't be changed: it sends none of what is new here, and it is answered exactly as before (§7 says how that is tested).

It builds on the tile game's capability gate (tile game design §9.3) and changes one sentence of it. "An app that can't draw a table's game never meets it" still holds for version 1.0. An app that says what it is (1.1 on) is told the truth instead.

## 1. Versions

| Version | What it is | Says what it is |
| --- | --- | --- |
| 1.0 | Commit `268262c`, Cat Tower only, in App Review. Cannot change. | No |
| 1.1 | `main`, in TestFlight. The first version with any of this. | Yes |

Three cases come up below: **1.0**; **1.1, current** (the newest on the store, and it can draw the table's game); **1.1, behind** (it says what it is, but the store has something newer, or the table's game needs a newer app).

## 2. What the app says

From 1.1 on, every HTTP request and socket upgrade, from the app and its widget extension, carries:

```
X-Pounce-App: platform=ios; version=1.1; build=57; protocol=1
```

Keys in any order; unknown keys are ignored. `version` is `CFBundleShortVersionString`, `build` is `CFBundleVersion`, `protocol` is the socket protocol the app speaks (`PounceKit.protocolVersion`).

There was no such header before. 1.0 sends only `Authorization` and `Content-Type`. Its `User-Agent` is URLSession's own (`Pounce/<build> CFNetwork/… Darwin/…`): the build but not the version, in a format Apple owns, so nothing reads it.

A request with no header, or one that can't be read (no platform, no version), is **version 1.0 speaking protocol 1**. That is the only app that doesn't say.

The server remembers the version per device next to the games it can draw, on the same call to the device's index (`DeviceIndex.players(declared, version)`). It costs no call of its own. A socket or tables request with no header forgets it: an older build is back on the device.

`PROTOCOL_VERSION` today: the server sends `protocol: 1` in every snapshot, and the app never sent its own. The app (1.0 and 1.1) checks the snapshot's number and treats any other as "update the app" (§6). `MIN_PROTOCOL` (new, `src/protocol.ts`, 1) is the oldest protocol the server still speaks.

## 3. What is current: `GET /v1/app`

Public, no credential, `no-store`. Every key is left out when it isn't known.

```json
{ "latest": "1.2", "minimum": "1.1", "storeUrl": "https://apps.apple.com/app/id6829560061", "testflightUrl": "https://testflight.apple.com/join/…" }
```

- **`latest`** is the version live on the App Store, as Apple's public lookup last said (`https://itunes.apple.com/lookup?id=6829560061`, or the id in `APP_STORE_URL`). The request to Apple carries nothing of the asking app: no header, no address, no id.
- **`minimum`** is `APP_MINIMUM` (empty in `wrangler.jsonc`: none), but only once Apple has named a version at least that new. A minimum set early, or mistyped, locks nobody out, and one set ahead of a release starts by itself when the release is live.
- **`storeUrl`** only while there is a listing. The app falls back to the built-in id.
- Today, before release, the lookup finds nothing and the answer is `{"testflightUrl": …}`.

**No request ever waits on Apple.** Every path, this route included, reads what is remembered (this isolate, then the data centre's cache, keyed on a path of the Worker's own host) and answers from it, however old. When the answer has had its time (six hours; 15 minutes after "not listed" or a failure) one lookup goes out in the background (`ctx.waitUntil`) for the next asker. One at a time per isolate, and Apple is marked as asked before the request leaves, so no number of requests, with or without a credential, whatever they claim to be, causes a second lookup in the same window. A lookup that fails changes nothing: the last version Apple named stays known, so a minimum that was being enforced goes on being enforced. A cold server that knows nothing enforces nothing, and says nothing.

**`APP_LATEST` and `APP_MINIMUM_FORCE`.** `APP_LATEST` (a version, or `off`) overrides only what apps are told is newest, which is the soft card. It is the server's word, not Apple's: it never lets the minimum turn anyone away, and no update push goes by it. Paired with `APP_MINIMUM` for a version that isn't out, it locks nobody out. The one way to enforce a minimum without Apple's word is `APP_MINIMUM_FORCE=on`, which is the owner saying "that version is out". `APP_LOOKUP=off` never asks Apple.

One rule runs through all of it: **nobody is told to update to a version they can't download.** When the lookup fails or the app isn't listed, the server says nothing, the soft card never shows, nobody is refused, and no update push is sent.

A separate route is the cheapest: it touches no Durable Object, the app asks it at most every six hours, and the answers that matter (§4.2, §4.3) carry what they need themselves.

## 4. The three moments

### 4.1 A newer version exists (soft)

`latest` is newer than the running app. Home shows a small card, "A new Pounce is ready", with Update and a close button. Never on a table, never an alert.

Schedule (`UpdatePolicy.soft`, PounceKit): once per new version, and after any dismissal nothing for seven days, whatever version comes out. Hidden on a TestFlight install (the App Store can't update it), in demos and in UI tests. On a child's device the card has no button and says "Ask a grown-up to update Pounce."

### 4.2 This table needs a newer app

An app that said what it is opens a table whose game it doesn't list (link, typed code, push tap or a pounce's table all open the same socket). The room answers the upgrade:

```
426
X-Pounce-Update: game
X-Pounce-Game: tiles
X-Pounce-Game-Title: Tuna%20Tiles
{"error":"game_unsupported","game":"tiles","title":"Tuna Tiles"}
```

The headers repeat the body because an app can't read the body of a refused upgrade. The app shows "This table is playing Tuna Tiles. Update Pounce to join." with Update and Home, and remembers the table.

**Locked tables.** `GET /v1/devices/me/tables`, for an app that said what it is, gains `locked` beside `tables` when there is something in it: the tables it was left out of that aren't over, each `{code, name?, game, title, updatedAt, seats?}`. `tables` itself is unchanged, so nothing that reads it can trip. The app adds the tables it was refused at on this device (kept locally for 30 days) and shows them on Home with a padlock. After the update the same row opens the table. So an invite doesn't vanish when the card is closed.

When nothing newer is on the store (a game still in TestFlight), the card says "Tuna Tiles isn't in this version of Pounce yet." and has no Update button.

### 4.3 This app is too old (hard)

`APP_MINIMUM` is above the app's version (and the store has that version), or the app speaks a protocol below `MIN_PROTOCOL`. An app that said what it is gets, on every authenticated route, on `POST /v1/devices` and on socket upgrades, before its credential is even checked:

```
426
X-Pounce-Update: required
{"error":"update_required","minimum":"1.2","storeUrl":"…","testflightUrl":"…"}
```

Two routes are exempt, so that someone can always leave: `DELETE /v1/me` (Apple requires account deletion for as long as the app runs) and `POST /v1/me/signout`. Every other route is refused, the other `/v1/me` routes included.

The app shows a full screen, "Update Pounce to keep playing", with Update and, for a signed-in person, a quiet way to their account (sign out, delete). `GET /v1/app` still answers, so the app can also raise the screen at launch, and takes it down again if the minimum is taken back. It waits for the age screen on a device that hasn't answered it, since the button depends on the age and that screen needs no server. The public pages, `/healthz` and Apple's notification route are untouched. (The existing 426 `upgrade_required`, for asking the socket route without a WebSocket upgrade, is a different answer and unchanged.)

### 4.4 The Update button (`UpdatePolicy.action`)

| Device | Button |
| --- | --- |
| App Store install, teen or adult | Opens `storeUrl`, or `https://apps.apple.com/app/id6829560061` |
| TestFlight install | "Open TestFlight": `testflightUrl`, or `itms-beta://` |
| Under 13 (kitten), or age not known yet | No link. "Ask a grown-up to update Pounce." |

A kitten's device sends nobody to the store: it shares no links, and Rate Pounce is an adult's. TestFlight is detected from StoreKit's `AppTransaction` environment (sandbox, outside Xcode and the simulator).

## 5. Reaching 1.0: the update push

1.0 shows none of this. One push can: **"Mia wants to play Tuna Tiles. Update Pounce to join."**, titled with the table (or with the person the withheld push was for). It goes to a device whose app can't draw a table's game, in two places:

1. **It tried to open the table** (a link or a typed code) and said nothing of itself. It gets the 404 as ever, and the push names the host. An app that said what it is gets §4.2's answer instead and no push.
2. **A push a person sent about the table was withheld from it** ("your move", a nudge, a pounce at the table, play again), for a seat's older device. It gets this one in its place.

It fits the notification policy, under these rules (`DeviceIndex.pushUpdate`, `notify/update.ts`):

- Only when the version Apple last said is live is newer than the device's app (1.0 for one that never said). Unknown: nothing. `APP_LATEST` doesn't count. The push never waits on Apple either: it goes by what is known when it is due.
- Once per table per device, ever, and no more than one per device every 20 minutes (the spacing every other unasked push keeps).
- Never to a kitten's device, with or without consent: a child isn't sent to the App Store, and consent covers "your move", pounces and nudges only.
- Never in a teen's night. Quiet (no sound) in the recipient's quiet hours.
- Never between people where either blocked the other. Never about your own table.
- With `NOTIFY` off, nothing.

**What 1.0 does with it** (read at `268262c`): the payload's `kind` is `update`, which 1.0 has no name for, its category is `STATUS` (no buttons), and it has no top-level `code`, no badge and no `streak`. `PushCoordinator.presentation` shows it as a banner, in the foreground too, and refreshes the tables list. A tap opens the app and nothing else (`NotifyActions.outcome` is `.none` without a `code`). The Notification Service Extension delivers it as it came (not a communication kind) and the widgets' snapshot is unchanged (no `streak`). A top-level `code` is what must never be there: 1.0 would open the table and be told it doesn't exist.

For someone on 1.0 tapping a link to a tile game table this is the one thing that explains what they see: the app bounces to Join, and the banner says why.

From 1.1 on the app knows the kind: a tap opens the table in `update.code`, which answers as §4.2 says, or deals them in once they have updated.

## 6. What a 1.0 app does, and retiring it

Read from `268262c`. Its networking and room code are byte for byte `main`'s, so each of these is also what 1.1 did before this work.

| The server answers | 1.0 does |
| --- | --- |
| Socket upgrade 404 | A table this device knew: "This table is closed". A linked or typed code it didn't: back to Join, the tiles shake. |
| Socket upgrade 426, or any status but 401, 404, 429 | Treats it as a lost connection: retries forever (0.25 s rising to 8 s), and after three failures shows "Can't reach the server" with Try again. Never says "update". |
| A snapshot whose `protocol` isn't 1 | Stops the socket and shows its own card: "Update the app to play. Get the newest Pounce from the App Store." Home button, no link. It reads only `t` and `protocol` of that frame. |
| An API call 426 | `APIError.server(426)`: Home keeps its last list without a word, a new game says "Couldn't start a game. Try again.", minting a device fails and every table then looks offline. Never says "update". |
| A push of a kind it doesn't know, no `code` | Shows it; a tap opens the app. |

So the only place 1.0 can be told to update is a table's socket, and only with a snapshot of another protocol. That decides the design: when `APP_MINIMUM` is above 1.0 (and the store has that version), **1.0's API calls are answered as ever, and every socket it opens is accepted, sent `{"t":"snapshot","protocol":0}` and closed.** It sees Home as usual, and any table, new game or practice game says "Update the app to play".

How safely 1.0 can be retired:

- It is clean: nothing loops, nothing looks broken, the words are right.
- It is blunt: the card has no button, so the person has to find the App Store themselves. The update push can't help, since it is per table.
- Its widgets, live table and "your move" pushes keep arriving, and each leads to the same card.
- A new game still creates a table on the server that nobody then enters.
- Before setting `APP_MINIMUM`, look at how many requests still come with no `X-Pounce-App`. Setting it is one line in `wrangler.jsonc`, and taking it back is the same line.
- Its account deletion and sign-out keep working: its API calls are answered as ever.

## 7. What each version experiences

| Situation | 1.0 | 1.1, current | 1.1, behind |
| --- | --- | --- | --- |
| A newer version is on the store | Nothing. | Nothing. | The soft card on Home, once per version. |
| Opens a table whose game it can't draw | 404: Join shakes, or "This table is closed". Once, the update push. | Sits down. | The card naming the game, with Update. The table stays on Home, locked. |
| Its tables list | The table is left out. | Listed. | Left out of `tables`, in `locked`. |
| A push about that table | Not sent. Once, the update push in its place. | Sent. | Not sent. Once, the update push in its place. |
| The minimum is raised above it | API as ever. Every table: its own "Update the app to play" card, no button. | Served. | 426 everywhere: the full "Update Pounce to keep playing" screen. |
| `GET /v1/app` | Never asks. | `latest` equals its own. | `latest` is newer. |

**How 1.0 is kept safe.** With `APP_MINIMUM` empty, as shipped, nothing a request without `X-Pounce-App` sends or receives changes. `tests/app-updates.test.ts` runs the requests 1.0 makes against a server with no update setting and against servers with all of them, and compares every status, header and body; it checks the Worker's calls to the device's index are the same calls with the same arguments; and it holds the tables body to `{"tables":[…]}` and the tile table's 404 to an empty body with no new header. The pinned fixtures (`tests/fixtures-pinned.test.ts`) are untouched. The one thing that reaches 1.0 unasked is the update push, and only once `latest` is above 1.0.

## 8. Where it lives

- Server: `src/app/` (`version.ts`, `status.ts`, `memory.ts`, `live.ts`), `src/notify/update.ts`, `lockedFor` in `src/room/tables.ts`, the gate in `src/index.ts`, the room's answer and `askToUpdate` in `src/room/game-room.ts`, `DeviceIndex.pushUpdate`. Tests: beside each, and `tests/app-updates.test.ts`.
- App: `PounceKit/Sources/PounceKit/Update/` (pure, unit tested), `Pounce/App/UpdateModel.swift`, `Pounce/Shell/UpdateViews.swift`. Demo arguments: `-demo-update <soft|locked|table|required>`, `-update-channel testflight`. Screenshots: `apps/play-ios/Art/screenshots/app-updates/`.

## 9. Open questions for JD

1. **1.0 at a tile game table.** It gets the 404, as asked. But 1.0 has a better card built in: answering that socket with the protocol-0 frame of §6 would show "Update the app to play" instead of a shaking Join screen. It is a one-line change in the room, it is what 1.0 was written to handle, and I think it is the better answer. Not built, because 1.0's answers were to stay exactly as they are.
2. **The soft card's schedule.** Built as: once per version, and seven quiet days after any dismissal. If you meant "show again after a week for the same version", it is one line in `UpdatePolicy.soft`.
3. **"Tuna Tiles" is a working title**, and it is now in a push. `TITLES` in `src/games/index.ts` must follow the app's `GameCatalog`.
4. **The update push on a join attempt names the host** to whoever holds the table's code. Joining would show them the same name and cat, so I think it is fine. It is not limited to connected partners, since a first invite is exactly when two people aren't connected yet.
5. **Which version draws which game.** The server doesn't know, so "there is something to update to" means "the store has a newer version than yours". If 1.2 ships without the tile game while `GAMES` lists it, people would be asked to update to a version that still can't join. Turn `GAMES` on only once the store version draws the game, or add a per-game minimum.
6. **TestFlight.** The soft card is hidden there. The other two moments say "Open TestFlight". The fallback `itms-beta://` link is from memory and untested on a device.
7. **The lookup is the US storefront's.** A phased release counts as live from its first day, since anyone can update by hand.
