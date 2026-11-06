# Parent consent for kittens (daily habit PR 9) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `2026-11-05-parent-consent-design.md`, all of it. A signed-in adult links a kitten's own device with a six-digit code, reads the direct notice, and gives verifiable parental consent by **text plus** through Twilio. That unlocks, for that kitten's device, "your move" pushes at tables where every other human is approved, and pounces from approved people. Approvals come from Apple's PermissionKit when the kitten has Communication Limits, otherwise from the parent's own list. Consent ends on a parent's revoke, the revoke link, a STOP reply, an App Store `RESCIND_CONSENT`, the kitten's deletion, or the kitten turning 13. `CONSENT` is on in production at merge (D4).

**Architecture:**
- **Server, pure (`src/consent/*.ts`, 100% coverage):**
  - `rules.ts`: the consent record and its state machine (link, text, confirm, second text, revoke, unlink, approvals), the push filter (`allows`), the second-text time, the texted-state expiry, phone normalizing, link codes and their attempt limit.
  - `twilio.ts`: the Messages REST call (basic auth with the API key), and `X-Twilio-Signature` signing and checking.
  - `appstore.ts`: a minimal DER reader, the x5c chain check to the pinned Apple Root CA - G3, ES256 JWS verification, and reading `RESCIND_CONSENT`.
  - `pages.ts`: the kitten notice page, the confirm and revoke pages, and the two texts' copy.
- **Server, glue (`src/kittens/*.ts`, Miniflare-tested like `pounces.ts`):**
  - `Consents` DO, one per kitten player: the record, its alarm (second text, texted expiry), sending texts, and revocation side effects.
  - `KittenIndex` DO, one instance: link codes, failed attempts, public kitten ids, parent → kitten links, text-link tokens, phone hashes, app transaction ids.
  - `kittens.ts`: the route flows.
- **Push gate:** `DeviceIndex.pushAlert` and `push` take an optional `{recipient, senders}`. A kitten's device refuses everything as today, unless `CONSENT` is on and the recipient's `Consents.allows(kind, senders)`.
- **App, pure (PounceKit `Kitten/`, Swift Testing):** wire types, `KittenService` (+ `APIClient`), `KittenStore`, the bell rule (`KittenBell`), the link-code and phone entries, the PermissionKit mirror plan (`KittenApprovals`), `PushPolicy.registersRemote(band:consented:)`, and `DemoKittenService`.
- **App:** the kitten's bell in the gear sheet, the parent's Kittens sheet (list, toggles, revoke, plus, keypad), the notice and phone page, the padlocked person in the Pounce sheet, `CommunicationLimitsBridge` (PermissionKit), `SignificantChangeGate` reused for the kitten-push change, and `PushCoordinator` registering a consented kitten.

**Tech Stack:** TypeScript, Cloudflare Workers, SQLite Durable Objects, WebCrypto, vitest with v8 coverage, Miniflare, OpenSSL (fixture certificates only); Swift 6 on CI's Xcode 26.6, SwiftUI, PermissionKit, DeclaredAgeRange, StoreKit `AppTransaction`, WebKit, Swift Testing, XCUITest, XcodeGen, ImageMagick.

**Spec:** `docs/superpowers/specs/2026-11-05-parent-consent-design.md` (binding, §4 decisions D1–D5); background `2026-11-04-daily-habit-design.md` §12, §13, §14.1, §15 row 9, §16.

**Base:** PRs 1–8 on main (`2026-11-05-live-table.md`, `2026-11-05-widgets.md`, `2026-11-04-notify-server.md`, `2026-11-04-notify-app.md`, `2026-11-04-app-accounts.md`).

## Global Constraints

- **`CONSENT` flag** (`consentOn(env)`): needs `NOTIFY` (so `STREAKS`). Off means today's behavior exactly: no kitten routes (404), no `/privacy/kitten-notice`, `/consent/*`, Twilio or App Store routes, and a kitten's device gets nothing. This is tested. `wrangler.jsonc` sets it on (D4).
- **Twilio is optional like the APNs key.** Texting needs all five secrets (below). Without them, `POST /v1/kittens/{id}/consent` answers 503 `not_configured`, nothing is sent, and the kitten stays pending.
- **No emoji anywhere. On screen:** names, table names and numerals only, except the Apple button, the notice page and the phone field (legal text, like the privacy page).
- **Art:** loud Toy palette; new pictures are `_ph` placeholders through `Art/tools/habit-placeholders.sh`.
- **Swift on Xcode 26.6:** no Swift 6.4-only features, no local constant shadowing a method it calls in its own initializer, no `Test.cancel`. PermissionKit's `AskCenter` and `ask(_:in:)` are iOS 26.2 and `requiredRegulatoryFeatures` 26.4: all `#available`-guarded (they're in the 26.6 SDK; checked in the 26.2 SDK's swiftinterface).
- **Server tests:** every Miniflare `describe` has `{ timeout: 30_000 }`. Presence is set before the deal where bots could race at `DEV_SPEED`.
- **Logs:** no ids, tokens, phone numbers or names.
- **Never handle real keys.** Fixture certificates and keys are generated locally and labeled test-only.
- **Environment:** simulators "Pounce consent iPhone 17 Pro" and "Pounce consent iPad Pro 13", shut down (not deleted) at the end; a private dev server port (not :4343 or :8787); never the physical iPhone.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Decisions where the spec is silent

**Ids and wire**
1. **No player ids on the wire** (an existing invariant: pushes and views never carry `p_`). So:
   - a kitten is addressed by a public id `k_` + 16 random bytes, made at the first link, kept in `KittenIndex`;
   - the kitten's own device uses `me` with `?person=`;
   - approvals are sent and returned as **pair ids**, mapped to partner player ids on the server;
   - the PermissionKit handle is `.custom(pairId)`, not `.custom(playerId)` as the spec sketches. It's opaque to Apple either way.
   - Cost if wrong: none for Apple; a re-formed pair (leave, then undo) gets a new id and is asked again.
2. **"People the kitten plays with"** = the kitten's pairs (streak partners). Someone at a table without a pair yet can't be approved, so "your move" at that table stays off until the pair forms after both take a turn.
3. **Linked parents are always approved**, in both modes: they consented, and a parent pouncing their own kid shouldn't need a toggle.

**Routes** (all need `CONSENT`; device-token auth unless public)

| Method and path | Who | Body → result |
|---|---|---|
| `POST /v1/kittens/me/link-code?person=` | kitten device | `{appTransactionId?}` → 201 `{code, expiresAt}` |
| `GET /v1/kittens/me?person=` | kitten device | → `{state, approved: [pair], linked}` |
| `PUT /v1/kittens/me/approved?person=` | kitten device | `{apple: [pair] \| null}` → 204 |
| `POST /v1/kittens/link` | signed-in adult | `{code}` → 201 `{kitten}`; 404 bad code; 429 too many tries |
| `GET /v1/kittens` | signed-in adult | → `{kittens: [ParentKitten]}` |
| `PUT /v1/kittens/{k}/approved` | linked parent | `{approved: [pair]}` → 204; 409 `apple_managed` |
| `POST /v1/kittens/{k}/consent` | linked parent | `{phone}` → 202 `{state: "texted"}`; 503 without Twilio |
| `DELETE /v1/kittens/{k}/consent` | linked parent | → 204 (revoke) |
| `DELETE /v1/kittens/{k}` | linked parent | → 204 (unlink this parent) |
| `GET /privacy/kitten-notice` | public | the direct notice |
| `GET /consent/{token}` | public | the confirm or revoke page, with a button |
| `POST /consent/{token}` | public | does it; the result page |
| `POST /v1/twilio/inbound` | Twilio | STOP replies, signature checked |
| `POST /v1/appstore/notifications` | Apple | `{signedPayload}`; `RESCIND_CONSENT` |

- `ParentKitten` = `{id, name, cat, state: "pending" \| "texted" \| "on", mode: "parent" \| "apple", people: [{pair, name, cat, approved}]}`.
- `DELETE /v1/kittens/{k}` (unlink) is beyond the spec's list. A parent who linked the wrong kitten needs it. When the last parent unlinks, the record goes.
- **GET confirms nothing.** SMS apps prefetch links for previews, so `GET /consent/{token}` only shows a page; its button `POST`s.

**States** (`pending` → `texted` → `consented`)
4. **Link** (any signed-in adult, band `adult`): adds the parent, and creates the record as `pending` if new. A kitten's device, a teen, a guest or a kitten player can't link (403).
5. **Text** (a linked parent, from `pending` or `texted`): normalizes the phone, sends text 1, stores the phone and who sent it, and moves to `texted`. A new number replaces the old one, and the old confirm token stops working. While `consented`: 409.
6. **Confirm** (`POST /consent/{confirm token}`, while `texted`): moves to `consented` and records who and when. It mints a revoke token and schedules text 2. Tokens are single-use. The confirm token lasts 7 days.
7. **Texted expiry:** if 7 days pass unconfirmed, the phone is deleted and the state goes back to `pending` (16 CFR 312.5(c)(1): delete the parent's contact information when consent isn't obtained in a reasonable time).
8. **Text 2** ("the plus"): at confirm + 24 h, moved to the next 10:00 when that falls outside 10:00–20:00 in the confirming parent's time zone (UTC when unknown). That's always within 24–48 h. The `Consents` alarm sends it once. A send that fails with Twilio's opted-out code (21610) revokes, as STOP does.
9. **Revoke** (a parent's tap, the revoke link, STOP, `RESCIND_CONSENT`): back to `pending`. The phone and tokens are deleted. The parents stay linked and the approvals stay, so consent can be given again. Every push token on the kitten's devices (APNs, widget, live) is deleted at once.
10. **End** (the kitten's deletion, 90-day expiry, turning 13): the whole record and its index rows are deleted, and the tokens are dropped too.
11. **A parent's account deleted:** that parent is unlinked. If they gave the consent, it's revoked. If no parent remains, the record goes. **Merges** repoint a parent (`from` → `to`).
12. **Turning 13** = a profile upload where a player whose band was `kitten` now has another band (Declared Age Range's weekly re-check, §14.1).

**Link codes**
13. Six digits, from crypto random, 10 minutes, single use. A new code replaces the kitten's previous one.
14. **Attempt limit:** 5 failed tries per parent in 10 minutes, then 429. That puts guessing one live code from a million at about 1 in 200,000 per 10 minutes per account.
15. **App transaction id:** sent with the link code (`AppTransaction.shared`'s `appTransactionID`, when StoreKit has one), applied at link, and indexed for `RESCIND_CONSENT`.

**The push gate**
16. **Kinds a consented kitten's device may get:**
    - `your_move`, when every other human seat's player is approved (a seat without a player isn't);
    - `pounce`, when the sender is approved;
    - the background `dismiss` (no alert; it clears notifications we already sent).
    - Nothing else: status, milestones, play again, pounce answers, reminders, widget pushes and the live table stay off.
17. **The fixed-time daily reminder** is the existing local 17:00 one (§14.1), off by default. It needs no server and no consent. Server reminders for kittens stay off, and learned timing stays off. Cost if wrong: a server reminder could be added under the same consent later.
18. **Where it's checked:** `DeviceIndex` asks the recipient's `Consents.allows(kind, senders)` per push, so revocation is immediate with no cached copy. It's one extra call, only for a kitten's device with `CONSENT` on.
19. **Token storage:** with `CONSENT` on, `PUT /v1/devices/me/push` from a kitten's device is refused (403) unless one of its players has consent. With it off, it behaves as today.
20. **A kitten's pounces:** once linked (any state), a kitten can't pounce someone unapproved (403 `not_approved`), matching the padlock. An unlinked kitten pounces as today.

**Approvals (D3)**
21. **Mode:** `apple` once the kitten's device mirrors with `{apple: [...]}`; back to `parent` when it sends `{apple: null}` (Communication Limits turned off). In `apple` mode, the parent's toggles show Apple's answers and can't be changed (409 `apple_managed`).
22. **Mirroring** (app): with Communication Limits, the app asks `knownHandles(in:)` for all the kitten's pair handles at launch, on each refresh and on every `AskCenter` response, and `PUT`s the known set when it changed. It asks PermissionKit (`.connect`, with the partner's name and cat) once per new partner, and again when the kitten taps a padlocked person.
23. **Validation:** both lists are cut to the kitten's real pairs, so neither a parent nor a tampered kitten client can approve a stranger. A tampered kitten client could still mirror "everyone it already plays with". That's accepted: Apple's answer exists only on the device.

**Twilio**
24. **Secrets:** `TWILIO_ACCOUNT_SID`, `TWILIO_API_KEY_SID`, `TWILIO_API_KEY_SECRET`, `TWILIO_MESSAGING_SERVICE_SID` (D1), plus **`TWILIO_AUTH_TOKEN`**.
    - Twilio signs webhooks with the account's Auth Token, which an API key can't do. Without the Auth Token a STOP couldn't be checked, so a parent's STOP would be ignored.
    - So texting needs all five: consent can't start unless STOP can end it.
    - CI warns and skips unless all five GitHub secrets (`PLAY_API_TWILIO_*`) are set.
    - Cost if wrong: JD makes one more secret.
25. **Send:** `POST https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json`, basic auth `apiKeySid:apiKeySecret`, form `To`, `MessagingServiceSid`, `Body`.
26. **STOP:** the inbound webhook's signature is checked against `https://play.conleychaos.com/v1/twilio/inbound` (the request URL) and the sorted form fields. A `Body` of STOP, STOPALL, UNSUBSCRIBE, CANCEL, END, QUIT, REVOKE or OPTOUT, or `OptOutType=STOP`, revokes every kitten whose consent uses that number (`phones` holds SHA-256 hashes). It answers empty TwiML. Twilio's Advanced Opt-Out also blocks further texts by itself.
27. **Copy:** no child's name or other information in a text, only the link (§312.5(b)(2) text plus: the child's information is never disclosed).
    - Text 1: "Pounce: a parent or guardian asked to allow notifications for a child's Pounce game. Read what we keep and confirm: {link} Reply STOP to cancel."
    - Text 2: "Pounce: you allowed notifications for a child's Pounce game. To revoke, tap {link} or reply STOP."

**App Store Server Notifications (D5)**
28. **Verification:**
    - `signedPayload` is a JWS with `alg: ES256` and a three-certificate `x5c`. The root must be byte-for-byte the pinned Apple Root CA - G3 (SHA-256 `63:34:3A:BF:…:91:79`, exported from macOS's system roots and matched against Apple's PKI page).
    - The intermediate must carry OID `1.2.840.113635.100.6.2.1` and the leaf `1.2.840.113635.100.6.11.1`.
    - Each certificate is signed by the next, the names chain, all are inside their validity now, and the JWS verifies with the leaf key.
    - `appData.signedAppTransactionInfo` is verified the same way. Its `appTransactionId` names the kitten.
    - `appData.bundleId` must be `SIWA_CLIENT_ID` (the bundle id). `environment` may be `Production` or `Sandbox` (TestFlight uses Sandbox).
    - No OCSP check. That's optional in Apple's own library; the pinned root and OIDs carry the trust.
29. **Response:** 200 for any verified notification, including types we ignore and unknown transactions, so Apple stops retrying. 400 for anything that fails verification.
30. **Tests:** fixture CA, intermediate and leaf made with OpenSSL (`fixtures/appstore/`, test-only), with the root passed in. Production code pins only Apple's root; there's no env override. The Miniflare entry reaches the handler with the fixture root through a test hook.

**Pages and notice**
31. `/privacy/kitten-notice` (approved by counsel 2026-11-06, D4) has the §312.4(c) contents:
    - who we are and how to reach us;
    - that we collected the parent's mobile number to get consent;
    - what consent allows us to collect from the child (a push token, and the people the child plays with) and why;
    - that we don't disclose it;
    - that we delete the number when consent ends, or after 7 days unconfirmed;
    - how to revoke and delete;
    - a link to `/privacy`.
32. `/privacy` gains a parent-consent section. Its "never collect phone numbers" line becomes "except a parent's, for consent".

**App**
33. **Kitten's bell** (gear sheet, in place of the kitten notify row, which stays below it):
    - **locked:** a padlocked bell and six numeral tiles. The code is fetched on open, and again on expiry.
    - **held:** a padlocked bell, no code. The significant change is owed or denied.
    - **pending / texted:** a sleeping bell.
    - **on:** the normal bell.
34. **Significant change:** a second change, id `kitten-push-2026-11`, shown only to a kitten, with its own description. `.askParent` holds the code until approved. A new install of this version agreed at download, like PR 2's.
35. **Push registration:** `PushPolicy.registersRemote(band:consented:)`. A kitten registers only when consented. When it isn't, a kitten that registered before unregisters at launch (the server already dropped its token).
36. **Parent:** a Kittens button (a kitten face with a heart) in the gear sheet, for a signed-in adult only. It opens a sheet:
    - each kitten's cat with its state (an hourglass for pending, a phone for texted, the bell for on);
    - a toggle per person (their cat and name);
    - the notice and phone button while pending;
    - revoke (the bell with a slash) while on;
    - unlink (the trash can);
    - a plus that opens the six-digit keypad (the age keypad's style).
37. **Notice and phone page:** a `WKWebView` of `/privacy/kitten-notice`, then the phone field (legal text, like the notice) and a send button.
38. **Pounce sheet:** a linked kitten's unapproved partner shows a padlock on their cat. Send is disabled, and a tap on the cat asks PermissionKit when the kitten has Communication Limits. The people row on Us shows the same padlock.
39. **Demo flags** (Debug): `-demo-kitten locked|held|pending|on` (the kitten's side, from `DemoKittenService`) and `-demo-kittens` (the parent's side, with two kittens), with `-stub-accounts signed-in` for the parent.

**After the whole-branch review** (Opus; findings fixed test-first)
40. **One change at a time in `Consents`** (I1): every mutating method runs on a per-object queue, so a revoke that lands while text 2 is out is applied after it, never overwritten by the older record. Test: `a revoke while text 2 is sending stays revoked`.
41. **Text limits** (I2): 3 texts a day per kitten and 5 a day per parent (`KittenIndex.texts`), 429 past that. Only North American numbers (`+1`, NANP shape) are texted: the sending number is US toll-free or 10DLC, and it closes SMS pumping abroad. Cost if wrong: a family abroad can't consent until JD widens `textable` and Twilio's geo permissions.
42. **No plus, no consent** (I4): text 2 that can't be delivered for a day (any failure, including Twilio unconfigured) revokes, as a 21610 opt-out does.
43. **Twilio's copy of the number** (I5): each text's SID is kept, and the texts are deleted from Twilio when contact info is forgotten (revoke, expiry, end). The notice says so.
44. **Cleanup failures propagate** (I6): `endKitten`, `parentGone` and `parentMerged` throw instead of logging, so the caller's own retry (deletion asked again, the player's alarm, a retried sign-in) runs them again.
45. **Smaller ones:** an approved partner who merges stays approved (M9); a room with no state gives "your move" senders `[null]` (M7); an app transaction id held by one kitten can't be taken by another (M8); the confirm token is stored before text 1 goes (M13); a global ceiling of 200 failed link tries per 10 minutes (M12); phone hashes are an HMAC under `TOKEN_SECRET` (M16); `/privacy` drops the consent section with `CONSENT` off (M11). The STOP webhook setup is documented as a JD step (I3).

## Review Focus

1. **The push gate fails closed.**
   - `CONSENT` off: a kitten's device gets nothing (today).
   - On but not consented: nothing.
   - Consented: only the three kinds, and only from approved senders. A human seat without a player blocks "your move".
   - Tests: Miniflare `push gating`; `rules.test.ts` `allows`.
2. **Revocation is immediate and complete on every path:** a parent's revoke, the revoke link, STOP, `RESCIND_CONSENT`, deletion, expiry and turning 13.
   - Tokens are dropped and the phone is deleted.
   - A push right after revocation is refused.
   - Tests: Miniflare `revoke` suite.
3. **No disclosure:**
   - no child's information in a text;
   - no player ids on the wire;
   - the phone stored only while texted or consented, and as a hash in the index;
   - nothing in logs.
4. **Verification:**
   - Twilio signatures, constant-time, over the exact URL and the sorted fields;
   - the JWS chain to the pinned root, the OIDs, validity and alg;
   - the inner app transaction JWS;
   - `bundleId`.
   - Tests: `twilio.test.ts`, `appstore.test.ts`, including tampered and wrong-root cases.
5. **Link-code abuse:** single use, 10-minute expiry, 5 failures per 10 minutes, adults only.
6. **GET never changes state** (`/consent/{token}`), because link prefetchers would confirm.
7. **The app never registers or uploads a kitten's token without consent, and an unknown band counts as kitten.**

---

### Task 1: The plan

- [ ] Commit this file: `docs: daily habit PR 9 (parent consent) plan`.

### Task 2: Server, pure consent rules (`src/consent/rules.ts`)

**Files:** Create `src/consent/rules.ts` and `rules.test.ts`. Modify `vitest.config.ts` (`src/consent/**` at 100%), `src/streaks/profile.ts` (`consentOn`), `src/env.ts`.

- [ ] Failing tests for:
  - each transition and every refusal (decisions 4–12);
  - `allows` (decision 16);
  - `secondTextAt` across zones, DST and the window edges;
  - the 7-day expiry;
  - `normalizePhone` (US 10 and 11 digits, E.164, junk);
  - `newLinkCode` (six digits, uniform from the RNG);
  - `attemptAllowed`;
  - `consentOn`.
- [ ] Then implement, see them pass, and commit `feat(play-api): consent rules`.

### Task 3: Server, Twilio and App Store verification (`twilio.ts`, `appstore.ts`, `pages.ts`)

**Files:** Create `src/consent/{twilio,appstore,pages}.ts` and their tests, and `fixtures/appstore/{root,intermediate,leaf}.pem`, `leaf.key.pem`, `wrong-root.pem` and `README.md`.

- [ ] **Twilio tests:**
  - the signature against Twilio's documented example;
  - tampered URL, field and signature;
  - the send request's URL, auth and form;
  - error-code parsing (21610).
- [ ] **App Store tests:**
  - a fixture chain verifies;
  - a wrong root, a missing OID, an expired certificate, a bad signature, a wrong alg, a two-certificate chain and a tampered payload are each refused;
  - `rescindTransaction` reads the inner JWS.
- [ ] **Pages tests:** the notice's contents; the confirm and revoke pages escape the name; the texts' copy carries no name.
- [ ] Commit `feat(play-api): Twilio, App Store JWS and consent pages`.

### Task 4: Server, DOs, routes, push gate

**Files:**
- Create `src/kittens/{consents,kitten-index,kittens}.ts`.
- Modify:
  - `src/index.ts` (routes, exports);
  - `src/room/device-index.ts` (the gate, `dropPushTokens`);
  - `src/notify/deliver.ts` (gate param);
  - `src/room/game-room.ts` (senders for your move);
  - `src/pounce/pounces.ts` (sender gate, a kitten's `not_approved`);
  - `src/players/{accounts,player}.ts` (turning 13, deletion, expiry, merge);
  - `src/http/privacy.ts`;
  - `wrangler.jsonc` (v5 migration, `CONSENT: on`, bindings);
  - `vitest.config.ts` excludes;
  - `.github/workflows/ci.yml`.
- Create `tests/consent-entry.ts` and `tests/consent.test.ts`; extend `tests/play-helpers.ts`.
- [ ] Miniflare tests, all failing first:
  - **link:** code, link, bad code, expired, reuse, attempt limit, a non-adult refused;
  - **consent:** text sent (fake Twilio), no Twilio → 503, confirm by POST only, GET changes nothing, text 2 by the alarm hook, texted expiry;
  - **revoke:** parent, link, STOP (signed, and unsigned refused), `RESCIND_CONSENT` (fixture root), turning 13, deletion;
  - **push gating:** approved and unapproved "your move" and pounce, a parent always approved, and `CONSENT` off is today exactly;
  - **approvals:** parent and Apple modes, and strangers cut;
  - a kitten's pounce to an unapproved person is 403.
- [ ] Commit `feat(play-api): parent consent for kittens`.

### Task 5: PounceKit

**Files:** Create `Sources/PounceKit/Kitten/{KittenWire,KittenService,KittenStore,KittenBell,LinkCodeEntry,PhoneEntry,KittenApprovals}.swift` and `Demo/DemoKittens.swift`, with tests. Modify `Store/PushPolicy.swift` and `Widgets/WidgetPushToken.swift`.

- [ ] Swift Testing:
  - wire decoding;
  - the bell rule for every state, held and code expiry;
  - `registersRemote(band:consented:)`, with unknown counting as kitten;
  - the entries;
  - the mirror plan: new partners to ask, the asked ones remembered, the mirror body only when changed, `nil` without Communication Limits;
  - the padlock rule;
  - store flows against a fake service.
- [ ] Commit `feat(play-ios): kitten consent model`.

### Task 6: App

**Files:**
- Create `Pounce/App/CommunicationLimitsBridge.swift`, `Pounce/Shell/{KittenBellView,KittensSheet,KittenNoticeSheet,DigitKeypad}.swift`.
- Modify `SignificantChangeGate.swift`, `AgeGate.swift` (Communication Limits flag), `AppModel.swift`, `PushCoordinator.swift`, `GearSheet.swift`, `Shell/PounceSheet.swift`, `UsView.swift`, `AgeGateView.swift` (shared keypad), `project.yml` if needed.
- Art: `_ph` placeholders `icon-bell-locked`, `icon-bell-asleep`, `icon-kittens`, `icon-padlock`, `icon-phone`, `icon-hourglass`, `icon-bell-off` via `habit-placeholders.sh`.
- [ ] XCUITest `KittenTests`: the locked bell with six tiles, held, asleep, on; the parent's panel with toggles, link by keypad, revoke; the padlocked partner in the Pounce sheet. Screenshot tests for the four shots.
- [ ] Commit `feat(play-ios): parent consent for kittens`.

### Task 7: Screenshots, docs, review, verification

- [ ] Own simulators and a private dev server. Shots:
  - `kitten-bell`, `kittens-panel`, `kitten-notice` and `pounce-padlock`;
  - each for iPhone portrait, iPad portrait and iPad landscape;
  - saved as `apps/play-ios/Art/screenshots/consent/<name>-<iphone|ipad>-<portrait|landscape>.jpg`;
  - landscape stored upright with EXIF orientation 1, checked with `file`.
- [ ] Update the README, MANUAL-CHECKLIST, `docs/privacy/retention-policy.md` and the privacy page.
- [ ] Whole-branch review on the most capable model; fix Critical and Important findings test-first.
- [ ] Full verification:
  - the server suite, `tsc` and `eslint`;
  - `swift test`;
  - the Debug simulator build and the Release unsigned build (as `ios.yml` runs it);
  - `check-assets`;
  - SmokeTests, NotifyTests, AccountTests and KittenTests.
- [ ] Rebase onto origin/main.

---

## Changes

### 2026-11-05: Twilio Verify instead of text plus by Programmable Messaging (design D6, JD)

JD chose Twilio Verify so Pounce needs no phone number of its own and no A2P 10DLC or toll-free registration. Verify sends only its own code message, so the flow and decisions 5–8, 24–27, 42, 43 and the STOP parts of 9, 26 and 45 change as below. Everything else above stands.

46. **Verify.** `twilio.ts` starts a verification (`POST verify.twilio.com/v2/Services/{VA…}/Verifications`, `To`, `Channel=sms`) and checks one (`/VerificationCheck`, `To`, `Code`), basic auth with the API key. Secrets, all or none: `TWILIO_ACCOUNT_SID`, `TWILIO_API_KEY_SID`, `TWILIO_API_KEY_SECRET`, `TWILIO_VERIFY_SERVICE_SID` (GitHub: `PLAY_API_TWILIO_*`). Verify's URLs don't name the account; its SID is kept so the set is whole. Without them, `POST …/consent` is 503 `not_configured` and nothing is sent, as before.
47. **States** `pending` → `code` → `consented` (replacing `texted`). The code state lasts **30 minutes** from the last send; then the number is deleted and the state is pending again (312.5(c)(1)). Verify's own code lasts 10 minutes; the extra time lets the parent ask for a fresh code without retyping the number.
48. **Check** (`POST /v1/kittens/{k}/consent/check`, `{code}`: six digits): `approved` → 200 `{state: "on"}`, consent, the number's owner (`codeBy`) is the consenting parent. A wrong code (Verify still `pending`) → 422 `wrong_code`, counted: 5 in 10 minutes per kitten, then 429 (like link codes). No live verification (Verify's 404: expired, used up, already approved; or any non-pending status) → 410 `expired`, still waiting for a code. Verify's 60202 or a 429 → 429. Not waiting → 409 `not_waiting`. Any linked parent may check (the code proves the phone).
49. **Resend** (`POST /v1/kittens/{k}/consent/resend`): the stored number again, no sooner than 30 s after the last send (429), and counting toward the daily limits: 3 a kitten, 5 a parent, and, new, **3 a number from anyone** (`KittenIndex.phone_texts`, the number's HMAC under `TOKEN_SECRET`, kept a day). Verify repeats the live code within its 10 minutes, or makes a fresh one after; its 5-send limit (60203) is a 429.
50. **The plus is a push** (`plusPush` in `pages.ts`, kind `consent`, category `CONSENT`, `kitten: k_…`, title the kitten's generated name, body legal text). Due at consent + 24 h moved into 10:00–20:00 in the consenting parent's zone, sent by the `Consents` alarm to every device of the consenting parent only (other linked parents get nothing). The parent's Pounce notification settings don't apply: it's the legal confirmation.
51. **Delivered** means some device of theirs got a 2xx from APNs. Otherwise retried hourly, never outside 10:00–20:00, and a day after it was due (with no device accepting it, including no token at all or no APNs key) consent is revoked (`no_plus`), as text plus's undeliverable second text did (decision 42).
52. **The panel** gains `confirmed` on `ParentKitten` (the plus was delivered); the card's bell gets a check, or a small hourglass while it's owed.
53. **App.** The notice sheet becomes notice, number, then the code: six tiles and `DigitKeys` (`consent.*` ids; six numerals check themselves), a loop arrow for another code (dim for 30 s, bouncing once Verify says the code expired), the phone for another number, and the hourglass when resting. After the right code the app asks iOS for notifications if it hasn't yet, because the plus needs them. A `CONSENT` category with a background, destructive, authentication-required **Revoke** action calls `DELETE /v1/kittens/{k}/consent`; a tap opens the Kittens panel on that kitten (`AppModel.showKittens(focus:)`, Debug `-open-kittens <k_…>`). New placeholder art: `icon-resend_ph`.
54. **Removed:** the confirm and revoke pages (`GET`/`POST /consent/{token}`, now 404), `/v1/twilio/inbound` and its `X-Twilio-Signature` check, `isStop`, Messaging sends, deleting texts by SID, `TWILIO_AUTH_TOKEN` and `TWILIO_MESSAGING_SERVICE_SID`. `KittenIndex` drops its `tokens` and `phones` tables; `Consents` drops its `sids`, `revoke_token` and `origin` rows; a stored record in the old shape is upgraded on read (one waiting on a texted link goes back to pending, its number deleted). Revoking stays available from the app, the push's Revoke, `RESCIND_CONSENT` and every lifecycle path.
55. **Approved by counsel (2026-11-06):** 16 CFR 312.5(b)(2) gives the text plus confirmatory contact as an example ("such as"). The push to the parent's own device stands in for the second text, and counsel approved it. If that changes, the fallback is Verify's custom template (2 to 4 weeks) or a Messaging number with 10DLC for one text.

**After the whole-branch review of the Verify change** (Opus; findings fixed test-first)

56. **A revoke is never lost** (I1): `KittenStore` keeps each revoke on disk before the request and drops it only when the server has it (or answers 404: nothing left to revoke). The app tries kept revokes again at launch and on every foreground. The notification's Revoke goes through the same queue.
57. **A refused resend doesn't lock the keypad** (I2): too soon or the day's codes used up only dims the loop arrow for another 30 s. Only five wrong codes rest the keypad, and only for the server's 10 minutes. Another number clears both.
58. **Consents from the text plus build end** (I3): a stored record in the old shape is rewritten and revoked when its `Consents` object loads (the number leaves storage at once, the kitten's push tokens go), because the revoke link and STOP that its texts promised went with Verify. The parents and approvals stay, so the parent can consent again with a code. Production likely has none (the Messaging secrets were never set).
59. **Smaller ones:** Verify calls time out after 10 s, so a hung call can't hold the record's queue (M6); `intoWindow` lands on 10:00 across a DST change (M11); "not waiting" refreshes the panel and closes the sheet if another parent already finished (M10); the focused card rings once on screen (M9); the notice says 30 minutes after the last code (M12); the checklist says which phones count as not delivered (M4).
