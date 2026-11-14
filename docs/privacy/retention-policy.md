# Pounce data retention policy

Draft for JD Conley (Conley Chaos LLC) to review, 4 November 2026; updated 10 November 2026 to match the code before the App Store launch, and 13 November 2026 for the first-run funnel (needs legal review). Written to meet the written-retention requirement of the amended COPPA Rule, 16 CFR § 312.10, and the retention rules in the daily habit design (`docs/superpowers/specs/2026-11-04-daily-habit-design.md` §14, §14.1). This is not legal advice. The public summary is the privacy page served by `apps/play-api/src/http/privacy.ts` at `play.conleychaos.com/privacy`, and the App Store Connect answers are in `docs/privacy/app-store-label.md`; keep all three in step.

## Principles

- Keep data only as long as the game needs it to run, plus the first-run funnel (below): anonymous getting-started steps on our own server, to see where new players get stuck. Nothing is kept for ads or resale, and no analytics goes to any other company.
- Delete automatically wherever the server can (Durable Object alarms), so retention never depends on someone remembering.
- A child's data (age band `kitten`, under 13) gets no longer retention than anyone else's, and the same 90-day guest expiry applies.

## What is kept, why, and for how long

| Data | Where | Purpose | Kept for | How it is deleted |
|---|---|---|---|---|
| Device id and device token (HMAC) | App Keychain; `DeviceIndex` DO | Lets the device rejoin its tables | Until the app's data is deleted; the server record goes with its players | Server: removed with the player data it indexes. App: removed with the app. |
| Person id and person key hash | App (`people.json`, Keychain); `Identities` DO, `Player` DO | Binds a guest player to the device that holds the key | With the player | Player deletion or guest expiry removes the identity rows. |
| Name and cat | `Player` DO meta; seats in `GameRoom`; table lists in other players' `Player` and `DeviceIndex` | Shown to people at the same table, and in their notifications (through APNs) | With the player; seats with the room | Account deletion; guest expiry; room close. Deletion removes the player id from every seat but leaves the seated name and cat until the room closes (7 days after its last activity). |
| Table names players type | `GameRoom`, table lists | Shown to the table | With the room | Room close, 7 days after its last activity (`CLEANUP_AFTER_MS`). |
| Game rooms: seats, turns, game state, nudges | `GameRoom` DO | Playing | 7 days after the last activity | `GameRoom.close` deletes all of it. |
| Age band (`kitten`, `teen`, `adult`) | `Player` and `DeviceIndex` | Age limits and safety defaults (§14.1) | With the player | With the player. The birth year typed on the age keypad is never stored: the app turns it into a band on the device and discards it at once (FTC policy statement, February 2026). |
| Time zone | `DeviceIndex`, `Player`, `Pair` | The day boundary for streaks | While the device is in use | Replaced by every profile upload. The `DeviceIndex` record has no expiry of its own (see open items). |
| APNs push, widget and Live Activity tokens | `DeviceIndex` | "Your move" notifications, widget refresh, the live table | Until APNs reports it dead or the app uploads a new one. They belong to the device, so deleting a player leaves them for the device's next player | Forgotten on a 410 or `BadDeviceToken`. For a kitten, kept only with a parent's consent (PR 9), and deleted from all of the kitten's devices the moment consent ends. |
| Sign in with Apple subject hash | `Identities`, `Player` | Finds the player on sign-in | With the identity | Unlink, sign-out of the last device, or account deletion. |
| Sign in with Apple refresh token | `Player.identities.secret` (only when `PLAY_API_SIWA_KEY_P8` is set) | Revocation on deletion, as Apple requires | With the identity | Revoked with Apple, then deleted, on unlink and on account deletion. |
| Synced state: settings, tutorial flags, archive | `Player.state` | Same settings and tables on every device | With the player | Account deletion; guest expiry. |
| Household people listed on an account | `Player.household` | Pass-and-play people follow the owner to another device | While the device that listed them stays linked | Sign-out or detach of that device; account deletion. |
| Tables list | `Player`, `DeviceIndex` | Home's list of tables | Until the room closes | Room close removes the entry. |
| Your own streak days | `Player.personal` | Your own streak | 8 days (`KEEP_DAYS`) | Pruned as days pass; lifetime best stays with the player. |
| Streak day rows (PR 3) | `Pair` DO | The shared streak | 120 days | Settlement prunes older rows. Lifetime counters stay with the pair until a member leaves it or deletes their account. |
| Play-time histogram (PR 5) | `Player.playtime` | Learning reminder times | With the player | Never collected for a kitten; account deletion. |
| Pounces (PR 5) | `Player.pounces` | "Come play with me" | 7 days | Alarm deletes them. |
| Pounce links (PR 5) | `Links` DO | Messages invites and the plus's QR | 7 days (`LINK_MS`), or once someone plays on it | Deleted when someone plays, or by the alarm on expiry. "In a bit" and "Not now" no longer use a link up: they make it that person's, and only they can open it again. |
| Parent's mobile number (PR 9) | `Consents` DO (per kitten); Twilio Verify while its code lasts and in its own records after | Verifiable parental consent: Twilio Verify texts it a six-digit code, which the parent types into the app | While consent lasts; 30 minutes if the code is never entered (16 CFR 312.5(c)(1)) | Deleted from the `Consents` record on revocation (in the app, the confirmation notification's Revoke, `RESCIND_CONSENT`, or the confirmation push not reaching the parent within a day), on the 30-minute expiry, when the child turns 13 or is deleted, and when the consenting parent unlinks or deletes their account. Twilio Verify holds the number with the verification while it is pending (a code lasts 10 minutes; it is gone once approved, after 5 wrong tries, or on expiry). Twilio's API reference marks the verification's `to` field as personal information with a 30-day minimum retention, and Verify Logs in the Twilio console show recent verifications; Twilio keeps it under its own privacy policy, and we can't delete it sooner through the API. Verify's message carries only the code, never anything about the child. |
| Parent's mobile number, keyed hash (PR 9) | `KittenIndex` (`phone_texts`) | No number gets more than 3 codes a day, from anyone | 24 hours from each code | Alarm prunes rows older than a day. HMAC-SHA-256 under `TOKEN_SECRET`, so the index alone can't be turned back into numbers. |
| Consent record: linked parents, state, approved people (PR 9) | `Consents` DO | Which parents may manage a kitten, and who may reach it | While at least one parent stays linked and the kitten is under 13 | Deleted when the last parent unlinks, the kitten turns 13, or the kitten's player is deleted or expires. Revocation keeps parents and approvals (no contact information) so consent can be given again. |
| Link codes (PR 9) | `KittenIndex` | Linking a kitten's device to a parent | 10 minutes, or once used | Alarm and use delete them. Failed tries: 10 minutes. |
| Wrong-code tries (PR 9) | `Consents` DO | At most 5 wrong codes in 10 minutes | 10 minutes | Dropped with the code state, on consent, or on revocation. |
| First-run funnel: per device, the first time it reached each getting-started step, the days it was used, app version, platform, language and region, how it came (`docs/funnel.md`) | D1 database `conleychaos-play-funnel` (`FUNNEL`) | Seeing where new players get stuck (first-run funnel design, Part 3). Keyed by an HMAC of the device id under `TOKEN_SECRET`: no device id, name, player, account, table code or address | A year after the device was last used | `prune` (`src/funnel/funnel.ts`), run after about one minting in 50; and `forget` when the device's player is deleted in the app (`DELETE /v1/me`). |
| Invite page counts | D1 `page_views` | How many invite pages are opened (and previewed) a day | A year | `prune`. A count per day and page; nothing about the viewer. |
| App transaction id (PR 9) | `Consents`, `KittenIndex` | Matching Apple's `RESCIND_CONSENT` to the kitten | With the consent record | Deleted with the record. |

## Expiry rules

- **Guest players:** a player with no sign-in identity that no device has touched for 90 days is deleted, together with its identities, device links and seats (seats fall back to the device). Implemented by `Player.alarm` (`GUEST_TTL_MS`).
- **Merged guest stubs:** 30 days after a merge (`STUB_TTL_MS`).
- **Deletion in the app:** any player can delete their server data from the gear sheet, signed in or not (App Store guideline 5.1.1(v)). A signed-in player deletes the account (trash can); a guest or a child's device uses Delete my data, which runs the same `DELETE /v1/me` for that person. `deleteMe` revokes Sign in with Apple, removes identities, leaves and deletes every pair, forgets links and pounce ids, ends a child's consent record (phone number, link codes, kid ids, parents, transaction id, push tokens) and unlinks a parent from their children, removes the player from the device and from every seat's player id, and deletes the `Player`. Left behind: seated names until each room closes; partners' pounce rows naming the player for up to 7 days; the `phone_texts` hash and `texts` rate-limit rows for up to a day; the device's own tokens and time zone; Cloudflare's 30-day point-in-time recovery (Durable Objects and D1 alike). The device's funnel rows are deleted with it.
- **Accounts:** kept until the person deletes the account in the app, which runs `deleteMe` (§14). There is no inactivity expiry for signed-in accounts yet; decide one before the App Store launch.

## Logs

- Worker invocation logs are off (`wrangler.jsonc`). Error logs carry event names and error codes: no player ids, pair ids, tokens, names or phone numbers. A few room errors log the room code (`game-room.ts`).
- The device-mint rate limit keeps client IP addresses in memory for a minute or so; they are never stored.
- Cloudflare's own platform logs follow Cloudflare's retention; we keep no copy.

## Backups

- Durable Object storage and D1 have Cloudflare's point-in-time recovery (30 days, D1's Time Travel). We take no other backups, so a deletion is final once that window passes.

## Requests

- A parent or player can ask to review or delete data by writing to privacy@conleychaos.com. Answer within 30 days. For a child, delete the player (or players) on that device by its person ids; no proof beyond the device is needed, because the app holds nothing that identifies the child.

## Review

- Reviewed with the security program each November, and whenever a PR adds a new kind of data. Next review: November 2027.

## Open items for JD

- Confirm that `privacy@conleychaos.com` exists and is read.
- COPPA's direct notice (§ 312.4(d)) asks for the operator's postal address and telephone number as well as an email. Add them to the privacy page before the App Store launch.
- Decide an inactivity expiry for signed-in accounts.
- `DeviceIndex` records (push tokens, time zone, table list) have no expiry. Consider pruning a device no player has touched for 90 days, like guests.
- A consenting parent's number is kept for as long as consent lasts, with no upper limit. Decide whether that is right or whether consent should be renewed.
- Deleting a player leaves their name in the seats of rooms still open (up to 7 days). Decide whether to blank it at once.
